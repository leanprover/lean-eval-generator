#!/usr/bin/env python3
"""Small dependency-free checks for the CLI transport contract."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / ".lake/build/bin/lean-eval-generator"


def invoke(payload: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(CLI)], input=payload, text=True, capture_output=True, check=False
    )


def request_with(problem: dict[str, object]) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "contextRoot": ".",
        "leanToolchain": "leanprover/lean4:v0.0.0\n",
        "mathlib": {"name": "mathlib", "git": "x", "rev": "y"},
        "templates": {"workspaceTest": ""},
        "problems": [problem],
    }


def problem() -> dict[str, object]:
    return {
        "id": "fixture",
        "title": "Fixture",
        "group": "formalization-evaluation",
        "status": "draft",
        "visible": True,
        "statementRevision": 1,
        "tags": ["example"],
        "moduleName": "Fixture",
        "holes": ["fixture"],
        "submitter": "tests",
        "moduleContent": "theorem fixture : True := by sorry\n",
        "resolvedHoles": [
            {
                "declarationName": "Fixture.fixture",
                "module": "Fixture",
                "startLine": 1,
                "startColumn": 0,
                "endLine": 1,
                "endColumn": 39,
                "explicitParameters": None,
                "sameModuleDependencies": [],
                "holeDependentDependencies": [],
                "kind": "theorem",
            }
        ],
    }


def assert_rejected(payload: dict[str, object], message: str) -> None:
    result = invoke(json.dumps(payload))
    assert result.returncode == 1
    assert result.stdout == ""
    assert message in result.stderr, result.stderr


def main() -> int:
    subprocess.run(["lake", "build"], cwd=ROOT, check=True)
    malformed = invoke("not json")
    assert malformed.returncode == 1
    assert malformed.stdout == ""
    assert "Invalid generator request" in malformed.stderr

    wrong_version = invoke(
        json.dumps(
            {
                "schemaVersion": 2,
                "contextRoot": ".",
                "leanToolchain": "leanprover/lean4:v0.0.0\n",
                "mathlib": {"name": "mathlib", "git": "x", "rev": "y"},
                "templates": {"workspaceTest": ""},
                "problems": [],
            }
        )
    )
    assert wrong_version.returncode == 1
    assert wrong_version.stdout == ""
    assert "Unsupported schemaVersion 2; expected 1" in wrong_version.stderr

    duplicate_tags = problem()
    duplicate_tags["tags"] = ["example", "example"]
    assert_rejected(request_with(duplicate_tags), "duplicate tag `example`")

    empty_title = problem()
    empty_title["title"] = ""
    assert_rejected(request_with(empty_title), "title must be non-empty")

    first = problem()
    duplicate_ids = request_with(first)
    duplicate_ids["problems"] = [first, problem()]
    assert_rejected(duplicate_ids, "Duplicate problem id `fixture`")

    print("PASS malformed, version, and schema-invariant errors stay off stdout")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
