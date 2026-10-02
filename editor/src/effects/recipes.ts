import { literal, type Effect } from "../model";

export interface Recipe { id: string; name: string; description: string; create: () => Effect[] }

// Recipes insert ordinary blocks; editing one never changes another card.
export const recipes: Recipe[] = [
  { id: "growing", name: "Growing damage", description: "Deal 2 + this card's turn counter, then increase it.", create: () => [
    { op: "damage", target: "selectedEnemy", amount: { kind: "binary", operator: "add", left: literal(2), right: { kind: "counter", id: "$thisCard", scope: "turn" } }, scalable: true },
    { op: "incrementCounter", id: "$thisCard", scope: "turn", amount: literal(1) },
  ] },
  { id: "combo", name: "Combo bonus", description: "Deal 4 if the previous card was this card, otherwise 2.", create: () => [
    { op: "if", condition: { kind: "compare", operator: "eq", left: { kind: "context", path: "previousCardId" }, right: { kind: "context", path: "thisCardId" } },
      then: [{ op: "damage", target: "selectedEnemy", amount: literal(4), scalable: true }],
      else: [{ op: "damage", target: "selectedEnemy", amount: literal(2), scalable: true }] },
  ] },
  { id: "charge", name: "Build charges", description: "Add 1 shared charge for this combat.", create: () => [
    { op: "incrementCounter", id: "shared.charges", scope: "combat", amount: literal(1) },
  ] },
  { id: "spend", name: "Spend charges", description: "Spend 2 shared combat charges to deal 6 damage.", create: () => [
    { op: "if", condition: { kind: "compare", operator: "gte", left: { kind: "counter", id: "shared.charges", scope: "combat" }, right: literal(2) },
      then: [{ op: "subtractCounter", id: "shared.charges", scope: "combat", amount: literal(2) }, { op: "damage", target: "selectedEnemy", amount: literal(6), scalable: true }], else: [] },
  ] },
];
