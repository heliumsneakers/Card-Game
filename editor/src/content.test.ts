import { describe, expect, it } from "vitest";
import initial from "../../game/content/content.json";
import { contentId, describeCard, deterministicJson, encounterCandidates, enemyPower, migrateDescriptions, removeCard, renderDescription, validateContent } from "./content";
import type { CardDefinition, ContentDocument } from "./model";

describe("content model", () => {
  it("derives stable IDs from names, including an empty editing state", () => {
    expect(contentId("card", "Fire Elemental")).toBe("card.fire_elemental");
    expect(contentId("card", "  Frost-Bite!  ")).toBe("card.frost_bite");
    expect(contentId("card", "")).toBe("card.untitled");
  });

  it("accepts the migrated catalog", () => {
    expect(validateContent(initial as ContentDocument)).toEqual([]);
    expect((initial as ContentDocument).cards.find((card) => card.id === "card.mend")?.element).toBe("nature");
  });

  it("calculates enemy power and room candidates from designer settings", () => {
    const content = migrateDescriptions(initial as ContentDocument);
    const goblin = content.enemies.find((enemy) => enemy.id === "enemy.goblin")!;
    const skeleton = content.enemies.find((enemy) => enemy.id === "enemy.skeleton")!;
    expect(enemyPower(goblin)).toBeCloseTo(1, 4);
    const roomThree = content.roomCurve.find((room) => room.room === 3)!;
    const candidates = encounterCandidates(content, roomThree);
    const mixed = candidates.find((candidate) => candidate.enemyIds.join("|") === "enemy.goblin|enemy.skeleton");
    expect(mixed?.power).toBeCloseTo((enemyPower(goblin) + enemyPower(skeleton)) * 1.5, 4);
    expect(candidates.flatMap((candidate) => candidate.enemyIds)).not.toContain("enemy.bone_lord");
  });

  it("assigns visual elements when loading older drafts", () => {
    const older = JSON.parse(JSON.stringify(initial)) as ContentDocument;
    delete (older.cards.find((card) => card.id === "card.arcane_ward") as unknown as { element?: string }).element;
    delete (older.cards.find((card) => card.id === "card.arcane_intellect") as unknown as { element?: string }).element;
    const migrated = migrateDescriptions(older);
    expect(migrated.cards.find((card) => card.id === "card.arcane_ward")?.element).toBe("earth");
    expect(migrated.cards.find((card) => card.id === "card.arcane_intellect")?.element).toBe("arcane");
  });

  it("generates readable text from blocks", () => {
    const card: CardDefinition = {
      id: "card.echo_bolt", name: "Echo Bolt", cost: 1, type: "DMG", element: "arcane", target: "enemy", enabled: true,
      description: "If this follows itself, deal {dmg=1} damage.",
      availability: { startingDeck: 0, shop: true, copyLimit: 3 },
      effects: [{ op: "if", condition: { kind: "compare", operator: "eq", left: { kind: "context", path: "previousCardId" }, right: { kind: "context", path: "thisCardId" } }, then: [{ op: "damage", target: "selectedEnemy", amount: { kind: "literal", value: 1 } }] }],
    };
    expect(describeCard(card)).toBe("If this follows itself, deal 1 damage.");
  });

  it("renders authored prose and marks calculated values", () => {
    expect(renderDescription("Deal {dmg=2} damage. Then gain {armor=2+1} Armor.")).toBe("Deal 2 damage. Then gain 3* Armor.");
    const changed: CardDefinition = {
      id: "card.changed", name: "Changed", cost: 1, type: "DMG", element: "fire", target: "enemy", enabled: true,
      description: "Deal {dmg=2} damage.", availability: { startingDeck: 0, shop: true, copyLimit: 3 },
      effects: [{ op: "damage", target: "selectedEnemy", amount: { kind: "literal", value: 3 } }],
    };
    expect(describeCard(changed)).toBe("Deal 3* damage.");
  });

  it("exports a stable final newline", () => {
    expect(deterministicJson(initial as ContentDocument).endsWith("\n")).toBe(true);
  });

  it("removes a card without mutating the original catalog", () => {
    const source = initial as ContentDocument;
    const removed = removeCard(source, "card.fireball");
    expect(removed.cards.some((card) => card.id === "card.fireball")).toBe(false);
    expect(source.cards.some((card) => card.id === "card.fireball")).toBe(true);
    expect(removed.cards).toHaveLength(source.cards.length - 1);
  });
});
