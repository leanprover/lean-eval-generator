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
