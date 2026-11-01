# Single entry point for local development and CI (ADR-0013).
# CI only calls these targets; never duplicate the commands elsewhere.

SWIFT ?= swift
IOS_DESTINATION ?= generic/platform=iOS
# The vector generator needs JDK 17 (Gradle 9 does not run on newer JDKs).
JAVA17_HOME ?= $(shell /usr/libexec/java_home -F -v 17 2>/dev/null || echo "$$(brew --prefix openjdk@17 2>/dev/null)/libexec/openjdk.jdk/Contents/Home")
GRADLEW := ../android-src/KV4PHT/gradlew
VECTORS := Packages/*/Tests/*/Vectors/*
# Generated sources: Codec2, vendored by tools/codec2-vectors (ADR-0027), the flasher stub of esp32-flash-lib and the
# app version from the Android app (ADR-0037).
VENDORED := Packages/KV4PDigital/Sources/CCodec2 Packages/KV4PDigital/COPYING-codec2 \
	Packages/KV4PFlasher/Sources/KV4PFlasher/ESP32Stub.generated.swift Config/Version.xcconfig
# SwiftPM names the scheme <package>-Package once there are several products.
SCHEME ?= $(shell xcodebuild -list -json 2>/dev/null | jq -r '.workspace.schemes | (map(select(endswith("-Package")))[0] // .[0])')

APP_PROJECT := App/KV4PHT.xcodeproj
# Where `make app` builds the app, so its Info.plist can be checked.
APP_DERIVED_DATA := .build/app
SWIFT_SOURCES := Package.swift Packages App

.PHONY: test coverage lint format privacy changed vectors vectors-check ios-build app icon testflight ci

test:
	$(SWIFT) test

# Tests run in parallel; atomic profile counters keep concurrent executions of the same code from losing counts.
COVERAGE_FLAGS := -Xswiftc -Xllvm -Xswiftc -instrprof-atomic-counter-update-all

coverage:
	$(SWIFT) test --enable-code-coverage $(COVERAGE_FLAGS)
	scripts/coverage-gate.sh "$$($(SWIFT) build --show-bin-path $(COVERAGE_FLAGS))"

lint:
	$(SWIFT) format lint --strict --recursive --parallel $(SWIFT_SOURCES)

format:
	$(SWIFT) format --in-place --recursive --parallel $(SWIFT_SOURCES)

privacy:
	scripts/privacy-check.sh $(BASE) $(HEAD_REF)

# Prints true/false: does BASE...HEAD_REF touch an Apple port path?
# ORACLE=--oracle also counts the Android sources of the test vectors.
changed:
	@scripts/apple-changed.sh '$(BASE)' '$(HEAD_REF)' $(ORACLE)

# Regenerates the golden test vectors from the unmodified Android code (ADR-0004)
# and the vendored Codec2 with its vectors from the pinned upstream commit (ADR-0027).
vectors:
	JAVA_HOME="$(JAVA17_HOME)" $(GRADLEW) --quiet --project-dir ../tools/test-vectors run
	../tools/codec2-vectors/generate.sh
	scripts/app-version.sh

# Fails if the committed vectors or vendored sources differ from the generator output.
vectors-check: vectors
	@if [ -n "$$(git status --porcelain --untracked-files=all -- '$(VECTORS)' $(VENDORED))" ]; then \
		echo "vectors: committed vectors are out of date, run 'make vectors' and commit:" >&2; \
		git status --short --untracked-files=all -- '$(VECTORS)' $(VENDORED) >&2; exit 1; fi
	@echo "vectors: ok"

ios-build:
	xcodebuild build -quiet -scheme '$(SCHEME)' -destination '$(IOS_DESTINATION)'

# Builds the app (ADR-0019) for macOS and iOS without code signing.
app:
	xcodebuild build -quiet -project $(APP_PROJECT) -scheme KV4PHT -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
	xcodebuild build -quiet -project $(APP_PROJECT) -scheme KV4PHT -destination '$(IOS_DESTINATION)' CODE_SIGNING_ALLOWED=NO \
		-derivedDataPath $(APP_DERIVED_DATA)
	scripts/app-plist-check.sh $(APP_DERIVED_DATA)/Build/Products/Debug-iphoneos/KV4PHT.app
	DRY_RUN=1 scripts/release-testflight.sh

# Signed iOS and macOS builds, uploaded to App Store Connect for TestFlight (ADR-0035). Needs TEAM_ID in the environment and the
# account in Xcode; DRY_RUN=1 makes an unsigned dry run. Not part of `ci`.
testflight:
	scripts/release-testflight.sh

# Renders the app icon from ../artwork/app-icon.svg (ADR-0033); commit the result.
icon:
	scripts/app-icon.sh

ci: lint privacy coverage ios-build app
