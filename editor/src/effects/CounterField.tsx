import { createContext, useContext } from "react";
import type { CardDefinition, CounterReference } from "../model";

export const AuthoringCards = createContext<Pick<CardDefinition, "id" | "name" | "element" >[]>([]);

/** Use the same ownership and lifetime controls for counter reads and writes. */
export function CounterField({ value, onChange }: { value: CounterReference; onChange: (value: CounterReference) => void }) {
  const cards = useContext(AuthoringCards);
  const owner = value.id === "$thisCard" ? "this" : value.id === "$thisInstance" ? "instance" : value.id.startsWith("card.") ? "card" : "shared";
  // Shared counters retain their explicit names; card counters use catalog choices.
  return <div className="counter-fields">
    <label><span>Counter owner</span><select value={owner} onChange={(event) => onChange({ ...value, id: event.target.value === "this" ? "$thisCard" : event.target.value === "instance" ? "$thisInstance" : event.target.value === "card" ? cards[0]?.id || "card.missing" : "shared." })}>
      <option value="this">This card (all copies)</option><option value="instance">This individual copy</option><option value="card">Another card (all copies)</option><option value="shared">Named shared counter</option>
    </select></label>
    {owner === "card" && <label><span>Card</span><select value={value.id} onChange={(event) => onChange({ ...value, id: event.target.value })}>
      {!cards.some((card) => card.id === value.id) && <option value={value.id}>Missing: {value.id}</option>}
      {cards.map((card) => <option key={card.id} value={card.id}>{card.name}</option>) }
    </select></label>}
    {owner === "shared" && <label><span>Counter name</span><input value={value.id} onChange={(event) => onChange({ ...value, id: event.target.value })} placeholder="shared." /></label>}
    <label><span>Reset</span><select value={value.scope || "turn"} onChange={(event) => onChange({ ...value, scope: event.target.value as CounterReference["scope"] })}><option value="turn">Each turn</option><option value="combat">Each combat</option></select></label>
  </div>;
}
