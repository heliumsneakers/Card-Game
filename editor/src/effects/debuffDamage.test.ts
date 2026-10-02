import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import fixtures from "../../../tests/fixtures/debuff_damage.json";
import initial from "../../../game/content/content.json";
import { DescriptionEditor } from "../DescriptionEditor";
import { renderDescription } from "../content";
import { literal, type ContentDocument, type Effect } from "../model";
import { StackFields } from "./fields";
import { initialPreviewState, previewEffects } from "./preview";
import { replaceCard } from "./references";
import { validateEffects } from "./validation";

/** Build a Freeze block with configurable duration and optional potency. */
function freeze(stacks: number, bonusDamage?: number): Effect {
  // Leave the field absent to exercise backward-compatible cards.
  return { op: "debuff", id: "debuff.freeze", target: "selectedEnemy", stacks: literal(stacks), ...(bonusDamage === undefined ? {} : { bonusDamage: literal(bonusDamage) }) };
}

describe("debuff bonus damage", () => {
  for (const fixture of fixtures) it(fixture.name, () => {
    const state = initialPreviewState();
    state.statuses["status.spell_power"] = fixture.spellPower;
    const effect = fixture.effect as Effect;
    const result = previewEffects({ id: "card.test", effects: [effect] }, state);
    expect(result.error).toBeUndefined();
    expect(result.state.debuffs[0][fixture.effect.id]).toBe(fixture.expectedStacks);
    expect(result.state.debuffDamage[0][fixture.effect.id]).toBe(fixture.expectedBonus);
    expect(result.state.enemies[0]).toBe(30); // Applying the debuff does not tick it.
    expect(state.debuffs[0]).toEqual({});
  });

  it("extends duration and retains the highest bonus", () => {
    const result = previewEffects({ id: "card.test", effects: [freeze(2, 4), freeze(1, 1), freeze(1), freeze(0, 99)] }, initialPreviewState());
    expect(result.state.debuffs[0]["debuff.freeze"]).toBe(4);
    expect(result.state.debuffDamage[0]["debuff.freeze"]).toBe(4);
    expect(result.steps[3].result).toContain("+4 damage per turn");
  });

  it("renders independent stack and damage controls and token buttons", () => {
    const effect = freeze(2, 3);
    const fields = renderToStaticMarkup(createElement(StackFields, { effect, onChange: () => {} }));
    expect(fields).toContain("Bonus damage per turn");
    expect(fields).toContain("Stacks affected by spell power");
    expect(fields).toContain("Bonus damage affected by spell power");
    const palette = renderToStaticMarkup(createElement(DescriptionEditor, { effects: [effect], description: "", onChange: () => {} }));
    expect(palette).toContain("Freeze bonus damage");
    expect(renderDescription("Freeze {freeze=0} with {freeze_damage=0} damage.", [effect])).toBe("Freeze 2* with 3* damage.");
    expect(renderDescription("{freeze_damage=0}/{freeze_damage2=0}", [freeze(1), freeze(1, 2), freeze(1, 5)])).toBe("2*/5*");
  });

  it("rejects invalid potency formulas and scaling flags", () => {
    for (const edit of [{ bonusDamage: literal(-1) }, { bonusDamage: { kind: "card", id: "card.test" } }, { damageScalable: "yes" }]) {
      const errors: string[] = [];
      validateEffects([{ ...freeze(1), ...edit }], "effects", { target: "enemy" }, new Set(["card.test"]), (_path, message) => errors.push(message));
      expect(errors.length).toBeGreaterThan(0);
    }
  });

  it("renames card references inside bonus damage formulas", () => {
    const source = structuredClone(initial) as ContentDocument;
    source.cards[0].effects = [{ op: "debuff", id: "debuff.freeze", target: "selectedEnemy", stacks: literal(1), bonusDamage: { kind: "counter", id: source.cards[0].id } }];
    const result = replaceCard(source, source.cards[0].id, { ...source.cards[0], id: "card.spark", name: "Spark" });
    expect(JSON.stringify(result.cards[0].effects)).toContain('"id":"card.spark"');
    expect(JSON.stringify(result.cards[0].effects)).not.toContain('"id":"card.firebolt"');
  });
});
