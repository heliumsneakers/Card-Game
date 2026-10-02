import { replaceCounterReference } from "./counterReferences";
import { debuffRegistry } from "./debuffs";
import { EffectEditor } from "../EffectEditor";
import { ExpressionEditor } from "../ExpressionEditor";
import { literal, type CardElement, type CardType, type Effect, type EffectTarget } from "../model";
import { CounterField } from "./CounterField";

export interface FieldProps { effect: Effect; onChange: (effect: Effect) => void }

/** Update a target mode and retain the chosen count only for group selection. */
function updateEnemyTarget(effect: Effect, target: EffectTarget, onChange: (effect: Effect) => void) {
  const next = Object.assign({}, effect, { target }) as Effect & { targetCount?: number };
  if (target === "selectedEnemies") next.targetCount = next.targetCount || 2;
  else delete next.targetCount;
  onChange(next);
}

/** Select an enemy group independently from the numeric amount. */
function TargetField({ value, onChange, allowMultiple = false, targetCount, onCountChange }: { value: EffectTarget; onChange: (target: EffectTarget) => void; allowMultiple?: boolean; targetCount?: number; onCountChange?: (count: number) => void }) {
  // Card-level target compatibility is checked by the content validator.
  return <>
    <label><span>Target</span><select value={value} onChange={(event) => onChange(event.target.value as EffectTarget)}><option value="selectedEnemy">Selected enemy</option>{allowMultiple && <option value="selectedEnemies">Choose multiple enemies</option>}<option value="otherEnemies">All other enemies</option><option value="allEnemies">All enemies</option></select></label>
    {allowMultiple && value === "selectedEnemies" && <label><span>Enemies to choose</span><input type="number" min="1" step="1" value={targetCount ?? 2} onChange={(event) => onCountChange?.(Number(event.target.value))} /></label>}
  </>;
}

/** Share spell-power controls across value-bearing effects. */
function ScalingField({ effect, onChange }: FieldProps) {
  // Counter changes and locals deliberately do not scale with spell power.
  if (!("scalable" in effect) && ["incrementCounter", "subtractCounter", "setCounter", "resetCounter", "setLocal", "if", "freeze"].includes(effect.op)) return null;
  return <label className="check"><input type="checkbox" checked={(effect as { scalable?: boolean }).scalable ?? false} onChange={(event) => onChange({ ...effect, scalable: event.target.checked } as Effect)} /> {effect.op === "debuff" ? "Stacks affected by spell power" : "Affected by spell power"}</label>;
}

/** Edit resource gains and damage through the common amount expression. */
export function AmountFields({ effect, onChange }: FieldProps) {
  if (!("amount" in effect) || typeof effect.amount === "number") return null;
  // Targets and caps remain optional capabilities of the selected operation.
  return <>
    {effect.op === "damage" && <TargetField value={effect.target} allowMultiple targetCount={effect.targetCount} onChange={(target) => updateEnemyTarget(effect, target, onChange)} onCountChange={(targetCount) => onChange({ ...effect, targetCount })} />}
    <ExpressionEditor value={effect.amount} onChange={(amount) => onChange({ ...effect, amount } as Effect)} label="Amount" />
    {effect.op === "mana" && <label><span>Mana cap</span><input type="number" min="0" value={effect.cap} onChange={(event) => onChange({ ...effect, cap: Number(event.target.value) })} /></label>}
    <ScalingField effect={effect} onChange={onChange} />
  </>;
}

/** Configure one cumulative bonus that the combat system applies to matching damage. */
export function DamageBonusFields({ effect, onChange }: FieldProps) {
  if (effect.op !== "damageBonus") return null;
  // “This” captures the card's current field; omitting a selector means every value.
  return <>
    <label><span>Element</span><select value={effect.element || "any"} onChange={(event) => {
      const { element: _element, ...rest } = effect;
      onChange(event.target.value === "any" ? rest : { ...effect, element: event.target.value as CardElement | "this" });
    }}><option value="any">Any element</option><option value="this">This card’s element</option><option value="fire">Fire</option><option value="ice">Ice</option><option value="nature">Nature</option><option value="earth">Earth</option><option value="arcane">Arcane</option></select></label>
    <label><span>Category</span><select value={effect.category || "any"} onChange={(event) => {
      const { category: _category, ...rest } = effect;
      onChange(event.target.value === "any" ? rest : { ...effect, category: event.target.value as CardType | "this" });
    }}><option value="any">Any category</option><option value="this">This card’s category</option><option value="DMG">Damage</option><option value="DEF">Defense</option><option value="HEAL">Healing</option><option value="UTIL">Utility</option></select></label>
    <ExpressionEditor value={effect.amount} onChange={(amount) => onChange({ ...effect, amount })} label="Bonus to add" />
    <ScalingField effect={effect} onChange={onChange} />
    <label><span>Duration</span><select value={effect.scope} onChange={(event) => onChange({ ...effect, scope: event.target.value as "turn" | "combat" })}><option value="turn">This turn</option><option value="combat">This combat</option></select></label>
    <small>Matching bonuses add together automatically. Play this again to increase the bonus.</small>
  </>;
}

/** Edit statuses and debuffs with their supported stack formulas. */
export function StackFields({ effect, onChange }: FieldProps) {
  if (effect.op !== "debuff" && effect.op !== "addStatus") return null;
  // Status identifiers are constrained to mechanics implemented by combat.
  return <>
    <label><span>{effect.op === "debuff" ? "Debuff" : "Status"}</span><select value={effect.id} onChange={(event) => onChange({ ...effect, id: event.target.value } as Effect)}>
      {effect.op === "debuff" ? Array.from(debuffRegistry.values()).map((definition) => <option key={definition.id} value={definition.id}>{definition.label}</option>) : <><option value="status.spell_power">Spell power</option><option value="status.mirror">Mirror copy</option></>}
    </select></label>
    {effect.op === "debuff" && <TargetField value={effect.target} allowMultiple targetCount={effect.targetCount} onChange={(target) => updateEnemyTarget(effect, target, onChange)} onCountChange={(targetCount) => onChange({ ...effect, targetCount })} />}
    <ExpressionEditor value={effect.stacks} onChange={(stacks) => onChange({ ...effect, stacks })} label={effect.op === "debuff" ? debuffRegistry.get(effect.id)?.stackLabel || "Stacks" : "Stacks"} />
    <ScalingField effect={effect} onChange={onChange} />
    {effect.op === "debuff" && <DebuffDamageFields effect={effect} onChange={onChange} />}
  </>;
}

/** Configure recurring damage independently from the debuff's duration formula. */
function DebuffDamageFields({ effect, onChange }: FieldProps) {
  if (effect.op !== "debuff") return null;
  // Omitting the optional fields preserves existing card behavior exactly.
  return <>
    <label className="check"><input type="checkbox" checked={effect.bonusDamage !== undefined} onChange={(event) => {
      const { bonusDamage: _damage, damageScalable: _scaling, ...base } = effect;
      onChange(event.target.checked ? { ...base, bonusDamage: literal(1), damageScalable: false } : base);
    }} /> Add bonus damage each turn</label>
    {effect.bonusDamage !== undefined && <>
      <ExpressionEditor value={effect.bonusDamage} onChange={(bonusDamage) => onChange({ ...effect, bonusDamage })} label="Bonus damage per turn" />
      <label className="check"><input type="checkbox" checked={effect.damageScalable ?? false} onChange={(event) => onChange({ ...effect, damageScalable: event.target.checked })} /> Bonus damage affected by spell power</label>
      <small>Deals extra damage when you end your turn, before enemies attack. Calculated when applied; reapplying keeps the higher bonus until the debuff expires.</small>
    </>}
  </>;
}

/** Preserve the target control for imported legacy Freeze blocks. */
export function FreezeFields({ effect, onChange }: FieldProps) {
  // Migration normally replaces these blocks before editing.
  return effect.op === "freeze" ? <TargetField value={effect.target} onChange={(target) => onChange({ ...effect, target })} /> : null;
}

/** Edit counter operations while accepting legacy numeric increments. */
export function CounterFields({ effect, onChange }: FieldProps) {
  if (effect.op !== "incrementCounter" && effect.op !== "subtractCounter" && effect.op !== "setCounter" && effect.op !== "resetCounter") return null;
  // Numeric legacy amounts become expressions only when the author edits them.
  return <><CounterField value={effect} onChange={(reference) => onChange(replaceCounterReference(effect, reference))} />
    {effect.op !== "resetCounter" && <ExpressionEditor value={typeof effect.amount === "number" ? literal(effect.amount) : effect.amount} onChange={(amount) => onChange({ ...effect, amount })} label={effect.op === "setCounter" ? "Value" : "Amount"} />}
    <small>Counters stay at or above zero. Earlier blocks affect later formulas.</small>
  </>;
}

/** Name a calculation that subsequent blocks can reuse. */
export function LocalFields({ effect, onChange }: FieldProps) {
  // Locals are scoped to a single resolution, including its chosen branches.
  return effect.op === "setLocal" ? <><label><span>Value name</span><input value={effect.name} onChange={(event) => onChange({ ...effect, name: event.target.value })} /></label><ExpressionEditor value={effect.value} onChange={(value) => onChange({ ...effect, value })} label="Formula" /></> : null;
}

/** Expose both conditional branches using the same nested block editor. */
export function ConditionalFields({ effect, onChange }: FieldProps) {
  if (effect.op !== "if") return null;
  // Empty branches are valid and mean that no action happens for that outcome.
  return <><ExpressionEditor value={effect.condition} onChange={(condition) => onChange({ ...effect, condition })} label="If" condition />
    <div className="nested-effects"><b>Then</b><EffectEditor effects={effect.then} onChange={(then) => onChange({ ...effect, then })} nested /></div>
    <div className="nested-effects"><b>Otherwise</b><EffectEditor effects={effect.else || []} onChange={(otherwise) => onChange({ ...effect, else: otherwise })} nested /></div>
  </>;
}
