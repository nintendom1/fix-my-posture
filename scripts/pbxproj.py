#!/usr/bin/env python3
"""Register Swift source files in the hand-maintained Xcode project."""

import argparse
import posixpath
import re
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


PROJECT_PATH = Path("PostureAnalysisApp.xcodeproj/project.pbxproj")
APP_PATH = PurePosixPath("PostureAnalysisApp")
ID_PREFIX = "10000012B"
ID_PATTERN = re.compile(r"[A-Z]10000012B\d{14}")
# These A/B numbers are reserved by a parked branch and must not be reused.
RESERVED_AB = {138, 139, 140, 141}


class PbxprojError(Exception):
    pass


@dataclass
class ObjectBlock:
    object_id: str
    comment: str
    start: int
    end: int
    body: str


@dataclass
class FileReference:
    object_id: str
    comment: str
    path: str
    source_type: str


@dataclass
class BuildFile:
    object_id: str
    comment: str
    file_ref: str


@dataclass
class Group:
    object_id: str
    comment: str
    path: str
    name: str
    children: list


def section_bounds(text, name):
    begin = f"/* Begin {name} section */"
    end = f"/* End {name} section */"
    start = text.find(begin)
    finish = text.find(end)
    if start == -1 or finish == -1 or finish < start:
        raise PbxprojError(f"Could not find the {name} section in {PROJECT_PATH}.")
    return start, finish + len(end)


def section_text(text, name):
    start, end = section_bounds(text, name)
    return text[start:end]


def section_object_blocks(text, section_name):
    start, end = section_bounds(text, section_name)
    section = text[start:end]
    pattern = re.compile(
        rf"(?m)^\t\t(?P<id>{ID_PATTERN.pattern}) /\* (?P<comment>.*?) \*/ = \{{\n"
        rf"(?P<body>.*?)^\t\t\}};",
        re.DOTALL,
    )
    return [
        ObjectBlock(
            match.group("id"),
            match.group("comment"),
            start + match.start(),
            start + match.end(),
            match.group("body"),
        )
        for match in pattern.finditer(section)
    ]


def pbx_value(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1].replace(r'\"', '"').replace(r"\\", "\\")
    return value


def pbx_path_value(value):
    if re.fullmatch(r"[A-Za-z0-9_./+\-]+", value):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', r'\"') + '"'


def group_records(text):
    groups = {}
    for block in section_object_blocks(text, "PBXGroup"):
        path_match = re.search(r"(?m)^\t\t\tpath = (.*?);$", block.body)
        name_match = re.search(r"(?m)^\t\t\tname = (.*?);$", block.body)
        children_match = re.search(
            r"(?ms)^\t\t\tchildren = \(\n(.*?)^\t\t\t\);", block.body
        )
        children = (
            re.findall(
                rf"(?m)^\s*({ID_PATTERN.pattern}) /\*.*?\*/,?\s*$",
                children_match.group(1),
            )
            if children_match
            else []
        )
        groups[block.object_id] = Group(
            block.object_id,
            block.comment,
            pbx_value(path_match.group(1)) if path_match else "",
            pbx_value(name_match.group(1)) if name_match else "",
            children,
        )
    return groups


def file_references(text):
    references = {}
    pattern = re.compile(
        rf"(?m)^\s*(?P<id>{ID_PATTERN.pattern}) /\* (?P<comment>.*?) \*/ = "
        rf"\{{isa = PBXFileReference; (?P<attrs>.*?) \}};\s*$"
    )
    for match in pattern.finditer(section_text(text, "PBXFileReference")):
        attrs = match.group("attrs")
        path_match = re.search(r"(?:^|; )path = (.*?);", attrs)
        type_match = re.search(r"(?:^|; )lastKnownFileType = (.*?);", attrs)
        if path_match:
            references[match.group("id")] = FileReference(
                match.group("id"),
                match.group("comment"),
                pbx_value(path_match.group(1)),
                pbx_value(type_match.group(1)) if type_match else "",
            )
    return references


def build_files(text):
    result = {}
    pattern = re.compile(
        rf"(?m)^\s*(?P<id>{ID_PATTERN.pattern}) /\* (?P<comment>.*?) \*/ = "
        rf"\{{isa = PBXBuildFile; fileRef = (?P<ref>{ID_PATTERN.pattern}) /\*.*?\*/; \}};\s*$"
    )
    for match in pattern.finditer(section_text(text, "PBXBuildFile")):
        result[match.group("id")] = BuildFile(
            match.group("id"), match.group("comment"), match.group("ref")
        )
    return result


def app_root_group(groups):
    candidates = [group.object_id for group in groups.values() if group.path == APP_PATH.name]
    if len(candidates) != 1:
        raise PbxprojError(
            f"Expected one PBXGroup with path = {APP_PATH.name}; found {len(candidates)}."
        )
    return candidates[0]


def group_index(text):
    groups = group_records(text)
    references = file_references(text)
    root_id = app_root_group(groups)
    occurrences = {}
    directories = {}

    def walk(group_id, directory, ancestry):
        if group_id in ancestry:
            return
        directories.setdefault(group_id, []).append(directory)
        group = groups[group_id]
        for child_id in group.children:
            if child_id in groups:
                child_group = groups[child_id]
                segment = child_group.path
                child_directory = posixpath.normpath(
                    posixpath.join(directory, segment) if segment else directory
                )
                walk(child_id, child_directory, ancestry | {group_id})
            elif child_id in references:
                reference = references[child_id]
                full_path = posixpath.normpath(posixpath.join(directory, reference.path))
                occurrences.setdefault(child_id, []).append((full_path, group_id))

    root_path = groups[root_id].path
    walk(root_id, root_path, set())
    return groups, references, root_id, occurrences, directories


def target_source_phases(text):
    source_blocks = {
        block.object_id: block
        for block in section_object_blocks(text, "PBXSourcesBuildPhase")
        if re.search(r"(?m)^\t\t\tisa = PBXSourcesBuildPhase;$", block.body)
    }
    target_map = {}
    for block in section_object_blocks(text, "PBXNativeTarget"):
        if not re.search(r"(?m)^\t\t\tisa = PBXNativeTarget;$", block.body):
            continue
        name_match = re.search(r"(?m)^\t\t\tname = (.*?);$", block.body)
        phases_match = re.search(
            r"(?ms)^\t\t\tbuildPhases = \(\n(.*?)^\t\t\t\);", block.body
        )
        if not name_match or not phases_match:
            continue
        target_name = pbx_value(name_match.group(1))
        for phase_id in re.findall(ID_PATTERN, phases_match.group(1)):
            if phase_id in source_blocks:
                target_map[phase_id] = target_name

    memberships = {}
    for phase_id, block in source_blocks.items():
        files_match = re.search(r"(?ms)^\t\t\tfiles = \(\n(.*?)^\t\t\t\);", block.body)
        if not files_match:
            continue
        memberships[phase_id] = re.findall(ID_PATTERN, files_match.group(1))
    return target_map, memberships


def target_phase_for(text, target_name):
    targets, _ = target_source_phases(text)
    matches = [phase_id for phase_id, name in targets.items() if name == target_name]
    if len(matches) != 1:
        raise PbxprojError(
            f"Expected one Sources phase for target {target_name}; found {len(matches)}."
        )
    return matches[0]


def expected_target(path):
    parts = PurePosixPath(path).parts
    if len(parts) > 1 and parts[1] == "Tests":
        return "PostureAnalysisAppTests"
    return "PostureAnalysisApp"


def validate_swift_path(raw_path, must_exist=False):
    normalized = raw_path.replace("\\", "/")
    pure_path = PurePosixPath(normalized)
    if pure_path.is_absolute() or ".." in pure_path.parts:
        raise PbxprojError(f"Path must be repository-relative: {raw_path}")
    path = PurePosixPath(posixpath.normpath(normalized))
    if not path.parts or path.parts[0] != APP_PATH.name or len(path.parts) < 2:
        raise PbxprojError(f"Path must be under {APP_PATH.name}/: {raw_path}")
    if path.suffix != ".swift":
        raise PbxprojError(f"Only Swift source files can be registered: {raw_path}")
    if must_exist and not (Path.cwd() / Path(*path.parts)).is_file():
        raise PbxprojError(f"Swift file does not exist: {path}")
    return path.as_posix()


def next_ab_id(text, id_base):
    definitions = re.findall(
        rf"(?m)^\t\t([AB]){ID_PREFIX}(\d{{14}}) /\*.*?\*/\s*=",
        text,
    )
    used = {int(number) for _, number in definitions}
    return max(max(used | RESERVED_AB, default=0) + 1, id_base)


def next_group_id(text):
    definitions = re.findall(
        rf"(?m)^\t\tH{ID_PREFIX}(\d{{14}}) /\*.*?\*/\s*=", text
    )
    used = [int(number) for number in definitions]
    return "H" + ID_PREFIX + f"{max(used, default=0) + 1:014d}"


def insert_section_line(text, section_name, line):
    marker = f"/* End {section_name} section */"
    index = text.index(marker)
    return text[:index] + line + "\n" + text[index:]


def update_group_children(text, group_id, child_id, comment, remove=False):
    blocks = section_object_blocks(text, "PBXGroup")
    block = next((item for item in blocks if item.object_id == group_id), None)
    if block is None:
        raise PbxprojError(f"Missing parent group {group_id}.")
    segment = text[block.start:block.end]
    lines = segment.splitlines(keepends=True)
    child_line = re.compile(rf"^\s*{re.escape(child_id)} /\*.*?\*/,\s*$")
    if remove:
        updated = [line for line in lines if not child_line.match(line.rstrip("\n"))]
    else:
        if any(child_line.match(line.rstrip("\n")) for line in lines):
            return text
        close_index = next(
            (index for index, line in enumerate(lines) if line.rstrip("\n") == "\t\t\t);"),
            None,
        )
        if close_index is None:
            raise PbxprojError(f"Group {group_id} has no children list.")
        lines.insert(close_index, f"\t\t\t\t{child_id} /* {comment} */,\n")
        updated = lines
    replacement = "".join(updated)
    return text[:block.start] + replacement + text[block.end:]


def create_group(text, parent_id, name):
    group_id = next_group_id(text)
    group = (
        f"\t\t{group_id} /* {name} */ = {{\n"
        "\t\t\tisa = PBXGroup;\n"
        "\t\t\tchildren = (\n"
        "\t\t\t);\n"
        f"\t\t\tpath = {pbx_path_value(name)};\n"
        '\t\t\tsourceTree = "<group>";\n'
        "\t\t};\n"
    )
    text = insert_section_line(text, "PBXGroup", group.rstrip("\n"))
    text = update_group_children(text, parent_id, group_id, name)
    return text, group_id


def ensure_parent_group(text, path):
    groups, _, root_id, _, _ = group_index(text)
    current_id = root_id
    path_parts = PurePosixPath(path).parts
    for segment in path_parts[1:-1]:
        groups = group_records(text)
        parent = groups[current_id]
        child_group_id = next(
            (
                child_id
                for child_id in parent.children
                if child_id in groups and groups[child_id].path == segment
            ),
            None,
        )
        if child_group_id is None:
            text, child_group_id = create_group(text, current_id, segment)
        current_id = child_group_id
    return text, current_id


def source_entry(build_id, filename, target):
    label = "TestSources" if target == "PostureAnalysisAppTests" else "Sources"
    return f"\t\t\t\t{build_id} /* {filename} in {label} */,"


def insert_source_entry(text, phase_id, entry):
    block = next(
        (item for item in section_object_blocks(text, "PBXSourcesBuildPhase") if item.object_id == phase_id),
        None,
    )
    if block is None:
        raise PbxprojError(f"Missing Sources phase {phase_id}.")
    segment = text[block.start:block.end]
    files_close = re.search(r"(?m)^\t\t\t\);$", segment)
    if not files_close:
        raise PbxprojError(f"Sources phase {phase_id} has no files list.")
    insertion = block.start + files_close.start()
    return text[:insertion] + entry + "\n" + text[insertion:]


def remove_source_entry(text, phase_id, build_id):
    block = next(
        (item for item in section_object_blocks(text, "PBXSourcesBuildPhase") if item.object_id == phase_id),
        None,
    )
    if block is None:
        raise PbxprojError(f"Missing Sources phase {phase_id}.")
    segment = text[block.start:block.end]
    lines = segment.splitlines(keepends=True)
    updated = [
        line
        for line in lines
        if not re.search(rf"\b{re.escape(build_id)}\b", line)
    ]
    return text[:block.start] + "".join(updated) + text[block.end:]


def remove_lines_for_ids(text, ids):
    ids = set(ids)
    if not ids:
        return text
    id_patterns = [re.compile(rf"\b{re.escape(object_id)}\b") for object_id in ids]
    lines = text.splitlines(keepends=True)
    return "".join(
        line
        for line in lines
        if not any(pattern.search(line) for pattern in id_patterns)
    )


def register_file(text, path, id_base):
    groups, references, _, occurrences, _ = group_index(text)
    already_registered = any(
        full_path == path
        for file_id, locations in occurrences.items()
        for full_path, _ in locations
    )
    if already_registered:
        return text, False, id_base

    text, parent_id = ensure_parent_group(text, path)
    number = next_ab_id(text, id_base)
    file_id = f"B{ID_PREFIX}{number:014d}"
    build_id = f"A{ID_PREFIX}{number:014d}"
    filename = PurePosixPath(path).name
    target = expected_target(path)
    suffix = "TestSources" if target == "PostureAnalysisAppTests" else "Sources"
    build_entry = (
        f"\t\t{build_id} /* {filename} in {suffix} */ = "
        f"{{isa = PBXBuildFile; fileRef = {file_id} /* {filename} */; }};"
    )
    file_entry = (
        f"\t\t{file_id} /* {filename} */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f"path = {pbx_path_value(filename)}; sourceTree = \"<group>\"; }};"
    )
    text = insert_section_line(text, "PBXBuildFile", build_entry)
    text = insert_section_line(text, "PBXFileReference", file_entry)
    text = update_group_children(text, parent_id, file_id, filename)
    phase_id = target_phase_for(text, target)
    text = insert_source_entry(text, phase_id, source_entry(build_id, filename, target))
    return text, True, number + 1


def path_occurrences(text, path):
    _, references, _, locations, _ = group_index(text)
    return [
        (file_id, reference, full_path, group_id)
        for file_id, reference in references.items()
        for full_path, group_id in locations.get(file_id, [])
        if full_path == path
    ]


def add_files(root, paths, id_base):
    project_path = root / PROJECT_PATH
    text = project_path.read_text()
    for raw_path in paths:
        path = validate_swift_path(raw_path, must_exist=True)
        text, added, _ = register_file(text, path, id_base)
        if added:
            print(f"Registered {path}")
        else:
            print(f"Already registered: {path}")
        id_base = max(id_base, next_ab_id(text, id_base))
    project_path.write_text(text)


def rename_file(root, old_raw_path, new_raw_path):
    old_path = validate_swift_path(old_raw_path)
    new_path = validate_swift_path(new_raw_path, must_exist=True)
    if old_path == new_path:
        return
    project_path = root / PROJECT_PATH
    text = project_path.read_text()
    matches = path_occurrences(text, old_path)
    if len(matches) != 1:
        raise PbxprojError(f"Expected one registered file at {old_path}; found {len(matches)}.")
    file_id, reference, _, old_parent_id = matches[0]
    build_file_map = build_files(text)
    build_ids = [
        build_id for build_id, entry in build_file_map.items() if entry.file_ref == file_id
    ]
    if len(build_ids) != 1:
        raise PbxprojError(f"Expected one PBXBuildFile for {old_path}; found {len(build_ids)}.")
    build_id = build_ids[0]
    _, memberships = target_source_phases(text)
    old_phases = [phase_id for phase_id, entries in memberships.items() if build_id in entries]
    if len(old_phases) != 1:
        raise PbxprojError(f"Expected one Sources phase entry for {old_path}; found {len(old_phases)}.")
    old_target_map, _ = target_source_phases(text)
    old_target = old_target_map.get(old_phases[0])
    new_target = expected_target(new_path)

    # Move the file reference into its destination group before updating paths.
    text = update_group_children(text, old_parent_id, file_id, reference.path, remove=True)
    text, new_parent_id = ensure_parent_group(text, new_path)
    new_name = PurePosixPath(new_path).name
    old_name = reference.path
    text = remove_source_entry(text, old_phases[0], build_id)

    lines = text.splitlines(keepends=True)
    updated_lines = []
    for line in lines:
        if re.search(rf"\b{re.escape(file_id)}\b|\b{re.escape(build_id)}\b", line):
            line = line.replace(old_name, new_name)
            if re.match(rf"\s*{re.escape(file_id)}\s", line):
                line = re.sub(r"(?<=path = ).*?(?=;)", pbx_path_value(new_name), line, count=1)
            if re.search(rf"\b{re.escape(build_id)}\b", line):
                line = re.sub(
                    r"in (?:TestSources|Sources)",
                    "in TestSources" if new_target == "PostureAnalysisAppTests" else "in Sources",
                    line,
                    count=1,
                )
        updated_lines.append(line)
    text = "".join(updated_lines)
    text = update_group_children(text, new_parent_id, file_id, new_name)
    phase_id = target_phase_for(text, new_target)
    text = insert_source_entry(text, phase_id, source_entry(build_id, new_name, new_target))
    project_path.write_text(text)
    print(f"Renamed registration {old_path} -> {new_path}")


def remove_files(root, paths):
    project_path = root / PROJECT_PATH
    text = project_path.read_text()
    ids_to_remove = set()
    for raw_path in paths:
        path = validate_swift_path(raw_path)
        matches = path_occurrences(text, path)
        if not matches:
            raise PbxprojError(f"No registered file found at {path}.")
        file_ids = {file_id for file_id, _, _, _ in matches}
        build_file_map = build_files(text)
        build_ids = {
            build_id
            for build_id, entry in build_file_map.items()
            if entry.file_ref in file_ids
        }
        ids_to_remove.update(file_ids | build_ids)
        print(f"Removed registration {path}")
    text = remove_lines_for_ids(text, ids_to_remove)
    project_path.write_text(text)


def check_project(root):
    project_path = root / PROJECT_PATH
    text = project_path.read_text()
    problems = []

    definition_ids = re.findall(
        rf"(?m)^\t\t({ID_PATTERN.pattern}) /\*.*?\*/\s*=", text
    )
    seen = set()
    duplicates = set()
    for object_id in definition_ids:
        if object_id in seen:
            duplicates.add(object_id)
        seen.add(object_id)
    for object_id in sorted(duplicates):
        problems.append(f"Duplicate object ID: {object_id}")

    try:
        groups, references, _, occurrences, _ = group_index(text)
        source_targets, phase_memberships = target_source_phases(text)
        build_file_map = build_files(text)
    except PbxprojError as error:
        problems.append(str(error))
        return problems

    swift_references = {
        file_id: reference
        for file_id, reference in references.items()
        if reference.source_type == "sourcecode.swift"
    }
    registered_paths = {}
    for file_id, reference in swift_references.items():
        locations = occurrences.get(file_id, [])
        if not locations:
            problems.append(f"Registered Swift file is not in an app group: {reference.comment}")
            continue
        if len(locations) != 1:
            problems.append(
                f"Registered Swift file appears {len(locations)} times in groups: "
                f"{locations[0][0]} ({file_id})"
            )
        full_path = locations[0][0]
        registered_paths.setdefault(full_path, []).append(file_id)
        disk_path = root / Path(*PurePosixPath(full_path).parts)
        if not disk_path.is_file():
            problems.append(f"Registered file is missing on disk: {full_path}")

        expected = expected_target(full_path)
        matching_builds = [
            (build_id, entry)
            for build_id, entry in build_file_map.items()
            if entry.file_ref == file_id
        ]
        if len(matching_builds) != 1:
            problems.append(
                f"{full_path} has {len(matching_builds)} PBXBuildFile entries; expected exactly one."
            )
            continue
        build_id, _ = matching_builds[0]
        phase_locations = [
            phase_id
            for phase_id, entries in phase_memberships.items()
            for entry_id in entries
            if entry_id == build_id
        ]
        if len(phase_locations) != 1:
            problems.append(
                f"{full_path} has {len(phase_locations)} Sources phase entries; expected exactly one."
            )
        for phase_id in phase_locations:
            actual = source_targets.get(phase_id, "unknown target")
            if actual != expected:
                problems.append(
                    f"{full_path} is in the {actual} Sources phase; expected {expected}."
                )

    swift_root = root / Path(*APP_PATH.parts)
    if swift_root.is_dir():
        disk_swift_paths = {
            path.relative_to(root).as_posix()
            for path in swift_root.rglob("*.swift")
            if path.is_file()
        }
        for path in sorted(disk_swift_paths):
            count = len(registered_paths.get(path, []))
            if count == 0:
                problems.append(f"Unregistered Swift file: {path}")
            elif count > 1:
                problems.append(f"Swift file is registered {count} times: {path}")

    return problems


def parse_args(arguments):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--id-base",
        type=int,
        default=0,
        help="minimum A/B ID number to allocate (default: next available project ID)",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    add_parser = subparsers.add_parser("add", help="register Swift files")
    add_parser.add_argument("paths", nargs="+")
    rename_parser = subparsers.add_parser("rename", help="update a registered Swift path")
    rename_parser.add_argument("old_path")
    rename_parser.add_argument("new_path")
    remove_parser = subparsers.add_parser("remove", help="remove Swift registrations")
    remove_parser.add_argument("paths", nargs="+")
    subparsers.add_parser("check", help="check Swift registrations")
    args = parser.parse_args(arguments)
    if args.id_base < 0 or args.id_base >= 10**14:
        parser.error("--id-base must be between 0 and 99999999999999")
    return args


def main(arguments=None):
    args = parse_args(arguments)
    root = Path.cwd()
    project_path = root / PROJECT_PATH
    if not project_path.is_file():
        print(f"Error: project file not found: {project_path}", file=sys.stderr)
        return 1
    try:
        if args.command == "add":
            add_files(root, args.paths, args.id_base)
            return 0
        if args.command == "rename":
            rename_file(root, args.old_path, args.new_path)
            return 0
        if args.command == "remove":
            remove_files(root, args.paths)
            return 0
        problems = check_project(root)
        if problems:
            for problem in problems:
                print(f"ERROR: {problem}")
            return 1
        print("Project Swift registrations are consistent.")
        return 0
    except (OSError, PbxprojError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
