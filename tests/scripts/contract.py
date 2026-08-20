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
    print("PASS malformed input and version errors stay off stdout")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

