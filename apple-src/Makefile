# Single entry point for local development and CI (ADR-0013).
# CI only calls these targets; never duplicate the commands elsewhere.

SWIFT ?= swift
IOS_DESTINATION ?= generic/platform=iOS
# SwiftPM names the scheme <package>-Package once there are several products.
SCHEME ?= $(shell xcodebuild -list -json 2>/dev/null | jq -r '.workspace.schemes | (map(select(endswith("-Package")))[0] // .[0])')

.PHONY: test coverage lint format privacy ios-build ci

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
	scripts/privacy-check.sh $(BASE)

ios-build:
	xcodebuild build -quiet -scheme '$(SCHEME)' -destination '$(IOS_DESTINATION)'

ci: lint privacy coverage ios-build
