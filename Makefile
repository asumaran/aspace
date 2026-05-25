# Override with: make install PREFIX=/usr/local APP_DEST=~/Applications
PREFIX   ?= $(HOME)/.local
APP_DEST ?= /Applications

APP_BUNDLE := build/Aspace.app
APP_NAME   := Aspace

.PHONY: all cli app test install uninstall clean help

all: app ## Build the CLI and the .app bundle (default)

cli: ## Build only the aspace CLI binary
	swift build -c release --product aspace

app: ## Build CLI + Aspace.app bundle (delegates to Scripts/build-app.sh)
	./Scripts/build-app.sh

test: ## Run the test suite
	swift test --parallel

install: app ## Install aspace CLI to $(PREFIX)/bin and Aspace.app to $(APP_DEST)
	@install -d "$(PREFIX)/bin"
	@BIN_PATH="$$(swift build -c release --product aspace --show-bin-path)/aspace"; \
	  install -m 0755 "$$BIN_PATH" "$(PREFIX)/bin/aspace"
	@echo "Installed CLI -> $(PREFIX)/bin/aspace"
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@rm -rf "$(APP_DEST)/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(APP_DEST)/$(APP_NAME).app"
	@echo "Installed app  -> $(APP_DEST)/$(APP_NAME).app"
	@echo
	@case ":$$PATH:" in \
	  *":$(PREFIX)/bin:"*) ;; \
	  *) printf "\033[33mWarning:\033[0m %s is not in your \$$PATH.\n" "$(PREFIX)/bin"; \
	     printf "Add this to your shell rc (~/.zshrc, ~/.bashrc, etc):\n\n"; \
	     printf "    export PATH=\"%s/bin:\$$PATH\"\n\n" "$(PREFIX)" ;; \
	esac
	@echo "Tip: open $(APP_DEST)/$(APP_NAME).app to start the menu bar app."

uninstall: ## Remove installed CLI and Aspace.app (does not touch ~/.config/aspace)
	@rm -f "$(PREFIX)/bin/aspace" && echo "Removed $(PREFIX)/bin/aspace" || true
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@rm -rf "$(APP_DEST)/$(APP_NAME).app" && echo "Removed $(APP_DEST)/$(APP_NAME).app" || true

clean: ## Remove build artifacts (.build, build, dist)
	rm -rf .build build dist

help: ## Show this help
	@awk 'BEGIN{FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
