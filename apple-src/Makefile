# Single entry point for local development and CI (ADR-0013).
# CI only calls these targets; never duplicate the commands elsewhere.

SWIFT ?= swift
IOS_DESTINATION ?= generic/platform=iOS
# The vector generator needs JDK 17 (Gradle 9 does not run on newer JDKs).
JAVA17_HOME ?= $(shell /usr/libexec/java_home -F -v 17 2>/dev/null || echo "$$(brew --prefix openjdk@17 2>/dev/null)/libexec/openjdk.jdk/Contents/Home")
GRADLEW := ../android-src/KV4PHT/gradlew
VECTORS := Packages/*/Tests/*/Vectors/*
# Generated sources: Codec2, vendored by tools/codec2-vectors (ADR-0027), and the flasher stub of esp32-flash-lib.
VENDORED := Packages/KV4PDigital/Sources/CCodec2 Packages/KV4PDigital/COPYING-codec2 \
	Packages/KV4PFlasher/Sources/KV4PFlasher/ESP32Stub.generated.swift
# SwiftPM names the scheme <package>-Package once there are several products.
SCHEME ?= $(shell xcodebuild -list -json 2>/dev/null | jq -r '.workspace.schemes | (map(select(endswith("-Package")))[0] // .[0])')

APP_PROJECT := App/KV4PHT.xcodeproj
# Where `make app` builds the app, so its Info.plist can be checked.
APP_DERIVED_DATA := .build/app
SWIFT_SOURCES := Package.swift Packages App

.PHONY: test coverage lint format privacy changed vectors vectors-check nightly-firmware ios-build app icon testflight ci a11y a11y-mac screenshots site site-tools site-check

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

# Fails if the committed vectors or vendored sources differ from the generator output.
vectors-check: vectors
	@if [ -n "$$(git status --porcelain --untracked-files=all -- '$(VECTORS)' $(VENDORED))" ]; then \
		echo "vectors: committed vectors are out of date, run 'make vectors' and commit:" >&2; \
		git status --short --untracked-files=all -- '$(VECTORS)' $(VENDORED) >&2; \
		git diff --unified=0 -- '$(VECTORS)' $(VENDORED) | cut -c1-200 | head -60 >&2; exit 1; fi
	@echo "vectors: ok"

# Replaces the bundled nightly firmware (ADR-0049); commit the result after a hardware test. Not part of `ci`.
nightly-firmware:
	scripts/update-nightly-firmware.sh

ios-build:
	xcodebuild build -quiet -scheme '$(SCHEME)' -destination '$(IOS_DESTINATION)'

# Builds the app (ADR-0019) for macOS and iOS without code signing.
app:
	xcodebuild build -quiet -project $(APP_PROJECT) -scheme KV4PHT -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
	xcodebuild build -quiet -project $(APP_PROJECT) -scheme KV4PHT -destination '$(IOS_DESTINATION)' CODE_SIGNING_ALLOWED=NO \
		-derivedDataPath $(APP_DERIVED_DATA)
	scripts/app-plist-check.sh $(APP_DERIVED_DATA)/Build/Products/Debug-iphoneos/KV4PHT.app
	DRY_RUN=1 scripts/release-testflight.sh

# The UI tests in the app's demo mode, with Apple's accessibility audit on every screen, on an iPhone, an iPad and an
# iPhone Duo simulator (ADR-0062). The findings go to .build/a11y/findings.txt. Not part of `ci`, as it needs the
# simulator; CI runs it in jobs of their own, one per device and selection (ADR-0072). UI_TESTS: all, audit or functional.
A11Y_DEVICES ?= iPhone 18 Pro,iPad Pro 11-inch (M5),iPhone Duo
UI_TESTS ?= all
a11y:
	scripts/a11y.sh '$(APP_PROJECT)' '$(A11Y_DEVICES)' '$(UI_TESTS)'

# The same audit on this Mac. It takes over the mouse and the keyboard while it runs, so it is started by hand only.
a11y-mac:
	scripts/a11y.sh '$(APP_PROJECT)' 'Mac'

# The screenshots of the App Store, the website and the manual, in light and dark (docs/apple/release.md, ADR-0076), one
# simulator at a time; "Mac" takes them on this Mac, which takes over the mouse and the keyboard meanwhile. The store's
# images go to .build/screenshots/store, the website's copies to docs/apple/site/img/screens. Not part of `ci`.
SCREENSHOT_DEVICES ?= iPhone 18 Pro,iPad Pro 13-inch (M5),Mac
screenshots:
	scripts/screenshots.sh '$(APP_PROJECT)' '$(SCREENSHOT_DEVICES)'

# Signed iOS and macOS builds, uploaded to App Store Connect for TestFlight (ADR-0035). Needs TEAM_ID in the environment and the
# account in Xcode; DRY_RUN=1 makes an unsigned dry run. Not part of `ci`.
testflight:
	scripts/release-testflight.sh

# Renders the app icon from ../artwork/app-icon.svg (ADR-0033); commit the result.
icon:
	scripts/app-icon.sh

# The website (ADR-0067), built into SITE_DIR; site-check also checks its links, without the internet.
SITE_DIR ?= .build/site

site:
	scripts/site.sh $(SITE_DIR)

site-tools:
	scripts/site-tools.sh

site-check: site
	lychee --offline --include-fragments --no-progress '$(SITE_DIR)/**/*.html'

ci: lint privacy coverage ios-build app
