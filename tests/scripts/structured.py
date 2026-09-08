"""Source-free contract: no context tree or .ilean, including dependent holes."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import tomllib

from contract import ROOT, invoke
from packages import package, run


def main():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        support = package(root / 'support', 'fixture_support', 'FixtureSupport',
                          'def FixtureSupport.value : Nat := 7\n')
        request = {'schemaVersion': 3, 'leanToolchain': (ROOT / 'lean-toolchain').read_text(),
                   'dependencies': [support], 'templates': {'workspaceTest': 'def main : IO Unit := pure ()\n'},
                   'problems': [{'id': 'structured', 'title': 'Structured fixtures',
                                 'imports': ['FixtureSupport'], 'declarations': [
                                     {'name': 'answer', 'kind': 'def', 'type': 'Nat', 'levels': []},
                                     {'name': 'second', 'kind': 'def', 'type': 'Fin (answer + 1)', 'levels': []},
                                     {'name': 'problem', 'kind': 'theorem',
                                      'type': 'answer = FixtureSupport.value ∧ second.val ≤ answer', 'levels': []},
                                     {'name': 'poly', 'kind': 'theorem',
                                      'type': '∀ (α : Type u) (x : α), x = x', 'levels': ['u']}]}]}
        result = invoke(json.dumps(request))
        assert result.returncode == 0, result.stderr
        assert invoke(json.dumps(request)).stdout == result.stdout
        response = json.loads(result.stdout)
        assert response['schemaVersion'] == 3
        files = {f['path']: f['content'] for f in response['files']}
        for f in response['files']:
            assert hashlib.sha256(f['content'].encode()).hexdigest() == f['sha256']
        assert tomllib.loads(files['lakefile.toml'])['require'] == [support]
        assert not any('Deps' in name or name.endswith('.ilean') for name in files)
        workspace = root / 'workspace'
        workspace.mkdir()
        for name, content in files.items():
            p = workspace / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content)
        submission = workspace / 'Submission.lean'
        text = submission.read_text()
        for proof in ['exact 7', 'exact ⟨0, by decide⟩', 'constructor <;> decide', 'intro α x; rfl']:
            text = text.replace('sorry', proof, 1)
        submission.write_text(text)
        run(['lake', 'update'], workspace)
        run(['lake', 'build', 'Challenge', 'Solution'], workspace)
        mutations = [
            lambda r: r.update(contextRoot='unused'),
            lambda r: r['dependencies'][0].update(rev='master'),
            lambda r: r['dependencies'].append(r['dependencies'][0]),
            lambda r: r['problems'][0].update(imports=['FixtureSupport\naxiom bad : False']),
            lambda r: r['problems'][0]['declarations'][0].update(name='../bad'),
            lambda r: r['problems'][0]['declarations'][0].update(kind='axiom'),
            lambda r: r['problems'][0]['declarations'][0].update(levels=['u\naxiom bad : False']),
            lambda r: r['problems'][0]['declarations'].append(r['problems'][0]['declarations'][0]),
        ]
        for mutation in mutations:
            bad = copy.deepcopy(request)
            mutation(bad)
            assert invoke(json.dumps(bad)).returncode != 0, bad
    print('PASS structured rendering, real Git dependencies, dependent holes, universes, malformed requests')


if __name__ == '__main__':
    main()
