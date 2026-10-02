import { useContext } from "react";
import { AuthoringCards, CounterField } from "./effects/CounterField";
import type { Expression } from "./model";

interface Props { value: Expression; onChange: (value: Expression) => void; label?: string; condition?: boolean }

const contextOptions = [
  ["previousCardId", "Previous card"], ["thisCardId", "This card"], ["mana", "Current mana"],
  ["hp", "Player HP"], ["turn", "Turn number"], ["livingEnemies", "Living enemies"],
] as const;

/** Edit typed expression trees; comparisons produce conditions, other values feed formulas. */
export function ExpressionEditor({ value, onChange, label = "Value", condition = false }: Props) {
  const cards = useContext(AuthoringCards);
  const kind = value.kind === "compare" ? "compare" : value.kind === "binary" ? "formula" : value.kind;
  // Changing kinds starts a valid, independent expression tree.
  const setKind = (next: string) => {
    if (next === "literal") onChange({ kind: "literal", value: 1 });
    if (next === "card") onChange({ kind: "card", id: cards[0]?.id || "card.missing" });
    if (next === "counter") onChange({ kind: "counter", id: "$thisCard" });
    if (next === "context") onChange({ kind: "context", path: condition ? "previousCardId" : "mana" });
    if (next === "local") onChange({ kind: "local", name: "damage" });
    if (next === "formula") onChange({ kind: "binary", operator: "add", left: { kind: "literal", value: 1 }, right: { kind: "literal", value: 1 } });
    if (next === "compare") onChange({ kind: "compare", operator: "eq", left: { kind: "context", path: "previousCardId" }, right: { kind: "context", path: "thisCardId" } });
  };

  return <div className="expression">
    <label><span>{label}</span>
      <select value={kind} onChange={(event) => setKind(event.target.value)}>
        {!condition && <option value="literal">Number</option>}
        {!condition && <option value="counter">Counter value</option>}
        {!condition && <option value="context">Game value</option>}
        {!condition && <option value="card">Card reference</option>}
        <option value="local">{condition ? "Calculated condition" : "Calculated value"}</option>
        {!condition && <option value="formula">Formula</option>}
        <option value="compare">Comparison</option>
      </select>
    </label>
    {value.kind === "literal" && <input aria-label={`${label} number`} type="number" min="0" value={value.value} onChange={(event) => onChange({ ...value, value: Math.max(0, Number(event.target.value)) })} />}
    {value.kind === "counter" && <CounterField value={value} onChange={(reference) => onChange({ ...value, ...reference })} />}
    {value.kind === "card" && <select aria-label={`${label} card`} value={value.id} onChange={(event) => onChange({ ...value, id: event.target.value })}>{!cards.some((card) => card.id === value.id) && <option value={value.id}>Missing: {value.id}</option>}{cards.map((card) => <option key={card.id} value={card.id}>{card.name}</option>)}</select>}
    {value.kind === "local" && <input aria-label={`${label} calculated name`} value={value.name} onChange={(event) => onChange({ ...value, name: event.target.value })} />}
    {value.kind === "context" && <select aria-label={`${label} game value`} value={value.path} onChange={(event) => onChange({ ...value, path: event.target.value as Extract<Expression, { kind: "context" }>["path"] })}>
      {contextOptions.map(([id, text]) => <option key={id} value={id}>{text}</option>)}
    </select>}
    {(value.kind === "binary" || value.kind === "compare") && <div className="formula-row">
      <ExpressionEditor value={value.left} onChange={(left) => onChange({ ...value, left } as Expression)} label="Left" />
      <select aria-label="Formula operator" value={value.operator} onChange={(event) => onChange({ ...value, operator: event.target.value } as Expression)}>
        {value.kind === "binary" ? <>
          <option value="add">+</option><option value="subtract">−</option><option value="multiply">×</option><option value="min">minimum</option><option value="max">maximum</option>
        </> : <>
          <option value="eq">is</option><option value="ne">is not</option><option value="lt">is less than</option><option value="lte">is at most</option><option value="gt">is greater than</option><option value="gte">is at least</option>
        </>}
      </select>
      <ExpressionEditor value={value.right} onChange={(right) => onChange({ ...value, right } as Expression)} label="Right" />
    </div>}
  </div>;
}
