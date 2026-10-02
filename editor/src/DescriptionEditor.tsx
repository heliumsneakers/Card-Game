import { debuffRegistry } from "./effects/debuffs";
import { useRef } from "react";
import type { Effect, Expression } from "./model";

interface Props {
  description: string;
  effects: Effect[];
  onChange: (description: string) => void;
}

const tokenNames: Partial<Record<Effect["op"], string>> = {
  damage: "dmg",
  armor: "armor",
  heal: "heal",
  draw: "draw",
  mana: "mana",
  addStatus: "stacks",
};

const tokenLabels: Record<string, string> = {
  dmg: "Damage",
  armor: "Armor",
  heal: "Healing",
  draw: "Cards drawn",
  mana: "Mana",
  stacks: "Status stacks",
};

// Collect value-bearing blocks from both conditional outcomes.
function flattenEffects(effects: Effect[]): Effect[] {
  return effects.flatMap((effect) => effect.op === "if"
    ? [effect, ...flattenEffects(effect.then), ...flattenEffects(effect.else || [])]
    : [effect]);
}

// Estimate a baseline for a newly inserted value token.
function staticValue(expression: Expression, effects: Effect[], seen = new Set<string>()): number {
  if (expression.kind === "card") return 0;
  if (expression.kind === "literal") return expression.value;
  if (expression.kind === "counter" || expression.kind === "context") return 0;
  if (expression.kind === "local") {
    // Break cycles while following named calculation dependencies.
    if (seen.has(expression.name)) return 0;
    const setter = flattenEffects(effects).find((effect): effect is Extract<Effect, { op: "setLocal" }> =>
      effect.op === "setLocal" && effect.name === expression.name);
    if (!setter) return 0;
    seen.add(expression.name);
    return staticValue(setter.value, effects, seen);
  }
  const left = staticValue(expression.left, effects, seen);
  const right = staticValue(expression.right, effects, seen);
  if (expression.kind === "compare") return 0;
  if (expression.operator === "add") return left + right;
  if (expression.operator === "subtract") return left - right;
  if (expression.operator === "multiply") return left * right;
  if (expression.operator === "min") return Math.min(left, right);
  return Math.max(left, right);
}

// Find the numeric expression associated with a description token.
function effectExpression(effect: Effect): Expression | undefined {
  if (effect.op === "damage" || effect.op === "armor" || effect.op === "heal" || effect.op === "draw" || effect.op === "mana") return effect.amount;
  if (effect.op === "addStatus") return effect.stacks;
  if (effect.op === "debuff") return effect.stacks;
  return undefined;
}

// Insert editable live-value tokens into freely authored card prose.
export function DescriptionEditor({ description, effects, onChange }: Props) {
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const counters: Record<string, number> = {};
  // Keep token numbering stable across repeated operations.
  const blocks = flattenEffects(effects).flatMap((effect) => {
    // Registry tokens keep different debuff amounts from sharing occurrence numbers.
    const debuff = effect.op === "debuff" ? debuffRegistry.get(effect.id) : undefined;
    const baseName = debuff?.token || tokenNames[effect.op];
    const expression = effectExpression(effect);
    if (!baseName || !expression) return [];
    const entries = [{ token: baseName, label: debuff ? `${debuff.label} stacks` : tokenLabels[baseName], expression }];
    // Offer a second live token when this block includes recurring damage.
    if (debuff && effect.op === "debuff" && effect.bonusDamage) entries.push({ token: `${baseName}_damage`, label: `${debuff.label} bonus damage`, expression: effect.bonusDamage });
    return entries.map((entry) => {
      counters[entry.token] = (counters[entry.token] || 0) + 1;
      const name = counters[entry.token] === 1 ? entry.token : `${entry.token}${counters[entry.token]}`;
      return { name, label: entry.label, value: staticValue(entry.expression, effects) };
    });
  });

  // Insert a token at the caret and restore focus after rendering.
  const insertBlock = (block: typeof blocks[number]) => {
    const textarea = inputRef.current;
    const start = textarea?.selectionStart ?? description.length;
    const end = textarea?.selectionEnd ?? start;
    const token = `{${block.name}=${block.value}}`;
    onChange(`${description.slice(0, start)}${token}${description.slice(end)}`);
    // React updates the textarea before the caret is restored.
    requestAnimationFrame(() => {
      textarea?.focus();
      textarea?.setSelectionRange(start + token.length, start + token.length);
    });
  };

  return <div className="description-editor">
    <label><span>Card description</span><textarea ref={inputRef} rows={4} value={description} placeholder="Deal {dmg=2} damage to target." onChange={(event) => onChange(event.target.value)} /></label>
    <div className="description-help">Write the wording yourself. Insert a value block where a live effect number should appear.</div>
    <div className="description-palette" aria-label="Insert value block">
      {blocks.length > 0
        ? blocks.map((block) => <button type="button" key={block.name} onClick={() => insertBlock(block)}>+ {block.label}{block.name.match(/\d+$/)?.[0] || ""}</button>)
        : <span>Add a numeric effect below to make its value block available.</span>}
    </div>
  </div>;
}
