.PHONY: tools assets run test test-contract clean

LOVE_BIN ?= $(shell if command -v love >/dev/null 2>&1; then command -v love; elif [ -x /Applications/love.app/Contents/MacOS/love ]; then echo /Applications/love.app/Contents/MacOS/love; elif [ -x /Applications/LÖVE.app/Contents/MacOS/love ]; then echo /Applications/LÖVE.app/Contents/MacOS/love; fi)

tools:
	cmake -S . -B build
	cmake --build build

assets: tools
	./build/rrespack assets game/assets/game.rres

run: assets
	@if [ -z "$(LOVE_BIN)" ]; then \
		echo "LÖVE was not found."; \
		echo "Install LÖVE 11.5, then retry: make run"; \
		echo "macOS download: https://love2d.org/"; \
		exit 1; \
	fi
	"$(LOVE_BIN)" game

test: tools
	@find game -name '*.lua' -type f -print | while IFS= read -r file; do \
		luajit -b "$$file" /tmp/cardgame-syntax.luac || exit 1; \
	done
	luajit tests/test_game.lua
	luajit tests/test_content.lua
	luajit tests/test_structure.lua
	luajit tests/test_effects.lua
	luajit tests/test_progression.lua
	luajit tests/test_contract.lua

# Node 22.6+ runs this read-only check against the existing TypeScript model.
test-contract:
	luajit tests/test_contract.lua
	node --experimental-strip-types tests/test_contract.mts

clean:
	cmake --build build --target clean
