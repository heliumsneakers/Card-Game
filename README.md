[Game Editor](https://heliumsneakers.github.io/Card-Game/)

## Requirements

- LÖVE 11.5
- A C++17 compiler
- CMake 3.16+

## Build and run

```sh
cmake -S . -B build
cmake --build build
./build/rrespack assets game/assets/game.rres
love game
```

Or use `make run`.

Run the headless gameplay checks with `make test` when LuaJIT is available.

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

```text
rrespack <input-directory> <output.rres>
```

The generated file uses the public rres v1.0 layout:

- 16 byte `rres` file header
- one `RAWD` chunk per file
- CRC32 path IDs
- four RAWD properties: size, two extension words, reserved
- CRC32 for every complete resource data block
