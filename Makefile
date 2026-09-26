.PHONY: tools assets run test clean

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
	luajit -b game/main.lua /tmp/cardgame-main.luac
	luajit -b game/src/cards.lua /tmp/cardgame-cards.luac
	luajit -b game/src/content.lua /tmp/cardgame-content.luac
	luajit -b game/src/effects.lua /tmp/cardgame-effects.luac
	luajit -b game/src/encounters.lua /tmp/cardgame-encounters.luac
	luajit -b game/src/json.lua /tmp/cardgame-json.luac
	luajit -b game/src/game.lua /tmp/cardgame-game.luac
	luajit -b game/src/rres.lua /tmp/cardgame-rres.luac
	luajit tests/test_game.lua
	luajit tests/test_content.lua

clean:
	cmake --build build --target clean
