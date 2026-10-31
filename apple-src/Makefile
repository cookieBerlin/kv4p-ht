# Single entry point for local development and CI (ADR-0013).
# CI only calls these targets; never duplicate the commands elsewhere.

SWIFT ?= swift
IOS_DESTINATION ?= generic/platform=iOS
# The vector generator needs JDK 17 (Gradle 9 does not run on newer JDKs).
JAVA17_HOME ?= $(shell /usr/libexec/java_home -F -v 17 2>/dev/null || echo "$$(brew --prefix openjdk@17 2>/dev/null)/libexec/openjdk.jdk/Contents/Home")
GRADLEW := ../android-src/KV4PHT/gradlew
VECTORS := Packages/*/Tests/*/Vectors/*
# SwiftPM names the scheme <package>-Package once there are several products.
SCHEME ?= $(shell xcodebuild -list -json 2>/dev/null | jq -r '.workspace.schemes | (map(select(endswith("-Package")))[0] // .[0])')

.PHONY: test coverage lint format privacy changed vectors vectors-check ios-build ci

test:
	$(SWIFT) test

coverage:
	$(SWIFT) test --enable-code-coverage
	scripts/coverage-gate.sh "$$($(SWIFT) test --show-codecov-path)"

lint:
	$(SWIFT) format lint --strict --recursive --parallel Package.swift Packages

format:
	$(SWIFT) format --in-place --recursive --parallel Package.swift Packages

privacy:
	scripts/privacy-check.sh $(BASE) $(HEAD_REF)

# Prints true/false: does BASE...HEAD_REF touch an Apple port path?
changed:
	@scripts/apple-changed.sh $(BASE) $(HEAD_REF)

# Regenerates the golden test vectors from the unmodified Android code (ADR-0004).
vectors:
	JAVA_HOME="$(JAVA17_HOME)" $(GRADLEW) --quiet --project-dir ../tools/test-vectors run

# Fails if the committed vectors differ from the generator output.
vectors-check: vectors
	@if [ -n "$$(git status --porcelain --untracked-files=all -- '$(VECTORS)')" ]; then \
		echo "vectors: committed vectors are out of date, run 'make vectors' and commit:" >&2; \
		git status --short --untracked-files=all -- '$(VECTORS)' >&2; exit 1; fi
	@echo "vectors: ok"

ios-build:
	xcodebuild build -quiet -scheme '$(SCHEME)' -destination '$(IOS_DESTINATION)'

ci: lint privacy coverage ios-build
