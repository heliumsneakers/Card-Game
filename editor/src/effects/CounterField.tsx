import { useContext } from "react";
import { AuthoringCards, type AuthoringCard } from "../AuthoringContext";
import type { CounterOwner, CounterReference, ExplicitCounterReference } from "../model";
import { counterCategories, counterElements, defaultCounterOwner, normalizeCounter } from "./counterReferences";

type CounterFieldProps = { value: CounterReference; onChange: (value: CounterReference) => void };
type OwnerProps = { owner: CounterOwner; onChange: (owner: CounterOwner) => void; cards: AuthoringCard[] };

/** Select the grouping rule without embedding reference-conversion logic in JSX. */
function CounterOwnerSelect({ owner, onChange, cards }: OwnerProps) {
  /** Supply complete defaults for the newly selected owner kind. */
  function handleChange(kind: CounterOwner["kind"]) {
    onChange(defaultCounterOwner(kind, cards[0]?.id));
  }
  return <label>
    <span>Counter owner</span>
    <select value={owner.kind} onChange={(event) => handleChange(event.target.value as CounterOwner["kind"])}>
      <option value="this">This card (all copies)</option>
      <option value="instance">This individual copy</option>
      <option value="card">Another card (all copies)</option>
      <option value="element">Cards sharing an element</option>
      <option value="category">Cards sharing a category</option>
      <option value="shared">Named shared counter</option>
    </select>
  </label>;
}

/** Render only the selection required by the current ownership mode. */
function CounterOwnerDetails({ owner, onChange, cards }: OwnerProps) {
  // Explicit branches keep each mode's fields and updates together.
  switch (owner.kind) {
    case "card": return <label>
      <span>Card</span>
      <select value={owner.cardId} onChange={(event) => onChange({ kind: "card", cardId: event.target.value })}>
        {!cards.some((card) => card.id === owner.cardId) && <option value={owner.cardId}>Missing: {owner.cardId}</option>}
        {cards.map((card) => <option key={card.id} value={card.id}>{card.name}</option>)}
      </select>
    </label>;
    case "element": return <label>
      <span>Element group</span>
      <select value={owner.element} onChange={(event) => onChange({ kind: "element", element: event.target.value as typeof owner.element })}>
        <option value="this">This card’s element</option>
        {counterElements.map((element) => <option key={element} value={element}>{element}</option>)}
      </select>
    </label>;
    case "category": return <label>
      <span>Category group</span>
      <select value={owner.category} onChange={(event) => onChange({ kind: "category", category: event.target.value as typeof owner.category })}>
        <option value="this">This card’s category</option>
        {counterCategories.map((category) => <option key={category} value={category}>{category}</option>)}
      </select>
    </label>;
    default: return null;
  }
}

/** Keep lifetime independent of the selected owner and counter name. */
function CounterScopeSelect({ scope, onChange }: { scope: ExplicitCounterReference["scope"]; onChange: (scope: "turn" | "combat") => void }) {
  return <label>
    <span>Reset</span>
    <select value={scope || "turn"} onChange={(event) => onChange(event.target.value as "turn" | "combat")}>
      <option value="turn">Each turn</option>
      <option value="combat">Each combat</option>
    </select>
  </label>;
}

/** Share ownership controls between counter reads, writes, and initial preview values. */
export function CounterField({ value, onChange }: CounterFieldProps) {
  const cards = useContext(AuthoringCards);
  const reference = normalizeCounter(value);

  /** Replace identity fields while preserving the enclosing effect or expression. */
  function updateReference(patch: Partial<ExplicitCounterReference>) {
    // Callers pass complete effect objects; dropping their op/amount would corrupt the block.
    const { id: _legacyId, ...rest } = value;
    onChange({ ...rest, ...reference, ...patch });
  }

  /** Change ownership without resetting the name or lifetime. */
  function handleOwnerChange(owner: CounterOwner) {
    updateReference({ owner });
  }

  /** Update the reset boundary without affecting the ownership rule. */
  function handleScopeChange(scope: "turn" | "combat") {
    updateReference({ scope });
  }

  return <div className="counter-fields">
    <CounterOwnerSelect owner={reference.owner} onChange={handleOwnerChange} cards={cards} />
    <CounterOwnerDetails owner={reference.owner} onChange={handleOwnerChange} cards={cards} />
    <label>
      <span>Counter name</span>
      <input value={reference.name} onChange={(event) => updateReference({ name: event.target.value })} placeholder="power" />
    </label>
    <CounterScopeSelect scope={reference.scope} onChange={handleScopeChange} />
    <small>Matching owner, name, and reset timing share one value. Cards use that value only when their formulas read it. “default” preserves existing card counters.</small>
  </div>;
}
