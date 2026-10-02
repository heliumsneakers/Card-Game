import type { CardDefinition, ContentDocument, Effect, Expression } from "../model";

/** Rewrite explicit card references without changing named shared counters. */
function renameExpression(value: Expression, previousId: string, nextId: string): Expression {
  // Formula trees may nest references below either operand.
  if (value.kind === "binary" || value.kind === "compare") return { ...value, left: renameExpression(value.left, previousId, nextId), right: renameExpression(value.right, previousId, nextId) };
  if ((value.kind === "counter" || value.kind === "card") && value.id === previousId) return { ...value, id: nextId };
  return value;
}

/** Visit both branches and each expression-bearing field during a rename. */
function renameEffects(effects: Effect[], previousId: string, nextId: string): Effect[] {
  // Shorthand references already follow the current card and need no rewrite.
  return effects.map((effect) => {
    if (effect.op === "if") return { ...effect, condition: renameExpression(effect.condition, previousId, nextId), then: renameEffects(effect.then, previousId, nextId), else: effect.else && renameEffects(effect.else, previousId, nextId) };
    let next = { ...effect };
    if ("id" in next && next.id === previousId) next = { ...next, id: nextId } as Effect as typeof next;
    if ("amount" in next && typeof next.amount !== "number") next = { ...next, amount: renameExpression(next.amount, previousId, nextId) };
    if (next.op === "debuff" && next.bonusDamage) next = { ...next, bonusDamage: renameExpression(next.bonusDamage, previousId, nextId) };
    if ("stacks" in next) next = { ...next, stacks: renameExpression(next.stacks, previousId, nextId) };
    if (next.op === "setLocal") next = { ...next, value: renameExpression(next.value, previousId, nextId) };
    return next;
  });
}

/** Update a card and repair references across the catalog in one state transition. */
export function replaceCard(content: ContentDocument, previousId: string, card: CardDefinition): ContentDocument {
  const cards = content.cards.map((current) => current.id === previousId ? card : current);
  // A conflicting draft ID is reported by validation rather than redirecting links.
  const canRename = previousId !== card.id && !content.cards.some((current) => current.id === card.id && current.id !== previousId);
  return { ...content, contentRevision: `draft-${Date.now()}`, cards: canRename ? cards.map((current) => ({ ...current, effects: renameEffects(current.effects, previousId, card.id) })) : cards };
}
