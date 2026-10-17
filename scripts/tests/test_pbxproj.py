import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HELPER = REPO_ROOT / "scripts" / "pbxproj.py"
PROJECT_RELATIVE = Path("PostureAnalysisApp.xcodeproj/project.pbxproj")
APP_RELATIVE = Path("PostureAnalysisApp")
ID_PREFIX = "10000012B"


class PbxprojTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        shutil.copytree(REPO_ROOT / "PostureAnalysisApp", self.root / APP_RELATIVE)
        project_path = self.root / PROJECT_RELATIVE
        project_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO_ROOT / PROJECT_RELATIVE, project_path)

    def tearDown(self):
        self.temporary_directory.cleanup()

    @property
    def project_path(self):
        return self.root / PROJECT_RELATIVE

    def project_text(self):
        return self.project_path.read_text()

    def write_project_text(self, contents):
        self.project_path.write_text(contents)

    def run_helper(self, *arguments):
        return subprocess.run(
            [sys.executable, str(HELPER), *arguments],
            cwd=self.root,
            text=True,
            capture_output=True,
            check=False,
        )

    def add_swift_file(self, relative_path, contents="struct Example {}\n"):
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        return path

    def assert_command_succeeded(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def source_phase_blocks(self, project_text=None):
        text = project_text or self.project_text()
        matches = list(
            re.finditer(
                r"(?m)^\s*([A-Z0-9]+) /\* (?:Sources|TestSources) \*/ = \{\n"
                r"(?:(?!^\s*\};).)*?^\s*\};",
                text,
                re.DOTALL,
            )
        )
        return matches

    def test_add_assigns_next_id(self):
        path = "PostureAnalysisApp/Utilities/NewHelper.swift"
        self.add_swift_file(path)

        result = self.run_helper("add", path)

        self.assert_command_succeeded(result)
        text = self.project_text()
        self.assertIn(f"A{ID_PREFIX}00000000000142", text)
        self.assertIn(f"B{ID_PREFIX}00000000000142", text)
        self.assertNotRegex(text, rf"[AB]{ID_PREFIX}0000000000013[89]")
        self.assertNotRegex(text, rf"[AB]{ID_PREFIX}0000000000014[01]")

    def test_add_idempotent(self):
        path = "PostureAnalysisApp/Utilities/Idempotent.swift"
        self.add_swift_file(path)

        self.assert_command_succeeded(self.run_helper("add", path))
        after_first_add = self.project_text()
        self.assert_command_succeeded(self.run_helper("add", path))

        self.assertEqual(self.project_text(), after_first_add)
        self.assertEqual(after_first_add.count("B10000012B00000000000142 /* Idempotent.swift */ ="), 1)
        self.assertEqual(after_first_add.count("A10000012B00000000000142 /* Idempotent.swift in Sources */ ="), 1)

    def test_add_creates_missing_groups(self):
        path = "PostureAnalysisApp/DesignSystem/Colors/Palette.swift"
        self.add_swift_file(path)

        self.assert_command_succeeded(self.run_helper("add", path))

        text = self.project_text()
        self.assertIn(f"H{ID_PREFIX}00000000000027 /* DesignSystem */", text)
        self.assertIn(f"H{ID_PREFIX}00000000000028 /* Colors */", text)
        self.assertIn("path = DesignSystem;", text)
        self.assertIn("path = Colors;", text)
        self.assertIn("Palette.swift", text)

    def test_add_routes_tests_to_test_target(self):
        path = "PostureAnalysisApp/Tests/NewFeatureTests.swift"
        self.add_swift_file(path)

        self.assert_command_succeeded(self.run_helper("add", path))

        text = self.project_text()
        build_file_id = f"A{ID_PREFIX}00000000000142"
        test_phase = next(
            match.group(0)
            for match in self.source_phase_blocks(text)
            if "TestSources" in match.group(0)
        )
        app_phase = next(
            match.group(0)
            for match in self.source_phase_blocks(text)
            if "/* Sources */" in match.group(0)
        )
        self.assertIn(build_file_id, test_phase)
        self.assertNotIn(build_file_id, app_phase)

    def test_check_flags_unregistered(self):
        path = "PostureAnalysisApp/Utilities/Unregistered.swift"
        self.add_swift_file(path)

        result = self.run_helper("check")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(path, result.stdout + result.stderr)

    def test_check_flags_missing_on_disk(self):
        (self.root / "PostureAnalysisApp/Models/Landmark.swift").unlink()

        result = self.run_helper("check")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Landmark.swift", result.stdout + result.stderr)

    def test_check_flags_duplicate_or_wrong_target(self):
        original = self.project_text()
        file_reference_id = f"B{ID_PREFIX}00000000000002"
        build_file_id = f"A{ID_PREFIX}00000000000002"
        duplicate_line = next(
            line
            for line in original.splitlines()
            if line.startswith(f"\t\t{file_reference_id} ")
        )
        self.write_project_text(original.replace(duplicate_line, duplicate_line + "\n" + duplicate_line, 1))

        duplicate_result = self.run_helper("check")

        self.assertEqual(duplicate_result.returncode, 1, duplicate_result.stdout + duplicate_result.stderr)
        self.assertRegex(duplicate_result.stdout + duplicate_result.stderr, r"(?i)duplicate.*ID|ID.*duplicate")

        text = original
        app_phase = next(
            match for match in self.source_phase_blocks(text) if "/* Sources */" in match.group(0)
        )
        test_phase = next(
            match for match in self.source_phase_blocks(text) if "TestSources" in match.group(0)
        )
        app_block = app_phase.group(0)
        app_block = app_block.replace(f"{build_file_id} /* LandmarkType.swift in Sources */", "", 1)
        test_block = test_phase.group(0).replace(
            "files = (\n", "files = (\n\t\t\t\t" + f"{build_file_id} /* LandmarkType.swift in Sources */,\n", 1
        )
        text = text[:app_phase.start()] + app_block + text[app_phase.end():]
        phase_offset = len(app_block) - len(app_phase.group(0))
        test_start = test_phase.start() + (phase_offset if test_phase.start() > app_phase.start() else 0)
        test_end = test_start + len(test_phase.group(0))
        text = text[:test_start] + test_block + text[test_end:]
        self.write_project_text(text)

        wrong_target_result = self.run_helper("check")

        self.assertEqual(wrong_target_result.returncode, 1, wrong_target_result.stdout + wrong_target_result.stderr)
        self.assertRegex(wrong_target_result.stdout + wrong_target_result.stderr, r"target|Sources")

    def test_rename_keeps_ids(self):
        old_path = "PostureAnalysisApp/Models/Landmark.swift"
        new_path = "PostureAnalysisApp/NewModels/RenamedLandmark.swift"
        old_file = self.root / old_path
        new_file = self.root / new_path
        new_file.parent.mkdir(parents=True, exist_ok=True)
        old_file.rename(new_file)
        before = self.project_text()
        old_reference_id = re.search(
            rf"(?m)^\s*(B{ID_PREFIX}00000000000003) /\* Landmark.swift \*/", before
        ).group(1)
        old_build_file_id = re.search(
            rf"(?m)^\s*(A{ID_PREFIX}00000000000003) /\* Landmark.swift in Sources \*/", before
        ).group(1)

        result = self.run_helper("rename", old_path, new_path)

        self.assert_command_succeeded(result)
        after = self.project_text()
        self.assertIn(f"{old_reference_id} /* RenamedLandmark.swift */", after)
        self.assertIn(f"{old_build_file_id} /* RenamedLandmark.swift in Sources */", after)
        self.assertIn("NewModels", after)
        self.assertNotIn(f"{old_build_file_id} /* Landmark.swift in Sources */", after)
        self.assert_command_succeeded(self.run_helper("check"))

    def test_remove_deletes_all_entries(self):
        path = "PostureAnalysisApp/Models/Landmark.swift"
        self.assert_command_succeeded(self.run_helper("remove", path))

        text = self.project_text()
        self.assertNotIn("Landmark.swift", text)
        self.assertNotIn(f"A{ID_PREFIX}00000000000003", text)
        self.assertNotIn(f"B{ID_PREFIX}00000000000003", text)

    def test_id_base_floor(self):
        path = "PostureAnalysisApp/Utilities/Floored.swift"
        self.add_swift_file(path)

        result = self.run_helper("--id-base", "500", "add", path)

        self.assert_command_succeeded(result)
        self.assertIn(f"A{ID_PREFIX}00000000000500", self.project_text())
        self.assertIn(f"B{ID_PREFIX}00000000000500", self.project_text())

    def test_check_passes_on_current_project(self):
        result = self.run_helper("check")

        self.assert_command_succeeded(result)


if __name__ == "__main__":
    unittest.main()
