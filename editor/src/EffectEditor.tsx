import { ExpressionEditor } from "./ExpressionEditor";
import { newEffect, type Effect, type EffectTarget, type Expression } from "./model";

interface Props { effects: Effect[]; onChange: (effects: Effect[]) => void; nested?: boolean }

const blockLabels: Record<Effect["op"], string> = {
  damage: "Damage", debuff: "Debuffs", freeze: "Legacy Freeze", armor: "Gain Armor", heal: "Heal", draw: "Draw Cards",
  mana: "Gain Mana", addStatus: "Add Status", incrementCounter: "Increment Counter", setLocal: "Set Value", if: "Conditional",
};

function TargetField({ value, onChange }: { value: EffectTarget; onChange: (target: EffectTarget) => void }) {
  return <label><span>Target</span><select value={value} onChange={(event) => onChange(event.target.value as EffectTarget)}><option value="selectedEnemy">Selected enemy</option><option value="otherEnemies">All other enemies</option><option value="allEnemies">All enemies</option></select></label>;
}

function EffectFields({ effect, onChange }: { effect: Effect; onChange: (effect: Effect) => void }) {
  if (effect.op === "damage") return <>
    <TargetField value={effect.target} onChange={(target) => onChange({ ...effect, target })} />
    <ExpressionEditor value={effect.amount} onChange={(amount) => onChange({ ...effect, amount })} label="Damage" />
    <label className="check"><input type="checkbox" checked={effect.scalable ?? false} onChange={(event) => onChange({ ...effect, scalable: event.target.checked })} /> Affected by spell power</label>
  </>;
  if (effect.op === "debuff") return <>
    <label><span>Debuff</span><select value={effect.id} onChange={(event) => onChange({ ...effect, id: event.target.value as typeof effect.id })}><option value="debuff.freeze">Freeze</option></select></label>
    <TargetField value={effect.target} onChange={(target) => onChange({ ...effect, target })} />
    <ExpressionEditor value={effect.stacks} onChange={(stacks) => onChange({ ...effect, stacks })} label="Stacks / turns" />
    <label className="check"><input type="checkbox" checked={effect.scalable ?? false} onChange={(event) => onChange({ ...effect, scalable: event.target.checked })} /> Affected by spell power</label>
  </>;
  if (effect.op === "freeze") return <TargetField value={effect.target} onChange={(target) => onChange({ ...effect, target })} />;
  if (effect.op === "armor" || effect.op === "heal" || effect.op === "draw") return <>
    <ExpressionEditor value={effect.amount} onChange={(amount) => onChange({ ...effect, amount } as Effect)} label="Amount" />
    <label className="check"><input type="checkbox" checked={effect.scalable ?? false} onChange={(event) => onChange({ ...effect, scalable: event.target.checked } as Effect)} /> Affected by spell power</label>
  </>;
  if (effect.op === "mana") return <>
    <ExpressionEditor value={effect.amount} onChange={(amount) => onChange({ ...effect, amount })} label="Amount" />
    <label><span>Mana cap</span><input type="number" min="0" value={effect.cap} onChange={(event) => onChange({ ...effect, cap: Number(event.target.value) })} /></label>
    <label className="check"><input type="checkbox" checked={effect.scalable ?? false} onChange={(event) => onChange({ ...effect, scalable: event.target.checked })} /> Affected by spell power</label>
  </>;
  if (effect.op === "addStatus") return <>
    <label><span>Status</span><select value={effect.id} onChange={(event) => onChange({ ...effect, id: event.target.value as typeof effect.id })}><option value="status.spell_power">Spell power</option><option value="status.mirror">Mirror copy</option></select></label>
    <ExpressionEditor value={effect.stacks} onChange={(stacks) => onChange({ ...effect, stacks })} label="Stacks" />
    <label className="check"><input type="checkbox" checked={effect.scalable ?? false} onChange={(event) => onChange({ ...effect, scalable: event.target.checked })} /> Affected by spell power</label>
  </>;
  if (effect.op === "incrementCounter") return <><label><span>Counter</span><input value={effect.id} onChange={(event) => onChange({ ...effect, id: event.target.value })} /></label><label><span>Add</span><input type="number" min="1" value={effect.amount} onChange={(event) => onChange({ ...effect, amount: Number(event.target.value) })} /></label></>;
  if (effect.op === "setLocal") return <><label><span>Value name</span><input value={effect.name} onChange={(event) => onChange({ ...effect, name: event.target.value })} /></label><ExpressionEditor value={effect.value} onChange={(value) => onChange({ ...effect, value })} label="Formula" /></>;
  const conditional = effect as Extract<Effect, { op: "if" }>;
  return <>
    <ExpressionEditor value={conditional.condition} onChange={(condition: Expression) => onChange({ ...conditional, condition })} label="If" condition />
    <div className="nested-effects"><b>Then</b><EffectEditor effects={conditional.then} onChange={(then) => onChange({ ...conditional, then })} nested /></div>
  </>;
}

export function EffectEditor({ effects, onChange, nested = false }: Props) {
  const update = (index: number, effect: Effect) => onChange(effects.map((current, currentIndex) => currentIndex === index ? effect : current));
  const move = (index: number, direction: -1 | 1) => {
    const target = index + direction;
    if (target < 0 || target >= effects.length) return;
    const next = [...effects];
    [next[index], next[target]] = [next[target], next[index]];
    onChange(next);
  };
  return <div className={nested ? "effect-list nested" : "effect-list"}>
    {effects.map((effect, index) => <section className={`effect effect-${effect.op}`} key={index}>
      <header><span className="drag-index">{index + 1}</span><strong>{blockLabels[effect.op]}</strong><div className="effect-actions"><button type="button" className="icon" aria-label="Move effect up" onClick={() => move(index, -1)} disabled={index === 0}>↑</button><button type="button" className="icon" aria-label="Move effect down" onClick={() => move(index, 1)} disabled={index === effects.length - 1}>↓</button><button type="button" className="icon danger" aria-label="Remove effect" onClick={() => onChange(effects.filter((_, currentIndex) => currentIndex !== index))}>×</button></div></header>
      <div className="effect-body"><EffectFields effect={effect} onChange={(next) => update(index, next)} /></div>
    </section>)}
    <div className="effect-palette" aria-label="Add effect">
      {(["damage", "debuff", "armor", "heal", "draw", "mana", "addStatus", "setLocal", "incrementCounter", "if"] as Effect["op"][]).map((op) => <button type="button" key={op} onClick={() => onChange([...effects, newEffect(op)])}>+ {blockLabels[op]}</button>)}
    </div>
  </div>;
}
