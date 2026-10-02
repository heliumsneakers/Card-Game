# Counter ownership

Counter reads and writes share the same controls: owner, name, and reset timing.
Matching choices address one stored value. Incrementing it changes what all
participating cards read; it does not automatically modify their damage formulas.

## Share power between fire cards

1. Add an Increment Counter block to the cards that contribute power.
2. Choose **Cards sharing an element**, **fire**, and the name **power**.
3. Choose **Each turn** or **Each combat** consistently.
4. In a damage formula, choose Counter value and enter those same choices.

An increment before the damage block includes the current card's contribution.
An increment after damage benefits later reads. **This card’s element** selects
the resolving card's current element; an explicit **fire** selection always
addresses the fire group, even on an ice card.

Category groups work the same way with DMG, DEF, HEAL, or UTIL. Category and
element groups are independent. Names such as `power` and `casts` allow multiple
independent counters within one group.

## Reference format

```json
{
  "owner": { "kind": "element", "element": "fire" },
  "name": "power",
  "scope": "turn"
}
```

Owner forms are `this`, `instance`, `card` with `cardId`, `element` with `element`,
`category` with `category`, and `shared`. Element/category selections accept
`"this"` to follow the resolving card. Every explicit reference has a nonempty
name. Omitted scope means `turn`; `combat` survives turn transitions.

Old references using `id` remain supported. Editing a reference converts it to
explicit ownership while preserving its existing value: card/copy IDs use the
name `default`, and shared IDs become the shared name. Do not supply both an
`id` and an `owner`. Shared names cannot begin with `@`, `$`, or `card.` because
those prefixes belong to internal keys and existing card references.

## Code locations

- `src/effects/CounterField.tsx`: form components and named change handlers.
- `src/effects/counterReferences.ts`: defaults, legacy conversion, key resolution,
  labels, validation, and safe reference replacement.
- `src/AuthoringContext.tsx`: catalog metadata shared by authoring components.
- `../game/src/domain/effects/counters.lua`: matching runtime key resolution.
- `../tests/fixtures/counter_owners.json`: shared Lua/TypeScript contract cases.

The execution preview and descriptions receive the card's element and category,
so their counter calculations use the same ownership rules as gameplay.
