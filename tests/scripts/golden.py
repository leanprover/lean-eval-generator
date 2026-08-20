#!/usr/bin/env python3
"""Byte-for-byte parity tests against checked-in LeanEval workspaces."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tomllib
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_IDS = json.loads(
    (PACKAGE_ROOT / "tests/fixtures/problem_ids.json").read_text(encoding="utf-8")
)


def run(command: list[str], *, cwd: Path, stdin: str | None = None) -> str:
    result = subprocess.run(
        command,
        cwd=cwd,
        input=stdin,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(command)}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result.stdout


def module_path(root: Path, module: str) -> Path:
    return root.joinpath(*module.split(".")).with_suffix(".lean")


def mathlib_pin(root: Path) -> dict[str, str]:
    lakefile = tomllib.loads((root / "lakefile.toml").read_text(encoding="utf-8"))
    matches = [item for item in lakefile["require"] if item["name"] == "mathlib"]
    if len(matches) != 1:
        raise RuntimeError("expected exactly one Mathlib dependency")
    return matches[0]


def prepare_request(root: Path) -> dict[str, object]:
    manifests: list[dict[str, object]] = []
    modules: set[str] = set()
    for problem_id in FIXTURE_IDS:
        manifest = tomllib.loads(
            (root / f"manifests/problems/{problem_id}.toml").read_text(encoding="utf-8")
        )
        manifests.append(manifest)
        modules.add(str(manifest["module"]))

    run(["lake", "build", *sorted(modules), "extract_theorem"], cwd=root)
    extractor = root / ".lake/build/bin/extract_theorem"
    problems: list[dict[str, object]] = []
    for manifest in manifests:
        module = str(manifest["module"])
        resolved = []
        for hole in manifest["holes"]:
            payload = run(
                ["lake", "env", str(extractor), module, str(hole)], cwd=root
            )
            extracted = json.loads(payload)
            source_range = extracted.pop("sourceRange")
            resolved.append({**extracted, **source_range})
        problems.append(
            {
                "id": manifest["id"],
                "title": manifest["title"],
                "group": manifest["group"],
                "status": manifest["status"],
                "visible": manifest["visible"],
                "statementRevision": manifest["statement_revision"],
                "tags": manifest["tags"],
                "moduleName": module,
                "holes": manifest["holes"],
                "submitter": manifest["submitter"],
                "notes": manifest.get("notes"),
                "source": manifest.get("source"),
                "informalSolution": manifest.get("informal_solution"),
                "moduleContent": module_path(root, module).read_text(encoding="utf-8"),
                "resolvedHoles": resolved,
            }
        )
    return {
        "schemaVersion": 1,
        "contextRoot": str(root),
        "leanToolchain": (root / "lean-toolchain").read_text(encoding="utf-8"),
        "mathlib": mathlib_pin(root),
        "templates": {
            "workspaceTest": (root / "templates/WorkspaceTest.lean").read_text(
                encoding="utf-8"
            )
        },
        "problems": problems,
    }


def expected_files(root: Path, problem_id: str) -> dict[str, bytes]:
    workspace = root / "generated" / problem_id
    ignored = {".lake", "build", ".cache", "lake-manifest.json"}
    return {
        path.relative_to(workspace).as_posix(): path.read_bytes()
        for path in workspace.rglob("*")
        if path.is_file() and not ignored.intersection(path.relative_to(workspace).parts)
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: golden.py /path/to/lean-eval", file=sys.stderr)
        return 2
    source_root = Path(sys.argv[1]).resolve()
    request = prepare_request(source_root)
    run(["lake", "build"], cwd=PACKAGE_ROOT)
    encoded_request = json.dumps(request, ensure_ascii=True, separators=(",", ":"))
    response_text = run(
        [str(PACKAGE_ROOT / ".lake/build/bin/lean-eval-generator")],
        cwd=PACKAGE_ROOT,
        stdin=encoded_request,
    )
    repeated = run(
        [str(PACKAGE_ROOT / ".lake/build/bin/lean-eval-generator")],
        cwd=PACKAGE_ROOT,
        stdin=encoded_request,
    )
    if repeated != response_text:
        raise AssertionError("identical requests produced different response bytes")
    response = json.loads(response_text)
    if response["schemaVersion"] != 1:
        raise AssertionError(f"unexpected response version: {response['schemaVersion']}")

    by_problem: dict[str, dict[str, bytes]] = {problem_id: {} for problem_id in FIXTURE_IDS}
    for item in response["files"]:
        content = item["content"].encode("utf-8")
        digest = hashlib.sha256(content).hexdigest()
        if item["sha256"] != digest:
            raise AssertionError(f"bad digest for {item['problemId']}/{item['path']}")
        by_problem[item["problemId"]][item["path"]] = content

    for problem_id in FIXTURE_IDS:
        expected = expected_files(source_root, problem_id)
        actual = by_problem[problem_id]
        if actual.keys() != expected.keys():
            raise AssertionError(
                f"{problem_id}: file set differs; "
                f"missing={sorted(expected.keys() - actual.keys())}, "
                f"extra={sorted(actual.keys() - expected.keys())}"
            )
        for path, expected_content in expected.items():
            if actual[path] != expected_content:
                raise AssertionError(f"{problem_id}/{path}: byte content differs")
        print(f"PASS {problem_id}: {len(actual)} files match byte-for-byte")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
