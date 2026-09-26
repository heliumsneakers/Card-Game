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

## GitHub Pages

The repository includes `.github/workflows/deploy-pages.yml`. It validates,
builds, and deploys `dist/editor` whenever `main` is pushed. The workflow sets
the Vite base path from the repository name, so both the editor assets and the
embedded love.js game work from a project URL such as
`https://USERNAME.github.io/CardGame/`.

After pushing the repository to GitHub, open **Settings → Pages** and choose
**GitHub Actions** as the deployment source. A successful workflow run exposes
the deployed URL in the repository's **Actions** tab.

For a local production build, the base path defaults to `/`:

```sh
npm run build:editor
```

To reproduce a project-site build locally:

```sh
VITE_BASE_PATH=/CardGame/ npm run build:editor
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
