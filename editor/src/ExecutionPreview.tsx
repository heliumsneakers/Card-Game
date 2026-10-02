import { useState } from "react";
import type { CardDefinition, CounterReference } from "./model";
import { CounterField } from "./effects/CounterField";
import { counterKey, initialPreviewState, nextPreviewTurn, previewEffects, type PreviewState } from "./effects/preview";
import { effectRegistry } from "./effects/registry";
import { validateEffects } from "./effects/validation";

/** Explore ordered effects with editable resources and repeatable counter state. */
export function ExecutionPreview({ card, cards }: { card: CardDefinition; cards: CardDefinition[] }) {
  const [state, setState] = useState(initialPreviewState);
  const [instance, setInstance] = useState(1);
  const [counter, setCounter] = useState<CounterReference>({ id: "$thisCard", scope: "turn" });
  const issues: string[] = [];
  validateEffects(card.effects, "effects", card, new Set(cards.map((item) => item.id)), (_path, message) => issues.push(message));
  const result = issues.length ? undefined : previewEffects(card, state, `${card.id}:${instance}`);
  const key = counterKey(counter, card, `${card.id}:${instance}`);

  /** Update a numeric scenario field without altering the authored card. */
  function field(name: keyof PreviewState, label: string, max = 999) {
    // Resource constraints keep sandbox scenarios physically meaningful.
    return <label key={name}><span>{label}</span><input type="number" min="0" max={max} value={Number(state[name])} onChange={(event) => setState({ ...state, [name]: Math.min(max, Math.max(0, Math.floor(Number(event.target.value)))) })} /></label>;
  }

  /** Commit a successful resolution and apply the card's status consumption. */
  function resolve() {
    if (!result || result.error) return;
    // Spell power is consumed after effects unless the card explicitly retains it.
    const next = structuredClone(result.state);
    if (!card.retainsStatuses?.includes("status.spell_power")) next.statuses["status.spell_power"] = 0;
    next.previousCardId = card.id;
    setState(next);
  }

  return <section className="panel execution-preview"><h2>Execution preview</h2><p>Set the state when effects start, after paying mana. Resolve repeatedly to explore counters. Draws use the available-card count; use the game preview for a full match.</p>
    <div className="field-grid">{field("mana", "Mana after cost")}{field("hp", "Player HP", state.maxHp)}{field("armor", "Armor")}{field("handSize", "Cards left in hand", 7)}{field("availableDraws", "Cards available to draw")}
      <label><span>Spell-power stacks</span><input type="number" min="0" value={state.statuses["status.spell_power"] || 0} onChange={(event) => setState({ ...state, statuses: { ...state.statuses, "status.spell_power": Math.max(0, Math.floor(Number(event.target.value))) } })} /></label>
      <label><span>Previous card</span><select value={state.previousCardId} onChange={(event) => setState({ ...state, previousCardId: event.target.value })}><option value="">None</option>{cards.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
      {state.enemies.map((hp, index) => <label key={index}><span>Enemy {index + 1} HP</span><input type="number" min="0" value={hp} onChange={(event) => setState({ ...state, enemies: state.enemies.map((current, i) => i === index ? Math.max(0, Math.floor(Number(event.target.value))) : current) })} /></label>)}
      <label><span>Selected enemy</span><select value={state.targetIndex} onChange={(event) => setState({ ...state, targetIndex: Number(event.target.value) })}>{state.enemies.map((_, index) => <option key={index} value={index}>Enemy {index + 1}</option>)}</select></label>
    </div>
    <details><summary>Set an initial counter</summary><CounterField value={counter} onChange={setCounter} /><label><span>Counter value</span><input type="number" min="0" value={state.counters[key] || 0} onChange={(event) => setState({ ...state, counters: { ...state.counters, [key]: Math.max(0, Math.floor(Number(event.target.value))) } })} /></label></details>
    <p>Turn {state.turn} · Copy {instance}</p><div className="effect-palette"><button type="button" onClick={resolve} disabled={!result || !!result.error}>Resolve effects</button><button type="button" onClick={() => setState(nextPreviewTurn(state))}>Next turn</button><button type="button" onClick={() => setInstance(instance + 1)}>Use a new copy</button><button type="button" onClick={() => { setState(initialPreviewState()); setInstance(1); }}>Reset combat</button></div>
    <h3>Next resolution</h3>{issues.length > 0 && <p role="alert">{issues[0]}</p>}{result?.error && <p role="alert">{result.error}</p>}
    <ol className="execution-trace">{result?.steps.map((step) => <li key={step.path}><strong>{step.path} · {effectRegistry[step.operation as keyof typeof effectRegistry].label}</strong>{step.inputs.length > 0 && <small>{step.inputs.join("; ")}</small>}<span>{step.result}</span></li>)}</ol>
    <details><summary>Current counters</summary>{Object.keys(state.counters).length ? <ul>{Object.entries(state.counters).map(([name, value]) => <li key={name}>{name}: {value}</li>)}</ul> : <p>All counters are zero.</p>}</details>
  </section>;
}
