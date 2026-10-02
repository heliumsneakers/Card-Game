import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { validateDebuffCatalog, generateDebuffs } from "./generate-debuffs.mjs";

const catalog = JSON.parse(await readFile(new URL("../game/content/debuffs.json", import.meta.url), "utf8"));

// Check the generated contract without rewriting the developer's working copy.
test("checked-in Lua metadata matches the shared source", async () => {
  await generateDebuffs(true);
});

test("metadata rejects ambiguous tokens, invalid defaults, and duplicate IDs", () => {
  const edits = [
    (value) => value.definitions.push(structuredClone(value.definitions[0])),
    (value) => { value.definitions[0].token = "dmg"; },
    (value) => { value.definitions[0].token = "freeze2"; },
    (value) => { value.definitions[0].defaultStacks = -1; },
    (value) => { value.definitions[0].color = [2, 0, 0]; },
    (value) => { value.defaultId = "debuff.missing"; },
    (value) => { value.definitions[0].legacyFlag = "alive"; },
  ];
  // Every failure uses a fresh catalog so one error cannot hide another.
  for (const edit of edits) {
    const candidate = structuredClone(catalog);
    edit(candidate);
    assert.throws(() => validateDebuffCatalog(candidate));
  }
});

test("a second debuff can reuse an existing behavior through metadata alone", () => {
  const candidate = structuredClone(catalog);
  const fixture = { ...candidate.definitions[0], id: "debuff.stun", token: "stun", label: "Stun" };
  delete fixture.legacyFlag;
  candidate.definitions.push(fixture);
  assert.equal(validateDebuffCatalog(candidate).definitions.length, 2);
  fixture.token = candidate.definitions[0].token;
  assert.throws(() => validateDebuffCatalog(candidate), /Duplicate debuff token/);
});
