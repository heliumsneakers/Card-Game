import type { Effect } from "./model";
import { effectRegistry } from "./effects/registry";
import { recipes } from "./effects/recipes";

interface Props { effects: Effect[]; onChange: (effects: Effect[]) => void; nested?: boolean }

/** Compose ordered blocks using registered editors and editable recipes. */
export function EffectEditor({ effects, onChange, nested = false }: Props) {
  // Replace one block without mutating the card's existing effect list.
  const update = (index: number, effect: Effect) => onChange(effects.map((current, currentIndex) => currentIndex === index ? effect : current));
  // Reordering changes execution order and is bounded to the current branch.
  const move = (index: number, direction: -1 | 1) => {
    const target = index + direction;
    if (target < 0 || target >= effects.length) return;
    const next = [...effects];
    [next[index], next[target]] = [next[target], next[index]];
    onChange(next);
  };
  return <div className={nested ? "effect-list nested" : "effect-list"}>
    {effects.map((effect, index) => {
      const module = effectRegistry[effect.op];
      const Fields = module.fields;
      return <section className={`effect effect-${effect.op}`} key={index}>
        <header><span className="drag-index">{index + 1}</span><strong>{module.label}</strong><div className="effect-actions"><button type="button" className="icon" aria-label="Move effect up" onClick={() => move(index, -1)} disabled={index === 0}>↑</button><button type="button" className="icon" aria-label="Move effect down" onClick={() => move(index, 1)} disabled={index === effects.length - 1}>↓</button><button type="button" className="icon danger" aria-label="Remove effect" onClick={() => onChange(effects.filter((_, currentIndex) => currentIndex !== index))}>×</button></div></header>
        <div className="effect-body"><Fields effect={effect} onChange={(next) => update(index, next)} /></div>
      </section>;
    })}
    {(["Effects", "Counters", "Logic"] as const).map((group) => <div key={group}><small>{group}</small><div className="effect-palette" aria-label={`Add ${group.toLowerCase()}`}>
      {Object.entries(effectRegistry).filter(([, module]) => !module.hidden && module.group === group).map(([op, module]) => <button type="button" key={op} onClick={() => onChange([...effects, module.create()])}>+ {module.label}</button>)}
    </div></div>)}
    {!nested && <details className="recipes"><summary>Insert an editable recipe</summary><p>Recipes append blocks below. Review the card target and rules text after inserting.</p>{recipes.map((recipe) => <button key={recipe.id} type="button" title={recipe.description} onClick={() => onChange([...effects, ...recipe.create()])}>+ {recipe.name}</button>)}</details>}
  </div>;
}
