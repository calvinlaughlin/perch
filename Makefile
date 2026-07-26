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

.PHONY: all app build run test check arch probe fmt lint clean install uninstall

all: app

## build — compile the executable only.
build:
	swift build -c $(CONFIG)

## app — assemble build/perch.app.
app: build
	@rm -rf "$(APP)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	@cp "$(BUILD_DIR)/$(NAME)" "$(CONTENTS)/MacOS/$(NAME)"
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
	@pkill -x $(NAME) 2>/dev/null || true
	@"$(CONTENTS)/MacOS/$(NAME)" >/dev/null 2>&1 & \
	  sleep 2; \
	  swift tools/NotchProbe.swift; \
	  status=$$?; \
	  pkill -x $(NAME) 2>/dev/null || true; \
	  exit $$status

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

## install — copy the bundle into /Applications.
install: app
	@rm -rf "$(PREFIX)/$(NAME).app"
	@cp -R "$(APP)" "$(PREFIX)/"
	@echo "installed to $(PREFIX)/$(NAME).app"

uninstall:
	@rm -rf "$(PREFIX)/$(NAME).app"

clean:
	@rm -rf .build build
