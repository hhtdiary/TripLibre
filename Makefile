# One-command workflows. Run `make help`.
# Needs: Xcode (xcode-select pointing at it), xcodegen (brew install xcodegen), python3.

SCHEME      := HHT
PROJECT     := HHT.xcodeproj
BUILD_DIR   := .build-xcode
SIM_NAME    ?= iPhone 17
EXPORT_DIR  := $(BUILD_DIR)/export-check
PY          := analysis/.venv/bin/python

CAL_DIR     := $(BUILD_DIR)/calibrate-smoke
CALIBRATE   := Packages/HHTCore/.build/release/hht-calibrate

.PHONY: help test project build sim phone analysis-env export-check calibrate-tool calibrate-smoke lint swift-lint swiftlint-baseline a11y ui-test ci clean

help:            ## list targets
	@grep -E '^[a-z0-9-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-14s %s\n", $$1, $$2}'

test:            ## run the core test suite (inference, edits, export, analytics)
	cd Packages/HHTCore && swift test

project:         ## regenerate HHT.xcodeproj from project.yml
	xcodegen generate

build: project   ## compile the iOS app for the simulator (no signing)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(BUILD_DIR) CODE_SIGNING_ALLOWED=NO build | tail -3

sim: build       ## install + launch in the simulator with demo data (SIM_NAME="iPhone 17")
	xcrun simctl boot "$(SIM_NAME)" 2>/dev/null || true
	open -a Simulator
	xcrun simctl install "$(SIM_NAME)" $(BUILD_DIR)/Build/Products/Debug-iphonesimulator/HHT.app
	xcrun simctl launch "$(SIM_NAME)" com.zyang91.hht -hhtDemo YES

phone: project   ## build, sign and install on the USB-connected iPhone (also renews the 7-day signature)
	./scripts/install-phone.sh

ui-test: project ## XCUITest flows + accessibility audits in the simulator (SIM_NAME="iPhone 17" or SIM_ID=<udid>; ONLY=HHTUITests/CoreFlowTests)
	$(if $(RESULT_BUNDLE),rm -rf $(RESULT_BUNDLE))
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=iOS Simulator,$(if $(SIM_ID),id=$(SIM_ID),name=$(SIM_NAME))' \
		-derivedDataPath $(BUILD_DIR) CODE_SIGNING_ALLOWED=NO $(if $(ONLY),-only-testing:$(ONLY)) \
		$(if $(RESULT_BUNDLE),-resultBundlePath $(RESULT_BUNDLE)) test

analysis-env:    ## create analysis/.venv with pandas etc.
	python3 -m venv analysis/.venv
	$(PY) -m pip install -q -r analysis/requirements.txt

export-check:    ## end-to-end: Swift writes a real export, Python loads and validates it
	rm -rf $(EXPORT_DIR) && mkdir -p $(EXPORT_DIR)
	cd Packages/HHTCore && HHT_EXPORT_DIR=$(abspath $(EXPORT_DIR)) swift test --filter writeExportForPythonCheck
	cd analysis && $(if $(wildcard $(PY)),.venv/bin/python,python3) check_export.py $(abspath $(EXPORT_DIR))

calibrate-tool:  ## build the offline replay tool (runs the production inference engine; issue #46)
	cd Packages/HHTCore && swift build -c release --product hht-calibrate

calibrate-smoke: calibrate-tool  ## synthetic end-to-end calibration: fixture → replay ×2 (determinism) → export → evaluate
	rm -rf $(CAL_DIR) && mkdir -p $(CAL_DIR)
	cd Packages/HHTCore && HHT_CALIBRATION_DIR=$(abspath $(CAL_DIR)) swift test --filter writeCalibrationFixture
	$(CALIBRATE) replay --db $(CAL_DIR)/fixture.sqlite --out $(CAL_DIR)/pred.json
	$(CALIBRATE) replay --db $(CAL_DIR)/fixture.sqlite --out $(CAL_DIR)/pred2.json
	cmp $(CAL_DIR)/pred.json $(CAL_DIR)/pred2.json
	python3 analysis/calibrate.py export --db $(CAL_DIR)/fixture.sqlite --out $(CAL_DIR)/reference --reviewed-default 1 --review-note synthetic
	python3 analysis/calibrate.py evaluate --reference $(CAL_DIR)/reference --pred $(CAL_DIR)/pred.json --out $(CAL_DIR)/results --days all --db $(CAL_DIR)/fixture.sqlite
	python3 analysis/check_calibration.py $(CAL_DIR)/results/metrics-all.json

# npm writes node_modules/.package-lock.json on install, so this reinstalls whenever the lockfile changes.
node_modules/.package-lock.json: package-lock.json
	npm ci

lint: node_modules/.package-lock.json swift-lint   ## docs JS/CSS/HTML (incl. accessibility rules), Markdown, Python, Swift (needs node, ruff, swiftlint, swiftformat)
	npm run lint
	ruff check

# Same versions CI pins (.github/workflows/ci.yml). `brew install swiftlint swiftformat` gets you close enough.
swift-lint:      ## SwiftLint (new violations only) + SwiftFormat check; CI pins SwiftLint 0.65.1, SwiftFormat 0.63.1
	swiftlint lint --strict --quiet --baseline .swiftlint-baseline.json
	swiftformat --lint .

swiftlint-baseline:  ## re-record existing SwiftLint violations after fixing some (commit the result)
	swiftlint lint --quiet --write-baseline .swiftlint-baseline.json || true

a11y: node_modules/.package-lock.json   ## axe-core WCAG 2.1 AA check of every docs page, light + dark (needs node + Chromium)
	npx playwright install chromium
	npm run a11y

ci: lint a11y test build export-check calibrate-smoke   ## everything GitHub Actions runs except ui-test (slow; run it separately)

clean:
	rm -rf $(BUILD_DIR) Packages/HHTCore/.build
