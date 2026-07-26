# perch — build, bundle, run.
#
# No .xcodeproj is committed. Everything is SwiftPM plus the bundle assembly below, so a clone
# builds with `make` and nothing else.

NAME       := perch
BUNDLE_ID  := dev.perch.perch
VERSION    := 0.1.0

# `make CONFIG=debug` for faster iteration builds.
CONFIG     ?= release
PREFIX     ?= /Applications

BUILD_DIR  := .build/$(CONFIG)
APP        := build/$(NAME).app
CONTENTS   := $(APP)/Contents

# Everything swift-format and the compiler should look at.
SWIFT_SOURCES := Sources Tests Package.swift

.PHONY: all app adapter build run test check arch probe ui-probe fmt lint \
        sign notarize release verify-release clean install uninstall

all: app

## build — compile the executable only.
build:
	swift build -c $(CONFIG)

## adapter — build MediaRemoteAdapter.framework from the vendored sources.
##
## Upstream builds with CMake; we invoke clang directly so a clone builds with `make` and nothing
## else. The sources are plain Objective-C against Foundation, so this costs one command and saves
## every contributor a Homebrew install.
##
## The framework is loaded by /usr/bin/perl via dl_load_file, which is the whole point of it —
## MediaRemote is entitlement-gated since macOS 15.4 and Perl's bundle identifier is entitled.
ADAPTER_DIR   := Vendor/mediaremote-adapter
ADAPTER_BUILD := build/adapter
ADAPTER_FW    := $(ADAPTER_BUILD)/MediaRemoteAdapter.framework
# Mirrors ADAPTER_SOURCES in the vendored CMakeLists.txt. Listed explicitly rather than globbed:
# `src/test/NowPlayingTest.m` belongs to upstream's test-client target, not the framework, and a
# glob would pull it in and fail to link against MediaPlayer. Re-check this list when updating.
ADAPTER_SRCS  := \
  $(ADAPTER_DIR)/src/adapter/env.m \
  $(ADAPTER_DIR)/src/adapter/get.m \
  $(ADAPTER_DIR)/src/adapter/globals.m \
  $(ADAPTER_DIR)/src/adapter/keys.m \
  $(ADAPTER_DIR)/src/adapter/now_playing.m \
  $(ADAPTER_DIR)/src/adapter/repeat.m \
  $(ADAPTER_DIR)/src/adapter/seek.m \
  $(ADAPTER_DIR)/src/adapter/send.m \
  $(ADAPTER_DIR)/src/adapter/shuffle.m \
  $(ADAPTER_DIR)/src/adapter/speed.m \
  $(ADAPTER_DIR)/src/adapter/stream.m \
  $(ADAPTER_DIR)/src/adapter/test.m \
  $(ADAPTER_DIR)/src/private/MediaRemote.m \
  $(ADAPTER_DIR)/src/utility/Debounce.m \
  $(ADAPTER_DIR)/src/utility/helpers.m

adapter: $(ADAPTER_FW)

$(ADAPTER_FW): $(ADAPTER_SRCS)
	@rm -rf "$(ADAPTER_FW)"
	@mkdir -p "$(ADAPTER_FW)/Versions/A/Resources"
	@clang -dynamiclib -fobjc-arc -O2 \
	    -mmacosx-version-min=14.0 \
	    -I"$(ADAPTER_DIR)/include" -I"$(ADAPTER_DIR)/src" \
	    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
	    -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
	    -o "$(ADAPTER_FW)/Versions/A/MediaRemoteAdapter" \
	    $(ADAPTER_SRCS)
	@printf '%s' \
	  '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>' \
	  '<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>' \
	  '<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>' \
	  '<key>CFBundlePackageType</key><string>FMWK</string>' \
	  '<key>CFBundleShortVersionString</key><string>0.7.6</string>' \
	  '</dict></plist>' > "$(ADAPTER_FW)/Versions/A/Resources/Info.plist"
	@ln -sf A "$(ADAPTER_FW)/Versions/Current"
	@ln -sf Versions/Current/MediaRemoteAdapter "$(ADAPTER_FW)/MediaRemoteAdapter"
	@ln -sf Versions/Current/Resources "$(ADAPTER_FW)/Resources"
	@echo "built $(ADAPTER_FW)"

## app — assemble build/perch.app.
app: build adapter
	@rm -rf "$(APP)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources" "$(CONTENTS)/Frameworks"
	@cp "$(BUILD_DIR)/$(NAME)" "$(CONTENTS)/MacOS/$(NAME)"
	@cp -R "$(ADAPTER_FW)" "$(CONTENTS)/Frameworks/"
	@cp "$(ADAPTER_DIR)/bin/mediaremote-adapter.pl" "$(CONTENTS)/Resources/"
	@sed -e 's|@VERSION@|$(VERSION)|g' \
	     -e 's|@BUNDLE_ID@|$(BUNDLE_ID)|g' \
	     Resources/Info.plist > "$(CONTENTS)/Info.plist"
	@# Ad-hoc signature. perch needs no entitlements, but an unsigned bundle gets re-prompted
	@# for permissions on every rebuild, which makes iterating miserable.
	@codesign --force --sign - "$(APP)" 2>/dev/null || true
	@echo "built $(APP)"

## run — rebuild and launch, with logs on stdout.
##
## Runs the binary from inside the bundle rather than via `open`, so Bundle.main still resolves
## to the .app (bundled resources work) but stdout stays attached to this terminal.
run: app
	@pkill -x $(NAME) 2>/dev/null || true
	@"$(CONTENTS)/MacOS/$(NAME)"

## test — run the unit test suite.
test:
	swift test

## check — the full gate: lint, build with warnings as errors, test.
##
## This is what CI runs and what to run before committing. Warnings are errors here on purpose:
## a warning nobody fixes is just a lie about the state of the code.
check: lint arch
	swift build -c debug -Xswiftc -warnings-as-errors
	swift test

## probe — measure what perch actually draws against the real camera housing.
##
## Not part of `check`: it needs a notched display, a granted Screen Recording permission, and an
## undisturbed pointer, none of which exist on CI. Run it after touching geometry, the panel, or
## the shape — the failures it catches are the ones unit tests structurally cannot see, because
## they happen after AppKit gets hold of our numbers.
probe: app
	@swift tools/NotchProbe.swift "$(CONTENTS)/MacOS/$(NAME)"

## ui-probe — verify the interface by driving it through the accessibility tree.
##
## Complements `probe`, which measures geometry in pixels. This one asserts on structure and
## behaviour: that controls exist, that pressing them changes real playback state, and that the
## panel survives being used. A dead button cannot be pressed, so it fails here by construction —
## which is precisely the class of bug a screenshot cannot reveal.
##
## Local only: needs a notched display, Accessibility permission, and something playing.
ui-probe: app
	@swift tools/UIProbe.swift "$(CONTENTS)/MacOS/$(NAME)"

## arch — enforce that PerchCore stays free of UI frameworks.
##
## PerchCore is pure logic so geometry, config, and state can be tested without a display. One
## stray `import AppKit` quietly ends that, and the cost only shows up much later when the tests
## need a window server. Cheaper to catch here.
arch:
	@if grep -rn --include='*.swift' \
	    -E '^[[:space:]]*import[[:space:]]+(AppKit|SwiftUI|Cocoa)' Sources/PerchCore; then \
	    echo "error: PerchCore must not import UI frameworks — see CLAUDE.md"; \
	    exit 1; \
	fi
	@echo "arch: PerchCore is UI-free"

## fmt — reformat sources in place.
fmt:
	swift format --in-place --recursive $(SWIFT_SOURCES)

## lint — check formatting and rules without modifying anything.
lint:
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)

# --- Release -----------------------------------------------------------------------------------
#
# Distribution needs three things beyond a build: a Developer ID signature, the hardened runtime,
# and a notarisation ticket stapled into the bundle. Without all three, Gatekeeper refuses a
# downloaded copy no matter how it was built.

# Overridable so CI or another machine can supply its own.
SIGN_IDENTITY ?= Developer ID Application
NOTARY_PROFILE ?= perch
DIST_DIR := build/dist
DIST_ZIP := $(DIST_DIR)/$(NAME)-$(VERSION).zip

## sign — Developer ID sign the bundle with the hardened runtime.
##
## Nested code is signed first and the bundle last: a signature covers what is inside it, so
## signing the app before its framework invalidates the app's own seal.
sign: app
	@codesign --force --options runtime --timestamp 	    --sign "$(SIGN_IDENTITY)" 	    "$(CONTENTS)/Frameworks/MediaRemoteAdapter.framework"
	@codesign --force --options runtime --timestamp 	    --sign "$(SIGN_IDENTITY)" 	    "$(APP)"
	@codesign --verify --deep --strict --verbose=2 "$(APP)"
	@echo "signed $(APP)"

## notarize — submit to Apple, wait, and staple the ticket into the bundle.
##
## Stapling matters: without it Gatekeeper has to reach Apple to check, so a first launch offline
## fails. Store credentials once with:
##   xcrun notarytool store-credentials $(NOTARY_PROFILE) ##     --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-password>
notarize: sign
	@mkdir -p "$(DIST_DIR)"
	@rm -f "$(DIST_ZIP)"
	@# ditto, not zip: it preserves the symlinks and extended attributes a framework depends on.
	@ditto -c -k --keepParent "$(APP)" "$(DIST_ZIP)"
	@xcrun notarytool submit "$(DIST_ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@xcrun stapler staple "$(APP)"
	@rm -f "$(DIST_ZIP)"
	@ditto -c -k --keepParent "$(APP)" "$(DIST_ZIP)"
	@echo "notarised: $(DIST_ZIP)"

## release — the full path to something a stranger can download and open.
release: notarize verify-release

## verify-release — check the result the way Gatekeeper will.
##
## `codesign` says the signature is valid; `spctl` says whether the system would actually let it
## run. They are different questions, and only the second one is the one users experience.
verify-release:
	@echo "signature:"
	@codesign --verify --deep --strict --verbose=2 "$(APP)" 2>&1 | sed 's/^/  /'
	@echo "hardened runtime:"
	@codesign -d --verbose=2 "$(APP)" 2>&1 | grep -E "flags=|Authority=" | sed 's/^/  /'
	@echo "stapled ticket:"
	@xcrun stapler validate "$(APP)" 2>&1 | sed 's/^/  /'
	@echo "gatekeeper:"
	@spctl --assess --type execute --verbose=4 "$(APP)" 2>&1 | sed 's/^/  /'

## install — copy the existing bundle into /Applications.
##
## Deliberately does NOT rebuild. `app` re-signs ad-hoc every time, so an install that rebuilt
## would silently throw away the Developer ID signature and notarisation ticket of a bundle you
## had just released — and the result looks fine until someone else downloads it.
##
## Run `make` first for a development build, or `make release` for a notarised one.
install:
	@test -d "$(APP)" || { 	    echo "no bundle at $(APP) — run 'make' or 'make release' first"; exit 1; 	}
	@rm -rf "$(PREFIX)/$(NAME).app"
	@cp -R "$(APP)" "$(PREFIX)/"
	@printf "installed to %s/%s.app — " "$(PREFIX)" "$(NAME)"
	@if codesign -d --verbose=2 "$(PREFIX)/$(NAME).app" 2>&1 | grep -q "Developer ID"; then 	    if xcrun stapler validate "$(PREFIX)/$(NAME).app" >/dev/null 2>&1; then 	        echo "signed and notarised"; 	    else 	        echo "Developer ID signed, NOT notarised"; 	    fi; 	else 	    echo "ad-hoc signed (development build)"; 	fi

uninstall:
	@rm -rf "$(PREFIX)/$(NAME).app"

clean:
	@rm -rf .build build
