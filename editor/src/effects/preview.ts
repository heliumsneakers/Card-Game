import { resolveCounterId, type CounterCard } from "./counterReferences.ts";
import { getDebuff, legacyFreezeId } from "./debuffs.ts";
import { addDamageBonus, matchingDamageBonus, type DamageBonusState } from "./damageModifiers.ts";
import type { CardDefinition, CounterReference, Effect, Expression } from "../model";

export interface PreviewState {
  mana: number; maxMana: number; hp: number; maxHp: number; armor: number; turn: number;
  previousCardId: string; enemies: number[]; debuffs: Record<string, number>[]; debuffDamage: Record<string, number>[]; targetIndex: number;
  handSize: number; availableDraws: number; statuses: Record<string, number>; counters: Record<string, number>;
  damageBonuses: DamageBonusState;
}
export interface TraceStep { path: string; operation: string; inputs: string[]; result: string }
export interface PreviewResult { state: PreviewState; steps: TraceStep[]; values: Map<Effect, number>; bonusDamageValues: Map<Effect, number>; error?: string }

/** Build a fresh sandbox; numeric inputs represent the state when effects start. */
export function initialPreviewState(): PreviewState {
  // The selected card has already left the hand and paid its mana cost.
  return { mana: 2, maxMana: 3, hp: 20, maxHp: 30, armor: 0, turn: 1, previousCardId: "", enemies: [30, 30], debuffs: [{}, {}], debuffDamage: [{}, {}], targetIndex: 0, handSize: 3, availableDraws: 10, statuses: {}, counters: {}, damageBonuses: { turn: {}, combat: {} } };
}

/** Resolve ownership and lifetime into an unambiguous sandbox key. */
export function counterKey(reference: CounterReference, card: string | CounterCard, instanceId: string): string {
  // String callers retain the old API; dynamic group owners require card metadata.
  const definition = typeof card === "string" ? { id: card } : card;
  return `${reference.scope || "turn"}:${resolveCounterId(reference, definition, instanceId)}`;
}

/** Clear turn state while retaining counters whose lifetime is the combat. */
export function nextPreviewTurn(state: PreviewState): PreviewState {
  // Mirror combat's turn transition: refill mana, retain previous-card history.
  const maxMana = Math.min(3, state.maxMana + 1);
  const canDraw = state.handSize < 7 && state.availableDraws > 0;
  return { ...state, turn: state.turn + 1, maxMana, mana: maxMana, handSize: state.handSize + Number(canDraw), availableDraws: state.availableDraws - Number(canDraw), counters: Object.fromEntries(Object.entries(state.counters).filter(([key]) => key.startsWith("combat:"))), damageBonuses: { ...state.damageBonuses, turn: {} } };
}

/** Resolve an effect list against a detached state and return an ordered trace. */
export function previewEffects(card: Pick<CardDefinition, "id" | "effects"> & Partial<Pick<CardDefinition, "element" | "type">>, source: PreviewState, instanceId = "1"): PreviewResult {
  const state: PreviewState = structuredClone(source);
  // Older hot-reloaded sandbox state may predate the potency map.
  state.debuffDamage ||= [];
  // Old saved sandbox state may predate centralized card damage bonuses.
  state.damageBonuses ||= { turn: {}, combat: {} };
  const steps: TraceStep[] = [];
  const values = new Map<Effect, number>();
  const bonusDamageValues = new Map<Effect, number>();
  const locals = new Map<string, number | string | boolean>();
  const surge = state.statuses["status.spell_power"] || 0;
  const multiplier = surge > 0 ? surge * 2 : 1;
  let inputs: string[] = [];

  /** Record a live input at the point where the expression reads it. */
  function read(label: string, value: number | string | boolean) {
    inputs.push(`${label} = ${String(value)}`);
    return value;
  }

  /** Evaluate typed expression operands in the same order as the Lua resolver. */
  function evaluate(expression: Expression): number | string | boolean {
    if (expression.kind === "literal") return expression.value;
    if (expression.kind === "card") return expression.id;
    if (expression.kind === "counter") {
      const key = counterKey(expression, card, instanceId);
      return read(key, state.counters[key] || 0);
    }
    if (expression.kind === "local") {
      if (!locals.has(expression.name)) throw new Error(`Unknown calculated value: ${expression.name}`);
      return read(expression.name, locals.get(expression.name)!);
    }
    if (expression.kind === "context") {
      const value = expression.path === "thisCardId" ? card.id : expression.path === "livingEnemies" ? state.enemies.filter((hp) => hp > 0).length : state[expression.path];
      return read(expression.path, value);
    }
    const left = evaluate(expression.left);
    const right = evaluate(expression.right);
    if (expression.kind === "compare") {
      if (expression.operator === "eq") return left === right;
      if (expression.operator === "ne") return left !== right;
      if (typeof left !== "number" || typeof right !== "number") throw new Error("Ordered comparisons require numbers.");
      if (expression.operator === "lt") return left < right;
      if (expression.operator === "lte") return left <= right;
      if (expression.operator === "gt") return left > right;
      return left >= right;
    }
    if (typeof left !== "number" || typeof right !== "number") throw new Error("Arithmetic requires numbers.");
    if (expression.operator === "add") return left + right;
    if (expression.operator === "subtract") return left - right;
    if (expression.operator === "multiply") return left * right;
    if (expression.operator === "min") return Math.min(left, right);
    return Math.max(left, right);
  }

  /** Clamp a computed amount before applying captured spell power. */
  function amount(expression: Expression | number, scalable = false): number {
    const value = typeof expression === "number" ? expression : evaluate(expression);
    if (typeof value !== "number" || !Number.isFinite(value)) throw new Error("Effect amount must be a finite number.");
    const base = Math.max(0, Math.floor(value));
    if (scalable) inputs.push(`spell power ×${multiplier}`);
    return base * (scalable ? multiplier : 1);
  }

  /** Execute a branch synchronously so subsequent blocks observe its mutations. */
  function execute(effects: Effect[], prefix: string) {
    effects.forEach((effect, index) => {
      const path = `${prefix}${index + 1}`;
      inputs = [];
      if (effect.op === "if") {
        const condition = evaluate(effect.condition);
        if (typeof condition !== "boolean") throw new Error("Conditions must be comparisons.");
        steps.push({ path, operation: effect.op, inputs, result: condition ? "Then branch" : "Otherwise branch" });
        execute(condition ? effect.then : effect.else || [], `${path}.${condition ? "then" : "else"}.`);
        return;
      }
      let result = "";
      if (effect.op === "setLocal") {
        const value = evaluate(effect.value);
        locals.set(effect.name, value);
        result = `${effect.name} = ${value}`;
      } else if (effect.op === "incrementCounter" || effect.op === "subtractCounter" || effect.op === "setCounter" || effect.op === "resetCounter") {
        const key = counterKey(effect, card, instanceId);
        const before = state.counters[key] || 0;
        const value = effect.op === "resetCounter" ? 0 : amount(effect.amount ?? 1);
        state.counters[key] = effect.op === "incrementCounter" ? before + value : effect.op === "subtractCounter" ? Math.max(0, before - value) : value;
        result = `${key}: ${before} → ${state.counters[key]}`;
      } else if (effect.op === "damageBonus") {
        const value = amount(effect.amount, effect.scalable);
        const key = addDamageBonus(state, effect, card, value);
        result = `${effect.element || "any element"} / ${effect.category || "any category"} bonus: ${state.damageBonuses[effect.scope][key].amount}`;
      } else {
        const baseValue = effect.op === "freeze" ? 1 : amount(effect.op === "debuff" || effect.op === "addStatus" ? effect.stacks : effect.amount, "scalable" in effect && effect.scalable);
        const value = effect.op === "damage" ? baseValue + matchingDamageBonus(state, card) : baseValue;
        if (effect.op === "damage" && value > baseValue) inputs.push(`matching damage bonuses +${value - baseValue}`);
        values.set(effect, value);
        // Capture potency now; later spell-power changes cannot alter active debuffs.
        const bonusDamage = effect.op === "debuff" && effect.bonusDamage ? amount(effect.bonusDamage, effect.damageScalable) : 0;
        if (effect.op === "debuff" && effect.bonusDamage) bonusDamageValues.set(effect, bonusDamage);
        if (effect.op === "damage" || effect.op === "debuff" || effect.op === "freeze") {
          const targets = state.enemies.map((hp, i) => hp > 0 && (effect.target === "allEnemies" || (effect.target === "selectedEnemy" ? i === state.targetIndex : i !== state.targetIndex)) ? i : -1).filter((i) => i >= 0);
          result = targets.length ? targets.map((i) => {
            if (effect.op === "damage") {
              const before = state.enemies[i];
              state.enemies[i] = Math.max(0, before - value);
              return `Enemy ${i + 1} HP: ${before} → ${state.enemies[i]} (${value})`;
            }
            // Each ID gets its own stack count; labels come from the shared catalog.
            const definition = getDebuff(effect.op === "freeze" ? legacyFreezeId : effect.id);
            const stacks = state.debuffs[i] ||= {};
            const before = stacks[definition.id] || 0;
            const bonuses = state.debuffDamage[i] ||= {};
            if (value > 0) {
              stacks[definition.id] = before + value;
              bonuses[definition.id] = Math.max(before > 0 ? bonuses[definition.id] || 0 : 0, bonusDamage);
            }
            const suffix = bonuses[definition.id] ? `; +${bonuses[definition.id]} damage per turn` : "";
            return `Enemy ${i + 1} ${definition.label}: ${before} → ${stacks[definition.id] || 0} (${value})${suffix}`;
          }).join("; ") : `No living targets (${value})`;
        } else if (effect.op === "addStatus") {
          const before = state.statuses[effect.id] || 0;
          state.statuses[effect.id] = before + value;
          result = `${effect.id}: ${before} → ${before + value}`;
        } else if (effect.op === "draw") {
          const drawn = Math.min(value, 7 - state.handSize, state.availableDraws);
          state.handSize += drawn; state.availableDraws -= drawn;
          result = `Draw ${drawn} of ${value}; hand ${state.handSize}/7`;
        } else {
          const field = effect.op === "heal" ? "hp" : effect.op === "armor" ? "armor" : "mana";
          const before = state[field];
          state[field] = effect.op === "heal" ? Math.min(state.maxHp, before + value) : effect.op === "mana" ? Math.min(effect.cap ?? state.maxMana, before + value) : before + value;
          result = `${field}: ${before} → ${state[field]} (${value})`;
        }
      }
      steps.push({ path, operation: effect.op, inputs, result });
    });
  }
  // Errors return diagnostics and partial trace, never commit partial sandbox state.
  try { execute(card.effects, ""); return { state, steps, values, bonusDamageValues }; }
  catch (error) { return { state: structuredClone(source), steps, values: new Map(), bonusDamageValues: new Map(), error: error instanceof Error ? error.message : String(error) }; }
}
