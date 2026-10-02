import catalog from "../../../game/content/debuffs.json" with { type: "json" };

export type DebuffId = `debuff.${string}`;
export interface DebuffDefinition {
  id: DebuffId; label: string; token: string; stackLabel: string;
  defaultStacks: number; scalable: boolean; behavior: string;
  actionText: string; badge: string; color: number[]; legacyFlag?: string;
}

// JSON is the source of truth; Lua consumes its generated, checked-in counterpart.
export const debuffRegistry = new Map<string, DebuffDefinition>(catalog.definitions.map((definition) => [definition.id, definition as DebuffDefinition]));
export const defaultDebuffId = catalog.defaultId as DebuffId;
export const legacyFreezeId = catalog.legacyOperations.freeze as DebuffId;

/** Resolve metadata centrally so labels and defaults never depend on a switch. */
export function getDebuff(id: string): DebuffDefinition {
  const definition = debuffRegistry.get(id);
  // Unknown IDs fail before an unsupported effect reaches the preview.
  if (!definition) throw new Error(`Unknown debuff: ${id}`);
  return definition;
}

/** Match a description token to one debuff rather than every debuff block. */
export function debuffForToken(token: string): DebuffDefinition | undefined {
  // Occurrence suffixes are removed by the description renderer before lookup.
  return Array.from(debuffRegistry.values()).find((definition) => definition.token === token);
}

/** Resolve the separate damage token attached to a registered debuff. */
export function debuffForDamageToken(token: string): DebuffDefinition | undefined {
  // Reserve the _damage suffix for potency rather than duration.
  return Array.from(debuffRegistry.values()).find((definition) => `${definition.token}_damage` === token);
}
