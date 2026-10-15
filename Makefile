.PHONY: build app run test lint format check dmg signing clean

SWIFT_SOURCES := Package.swift Sources Tests

# The Command Line Tools ship Swift Testing's macro plugin outside the compiler's default search
# path; point at it when no full Xcode is selected.
DEVELOPER_DIR_PATH := $(shell xcode-select -p)
TEST_FLAGS := $(if $(findstring CommandLineTools,$(DEVELOPER_DIR_PATH)),\
	-Xswiftc -plugin-path -Xswiftc $(DEVELOPER_DIR_PATH)/usr/lib/swift/host/plugins/testing)

build:
	swift build

# A signed .app for this Mac. Run `make signing` once first so permissions survive rebuilds.
app:
	ARCHS=$(shell uname -m) DMG=0 VERSION=0.0.0-dev scripts/build.sh

run: app
	-pkill -x Vocume
	@while pgrep -x Vocume > /dev/null; do sleep 0.1; done  # `open` fails while the old one quits
	open build/Vocume.app

signing:
	scripts/dev-signing.sh

test:
	swift test $(TEST_FLAGS)

lint:
	swift format lint --strict --recursive $(SWIFT_SOURCES)

format:
	swift format format --in-place --recursive $(SWIFT_SOURCES)

# Everything CI checks.
check: lint build test

dmg:
	scripts/build.sh

clean:
	rm -rf .build build
