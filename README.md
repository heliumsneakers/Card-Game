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
