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

## Structured declarations (version 2)

Version 2 accepts package pins, imports, and ordered declarations with `name`,
`kind`, `type`, and explicit `levels`. It renders Challenge, Submission and Solution
without a context directory, source ranges, `.ilean`, helper discovery, or source
rewriting. Definitions in Solution are reducible aliases to the submitted values,
so later hole types can depend on earlier holes. Signatures contain all binders;
Solution forwards them with an explicit `@` reference and universe arguments.

The schemas are `schemas/request-v2.schema.json` and `schemas/response-v2.schema.json`.
Types and the test-driver template are trusted source supplied by the consumer,
just as moduleContent is trusted in v1. The consumer must validate the signatures
with its own Lean environment and compile the generated Challenge before use.
The renderer does not interpret type syntax using its potentially different Lean
version. Import boundaries are validated with Lean's header parser. Version 1
remains unchanged; no legacy source-processing path is used for v2 requests.

Run `python3 tests/scripts/structured.py` to exercise real Git package resolution,
dependent definition holes, polymorphic theorems, deterministic output and invalid
request rejection, without any source context or compiler metadata.

The renderer requires `openssl` on `PATH` for SHA-256 file digests (macOS and Linux);
GNU `sha256sum` is not required. Deploy a reviewed generator revision built with its
pinned Lean toolchain, and record the executable digest alongside the source revision.
The wire schema version identifies the contract, not the executable provenance.
