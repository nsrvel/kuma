SCHEME ?= Kuma
PROJECT ?= apps/mac/Kuma.xcodeproj
DESTINATION ?= platform=macOS
DERIVED_DATA ?= apps/mac/.build
CONFIGURATION ?= Debug
RELEASE_DERIVED ?= apps/mac/.derivedData
SPM_DIR ?= apps/mac/.spm

APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/Kuma.app

XCODEBUILD := xcodebuild \
	-project $(PROJECT) \
	-scheme $(SCHEME) \
	-destination '$(DESTINATION)' \
	-derivedDataPath $(DERIVED_DATA) \
	-configuration $(CONFIGURATION)

.PHONY: help build run open test clean dmg daemon daemon-build daemon-run daemon-install daemon-status daemon-logs cli cli-test cli-install

help:
	@echo "Kuma — common targets"
	@echo ""
	@echo "  App (macOS Swift):"
	@echo "    make build          Build Kuma.app (output: $(APP))"
	@echo "    make run            Build and open the app"
	@echo "    make open           Open the app (must exist; run make build first)"
	@echo "    make test           Run KumaTests"
	@echo "    make dmg            Release build + dist/Kuma-<version>.dmg"
	@echo "    make clean          Remove $(DERIVED_DATA) and $(RELEASE_DERIVED)"
	@echo ""
	@echo "  Daemon (Rust Backend):"
	@echo "    make daemon         Test Kuma daemon workspace"
	@echo "    make daemon-build   Build release daemon binary"
	@echo "    make daemon-run     Run daemon in foreground (interactive)"
	@echo "    make daemon-install Install & auto-start LaunchAgent background service"
	@echo "    make daemon-status  Check daemon background service status"
	@echo "    make daemon-logs    Stream live daemon stdout & stderr logs"
	@echo ""
	@echo "  CLI (Go Client):"
	@echo "    make cli            Build Kuma Go CLI (output: apps/cli/bin/kuma)"
	@echo "    make cli-test       Run Kuma Go CLI unit tests"
	@echo "    make cli-install    Build and install Kuma CLI to ~/.local/bin/kuma"
	@echo ""
	@echo "Overrides: SCHEME, CONFIGURATION, DERIVED_DATA, DESTINATION, RELEASE_DERIVED, SPM_DIR"

build:
	$(XCODEBUILD) build

run: build
	open "$(APP)"

open:
	@test -d "$(APP)" || (echo "Missing $(APP) — run: make build" && exit 1)
	open "$(APP)"

test:
	$(XCODEBUILD) test

daemon:
	cd apps/daemon && cargo test --workspace

daemon-build:
	./scripts/kuma-daemon.sh build

daemon-run:
	./scripts/kuma-daemon.sh build
	./apps/daemon/target/release/kuma daemon run

daemon-install:
	./scripts/kuma-daemon.sh install

daemon-status:
	./scripts/kuma-daemon.sh status

daemon-logs:
	./scripts/kuma-daemon.sh logs

cli:
	cd apps/cli && go build -o bin/kuma .

cli-test:
	cd apps/cli && go test -v ./...

cli-install:
	cd apps/cli && go build -o $(HOME)/.local/bin/kuma .

dmg:
	chmod +x apps/mac/Scripts/make-dmg.sh apps/mac/Scripts/mac-sign-app.sh apps/mac/Scripts/mac-notarize-dmg.sh
	DERIVED_DATA_PATH="$(CURDIR)/$(RELEASE_DERIVED)" \
	CLONED_SOURCE_PACKAGES_DIR="$(CURDIR)/$(SPM_DIR)" \
	./apps/mac/Scripts/make-dmg.sh

clean:
	rm -rf "$(DERIVED_DATA)" "$(RELEASE_DERIVED)" apps/mac/dist
