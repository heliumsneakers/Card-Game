import type { CardDefinition, Effect } from "../model";

/** Store a bonus after resolving any card-relative filters. */
export function addDamageBonus(state: { damageBonuses: DamageBonusState }, effect: Extract<Effect, { op: "damageBonus" }>, card: Partial<Pick<CardDefinition, "element" | "type">>, amount: number): string {
  // Missing metadata is allowed for unrelated sandbox cards, but not for “this”.
  const element = effect.element === "this" ? card.element : effect.element;
  const category = effect.category === "this" ? card.type : effect.category;
  if (effect.element === "this" && !element || effect.category === "this" && !category) throw new Error("This card's element and category are required for its damage bonus.");
  // A stable key lets repeated matching effects grow one active bonus.
  const key = `${element || "*"}|${category || "*"}`;
  const bonuses = state.damageBonuses[effect.scope];
  const current = bonuses[key] || { element, category, amount: 0 };
  bonuses[key] = { ...current, amount: current.amount + amount };
  return key;
}

/** Add all active turn and combat bonuses whose filters match this card. */
export function matchingDamageBonus(state: { damageBonuses: DamageBonusState }, card: Partial<Pick<CardDefinition, "element" | "type">>): number {
  // Wildcard filters can combine with narrower element/category filters.
  return Object.values(state.damageBonuses).flatMap(Object.values).reduce((total, bonus) => {
    const matchesElement = !bonus.element || bonus.element === card.element;
    const matchesCategory = !bonus.category || bonus.category === card.type;
    return total + (matchesElement && matchesCategory ? bonus.amount : 0);
  }, 0);
}

/** Keep the stored filter and amount needed to apply each active bonus. */
export interface DamageBonusEntry { element?: string; category?: string; amount: number }
export interface DamageBonusState { turn: Record<string, DamageBonusEntry>; combat: Record<string, DamageBonusEntry> }
