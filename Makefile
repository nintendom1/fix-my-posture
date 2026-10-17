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
	@python3 -c 'import shutil; from pathlib import Path; p = Path("build/design/actual"); shutil.rmtree(p, ignore_errors=True); p.mkdir(parents=True, exist_ok=True)'
	TEST_RUNNER_FMP_SNAPSHOT_DIR="$(PWD)/build/design/actual" xcodebuild test \
		-project PostureAnalysisApp.xcodeproj \
		-scheme PostureAnalysisApp \
		-destination '$(DESIGN_DESTINATION)' \
		-derivedDataPath build/design/snapshots \
		-parallel-testing-enabled NO \
		-only-testing:PostureAnalysisAppTests/DesignHarnessTests \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testTrainFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testTrainScrolledBy200KeepsCompactHeaderAndSettingsReachable \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testRoutinesFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testRoutineDetailFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testRoutineEditorFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testRoutineEditorPickerFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testNewRoutineFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testLibraryFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testExerciseDetailFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testWorkoutCameraReadyFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testWorkoutCameraActiveFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testWorkoutCameraPausedFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testWorkoutCameraTipFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testWorkoutCameraRestCoachMutedFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testWorkoutCameraLostMicOffFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testWorkoutCameraTiltFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testWorkoutCompleteFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testProgressFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testHistoryFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testPostureFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testAssessmentFrame \
		-only-testing:PostureAnalysisAppTests/DesignMetricsTests/testSettingsFrame \
		CODE_SIGNING_ALLOWED=NO

design-diff:
	@if [ ! -f "$(DESIGN_BUNDLE)" ]; then \
		echo "Skipping design-diff: local design bundle is absent."; \
	else \
		swift scripts/design/diff.swift --tolerance 16; \
	fi

design-check: design-reference design-snapshots design-diff
	@if [ -f build/design/diff/summary.json ]; then cat build/design/diff/summary.json; fi
