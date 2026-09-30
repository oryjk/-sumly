SIM ?= iPhone 17

.PHONY: generate build test test-auth open upload

generate:
	xcodegen generate

build: generate
	xcodebuild -project Sumly.xcodeproj -scheme Sumly \
		-destination 'platform=iOS Simulator,name=$(SIM)' build

test: generate
	xcodebuild -project Sumly.xcodeproj -scheme Sumly \
		-destination 'platform=iOS Simulator,name=$(SIM)' test

open: generate
	open Sumly.xcodeproj

upload:
	bash scripts/upload_app_store.sh

# Auth core only; no simulator, backend, or delivery-provider access.
test-auth:
	swift test
