#!/usr/bin/env python3
"""Small dependency-free checks for the CLI transport contract."""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

from golden import module_path as golden_module_path


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


def lakefile_for(payload: dict[str, object]) -> str:
    result = invoke(json.dumps(payload))
    assert result.returncode == 0, result.stderr
    files = json.loads(result.stdout)["files"]
    [lakefile] = [item["content"] for item in files if item["path"] == "lakefile.toml"]
    return lakefile


def check_extra_dependencies() -> None:
    """Render a problem importing a non-Mathlib package through the CLI."""
    mathlib = '[[require]]\nname = "mathlib"\ngit = "x"\nrev = "y"\n\n'
    tauceti = '[[require]]\nname = "TauCeti"\ngit = "https://t.example"\nrev = "abc"\n\n'
    dependencies = [
        {"name": "TauCeti", "git": "https://t.example", "rev": "abc"},
        {"name": "Cli", "git": "https://c.example", "rev": "def"},
    ]
    with tempfile.TemporaryDirectory() as directory:
        context = Path(directory)
        ilean = context / ".lake/build/lib/lean"
        ilean.mkdir(parents=True)
        for module, header in [
            ("WithTauCeti", "import TauCeti.GroupTheory.Classification\n\n"),
            ("MathlibOnly", "import Mathlib.Logic.Basic\n\n"),
        ]:
            content = header + "theorem fixture : True := by sorry\n"
            (context / f"{module}.lean").write_text(content, encoding="utf-8")
            (ilean / f"{module}.ilean").write_text('{"decls": {}}', encoding="utf-8")
            fixture = problem()
            fixture["moduleName"] = module
            fixture["moduleContent"] = content
            hole = fixture["resolvedHoles"][0]
            hole["module"] = module
            hole["declarationName"] = "fixture"
            hole["startLine"] = hole["endLine"] = 3
            payload = request_with(fixture)
            payload["contextRoot"] = str(context)
            baseline = lakefile_for(payload)
            payload["dependencies"] = dependencies
            lakefile = lakefile_for(payload)
            assert "Cli" not in lakefile, lakefile
            if module == "WithTauCeti":
                assert baseline.count("[[require]]") == 1, baseline
                assert tauceti + mathlib in lakefile, lakefile
                assert lakefile.count("[[require]]") == 2, lakefile
            else:
                assert lakefile == baseline, lakefile


def main() -> int:
    subprocess.run(["lake", "build"], cwd=ROOT, check=True)
    subprocess.run(
        ["lake", "env", "lean", "--run", "tests/Context.lean"],
        cwd=ROOT,
        check=True,
    )
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

    unknown_field = request_with(problem())
    unknown_field["unexpected"] = True
    assert_rejected(unknown_field, "request contains an unknown field")

    nested_unknown = request_with(problem())
    nested_unknown["problems"][0]["unexpected"] = True
    assert_rejected(nested_unknown, "problem contains an unknown field")

    mathlib_unknown = request_with(problem())
    mathlib_unknown["mathlib"]["unexpected"] = True
    assert_rejected(mathlib_unknown, "mathlib contains an unknown field")

    template_unknown = request_with(problem())
    template_unknown["templates"]["unexpected"] = True
    assert_rejected(template_unknown, "templates contains an unknown field")

    hole_unknown = request_with(problem())
    hole_unknown["problems"][0]["resolvedHoles"][0]["unexpected"] = True
    assert_rejected(hole_unknown, "resolvedHole contains an unknown field")

    with tempfile.TemporaryDirectory() as directory:
        context = Path(directory)
        module_name = "Arxiv.«0912.2382».Fixture"
        module_content = "theorem fixture : True := by sorry\n"
        module_path = context / "Arxiv" / "0912.2382" / "Fixture.lean"
        assert golden_module_path(context, module_name) == module_path
        module_path.parent.mkdir(parents=True)
        module_path.write_text(module_content, encoding="utf-8")
        quoted = problem()
        quoted["moduleName"] = module_name
        quoted["moduleContent"] = module_content
        quoted["resolvedHoles"][0]["module"] = module_name
        quoted["resolvedHoles"][0]["declarationName"] = f"{module_name}.fixture"
        payload = request_with(quoted)
        payload["contextRoot"] = str(context)
        result = invoke(json.dumps(payload))
        assert result.returncode == 1
        assert result.stdout == ""
        expected_ilean = context / ".lake/build/lib/lean/Arxiv/0912.2382/Fixture.ilean"
        assert str(expected_ilean) in result.stderr, result.stderr
        assert "Arxiv/«0912/2382»" not in result.stderr

    extra_named_mathlib = request_with(problem())
    extra_named_mathlib["dependencies"] = [{"name": "mathlib", "git": "x", "rev": "y"}]
    assert_rejected(extra_named_mathlib, "must not contain `mathlib`")

    dependency_unknown = request_with(problem())
    dependency_unknown["dependencies"] = [
        {"name": "TauCeti", "git": "x", "rev": "y", "subDir": "z"}
    ]
    assert_rejected(dependency_unknown, "dependency contains an unknown field")

    check_extra_dependencies()

    print("PASS schema errors stay off stdout and quoted source/ilean paths resolve")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
