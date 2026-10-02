import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import fixtures from "../../../tests/fixtures/counter_owners.json";
import initial from "../../../game/content/content.json";
import { AuthoringCards } from "../AuthoringContext";
import { describeCard } from "../content";
import { literal, type CardDefinition, type ContentDocument, type CounterReference, type Effect } from "../model";
import { CounterField } from "./CounterField";
import { counterIssues, defaultCounterOwner, normalizeCounter, replaceCounterReference, resolveCounterId } from "./counterReferences";
import { counterKey, initialPreviewState, nextPreviewTurn, previewEffects } from "./preview";
import { replaceCard } from "./references";
import { validateEffects } from "./validation";

const ids = new Set(["card.firebolt", "card.fireball"]);

/** Create a minimal card for cross-card counter resolutions. */
function card(id: string, element: CardDefinition["element"], type: CardDefinition["type"], effects: Effect[]): CardDefinition {
  return { ...(initial.cards[0] as CardDefinition), id, element, type, effects, description: "Deal {dmg=0} damage." };
}

/** Increment a shared slot before reading it into damage in the same resolution. */
function effects(reference: CounterReference): Effect[] {
  return [
    { op: "incrementCounter", ...reference, amount: literal(1) },
    { op: "damage", target: "selectedEnemy", amount: { kind: "counter", ...reference } },
  ];
}

describe("counter ownership contract", () => {
  // Shared fixtures catch disagreement between Lua storage keys and the editor.
  for (const fixture of fixtures.valid) it(fixture.name, () => {
    const reference = fixture.reference as CounterReference;
    const definition = fixture.card as CardDefinition;
    expect(counterIssues(reference as unknown as Record<string, unknown>, ids)).toEqual([]);
    expect(resolveCounterId(reference, definition, fixture.instanceId)).toBe(fixture.expected);
    expect(resolveCounterId(normalizeCounter(reference), definition, fixture.instanceId)).toBe(fixture.expected);
    expect(counterKey(reference, definition, fixture.instanceId)).toBe(`turn:${fixture.expected}`);
  });

  it("rejects malformed ownership on both reads and writes", () => {
    for (const reference of fixtures.invalid) {
      for (const effect of [{ op: "incrementCounter", ...reference, amount: literal(1) }, { op: "damage", target: "selectedEnemy", amount: { kind: "counter", ...reference } }]) {
        const errors: string[] = [];
        validateEffects([effect], "effects", { target: "enemy" }, ids, (_path, message) => errors.push(message));
        expect(errors.length).toBeGreaterThan(0);
      }
    }
  });

  it("shares by element across cards but isolates elements, names, categories and lifetimes", () => {
    const reference: CounterReference = { owner: { kind: "element", element: "this" }, name: "power" };
    const firebolt = card("card.firebolt", "fire", "DMG", effects(reference));
    const fireball = card("card.fireball", "fire", "DMG", effects(reference));
    let result = previewEffects(firebolt, initialPreviewState());
    result = previewEffects(fireball, result.state);
    expect(result.error).toBeUndefined();
    expect(result.state.enemies[0]).toBe(27); // The two cards read 1, then 2.
    const ice = previewEffects(card("card.ice", "ice", "DMG", effects(reference)), result.state);
    expect(ice.state.enemies[0]).toBe(26);
    const named = previewEffects(card("card.fireball", "fire", "DMG", effects({ ...reference, name: "casts" })), result.state);
    expect(named.state.enemies[0]).toBe(26);
    const category: CounterReference = { owner: { kind: "category", category: "this" }, name: "power", scope: "combat" };
    result = previewEffects(card("card.firebolt", "fire", "DMG", effects(category)), result.state);
    result = previewEffects(card("card.ice", "ice", "DMG", effects(category)), result.state);
    expect(result.state.enemies[0]).toBe(24); // Category sharing crosses element boundaries.
    const next = nextPreviewTurn(result.state);
    expect(Object.keys(next.counters)).toEqual([counterKey(category, firebolt, "1")]);
    expect(next.counters[counterKey(category, firebolt, "1")]).toBe(2);
    expect(previewEffects(firebolt, next).state.enemies[0]).toBe(23);
    expect(initialPreviewState().counters).toEqual({});
  });

  it("supports set, subtract, and reset on the same explicit group", () => {
    const reference: CounterReference = { owner: { kind: "element", element: "fire" }, name: "power" };
    const definition = card("card.firebolt", "fire", "DMG", [
      { op: "setCounter", ...reference, amount: literal(5) },
      { op: "subtractCounter", ...reference, amount: literal(2) },
      { op: "damage", target: "selectedEnemy", amount: { kind: "counter", ...reference } },
      { op: "resetCounter", ...reference },
    ]);
    const result = previewEffects(definition, initialPreviewState());
    expect(result.error).toBeUndefined();
    expect(result.state.enemies[0]).toBe(27);
    expect(result.state.counters[counterKey(reference, definition, "1")]).toBe(0);
  });

  it("uses group metadata in ordered descriptions without mutating the source", () => {
    const definition = card("card.firebolt", "fire", "DMG", effects({ owner: { kind: "element", element: "this" }, name: "power" }));
    const before = structuredClone(definition);
    expect(describeCard(definition)).toBe("Deal 1* damage.");
    expect(definition).toEqual(before);
  });

  it("upgrades edits without retaining stale identity fields or dropping effect data", () => {
    const original: Effect = { op: "incrementCounter", id: "$thisCard", scope: "combat", amount: literal(3) };
    const updated = replaceCounterReference(original, { ...normalizeCounter(original), owner: defaultCounterOwner("element") });
    expect(updated).toEqual({ op: "incrementCounter", owner: { kind: "element", element: "this" }, name: "default", scope: "combat", amount: literal(3) });
    expect(defaultCounterOwner("card", "card.fireball")).toEqual({ kind: "card", cardId: "card.fireball" });
    expect(resolveCounterId(original, { id: "card.firebolt" }, "1")).toBe(resolveCounterId(normalizeCounter(original), { id: "card.firebolt" }, "1"));
  });

  it("renames explicit card owners in nested reads and writes", () => {
    const source = structuredClone(initial) as ContentDocument;
    const reference: CounterReference = { owner: { kind: "card", cardId: source.cards[0].id }, name: "power" };
    source.cards[1].effects = [{ op: "if", condition: { kind: "compare", operator: "eq", left: literal(1), right: literal(1) }, then: effects(reference), else: [{ op: "resetCounter", ...reference }] }];
    const renamed = replaceCard(source, source.cards[0].id, { ...source.cards[0], id: "card.spark", name: "Spark" });
    expect(JSON.stringify(renamed.cards[1].effects)).not.toContain('"cardId":"card.firebolt"');
    expect(JSON.stringify(renamed.cards[1].effects).match(/"cardId":"card.spark"/g)).toHaveLength(3);
  });

  it("renders readable controls for all ownership modes", () => {
    for (const kind of ["this", "instance", "card", "element", "category", "shared"] as const) {
      const value: CounterReference = { owner: defaultCounterOwner(kind, "card.firebolt"), name: "power" };
      const markup = renderToStaticMarkup(createElement(AuthoringCards.Provider, { value: initial.cards as CardDefinition[] }, createElement(CounterField, { value, onChange: () => {} })));
      expect(markup).toContain("Cards sharing an element");
      expect(markup).toContain("Cards sharing a category");
      expect(markup).toContain("Counter name");
      if (kind === "element") expect(markup).toContain("Element group");
      if (kind === "category") expect(markup).toContain("Category group");
    }
  });
});
