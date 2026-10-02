import { debuffRegistry } from "./debuffs.ts";
import type { CardDefinition } from "../model";
import { effectDefaults } from "./defaults.ts";

type ValueType = "number" | "card" | "boolean" | "invalid";
type AddIssue = (path: string, message: string) => void;
type Locals = Map<string, ValueType>;

/** Validate untrusted effect trees and check references before execution. */
export function validateEffects(effects: unknown, path: string, card: Pick<CardDefinition, "target">, cardIds: Set<string>, add: AddIssue, locals: Locals = new Map(), depth = 0): Locals {
  // Bound nesting before traversing imported JSON.
  if (!Array.isArray(effects)) { add(path, "Effects must be an array."); return locals; }
  if (depth > 3) { add(path, "Conditional nesting exceeds 3."); return locals; }
  if (effects.length > 64) add(path, "A branch cannot contain more than 64 effects.");

  /** Require a safe counter key and an implemented lifetime. */
  function counter(value: Record<string, unknown>, at: string) {
    if (typeof value.id !== "string" || !value.id.trim() || value.id.startsWith("@") || (value.id.startsWith("$") && value.id !== "$thisCard" && value.id !== "$thisInstance")) add(`${at}.id`, "Choose a counter owner or a non-empty shared name.");
    if (typeof value.id === "string" && value.id.startsWith("card.") && !cardIds.has(value.id)) add(`${at}.id`, "Referenced card does not exist.");
    if (value.scope !== undefined && value.scope !== "turn" && value.scope !== "combat") add(`${at}.scope`, "Choose turn or combat lifetime.");
  }

  /** Infer expression types and reject missing locals or mixed operands. */
  function expression(value: unknown, at: string, nesting = 0): ValueType {
    if (nesting > 12) { add(at, "Expression nesting exceeds 12."); return "invalid"; }
    if (!value || typeof value !== "object") { add(at, "Expected an expression."); return "invalid"; }
    const expr = value as Record<string, unknown>;
    if (expr.kind === "literal") {
      if (typeof expr.value !== "number" || !Number.isSafeInteger(expr.value) || expr.value < 0) add(at, "Use a non-negative safe whole number.");
      return "number";
    }
    if (expr.kind === "counter") { counter(expr, at); return "number"; }
    if (expr.kind === "card") {
      if (typeof expr.id !== "string" || !cardIds.has(expr.id)) add(at, "Referenced card does not exist.");
      return "card";
    }
    if (expr.kind === "context") {
      if (expr.path === "thisCardId" || expr.path === "previousCardId") return "card";
      if (["mana", "hp", "turn", "livingEnemies"].includes(String(expr.path))) return "number";
      add(at, "Unsupported game value."); return "invalid";
    }
    if (expr.kind === "local") {
      const type = locals.get(String(expr.name));
      if (!type) add(at, "Calculated value must be set earlier on every possible path.");
      return type || "invalid";
    }
    if (expr.kind !== "binary" && expr.kind !== "compare") { add(at, "Unsupported expression kind."); return "invalid"; }
    const left = expression(expr.left, `${at}.left`, nesting + 1);
    const right = expression(expr.right, `${at}.right`, nesting + 1);
    if (expr.kind === "binary") {
      if (!["add", "subtract", "multiply", "min", "max"].includes(String(expr.operator))) add(at, "Unsupported arithmetic operator.");
      if (left !== "number" || right !== "number") add(at, "Arithmetic requires two numbers.");
      return "number";
    }
    if (!["eq", "ne", "lt", "lte", "gt", "gte"].includes(String(expr.operator))) add(at, "Unsupported comparison operator.");
    if (left !== right || left === "invalid") add(at, "Compare values of the same type.");
    if (expr.operator !== "eq" && expr.operator !== "ne" && left !== "number") add(at, "Ordered comparisons require numbers.");
    return "boolean";
  }

  /** Enforce the type expected by an effect input. */
  function expect(value: unknown, at: string, type: ValueType) {
    if (expression(value, at) !== type) add(at, `Expected a ${type} value.`);
  }

  effects.forEach((raw, index) => {
    const at = `${path}[${index}]`;
    if (!raw || typeof raw !== "object" || !Object.hasOwn(effectDefaults, raw.op)) { add(at, "Unsupported effect operation."); return; }
    const effect = raw as Record<string, unknown>;
    if (effect.scalable !== undefined && typeof effect.scalable !== "boolean") add(at, "Spell-power scaling must be a boolean.");
    if (effect.op === "if") {
      expect(effect.condition, `${at}.condition`, "boolean");
      const yes = validateEffects(effect.then, `${at}.then`, card, cardIds, add, new Map(locals), depth + 1);
      const no = validateEffects(effect.else ?? [], `${at}.else`, card, cardIds, add, new Map(locals), depth + 1);
      // Only definitely assigned values may escape a conditional.
      locals.clear();
      yes.forEach((type, name) => { if (no.get(name) === type) locals.set(name, type); });
      return;
    }
    if (effect.op === "setLocal") {
      const type = expression(effect.value, `${at}.value`);
      if (typeof effect.name !== "string" || !/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(effect.name)) add(at, "Use a valid calculated-value name.");
      else locals.set(effect.name, type);
      return;
    }
    if (["incrementCounter", "subtractCounter", "setCounter", "resetCounter"].includes(String(effect.op))) {
      counter(effect, at);
      if (effect.op !== "resetCounter") {
        // Old v1 increments may omit amount, which means one.
        const amount = effect.amount ?? (effect.op === "incrementCounter" ? 1 : undefined);
        expect(typeof amount === "number" ? { kind: "literal", value: amount } : amount, `${at}.amount`, "number");
      }
      return;
    }
    if (effect.op !== "freeze") expect(effect.op === "debuff" || effect.op === "addStatus" ? effect.stacks : effect.amount, `${at}.amount`, "number");
    // Damage and duration have separate types and scaling controls.
    if (effect.op === "debuff" && effect.bonusDamage !== undefined) expect(effect.bonusDamage, `${at}.bonusDamage`, "number");
    if (effect.op === "debuff" && effect.damageScalable !== undefined && typeof effect.damageScalable !== "boolean") add(at, "Bonus damage scaling must be a boolean.");
    if (effect.op === "debuff" && !debuffRegistry.has(String(effect.id))) add(at, "Unsupported debuff.");
    if (effect.op === "addStatus" && effect.id !== "status.spell_power" && effect.id !== "status.mirror") add(at, "Unsupported status.");
    if (effect.op === "mana" && effect.cap !== undefined && (typeof effect.cap !== "number" || !Number.isSafeInteger(effect.cap) || effect.cap < 0)) add(at, "Mana cap must be a non-negative whole number.");
    if (["damage", "debuff", "freeze"].includes(String(effect.op))) {
      if (!["selectedEnemy", "otherEnemies", "allEnemies"].includes(String(effect.target))) add(at, "Unsupported enemy target.");
      if (effect.target === "selectedEnemy" && card.target !== "enemy" && card.target !== "multi") add(at, "Selected enemy requires One Enemy or Multiple Enemies.");
      if (effect.target === "otherEnemies" && card.target !== "multi") add(at, "Other enemies requires Multiple Enemies.");
      if (effect.target === "allEnemies" && card.target !== "all" && card.target !== "multi") add(at, "All enemies requires All Enemies or Multiple Enemies.");
    }
  });
  return locals;
}
