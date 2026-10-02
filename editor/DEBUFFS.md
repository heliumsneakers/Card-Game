# Adding a debuff

`game/content/debuffs.json` is the shared catalog. The editor reads it directly;
the game uses `game/src/domain/debuffs/definitions.lua`, generated from that catalog.
Do not edit the generated Lua file.

## Reuse an existing mechanic

1. Add an entry to `definitions` in the JSON catalog with a unique `id` and `token`.
2. Choose an implemented `behavior`. Currently `skipAction` skips an enemy action
   and consumes one stack per action.
3. Run `npm run debuffs:generate` from the repository root.
4. Run `npm run test:editor`, `make test`, and `npm run build:editor`.

Example entry for a second action-skipping debuff (not included in the shipped catalog):

```json
{
  "id": "debuff.stun",
  "label": "Stun",
  "token": "stun",
  "stackLabel": "Turns stunned",
  "defaultStacks": 1,
  "scalable": false,
  "behavior": "skipAction",
  "actionText": "IS STUNNED",
  "badge": "STUNNED",
  "color": [0.8, 0.7, 0.4]
}
```

The dropdown, ID validation, default block, stack label, generated descriptions,
value-token palette, execution trace, and enemy badges consume registry metadata.
The `defaultId` chooses the debuff inserted by the Debuffs button. Changing an
existing block's debuff preserves its authored stack formula and scaling setting.

Each token selects only that debuff: `{stun=1}`, `{stun2=1}`, etc. Tokens must be
unique lowercase letters/underscores with no numeric suffix or built-in token name.
Colors are RGB components from zero to one. Omit `legacyFlag` on new entries;
that field preserves old `frozen` enemy state. Leave `legacyOperations` unchanged.

## Add a new mechanic

Add a named function to `game/src/domain/debuffs/behaviors.lua`, then use its name
in the JSON entry's `behavior` field:

```lua
-- Process stacks immediately before this enemy would attack.
function Behaviors.yourBehavior(definition, stacks, actions)
    -- Apply this mechanic through the provided operations.
    actions.setStacks(math.max(0, stacks - 1))
    return false -- true skips the enemy's attack; false allows it
end
```

The callback receives metadata, the current stack count, and these operations:

- `actions.setStacks(number)`: change this debuff's stack count.
- `actions.damage(number)`: damage this enemy through normal combat rules.
- `actions.notice(message)`: optional presentation callback; check it before use.
- `actions.name`: the affected enemy's display name.

Hooks run in catalog order once before each living enemy's action. A skipped
attack does not stop other active hooks from running. A killed enemy stops later
hooks and cannot attack; killing the last enemy advances the encounter.

This hook covers behavior before an enemy attack. A mechanic triggered by card
play, incoming damage, or another event needs a corresponding new lifecycle hook.
The editor's execution sandbox previews application and independent stack counts;
it does not simulate enemy attacks or debuff expiration. Test turn behavior in
the embedded game and add Lua regression tests for a new mechanic.

## Generated-file workflow

`npm run dev`, `npm run build:web`, and `make run` regenerate the Lua catalog.
Tests run a read-only freshness check and report how to regenerate stale output.
Commit both the JSON source and generated Lua catalog together. Runtime registry
initialization rejects an entry whose behavior function does not exist.

The shared test fixture `tests/fixtures/debuff_registry.json` exercises a second,
test-only debuff across TypeScript and Lua. It does not add a gameplay debuff.
