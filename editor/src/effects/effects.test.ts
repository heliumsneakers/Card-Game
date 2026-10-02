import { describe, expect, it } from "vitest";
import contract from "../../../tests/effect-contract.json";
import initial from "../../../game/content/content.json";
import { migrateDescriptions, renderDescription, validateContent } from "../content";
import { literal, type ContentDocument, type Effect } from "../model";
import { initialPreviewState, nextPreviewTurn, previewEffects } from "./preview";
import { replaceCard } from "./references";
import { recipes } from "./recipes";
import { effectDefaults } from "./defaults";
import { validateEffects } from "./validation";

/** Collect validation messages against a small catalog used by both languages. */
function errors(effects: unknown) {
  const issues: string[] = [];
  validateEffects(effects, "effects", { target: "multi" }, new Set(["card.test", "card.partner"]), (_path, message) => issues.push(message));
  return issues;
}

describe("shared effect contract", () => {
  for (const fixture of contract.valid) it(fixture.name, () => {
    expect(errors(fixture.effects)).toEqual([]);
    const source = initialPreviewState();
    source.statuses["status.spell_power"] = "spellPower" in fixture ? fixture.spellPower! : 0;
    let state = source;
    // Repeated resolves exercise persistent counters and fresh local scopes.
    for (let index = 0; index < ("repetitions" in fixture ? fixture.repetitions! : 1); index += 1) {
      const result = previewEffects({ id: "card.test", effects: fixture.effects as Effect[] }, state, "instanceId" in fixture ? fixture.instanceId : undefined);
      expect(result.error).toBeUndefined();
      state = result.state;
    }
    expect(state.enemies[0]).toBe(fixture.expectedHp);
    expect(state.counters).toEqual(fixture.expectedCounters);
    expect(source.enemies[0]).toBe(30);
    expect(source.counters).toEqual({});
  });
  for (const fixture of contract.invalid) it(`rejects ${fixture.name}`, () => {
    expect(errors(fixture.effects).length).toBeGreaterThan(0);
  });
});

describe("authoring workflows", () => {
  it("renders counter changes before later description values", () => {
    const effects: Effect[] = [{ op: "incrementCounter", id: "$thisCard", amount: 3 }, { op: "damage", target: "selectedEnemy", amount: { kind: "counter", id: "$thisCard" } }];
    expect(renderDescription("Deal {dmg=2} damage.", effects, "card.test")).toBe("Deal 3* damage.");
  });
  it("flags deleted card references and excessive nesting", () => {
    expect(errors([{ op: "incrementCounter", id: "card.deleted", amount: 1 }]).length).toBeGreaterThan(0);
    let value: import("../model").Expression = literal(1);
    for (let index = 0; index < 14; index += 1) value = { kind: "binary", operator: "add", left: value, right: literal(1) };
    expect(errors([{ op: "damage", target: "selectedEnemy", amount: value }]).length).toBeGreaterThan(0);
  });
  it("repairs explicit reader and writer references across nested branches", () => {
    const source = migrateDescriptions(structuredClone(initial) as ContentDocument);
    const old = source.cards[0];
    source.cards[1].effects = [{ op: "if", condition: { kind: "compare", operator: "eq", left: { kind: "context", path: "previousCardId" }, right: { kind: "card", id: old.id } }, then: [{ op: "incrementCounter", id: old.id, amount: 1 }], else: [{ op: "setLocal", name: "count", value: { kind: "counter", id: old.id } }] }];
    const renamed = replaceCard(source, old.id, { ...old, id: "card.spark", name: "Spark" });
    expect(JSON.stringify(renamed.cards.map((card) => card.effects))).not.toContain(old.id);
    expect(JSON.stringify(source.cards[1].effects)).toContain(old.id);
    expect(validateContent(renamed)).toEqual([]);
  });
  it("keeps combat state across turns and isolates physical copies", () => {
    const card = { id: "card.test", effects: [{ op: "incrementCounter", id: "$thisInstance", scope: "combat", amount: literal(1) }, { op: "incrementCounter", id: "$thisCard", amount: 1 }] as Effect[] };
    const first = previewEffects(card, initialPreviewState(), "1").state;
    const second = previewEffects(card, nextPreviewTurn(first), "2").state;
    expect(second.counters).toEqual({ "combat:@instance:1": 1, "combat:@instance:2": 1, "turn:card.test": 1 });
  });
  it("inserts independent recipes that validate and remain ordinary blocks", () => {
    for (const recipe of recipes) {
      const first = recipe.create();
      expect(errors(first)).toEqual([]);
      first.length = 0;
      expect(recipe.create().length).toBeGreaterThan(0);
    }
    for (const create of Object.values(effectDefaults)) expect(errors([create()])).toEqual([]);
  });
  it("lets one card build charges and another spend them", () => {
    const source = initialPreviewState();
    const build = { id: "card.test", effects: recipes.find((recipe) => recipe.id === "charge")!.create() };
    const spend = { id: "card.partner", effects: recipes.find((recipe) => recipe.id === "spend")!.create() };
    const charged = previewEffects(build, previewEffects(build, source).state).state;
    const result = previewEffects(spend, charged);
    expect(result.state.enemies[0]).toBe(24);
    expect(result.state.counters["combat:shared.charges"]).toBe(0);
  });
  it("reports resource and counter inputs in execution order", () => {
    const result = previewEffects({ id: "card.test", effects: [{ op: "incrementCounter", id: "$thisCard", amount: { kind: "context", path: "mana" } }, { op: "damage", target: "selectedEnemy", amount: { kind: "counter", id: "$thisCard" } }] }, initialPreviewState());
    expect(result.steps[0].inputs).toContain("mana = 2");
    expect(result.steps[1].inputs).toContain("turn:card.test = 2");
  });
});
