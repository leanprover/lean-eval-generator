"""Generate and build an external-package workspace using real Lean metadata."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib

from contract import CLI, ROOT, assert_rejected, invoke, problem, request_with


def run(args, cwd, env=None):
    result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(f"{args}:\n{result.stdout}\n{result.stderr}")
    return result.stdout.strip()


def package(root, name, module, content):
    root.mkdir()
    (root / "lakefile.toml").write_text(
        f'name = "{name}"\n[[lean_lib]]\nname = "{module}"\n'
    )
    (root / "lean-toolchain").write_text((ROOT / "lean-toolchain").read_text())
    (root / f"{module}.lean").write_text(content)
    run(["git", "init", "-q"], root)
    run(["git", "add", "."], root)
    run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
         "commit", "-qm", "fixture"], root)
    return {"name": name, "git": str(root), "rev": run(["git", "rev-parse", "HEAD"], root)}


def main():
    run(["lake", "--wfail", "build"], ROOT)
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        mathlib = package(root / "mathlib", "mathlib", "Mathlib", "-- Empty fixture library.\n")
        dependency = package(root / "support", "fixture_support", "FixtureSupport",
                             "namespace FixtureSupport\ndef value : Nat := 7\nend FixtureSupport\n")
        run(["lake", "build", "FixtureSupport"], root / "support")
        context = root / "context"
        context.mkdir()
        source = "import FixtureSupport\n\ntheorem fixture : FixtureSupport.value = 7 := by sorry\n"
        (context / "Fixture.lean").write_text(source)
        metadata = context / ".lake/build/lib/lean/Fixture.ilean"
        metadata.parent.mkdir(parents=True)
        env = dict(os.environ, LEAN_PATH=str(root / "support/.lake/build/lib/lean"))
        run(["lake", "env", "lean", "-i", str(metadata), str(context / "Fixture.lean")], ROOT, env)
        p = problem()
        p["moduleContent"] = source
        p["resolvedHoles"][0].update(declarationName="fixture", startLine=3,
            startColumn=0, endLine=3, endColumn=len(source.splitlines()[2]), explicitParameters=[])
        payload = request_with(p)
        payload.update(schemaVersion=2, contextRoot=str(context), mathlib=mathlib,
                       leanToolchain=(ROOT / "lean-toolchain").read_text(), dependencies=[dependency])
        result = invoke(json.dumps(payload))
        assert result.returncode == 0, result.stderr
        assert invoke(json.dumps(payload)).stdout == result.stdout
        response = json.loads(result.stdout)
        assert response["schemaVersion"] == 2
        files = {f["path"]: f["content"] for f in response["files"]}
        for f in response["files"]:
            assert hashlib.sha256(f["content"].encode()).hexdigest() == f["sha256"]
        assert tomllib.loads(files["lakefile.toml"])["require"] == [mathlib, dependency]
        assert "ChallengeDeps.lean" not in files
        for path in ("Challenge.lean", "Submission.lean", "Solution.lean"):
            assert "import FixtureSupport" in files[path]
            assert "def value" not in files[path]
        workspace = root / "workspace"
        workspace.mkdir()
        for path, content in files.items():
            target = workspace / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
        submission = workspace / "Submission.lean"
        submission.write_text(submission.read_text().replace("sorry", "rfl"))
        run(["lake", "update"], workspace)
        run(["lake", "build", "Challenge", "Solution"], workspace)

        # v1 stays strict, including rejection of even an empty new field.
        payload["schemaVersion"] = 1
        assert_rejected(payload, "request contains an unknown field")
        payload["schemaVersion"] = 2
        for deps, message in [
            ([dependency, dependency], "Duplicate dependency"),
            ([dict(dependency, name="mathlib")], "Duplicate dependency"),
            ([dict(dependency, rev="main")], "full lowercase commit SHA"),
            ([dict(dependency, name="../escape")], "package identifiers"),
            ([dict(dependency, extra=True)], "dependency contains an unknown field"),
        ]:
            payload["dependencies"] = deps
            assert_rejected(payload, message)
        payload["dependencies"] = []
        v2 = json.loads(invoke(json.dumps(payload)).stdout)
        del payload["dependencies"]
        payload["schemaVersion"] = 1
        v1 = json.loads(invoke(json.dumps(payload)).stdout)
        assert v1["files"] == v2["files"], "Empty v2 dependencies changed legacy rendering"
    print("PASS package imports, real metadata, workspace build, pins, and v1 parity")


if __name__ == "__main__":
    main()
