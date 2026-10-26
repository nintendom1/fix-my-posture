.PHONY: ios ios-devices diagnostics viewer replay-sessions design-reference design-snapshots design-diff design-check notification-character notification-character-check

DESIGN_BUNDLE := fix-my-posture-mobile-app-design/project/Fix My Posture Redesign.dc.html
DESIGN_DESTINATION ?= platform=iOS Simulator,name=iPhone 15 Pro

CHARACTER_DIR := Design/NotificationCharacter
CHARACTER_VENV := build/notification-character/venv
CHARACTER_ARGS ?=

ios:
	@bash scripts/run-ios.sh

ios-devices:
	@xcrun devicectl list devices --timeout 30

# Copies developer workout recordings from the iPhone into diagnostics/sessions/ (gitignored).
diagnostics:
	@bash scripts/diagnostics/pull.sh

# Opens the session replay viewer for those recordings at http://127.0.0.1:4317 (Ctrl-C stops it).
viewer:
	@node tools/session-replay/server.mjs --open

# Replays pulled recordings through the current pipeline: each must reproduce the reps the phone counted, and
# build/replay-report.txt lists every attempt the analyzers let go. SESSION_DIR defaults to diagnostics/sessions.
SESSION_DIR ?= diagnostics/sessions
replay-sessions:
	@mkdir -p build && rm -f build/replay-report.txt
	@dir="$$(cd "$(SESSION_DIR)" && pwd)" || exit 1; status=0; \
		TEST_RUNNER_FMP_SESSION_DIR="$$dir" TEST_RUNNER_FMP_REPLAY_REPORT="$$PWD/build/replay-report.txt" \
		xcodebuild test -project PostureAnalysisApp.xcodeproj -scheme PostureAnalysisApp \
		-destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
		-only-testing:PostureAnalysisAppTests/WorkoutSessionReplayTests/testLocalRecordingsReplayToWhatThePhoneCounted \
		> build/replay-sessions.log 2>&1 || status=$$?; \
		grep -E "error:|Executed .* tests|TEST (SUCCEEDED|FAILED)" build/replay-sessions.log | sort -u; \
		cat build/replay-report.txt 2>/dev/null; exit $$status

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

# Pinned psd-tools and Pillow live in an ignored venv, rebuilt whenever requirements.txt changes.
$(CHARACTER_VENV)/.installed: $(CHARACTER_DIR)/requirements.txt
	python3 -m venv $(CHARACTER_VENV)
	$(CHARACTER_VENV)/bin/pip install --quiet --disable-pip-version-check -r $(CHARACTER_DIR)/requirements.txt
	@touch $@

# make notification-character                                             rewrite the example PNGs and the app's notification assets
# make notification-character CHARACTER_ARGS="--character canonical --crop close-up"
# make notification-character CHARACTER_ARGS=--list                       show valid characters, crops, layers
notification-character: $(CHARACTER_VENV)/.installed
ifeq ($(strip $(CHARACTER_ARGS)),)
	$(CHARACTER_VENV)/bin/python $(CHARACTER_DIR)/render_character.py --examples
	$(CHARACTER_VENV)/bin/python $(CHARACTER_DIR)/render_character.py --assets
else
	$(CHARACTER_VENV)/bin/python $(CHARACTER_DIR)/render_character.py $(CHARACTER_ARGS)
endif

notification-character-check: $(CHARACTER_VENV)/.installed
	$(CHARACTER_VENV)/bin/python $(CHARACTER_DIR)/render_character.py --check
	$(CHARACTER_VENV)/bin/python -m unittest discover -s scripts/tests -q
