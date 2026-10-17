.PHONY: ios ios-devices design-reference design-snapshots design-diff design-check

DESIGN_BUNDLE := fix-my-posture-mobile-app-design/project/Fix My Posture Redesign.dc.html
DESIGN_DESTINATION ?= platform=iOS Simulator,name=iPhone 15 Pro

ios:
	@bash scripts/run-ios.sh

ios-devices:
	@xcrun devicectl list devices --timeout 30

design-reference:
	@if [ ! -f "$(DESIGN_BUNDLE)" ]; then \
		echo "Skipping design-reference: local design bundle is absent."; \
	else \
		node scripts/design/render.mjs; \
	fi

design-snapshots:
	@mkdir -p build/design/actual
	TEST_RUNNER_FMP_SNAPSHOT_DIR="$(PWD)/build/design/actual" xcodebuild test \
		-project PostureAnalysisApp.xcodeproj \
		-scheme PostureAnalysisApp \
		-destination '$(DESIGN_DESTINATION)' \
		-derivedDataPath build/design/snapshots \
		-parallel-testing-enabled NO \
		-only-testing:PostureAnalysisAppTests/DesignHarnessTests \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testTrainFrame \
		CODE_SIGNING_ALLOWED=NO

design-diff:
	@if [ ! -f "$(DESIGN_BUNDLE)" ]; then \
		echo "Skipping design-diff: local design bundle is absent."; \
	else \
		swift scripts/design/diff.swift; \
	fi

design-check: design-reference design-snapshots design-diff
	@if [ -f build/design/diff/summary.json ]; then cat build/design/diff/summary.json; fi
