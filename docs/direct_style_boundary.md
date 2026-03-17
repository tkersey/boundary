# Direct-Style Boundary

`shift` now treats the ordinary source-validated lowering surface through
`shift.ordinary` and the `shift-ordinary-lower` tool as the canonical authored-body
story. The lexical `shift.with(...)`, `shift.effect.*`, `shift.effect.Define(.{ ... })`,
and `shift.algebraic` surfaces remain public compatibility/runtime entrypoints.
The older root prompt surface remains retained compat/internal scaffolding
beneath that canonical story.

The lowered path is only acceptable as hidden support infrastructure beneath
that surface. Today, that support comes in two internal forms:

- `src/program_frontend.zig` lowers internal structured programs into the
  canonical lowered IR in `src/parity_scenarios.zig`
- `src/ordinary_zig_lowering.zig` validates the canonical ordinary corpus,
  witness set, generated/user-defined examples, algebraic examples, and built-in
  effect source rows, then projects them onto canonical lowered scenarios
- `src/program_bridge.zig` maps a named unchanged-body direct-style subset onto
  the same lowered scenarios for parity proof
- `src/private_lowered_runtime.zig` executes the currently supported bridge
  subset through an internal lowered-runtime seam

The current limit is structural:

- the bridge currently supports only a named subset of unchanged direct-style
  cases
- the canonical ordinary track is still structurally restricted even though it
  now covers the repo-owned replacement ledger
- the long-horizon replacement scope for current public/proof surfaces is tracked
  separately in `docs/surface_replacement_matrix.json`
- arbitrary public-style `fn body() ...` code still relies on host-language
  control flow and the stackful runtime
- there is no general body-to-IR transformation, capture pass, or compiler/plugin
  layer that can recover arbitrary direct-style control structure from ordinary
  Zig code

So the current answer is:

- structured internal programs are supported as scaffolding
- a limited unchanged-body bridge subset is supported for parity proof
- the canonical ordinary-Zig restricted-lowering surface is supported for the
  full repo-owned replacement ledger
- arbitrary unchanged direct-style bodies are not

This document is backed by `test/program_frontend_boundary_test.zig`,
`test/direct_style_bridge_boundary_test.zig`, `test/ordinary_zig_boundary_test.zig`,
and the structured-program lowering snapshots under `test/authoring_lowerings/`.
