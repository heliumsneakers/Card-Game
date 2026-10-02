import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

const source = new URL("../game/content/debuffs.json", import.meta.url);
const destination = new URL("../game/src/domain/debuffs/definitions.lua", import.meta.url);
const reservedTokens = new Set(["dmg", "armor", "heal", "draw", "mana", "stacks"]);

/** Reject ambiguous IDs, tokens, and malformed authoring defaults before generation. */
export function validateDebuffCatalog(catalog) {
  assert(Array.isArray(catalog.definitions) && catalog.definitions.length, "Define at least one debuff.");
  const ids = new Set(), tokens = new Set(), flags = new Set();
  for (const definition of catalog.definitions) {
    // Tokens cannot end in digits because descriptions use numeric occurrence suffixes.
    assert(/^debuff\.[a-z][a-z0-9_]*$/.test(definition.id), "Invalid debuff ID.");
    assert(!ids.has(definition.id), `Duplicate debuff ID: ${definition.id}`);
    assert(/^[a-z][a-z_]*$/.test(definition.token) && !reservedTokens.has(definition.token) && !definition.token.endsWith("_damage"), "Invalid or reserved debuff token.");
    assert(!tokens.has(definition.token), `Duplicate debuff token: ${definition.token}`);
    for (const field of ["label", "stackLabel", "behavior", "actionText", "badge"]) {
      assert(typeof definition[field] === "string" && definition[field].trim() && !/[\x00-\x1f\x7f]/.test(definition[field]), `Invalid ${field}.`);
    }
    assert(Number.isSafeInteger(definition.defaultStacks) && definition.defaultStacks > 0, "Default stacks must be a positive whole number.");
    assert(typeof definition.scalable === "boolean", "scalable must be a boolean.");
    assert(Array.isArray(definition.color) && definition.color.length === 3 && definition.color.every((value) => Number.isFinite(value) && value >= 0 && value <= 1), "Color must contain three values from zero to one.");
    if (definition.legacyFlag !== undefined) {
      assert(definition.legacyFlag === "frozen" && !flags.has(definition.legacyFlag), "Only the existing frozen flag is supported.");
      flags.add(definition.legacyFlag);
    }
    ids.add(definition.id); tokens.add(definition.token);
  }
  assert(ids.has(catalog.defaultId), "Default debuff must be registered.");
  assert(catalog.legacyOperations && ids.has(catalog.legacyOperations.freeze), "Legacy Freeze must resolve to a registered debuff.");
  return catalog;
}

/** Serialize metadata as Lua tables so requiring game rules performs no disk reads. */
function lua(value, indent = "") {
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  // All metadata is declarative; functions belong in the runtime behavior registry.
  assert(value && typeof value === "object", "Unsupported registry value.");
  const next = `${indent}    `;
  const entries = Array.isArray(value) ? value.map((item) => `${next}${lua(item, next)}`)
    : Object.entries(value).map(([key, item]) => `${next}[${JSON.stringify(key)}] = ${lua(item, next)}`);
  return `{\n${entries.join(",\n")}\n${indent}}`;
}

/** Generate the checked-in Lua catalog or fail a read-only freshness check. */
export async function generateDebuffs(check = false) {
  const catalog = validateDebuffCatalog(JSON.parse(await readFile(source, "utf8")));
  const result = `-- Generated from game/content/debuffs.json; do not edit this copy.\n-- Regenerate with: npm run debuffs:generate\nreturn ${lua(catalog)}\n`;
  // CI checks freshness instead of silently fixing uncommitted generated files.
  if (check) assert.equal(await readFile(destination, "utf8"), result, "Debuff catalog is stale. Run npm run debuffs:generate.");
  else await writeFile(destination, result);
}

// Allow tests to import validation without invoking the command-line entry point.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await generateDebuffs(process.argv.includes("--check"));
}
