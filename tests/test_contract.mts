// Reads the existing editor model without changing editor code or dependencies.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { renderDescription, enemyPower, validateContent } from "../editor/src/content.ts";

const fixture = JSON.parse(readFileSync(new URL("./fixtures/content_contract.json", import.meta.url), "utf8"));
const source = JSON.parse(readFileSync(new URL("../game/content/content.json", import.meta.url), "utf8"));
assert.deepEqual(validateContent(source), []);
for (const item of fixture.descriptions) assert.equal(renderDescription(item.description, item.effects), item.expected);
for (const item of fixture.enemies) assert.ok(Math.abs(enemyPower(item) - item.expectedPower) < 0.000001);
for (const edit of fixture.invalidEdits) {
  const document = structuredClone(source);
  document[edit.collection][0][edit.field] = edit.value;
  assert.ok(validateContent(document).length > 0);
}
console.log("shared TypeScript content contract passed");
