# Damage bonuses

Use the **Damage Bonus** effect to add a temporary, automatic modifier to matching
card damage. Matching cards do not need their own counters or updated damage formulas.

Choose an element, category, or both. A missing selector matches any value; **This
card's ...** captures the current card's field when its effect resolves. If both
selectors are set, a card must match both. The amount is evaluated when granted,
can use spell power, and is added after the matching card's normal damage formula.

Bonuses with the same selectors and duration accumulate. For example, playing a
Fire card with a +2 Fire damage bonus and later another matching +1 bonus makes
matching Fire damage deal +3 for the rest of that duration. Turn bonuses expire
when the next turn starts. Combat bonuses expire when the encounter ends.

A card can grant a bonus to itself because effects resolve in order. Put its
Damage Bonus effect after its damage block when it should benefit later cards.
This allows cards such as a Flame Surge to grant +2 Fire damage, while a card
that grows the bonus can grant +1 Fire damage each time it is played.

Implementation lives in `src/effects/fields.tsx`,
`src/effects/damageModifiers.ts`, and `../game/src/domain/damage_modifiers.lua`.
The combat adapter adds matching values centrally when a damage effect resolves.
