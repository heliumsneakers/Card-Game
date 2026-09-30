export type CardType = "DMG" | "DEF" | "HEAL" | "UTIL";
export type CardElement = "fire" | "ice" | "nature" | "earth" | "arcane";
export type CardTarget = "enemy" | "multi" | "all" | "self";
export type EffectTarget = "selectedEnemy" | "otherEnemies" | "allEnemies";

export type Expression =
  | { kind: "literal"; value: number }
  | { kind: "counter"; id: string }
  | { kind: "local"; name: string }
  | { kind: "context"; path: "previousCardId" | "thisCardId" | "mana" | "hp" | "turn" | "livingEnemies" }
  | { kind: "binary"; operator: "add" | "subtract" | "multiply" | "min" | "max"; left: Expression; right: Expression }
  | { kind: "compare"; operator: "eq" | "ne" | "lt" | "lte" | "gt" | "gte"; left: Expression; right: Expression };

export type Effect =
  | { op: "damage"; target: EffectTarget; amount: Expression; scalable?: boolean }
  | { op: "debuff"; id: "debuff.freeze"; target: EffectTarget; stacks: Expression; scalable?: boolean }
  /** Legacy schema-v1 Freeze effects are migrated to a debuff block on load. */
  | { op: "freeze"; target: EffectTarget }
  | { op: "armor" | "heal" | "draw"; amount: Expression; scalable?: boolean }
  | { op: "mana"; amount: Expression; cap: number; scalable?: boolean }
  | { op: "addStatus"; id: "status.spell_power" | "status.mirror"; stacks: Expression; scalable?: boolean }
  | { op: "incrementCounter"; id: string; amount: number }
  | { op: "setLocal"; name: string; value: Expression }
  | { op: "if"; condition: Expression; then: Effect[]; else?: Effect[] };

export interface CardDefinition {
  id: string;
  name: string;
  cost: number;
  type: CardType;
  element: CardElement;
  target: CardTarget;
  enabled: boolean;
  description: string;
  retainsStatuses?: string[];
  availability: { startingDeck: number; shop: boolean; shopChance: number; copyLimit: number };
  effects: Effect[];
}

export interface EnemyDefinition {
  id: string;
  name: string;
  damage: { min: number; max: number };
  hp: { min: number; max: number };
  enabled: boolean;
  generation: {
    spawnEnabled: boolean;
    spawnWeight: number;
    minimumRoom: number;
    maximumRoom?: number;
    maximumCopies: number;
    bossOnly: boolean;
    tags: string[];
    powerOverride?: number;
  };
}

export interface RoomDefinition {
  room: number;
  power: number;
  minimumEnemies: number;
  maximumEnemies: number;
  minimumBudgetRatio: number;
  maximumBudgetRatio: number;
  requiredTags: string[];
  excludedTags: string[];
}

export interface EndlessDefinition {
  startingPower: number;
  powerPerRoom: number;
  minimumEnemies: number;
  maximumEnemies: number;
  minimumBudgetRatio: number;
  maximumBudgetRatio: number;
}

export interface ContentDocument {
  schemaVersion: 1;
  contentRevision: string;
  cards: CardDefinition[];
  enemies: EnemyDefinition[];
  roomCurve: RoomDefinition[];
  endless: EndlessDefinition;
}

export const literal = (value: number): Expression => ({ kind: "literal", value });

export function newEffect(op: Effect["op"]): Effect {
  if (op === "damage") return { op, target: "selectedEnemy", amount: literal(2), scalable: true };
  if (op === "debuff") return { op, id: "debuff.freeze", target: "selectedEnemy", stacks: literal(1), scalable: false };
  if (op === "freeze") return { op, target: "selectedEnemy" };
  if (op === "mana") return { op, amount: literal(2), cap: 3, scalable: true };
  if (op === "addStatus") return { op, id: "status.spell_power", stacks: literal(1) };
  if (op === "incrementCounter") return { op, id: "$thisCard", amount: 1 };
  if (op === "setLocal") return { op, name: "damage", value: literal(2) };
  if (op === "if") return {
    op,
    condition: { kind: "compare", operator: "eq", left: { kind: "context", path: "previousCardId" }, right: { kind: "context", path: "thisCardId" } },
    then: [{ op: "damage", target: "selectedEnemy", amount: literal(1), scalable: true }],
  };
  return { op, amount: literal(op === "heal" ? 5 : 2), scalable: true };
}
