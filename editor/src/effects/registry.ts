import type { ComponentType } from "react";
import type { Effect } from "../model";
import { effectDefaults } from "./defaults";
import { AmountFields, ConditionalFields, CounterFields, DamageBonusFields, FreezeFields, LocalFields, StackFields, type FieldProps } from "./fields";

type EffectModule = { label: string; fields: ComponentType<FieldProps>; group: "Effects" | "Counters" | "Logic"; create: () => Effect; hidden?: boolean };

/** Bind the authoring UI to the same factories used by newEffect. */
function block(op: Effect["op"], label: string, fields: ComponentType<FieldProps>, group: EffectModule["group"] = "Effects", hidden = false): EffectModule {
  // Gameplay implementations stay in Lua; this registry owns authoring metadata.
  return { label, fields, group, create: effectDefaults[op], hidden };
}

export const effectRegistry: Record<Effect["op"], EffectModule> = {
  damage: block("damage", "Damage", AmountFields),
  damageBonus: block("damageBonus", "Damage Bonus", DamageBonusFields),
  debuff: block("debuff", "Debuffs", StackFields),
  freeze: block("freeze", "Legacy Freeze", FreezeFields, "Effects", true),
  armor: block("armor", "Gain Armor", AmountFields),
  heal: block("heal", "Heal", AmountFields),
  draw: block("draw", "Draw Cards", AmountFields),
  mana: block("mana", "Gain Mana", AmountFields),
  addStatus: block("addStatus", "Add Status", StackFields),
  incrementCounter: block("incrementCounter", "Increment Counter", CounterFields, "Counters"),
  subtractCounter: block("subtractCounter", "Subtract Counter", CounterFields, "Counters"),
  setCounter: block("setCounter", "Set Counter", CounterFields, "Counters"),
  resetCounter: block("resetCounter", "Reset Counter", CounterFields, "Counters"),
  setLocal: block("setLocal", "Set Value", LocalFields, "Logic"),
  if: block("if", "Conditional", ConditionalFields, "Logic"),
};
