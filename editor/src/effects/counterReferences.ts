import type { CardDefinition, CounterOwner, CounterReference, ExplicitCounterReference } from "../model";

// These lists keep owner controls and validation on the same vocabulary.
export const counterElements = ["fire", "ice", "nature", "earth", "arcane"] as const;
export const counterCategories = ["DMG", "DEF", "HEAL", "UTIL"] as const;
export type CounterCard = Pick<CardDefinition, "id"> & Partial<Pick<CardDefinition, "element" | "type">>;

/** Convert old IDs into explicit ownership without changing their storage keys. */
export function normalizeCounter(reference: CounterReference): ExplicitCounterReference {
  if (reference.owner) return reference;
  const scope = reference.scope || "turn";
  const id = reference.id;
  // Legacy card counters use the default slot; shared names already identify their slot.
  if (id === "$thisCard") return { owner: { kind: "this" }, name: "default", scope };
  if (id === "$thisInstance") return { owner: { kind: "instance" }, name: "default", scope };
  if (id.startsWith("card.")) return { owner: { kind: "card", cardId: id }, name: "default", scope };
  return { owner: { kind: "shared" }, name: id, scope };
}

/** Choose complete owner defaults when the author changes ownership mode. */
export function defaultCounterOwner(kind: CounterOwner["kind"], firstCardId?: string): CounterOwner {
  switch (kind) {
    case "card": return { kind, cardId: firstCardId || "card.missing" };
    case "element": return { kind, element: "this" };
    case "category": return { kind, category: "this" };
    default: return { kind };
  }
}

/** Resolve a reference identically to Lua; group counters never alias plain shared names. */
export function resolveCounterId(reference: CounterReference, card: CounterCard, instanceId: string): string {
  const { owner, name } = normalizeCounter(reference);
  let base: string;
  switch (owner.kind) {
    case "shared": return name;
    case "this": base = card.id; break;
    case "card": base = owner.cardId; break;
    case "instance": base = `@instance:${instanceId}`; break;
    case "element": {
      const element = owner.element === "this" ? card.element : owner.element;
      if (!element) throw new Error("Current card element is required for this counter.");
      base = `@element:${element}`;
      break;
    }
    case "category": {
      const category = owner.category === "this" ? card.type : owner.category;
      if (!category) throw new Error("Current card category is required for this counter.");
      base = `@category:${category}`;
      break;
    }
  }
  // Length-prefix the base in UTF-8 bytes to match Lua and avoid delimiter collisions.
  if (name === "default") return base;
  return `@named:${new TextEncoder().encode(base).length}:${base}:${name}`;
}

/** Describe ownership without exposing internal storage-key syntax to authors. */
export function counterLabel(reference: CounterReference): string {
  const { owner, name } = normalizeCounter(reference);
  switch (owner.kind) {
    case "this": return `This card / ${name}`;
    case "instance": return `This copy / ${name}`;
    case "card": return `${owner.cardId} / ${name}`;
    case "element": return `${owner.element === "this" ? "This card’s element" : owner.element} / ${name}`;
    case "category": return `${owner.category === "this" ? "This card’s category" : owner.category} / ${name}`;
    case "shared": return name;
  }
}

/** Validate explicit or legacy ownership before either runtime resolves a key. */
export function counterIssues(value: Record<string, unknown>, cardIds: Set<string>): string[] {
  const errors: string[] = [];
  if (value.scope !== undefined && value.scope !== "turn" && value.scope !== "combat") errors.push("Choose turn or combat lifetime.");
  if (value.owner === undefined) {
    const id = value.id;
    if (typeof id !== "string" || !id.trim() || id.startsWith("@") || (id.startsWith("$") && id !== "$thisCard" && id !== "$thisInstance")) errors.push("Choose a counter owner or a non-empty shared name.");
    if (typeof id === "string" && id.startsWith("card.") && !cardIds.has(id)) errors.push("Referenced card does not exist.");
    if (value.name !== undefined) errors.push("Named counters require an explicit owner.");
    return errors;
  }
  // Reject mixed formats instead of guessing which identity should win.
  if (value.id !== undefined) errors.push("Use an owner or a legacy ID, not both.");
  if (typeof value.name !== "string" || !value.name.trim()) errors.push("Counter name must not be empty.");
  const owner = value.owner as Record<string, unknown> | null;
  if (!owner || typeof owner !== "object" || Array.isArray(owner)) return [...errors, "Choose a valid counter owner."];
  switch (owner.kind) {
    case "this": case "instance": break;
    case "card": if (typeof owner.cardId !== "string" || !cardIds.has(owner.cardId)) errors.push("Referenced card does not exist."); break;
    case "element": if (owner.element !== "this" && !counterElements.some((element) => element === owner.element)) errors.push("Choose a valid element."); break;
    case "category": if (owner.category !== "this" && !counterCategories.some((category) => category === owner.category)) errors.push("Choose a valid category."); break;
    case "shared":
      // Reserved prefixes belong to card and internal keys, including old content.
      if (typeof value.name === "string" && /^(?:@|\$|card\.)/.test(value.name)) errors.push("Shared names cannot use reserved prefixes.");
      break;
    default: errors.push("Choose a valid counter owner.");
  }
  return errors;
}

/** Replace reference fields without retaining a stale legacy ID or losing effect data. */
export function replaceCounterReference<T extends CounterReference>(value: T, reference: CounterReference): T {
  const { id: _id, owner: _owner, name: _name, scope: _scope, ...rest } = value;
  return { ...rest, ...reference } as T;
}
