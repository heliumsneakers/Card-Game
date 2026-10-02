import type { DebuffId } from "./effects/debuffs.ts";
import { effectDefaults } from "./effects/defaults.ts";

export type CardType = "DMG" | "DEF" | "HEAL" | "UTIL";
export type CardElement = "fire" | "ice" | "nature" | "earth" | "arcane";
export type CardTarget = "enemy" | "multi" | "all" | "self";
export type EffectTarget = "selectedEnemy" | "selectedEnemies" | "otherEnemies" | "allEnemies";

/** Ownership is independent from the counter name and reset timing. */
export type CounterOwner =
  | { kind: "this" | "instance" | "shared" }
  | { kind: "card"; cardId: string }
  | { kind: "element"; element: CardElement | "this" }
  | { kind: "category"; category: CardType | "this" };
export interface ExplicitCounterReference { owner: CounterOwner; name: string; scope?: "turn" | "combat"; id?: never }
/** Old IDs remain readable; editing ownership upgrades only that reference. */
export type CounterReference = ExplicitCounterReference | { id: string; scope?: "turn" | "combat"; owner?: never; name?: never };

export type Expression =
  | { kind: "literal"; value: number }
  | ({ kind: "counter" } & CounterReference)
  | { kind: "card"; id: string }
  | { kind: "local"; name: string }
  | { kind: "context"; path: "previousCardId" | "thisCardId" | "mana" | "hp" | "turn" | "livingEnemies" }
  | { kind: "binary"; operator: "add" | "subtract" | "multiply" | "min" | "max"; left: Expression; right: Expression }
  | { kind: "compare"; operator: "eq" | "ne" | "lt" | "lte" | "gt" | "gte"; left: Expression; right: Expression };

export type Effect =
  | { op: "damage"; target: EffectTarget; targetCount?: number; amount: Expression; scalable?: boolean }
  | { op: "damageBonus"; element?: CardElement | "this"; category?: CardType | "this"; amount: Expression; scalable?: boolean; scope: "turn" | "combat" }
  | { op: "debuff"; id: DebuffId; target: EffectTarget; targetCount?: number; stacks: Expression; scalable?: boolean; bonusDamage?: Expression; damageScalable?: boolean }
  /** Legacy schema-v1 Freeze effects are migrated to a debuff block on load. */
  | { op: "freeze"; target: EffectTarget }
  | { op: "armor" | "heal" | "draw"; amount: Expression; scalable?: boolean }
  | { op: "mana"; amount: Expression; cap: number; scalable?: boolean }
  | { op: "addStatus"; id: "status.spell_power" | "status.mirror"; stacks: Expression; scalable?: boolean }
  | ({ op: "incrementCounter" | "subtractCounter" | "setCounter"; amount: number | Expression } & CounterReference)
  | ({ op: "resetCounter" } & CounterReference)
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

/** Create a numeric expression without sharing mutable blocks. */
export const literal = (value: number): Expression => ({ kind: "literal", value });

/** Create an independent block using the registered defaults. */
export function newEffect(op: Effect["op"]): Effect {
  // Factories keep nested branches and formulas independent across cards.
  return effectDefaults[op]();
}
