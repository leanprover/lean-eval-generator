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

## Pinned package dependencies

Schema version 2 adds a required `dependencies` array to the version 1 request.
Each entry contains `name`, `git`, and `rev`; `rev` must be a full lowercase Git
commit SHA. Names must be distinct and must not repeat `mathlib`. For example:

```json
"dependencies": [
  {"name": "example_support", "git": "https://example.org/support.git",
   "rev": "0123456789abcdef0123456789abcdef01234567"}
]
```

The renderer emits these dependencies in the workspace Lakefile. Imports of
package modules are preserved when their source files are outside `contextRoot`.
Keep package checkouts in Lake's package directory, not alongside the input
module in `contextRoot`: source modules found there retain the existing local
dependency-copying behavior. Dependencies are request-wide, so batch problems
that use the same environment together.

The consumer approves the dependency source and resolves a compatible Lean and
Mathlib environment. The generator does not fetch packages or execute their code.
It still requires real declaration metadata under `contextRoot`. The response
uses the request's schema version and the same file-map shape.

Version 1 remains unchanged and rejects the new field. A version 2 request with
an empty dependency array produces the same files as its version 1 equivalent.
The complete contracts are `schemas/request-v2.schema.json` and
`schemas/response-v2.schema.json`. Run the offline package integration test with:

```sh
python3 tests/scripts/packages.py
```

The test creates local Git packages, compiles real Lean declaration metadata,
generates a workspace, fills its proof, and builds its fixed Solution adapter.
