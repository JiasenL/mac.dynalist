# Build, sign and install Dynalist.app (tao + wry) on macOS.

APP_NAME        ?= Dynalist.app
EXECUTABLE_NAME := Dynalist
APP_INSTALL_DIR ?= /Applications
APP_BUNDLE_PATH := $(APP_INSTALL_DIR)/$(APP_NAME)

# Codesign configuration (same identity as app.coconut).
CODESIGN_IDENTITY ?= Local Dev CLI
CODESIGN_FLAGS    ?= --force --timestamp=none
CODESIGN_ENTITLEMENTS ?=

CARGO_PROFILE ?= release
DIST_DIR      := $(CURDIR)/dist
STAGED_APP    := $(DIST_DIR)/$(APP_NAME)
ICON_SRC      := $(CURDIR)/macos/icon.icns
ICON_URL      := https://dynalist.io/assets/icon/android-chrome-192x192.png

ifeq ($(CARGO_PROFILE),release)
CARGO_FLAGS := --release
else
CARGO_FLAGS :=
endif

# UNIVERSAL=1 builds an arm64 + x86_64 fat binary (used for DMG releases).
UNIVERSAL ?= 0
ifeq ($(UNIVERSAL),1)
BIN_PATH := $(CURDIR)/target/universal/$(CARGO_PROFILE)/$(EXECUTABLE_NAME)
else
BIN_PATH := $(CURDIR)/target/$(CARGO_PROFILE)/$(EXECUTABLE_NAME)
endif

VERSION  ?= $(shell sed -n 's/^version *= *"\(.*\)"/\1/p' Cargo.toml | head -1)
DMG_PATH := $(DIST_DIR)/Dynalist-$(VERSION).dmg

.PHONY: help run dev build assemble deliver dmg uninstall icon clean

help:
	@printf "Available targets:\n"
	@printf "  make run       # cargo run (debug, devtools enabled)\n"
	@printf "  make dev       # Build debug bundle, sign, and open it from dist/\n"
	@printf "  make assemble  # Build release bundle in dist/ and sign it\n"
	@printf "  make deliver   # Build, sign, install to $(APP_INSTALL_DIR), and open it\n"
	@printf "  make dmg       # Build dist/Dynalist-<version>.dmg (add UNIVERSAL=1 for arm64+x86_64)\n"
	@printf "  make uninstall # Remove $(APP_BUNDLE_PATH)\n"
	@printf "  make icon      # Regenerate macos/icon.icns from dynalist.io\n"
	@printf "  make clean     # Remove target/ and dist/\n"

run:
	@cargo run

dev:
	@$(MAKE) assemble CARGO_PROFILE=debug
	@open "$(STAGED_APP)"

build:
ifeq ($(UNIVERSAL),1)
	@echo "Compiling Rust universal ($(CARGO_PROFILE))..."
	@cargo build $(CARGO_FLAGS) --target aarch64-apple-darwin
	@cargo build $(CARGO_FLAGS) --target x86_64-apple-darwin
	@mkdir -p "$(dir $(BIN_PATH))"
	@lipo -create -output "$(BIN_PATH)" \
		"target/aarch64-apple-darwin/$(CARGO_PROFILE)/$(EXECUTABLE_NAME)" \
		"target/x86_64-apple-darwin/$(CARGO_PROFILE)/$(EXECUTABLE_NAME)"
	@lipo -info "$(BIN_PATH)"
else
	@echo "Compiling Rust ($(CARGO_PROFILE))..."
	@cargo build $(CARGO_FLAGS)
endif

assemble: $(ICON_SRC) build
	@test -x "$(BIN_PATH)" || { echo "Missing binary: $(BIN_PATH)"; exit 1; }
	@rm -rf "$(STAGED_APP)"
	@mkdir -p "$(STAGED_APP)/Contents/MacOS" "$(STAGED_APP)/Contents/Resources"
	@cp "$(BIN_PATH)" "$(STAGED_APP)/Contents/MacOS/$(EXECUTABLE_NAME)"
	@cp "$(ICON_SRC)" "$(STAGED_APP)/Contents/Resources/icon.icns"
	@cp macos/Info.plist "$(STAGED_APP)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(STAGED_APP)/Contents/Info.plist"
	@chmod +x "$(STAGED_APP)/Contents/MacOS/$(EXECUTABLE_NAME)"
	@if [ -z "$(strip $(CODESIGN_IDENTITY))" ]; then \
		echo "CODESIGN_IDENTITY is required so LuLu can recognize the app."; \
		exit 1; \
	fi
	@echo "Codesigning with '$(CODESIGN_IDENTITY)'..."
	@CMD="codesign $(CODESIGN_FLAGS) --sign \"$(CODESIGN_IDENTITY)\""; \
	if [ -n "$(strip $(CODESIGN_ENTITLEMENTS))" ]; then \
		CMD="$$CMD --entitlements \"$(CODESIGN_ENTITLEMENTS)\""; \
	fi; \
	eval "$$CMD \"$(STAGED_APP)\""
	@codesign --verify --strict --verbose=2 "$(STAGED_APP)"

# Drag-to-install DMG (Dynalist.app + /Applications shortcut).
dmg: assemble
	@echo "Creating $(DMG_PATH)..."
	@rm -rf "$(DIST_DIR)/dmg-root" "$(DMG_PATH)"
	@mkdir -p "$(DIST_DIR)/dmg-root"
	@cp -R "$(STAGED_APP)" "$(DIST_DIR)/dmg-root/"
	@ln -s /Applications "$(DIST_DIR)/dmg-root/Applications"
	@hdiutil create -volname "Dynalist" -srcfolder "$(DIST_DIR)/dmg-root" \
		-ov -format UDZO "$(DMG_PATH)" >/dev/null
	@rm -rf "$(DIST_DIR)/dmg-root"
	@echo "Built $(DMG_PATH)"

deliver:
	@echo "Building Dynalist (Rust / tao + wry)..."
	@$(MAKE) assemble CARGO_PROFILE=release
	@echo "Closing running application..."
	@osascript -e 'quit app "Dynalist"' >/dev/null 2>&1 || true
	@pkill -f "$(APP_BUNDLE_PATH)" || true
	@sleep 1
	@rm -rf "$(APP_BUNDLE_PATH)"
	@echo "Installing to $(APP_INSTALL_DIR)..."
	@cp -R "$(STAGED_APP)" "$(APP_BUNDLE_PATH)"
	@if [ -n "$(strip $(CODESIGN_IDENTITY))" ]; then \
		echo "Codesigning $(APP_BUNDLE_PATH) with identity '$(CODESIGN_IDENTITY)'"; \
		CMD="codesign $(CODESIGN_FLAGS) --sign \"$(CODESIGN_IDENTITY)\""; \
		if [ -n "$(strip $(CODESIGN_ENTITLEMENTS))" ]; then \
			CMD="$$CMD --entitlements \"$(CODESIGN_ENTITLEMENTS)\""; \
		fi; \
		eval "$$CMD \"$(APP_BUNDLE_PATH)\""; \
	else \
		echo "Skipping codesign; set CODESIGN_IDENTITY=<identity> to enable signing."; \
	fi
	@echo "Installation complete."
	@echo "Opening application..."
	@open "$(APP_BUNDLE_PATH)"

uninstall:
	@osascript -e 'quit app "Dynalist"' >/dev/null 2>&1 || true
	@rm -rf "$(APP_BUNDLE_PATH)"
	@echo "Removed $(APP_BUNDLE_PATH)"

# Build an .icns from the official Dynalist web icon (upscaled from 192px).
$(ICON_SRC):
	@$(MAKE) icon

icon:
	@echo "Generating $(ICON_SRC)..."
	@TMP=$$(mktemp -d); \
	curl -sfL "$(ICON_URL)" -o "$$TMP/src.png" || { echo "Icon download failed"; exit 1; }; \
	mkdir -p "$$TMP/icon.iconset"; \
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s "$$TMP/src.png" --out "$$TMP/icon.iconset/icon_$${s}x$${s}.png" >/dev/null; \
		d=$$((s*2)); \
		sips -z $$d $$d "$$TMP/src.png" --out "$$TMP/icon.iconset/icon_$${s}x$${s}@2x.png" >/dev/null; \
	done; \
	mkdir -p macos; \
	iconutil -c icns "$$TMP/icon.iconset" -o "$(ICON_SRC)"; \
	rm -rf "$$TMP"

clean:
	@cargo clean
	@rm -rf "$(DIST_DIR)"
