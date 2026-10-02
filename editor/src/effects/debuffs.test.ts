import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { StackFields } from "./fields";
import { DescriptionEditor } from "../DescriptionEditor";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fixture from "../../../tests/fixtures/debuff_registry.json";
import initial from "../../../game/content/content.json";
import { migrateDescriptions, renderDescription, validateContent } from "../content";
import { literal, newEffect, type ContentDocument, type Effect } from "../model";
import { debuffRegistry, defaultDebuffId, getDebuff, type DebuffDefinition } from "./debuffs";
import { initialPreviewState, previewEffects } from "./preview";
import { validateEffects } from "./validation";

// Test-only metadata proves new IDs reach consumers without editing their switches.
beforeEach(() => { debuffRegistry.set(fixture.definition.id, fixture.definition as DebuffDefinition); });
afterEach(() => { debuffRegistry.delete(fixture.definition.id); });

describe("debuff registry", () => {
  it("renders registered dropdown options, stack labels, and token buttons", () => {
    // Render the real components so registry wiring is checked beyond data helpers.
    const effect = fixture.effects[1] as Effect;
    const fields = renderToStaticMarkup(createElement(StackFields, { effect, onChange: () => {} }));
    expect(fields).toContain('value="debuff.test_stun"');
    expect(fields).toContain("Test Stun");
    expect(fields).toContain("Turns stunned");
    const description = renderToStaticMarkup(createElement(DescriptionEditor, { effects: fixture.effects as Effect[], description: "", onChange: () => {} }));
    expect(description).toContain("Test Stun stacks");
    expect(description).toContain("Freeze stacks");
  });
  it("drives default blocks from catalog metadata", () => {
    const definition = getDebuff(defaultDebuffId);
    expect(newEffect("debuff")).toEqual({ op: "debuff", id: definition.id, target: "selectedEnemy", stacks: literal(definition.defaultStacks), scalable: definition.scalable });
    expect(getDebuff(fixture.definition.id).label).toBe("Test Stun");
  });

  it("validates registered IDs and rejects unknown IDs", () => {
    const issues: string[] = [];
    validateEffects(fixture.effects, "effects", { target: "enemy" }, new Set(), (_path, message) => issues.push(message));
    expect(issues).toEqual([]);
    validateEffects([{ op: "debuff", id: "debuff.missing", target: "selectedEnemy", stacks: literal(1) }], "effects", { target: "enemy" }, new Set(), (_path, message) => issues.push(message));
    expect(issues).toContain("Unsupported debuff.");
  });

  it("keeps different debuffs independent in previews and description tokens", () => {
    const effects = fixture.effects as Effect[];
    const source = initialPreviewState();
    const result = previewEffects({ id: "card.test", effects }, source);
    expect(result.error).toBeUndefined();
    expect(result.state.debuffs[0]).toEqual({ "debuff.freeze": 3, "debuff.test_stun": 3 });
    expect(result.state.debuffs[1]).toEqual({});
    expect(source.debuffs[0]).toEqual({});
    expect(result.steps[1].result).toContain("Test Stun: 0 → 3");
    expect(renderDescription(fixture.description, effects)).toBe(fixture.expectedDescription);
  });

  it("uses registry labels and numbered tokens when migrating descriptions", () => {
    const content = structuredClone(initial) as ContentDocument;
    content.cards[0].effects = fixture.effects as Effect[];
    delete (content.cards[0] as Partial<typeof content.cards[number]>).description;
    const migrated = migrateDescriptions(content);
    expect(migrated.cards[0].description).toBe("Apply {freeze=1} Freeze to target. Apply {test_stun=3} Test Stun to target. Apply {freeze2=2} Freeze to target.");
    expect(validateContent(migrated)).toEqual([]);
  });

  it("preserves legacy Freeze and scales stacks only when requested", () => {
    const source = initialPreviewState();
    source.statuses["status.spell_power"] = 1;
    source.enemies[1] = 0;
    const result = previewEffects({ id: "card.test", effects: [
      { op: "freeze", target: "allEnemies" },
      { op: "debuff", id: "debuff.test_stun", target: "allEnemies", stacks: literal(2), scalable: true },
    ] }, source);
    expect(result.state.debuffs[0]).toEqual({ "debuff.freeze": 1, "debuff.test_stun": 4 });
    expect(result.state.debuffs[1]).toEqual({});
  });
});
