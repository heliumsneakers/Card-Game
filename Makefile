.PHONY: tools assets run test test-contract clean

LOVE_BIN ?= $(shell if command -v love >/dev/null 2>&1; then command -v love; elif [ -x /Applications/love.app/Contents/MacOS/love ]; then echo /Applications/love.app/Contents/MacOS/love; elif [ -x /Applications/LÖVE.app/Contents/MacOS/love ]; then echo /Applications/LÖVE.app/Contents/MacOS/love; fi)

# Build the native resource packer used by asset generation and the test target.
tools:
	cmake -S . -B build
	cmake --build build

# Optional packer workflow; the current game does not load this archive.
assets: tools
	./build/rrespack assets game/assets/game.rres

# The Lua game runs directly from source; no native build or asset archive is needed.
run:
	node tools/generate-debuffs.mjs
	@if [ -z "$(LOVE_BIN)" ]; then \
		echo "LÖVE was not found."; \
		echo "Install LÖVE 11.5, then retry: make run"; \
		echo "macOS download: https://love2d.org/"; \
		exit 1; \
	fi
	"$(LOVE_BIN)" game

# Compile Lua modules for syntax checks, then run each headless regression suite.
test: tools
	node tools/generate-debuffs.mjs --check
	@find game -name '*.lua' -type f -print | while IFS= read -r file; do \
		luajit -b "$$file" /tmp/cardgame-syntax.luac || exit 1; \
	done
	luajit tests/test_game.lua
	luajit tests/test_content.lua
	luajit tests/test_structure.lua
	luajit tests/test_effects.lua
	luajit tests/test_effect_contract.lua
	luajit tests/test_debuffs.lua
	luajit tests/test_debuff_damage.lua
	luajit tests/test_progression.lua
	luajit tests/test_contract.lua

# Node 22.6+ runs this read-only check against the existing TypeScript model.
test-contract:
	node tools/generate-debuffs.mjs --check
	luajit tests/test_effect_contract.lua
	luajit tests/test_debuffs.lua
	luajit tests/test_debuff_damage.lua
	luajit tests/test_contract.lua
	node --experimental-strip-types tests/test_contract.mts

# Remove CMake-generated build products without deleting project source.
clean:
	cmake --build build --target clean
