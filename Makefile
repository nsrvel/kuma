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

.PHONY: help build run open test clean dmg daemon cli cli-test cli-install

help:
	@echo "Kuma — common targets"
	@echo ""
	@echo "  make build       Build Kuma.app (output: $(APP))"
	@echo "  make run         Build and open the app"
	@echo "  make open        Open the app (must exist; run make build first)"
	@echo "  make test        Run KumaTests"
	@echo "  make daemon      Test Kuma daemon (Rust workspace in apps/daemon)"
	@echo "  make cli         Build Kuma Go CLI (output: apps/cli/bin/kuma)"
	@echo "  make cli-test    Run Kuma Go CLI tests"
	@echo "  make cli-install Build and install Kuma CLI to ~/.local/bin/kuma"
	@echo "  make dmg         Release build + dist/Kuma-<version>.dmg (see apps/mac/Scripts/make-dmg.sh)"
	@echo "  make clean       Remove $(DERIVED_DATA) and $(RELEASE_DERIVED)"
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
