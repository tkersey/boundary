# Direct-Style Boundary

`shift` now treats the effects-library surface built around `shift.with(...)`
and `shift.effect.*` as the supported public authored-body story. The
structural vocabulary and lowering entrypoints live in `shift_compile.ir`,
`shift_compile.lowering`, and `shift_compile.lower`. The source-lowering
toolchain remains restricted internal scaffolding beneath that public story,
and the retained `shift_vm` lane is compatibility-only.

The lowered path is only acceptable as hidden support infrastructure beneath
that surface. Today, that support comes in two internal forms:

- `src/program_frontend.zig` lowers internal structured programs into the
  canonical lowered IR in `src/parity_scenarios.zig`
- `src/source_lowering.zig` structurally validates the canonical source corpus,
  witness set, generated/user-defined examples, algebraic examples, and built-in
  declaration rows, then projects accepted rows onto canonical lowered scenarios
- `src/program_bridge.zig` now routes the supported unchanged-body example and
  witness subset through the same shared authoring-lowering core before replaying
  canonical lowered scenarios for parity proof
- `src/private_lowered_runtime.zig` executes the currently supported bridge
  subset through an internal lowered-runtime seam

The current limit is structural:

- the bridge currently supports only a named subset of unchanged direct-style
  cases
- the internal source-lowering track is still structurally restricted even
  though it now covers the repo-owned coverage matrix and emits checked
  admission/rejection artifacts
- the current proof-facing source-lowering scope is tracked separately in
  `docs/source_lowering_coverage_matrix.json`
- arbitrary unchanged public-style `fn body() ...` code still relies on
  host-language control flow and the stackful runtime
- there is no general body-to-IR transformation, capture pass, or compiler/plugin
  layer that can recover arbitrary direct-style control structure from ordinary
  Zig code

So the current answer is:

- structured internal programs are supported as scaffolding
- a limited unchanged-body bridge subset is supported for parity proof
- the canonical source-lowering restricted surface is supported for the full
  repo-owned source-lowering coverage matrix
- arbitrary unchanged direct-style bodies are not
- the public product story is still the lexical effects-library surface rather
  than the lowering toolchain

This document is backed by `test/program_frontend_boundary_test.zig`,
`test/direct_style_bridge_boundary_test.zig`, `test/source_lowering_boundary_test.zig`,
`test/source_lowering_rejection_corpus_test.zig`, and the structured-program
lowering snapshots under `test/authoring_lowerings/`.
