import type { Expression } from "./model";

interface Props { value: Expression; onChange: (value: Expression) => void; label?: string; condition?: boolean }

const contextOptions = [
  ["previousCardId", "Previous card"], ["thisCardId", "This card"], ["mana", "Current mana"],
  ["hp", "Player HP"], ["turn", "Turn number"], ["livingEnemies", "Living enemies"],
] as const;

export function ExpressionEditor({ value, onChange, label = "Value", condition = false }: Props) {
  const kind = value.kind === "compare" ? "compare" : value.kind === "binary" ? "formula" : value.kind;
  const setKind = (next: string) => {
    if (next === "literal") onChange({ kind: "literal", value: 1 });
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
        {!condition && <option value="counter">Times played this turn</option>}
        <option value="context">Game value</option>
        {!condition && <option value="local">Calculated value</option>}
        {!condition && <option value="formula">Formula</option>}
        {condition && <option value="compare">Comparison</option>}
      </select>
    </label>
    {value.kind === "literal" && <input aria-label={`${label} number`} type="number" min="0" value={value.value} onChange={(event) => onChange({ ...value, value: Math.max(0, Number(event.target.value)) })} />}
    {value.kind === "counter" && <span className="token">this card</span>}
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
