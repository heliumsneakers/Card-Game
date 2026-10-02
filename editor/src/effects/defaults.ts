import { defaultDebuffId, getDebuff } from "./debuffs.ts";
import type { Effect, Expression } from "../model";

/** Keep default numeric leaves independent across inserted blocks. */
const number = (value: number): Expression => ({ kind: "literal", value });

// Each factory creates fresh state, including nested expressions and branches.
export const effectDefaults: Record<Effect["op"], () => Effect> = {
  damage: () => ({ op: "damage", target: "selectedEnemy", amount: number(2), scalable: true }),
  damageBonus: () => ({ op: "damageBonus", element: "this", amount: number(1), scalable: false, scope: "turn" }),
  debuff: () => {
    // The catalog owns each debuff’s initial amount and scaling preference.
    const definition = getDebuff(defaultDebuffId);
    return { op: "debuff", id: definition.id, target: "selectedEnemy", stacks: number(definition.defaultStacks), scalable: definition.scalable };
  },
  freeze: () => ({ op: "freeze", target: "selectedEnemy" }),
  armor: () => ({ op: "armor", amount: number(2), scalable: true }),
  heal: () => ({ op: "heal", amount: number(5), scalable: true }),
  draw: () => ({ op: "draw", amount: number(2), scalable: true }),
  mana: () => ({ op: "mana", amount: number(2), cap: 3, scalable: true }),
  addStatus: () => ({ op: "addStatus", id: "status.spell_power", stacks: number(1) }),
  incrementCounter: () => ({ op: "incrementCounter", id: "$thisCard", scope: "turn", amount: number(1) }),
  subtractCounter: () => ({ op: "subtractCounter", id: "$thisCard", scope: "turn", amount: number(1) }),
  setCounter: () => ({ op: "setCounter", id: "$thisCard", scope: "turn", amount: number(1) }),
  resetCounter: () => ({ op: "resetCounter", id: "$thisCard", scope: "turn" }),
  setLocal: () => ({ op: "setLocal", name: "damage", value: number(2) }),
  if: () => ({ op: "if", condition: { kind: "compare", operator: "eq", left: { kind: "context", path: "previousCardId" }, right: { kind: "context", path: "thisCardId" } }, then: [], else: [] }),
};
