# LeanEval Generator

This package contains the deterministic workspace renderer extracted from
LeanEval. Its `lean-eval-generator` executable accepts one versioned JSON
request on stdin (or from a single file argument), writes one JSON response to
stdout, and writes diagnostics only to stderr.

The schema-version-1 request supplies benchmark context, exact Lean/Mathlib pins, templates,
marked module content, and hole metadata resolved by the consumer's Lean
environment. The response contains the complete generated file map and a
SHA-256 digest for every file. The executable does not write generated files.
The normative wire shapes are in `schemas/request-v1.schema.json` and
`schemas/response-v1.schema.json`.

Run the representative theorem- and definition-hole golden tests with:

```sh
python3 tests/scripts/golden.py /path/to/lean-eval
python3 tests/scripts/contract.py
```

The benchmark context is still required in schema version 1 to resolve trusted imported
modules and declaration spans from `.ilean` data. A future wire version can
replace that context with an explicit dependency bundle without changing schema version 1.

The consumer owns hole resolution. A consumer resolves declarations under its
pinned target environment, then passes the resulting ranges and dependency
data to this renderer. Consumer-specific fixtures and source trees do not
belong in this foundation package.

## Workspace dependencies

Every generated `lakefile.toml` requires Mathlib at the pinned revision. A
problem may also import modules from another package. The library API reads
the candidate packages from the consumer's root `lakefile.toml`
(`loadRootDependencies`); a CLI request lists them in the optional
`dependencies` array of `{name, git, rev}` pins, and omitting that array means
Mathlib only. A candidate is required by a workspace exactly when its `name`
equals the first component of a module the problem imports, after following
repo-local imports: `import TauCeti.Foo.Bar` selects the package named
`TauCeti`. Tooling packages are therefore never required, because no problem
imports them. Selected packages are emitted in root order before Mathlib,
which stays last so that Lake resolves shared transitive dependencies from
Mathlib's pins.

A selected root require must be a plain git require with a non-empty `git` and
`rev`; `subDir`, `scope`, `options`, a table-valued `git` or any other field is
an error, since the workspace would not reproduce it. Unselected requires are
not checked. A package whose library root differs from its package name is not
matched; the generated workspace then fails to build on the missing import
rather than silently changing the statement.

The emitted requires are pruned to what the problem imports, but their
transitive dependencies are not pinned in the workspace lakefile. A consumer
that builds a generated workspace should install the root `lake-manifest.json`
into it (as lean-eval's CI does) rather than running `lake update`, so that
every package resolves to the same revision as in the root workspace.
