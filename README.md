[Game Editor](https://heliumsneakers.github.io/Card-Game/)

## Requirements

- LÖVE 11.5
- Make (for the commands below; `love game` also works directly)

A C++17 compiler and CMake 3.16+ are needed only for the resource packer
and the current `make test` target.

## Build and run

```sh
make run
```

Run this from the repository root. It launches the Lua source with LÖVE; no
`assets/` directory, resource archive, or `build/` directory is required.
The current game draws its visuals directly and reads `game/content/content.json`.

If LÖVE is not on your PATH, provide its executable explicitly:

```sh
make run LOVE_BIN="/path/to/love"
```

Run the headless gameplay checks with `make test` when LuaJIT is available.

## Game code layout

`game/main.lua` forwards LÖVE callbacks to `src/app.lua`. The app loads and
validates content, supplies seed creation, and owns screens, overlays, pointer
input, fonts, and visual feedback. Its combat controller owns card selection.

- `game/src/core/`: virtual 1920×1080 viewport, pointer gestures, and the scene stack.
- `game/src/screens/`: combat, reward, and end screen drawing and actions.
- `game/src/ui/`: shared drawing helpers, theme, card/HUD views, deck viewer, and inspection overlay.
- `game/src/presentation/`: card colors/descriptions and transient feedback (notices, flashes, shake timers).
- `game/src/domain/deck.lua`: pile setup, shuffle, draw/redraw, discard, copies, and deck counts.
- `game/src/domain/rewards.lua`: reward offers, pick limits, and applying picks to the master deck.
- `game/src/domain/combat.lua`: combat setup, enemy creation, card play, damage, turn rules, and enemy pacing. It owns the operations exposed to effects.
- `game/src/domain/effects/`: expression evaluation, effect handlers, and ordered resolution.
- `game/src/domain/run.lua`: run initialization, room plans, boss/endless progression, and run transitions.
- `game/src/game.lua`: gameplay entry point coordinating the domain modules.
- `game/src/presentation/combat_controller.lua`: card selection and combat interaction handling; the combat screen forwards gestures to it.
- `game/src/cards.lua`: per-game catalog wrapper and card creation; requiring it performs no file reads.
- `game/src/presentation/descriptions.lua`: authored and generated card descriptions, using scalar queries and the shared expression evaluator.
- `game/src/effects.lua`: runtime resolver import alias; description rendering is separate.
- `game/src/encounters.lua` and `content.lua`: encounter generation and content validation/loading.
- `game/content/content.json`: the card, enemy, and encounter data used by both the game and the editor.

### Ownership and dependencies

Create a headless game with an explicitly loaded catalog and seed:

```lua
local catalog = assert(Content.load("content/content.json"))
local game = Game.new(30, 12345, { catalog = catalog })
local card = game.cards:make("card.fireball")
```

`Game.new` requires `dependencies.catalog`. Each game builds its own card wrapper,
starting-deck list, and shop pool. Treat the supplied catalog as read-only for the
lifetime of that game; create a new game with a new catalog to replace content.
There is no global `Cards.setCatalog` operation. A fixed seed repeats on restart;
without one, `dependencies.seedSource` supplies each run seed (default `os.time`).
The app supplies the existing LÖVE-based seed calculation.

Existing gameplay methods remain on `Game`, while data belongs to explicit state objects:

| Owner | Data |
| --- | --- |
| `game.run` | Run state, seed, HP/armor, master deck, room and endless progress |
| `game.combat` | Phase, wave, turn, mana, enemies, statuses, counters, encounter metadata and enemy pacing |
| `game.deck` | `hand`, `draw`, and `discard` piles |
| `game.rewards` | Offered `choices` and selected `picks` (created when rewards open) |
| `app.combatController` | Selected card and interpretation of combat gestures |

Callers use these owners directly; there are no forwarding aliases for the old
flat fields. For example, `game.hp` is now `game.run.hp`, and `game.hand` is
`game.deck.hand`. A new room replaces combat/deck state; a restart replaces run
state too. Domain modules receive the specific state and dependencies they need,
never the whole `Game` coordinator. They do not load content or reference LÖVE.

`Run.afterClear` decides whether a clear opens rewards, starts the boss wave, or
advances a room. `Game` applies that decision in the existing order.
`Combat.advanceTurn` shares mana refill, counter reset, and draw logic between
normal turns and boss-wave advancement; phase changes use `Combat.setPhase`.
Run state changes use `Run.setState`. These are ordinary functions, not a new
state-machine framework.

Statuses and counters have one authoritative representation:
`game.combat.statuses["status.spell_power"]`,
`game.combat.statuses["status.mirror"]`, and
`game.combat.turnCounters["card.firebolt"]`. The redundant `surge`, `mirror`, and
`fb` fields are removed. Their gameplay behavior is unchanged.

The controller clears selection after successful plays and valid end turns;
App clears it on screen changes and Escape. Screens use `game.cards` for definitions
and `presentation/cards.lua` for colors and descriptions. The optional
`dependencies.feedback` object provides `reset`, `notice`, `enemyDamaged`, and
`playerDamaged` callbacks. The app owns and updates its timers; headless games can
omit it. These direct callbacks preserve existing feedback without an event bus.

The game rules and content format are unchanged. `make test` syntax checks game
Lua modules and runs gameplay, content, dependency-isolation, deck/reward, and
presentation integration checks, effect ordering, progression, and description checks.
`make test-contract` also reads `tests/fixtures/content_contract.json` from Lua and
the existing TypeScript model (Node 22.6+). It checks agreed description, enemy-power,
and validation cases without modifying the editor. The fixture is a focused
contract, not a complete equivalence check of both validators.
Presentation tests stub graphics calls; they do
not verify rendered appearance.

### Effect boundary

`Resolver.resolve(definition, cardId, query, actions, multiplier)` executes effects
in order. Each resolution has fresh locals. `query.counter(id)` and
`query.value(path)` return scalar values from the current combat state, so later
effects see earlier mutations. The spell-power multiplier is captured once before
execution, preserving current behavior.

Handlers receive named operations: `damage`, `freeze`, `armor`, `heal`, `draw`,
`mana`, `addStatus`, and `incrementCounter`. Combat binds these operations to the
selected target, state, RNG, and optional feedback. Handlers do not receive a
`Game` object, enemies, or mutable piles. Existing status consumption rules are preserved; generalized status hooks are
deferred.

`Descriptions.describe(definition, query, cardId, multiplier)` accepts the same
scalar queries without mutation operations. It owns text templates and generated
prose; the expression evaluator contains no presentation or combat dependencies.
`presentation/cards.lua` adapts a game to this read interface for the UI.
`src/effects.lua` no longer exposes `describe` or `evaluate`; their owners are
`presentation/descriptions.lua` and `domain/effects/expressions.lua` respectively.
No events, command dispatch, or state-machine framework has been introduced.

## Designer web editing tool

Local build with: 
```sh
npm install
npm run dev
```

Useful commands:

```sh
make test             # Lua syntax, gameplay parity, schema/interpreter tests
npm run typecheck     # strict TypeScript checks
npm run test:editor   # editor model tests
npm run build:editor  # production editor bundle in dist/editor
```

The editor also includes two world-design tools:

- **Tile catalog** labels all 115 isometric sprites and exposes their WFC layer, biome, weight, walkability, tags, and directional sockets.
- **Room builder** selects seeded dimensions inside a template's width/height bounds, runs a Simple Tiled WFC collapse, places biome objects and enemy-spawn markers in later passes, supports pinned cells, and exports the catalog, template, and result as JSON.

The solver in `editor/src/wfc.ts` follows the observation and adjacency-propagation structure of Maxim Gumin's MIT-licensed [WaveFunctionCollapse](https://github.com/mxgmn/WaveFunctionCollapse) project. Tile metadata is the source of adjacency truth: matching directional socket strings are compatible, and `*` acts as a wildcard.

## Packer

This is an optional, separate workflow for packing files from an `assets/`
directory you supply. The current game does not load the resulting archive.

```sh
make assets
```

To build just the packer, use `make tools`. Its command-line interface is:

```text
rrespack <input-directory> <output.rres>
```

The generated file uses the public rres v1.0 layout:

- 16 byte `rres` file header
- one `RAWD` chunk per file
- CRC32 path IDs
- four RAWD properties: size, two extension words, reserved
- CRC32 for every complete resource data block
