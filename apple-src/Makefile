# Single entry point for local development and CI (ADR-0013).
# CI only calls these targets; never duplicate the commands elsewhere.

SWIFT ?= swift
IOS_DESTINATION ?= generic/platform=iOS
# The vector generator needs JDK 17 (Gradle 9 does not run on newer JDKs).
JAVA17_HOME ?= $(shell /usr/libexec/java_home -F -v 17 2>/dev/null || echo "$$(brew --prefix openjdk@17 2>/dev/null)/libexec/openjdk.jdk/Contents/Home")
GRADLEW := ../android-src/KV4PHT/gradlew
VECTORS := Packages/*/Tests/*/Vectors/*
# Codec2, vendored by tools/codec2-vectors together with its vectors (ADR-0027).
VENDORED := Packages/KV4PDigital/Sources/CCodec2 Packages/KV4PDigital/COPYING-codec2
# SwiftPM names the scheme <package>-Package once there are several products.
SCHEME ?= $(shell xcodebuild -list -json 2>/dev/null | jq -r '.workspace.schemes | (map(select(endswith("-Package")))[0] // .[0])')

APP_PROJECT := App/KV4PHT.xcodeproj
SWIFT_SOURCES := Package.swift Packages App

.PHONY: test coverage lint format privacy changed vectors vectors-check ios-build app ci

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
		git status --short --untracked-files=all -- '$(VECTORS)' $(VENDORED) >&2; exit 1; fi
	@echo "vectors: ok"

ios-build:
	xcodebuild build -quiet -scheme '$(SCHEME)' -destination '$(IOS_DESTINATION)'

# Builds the app (ADR-0019) for macOS and iOS without code signing.
app:
	xcodebuild build -quiet -project $(APP_PROJECT) -scheme KV4PHT -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
	xcodebuild build -quiet -project $(APP_PROJECT) -scheme KV4PHT -destination '$(IOS_DESTINATION)' CODE_SIGNING_ALLOWED=NO

ci: lint privacy coverage ios-build app
