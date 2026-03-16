# Direct-Style Boundary

`shift` still treats the public prompt-value `shift/reset` surface as the only
product truth.

The lowered path is only acceptable as hidden support infrastructure beneath
that surface. Today, that support comes in two internal forms:

- `src/program_frontend.zig` lowers internal structured programs into the
  canonical lowered IR in `src/parity_scenarios.zig`
- `src/program_bridge.zig` maps a named unchanged-body direct-style subset onto
  the same lowered scenarios for parity proof
- `src/ordinary_zig_lowering.zig` maps the wave-one ordinary-Zig experimental
  subset onto the same lowered scenarios for contract proof
- `src/private_lowered_runtime.zig` executes the currently supported bridge
  subset through an internal lowered-runtime seam

The current limit is structural:

- the bridge currently supports only a named subset of unchanged direct-style
  cases
- the ordinary-Zig experimental track currently supports only the exact wave-one
  subset documented in `docs/ordinary_zig_contract.md`
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
- an internal-only ordinary-Zig restricted-lowering subset is supported for
  experimental contract proof
- arbitrary unchanged direct-style bodies are not

This document is backed by `test/program_frontend_boundary_test.zig`,
`test/direct_style_bridge_boundary_test.zig`, `test/ordinary_zig_boundary_test.zig`,
and the structured-program lowering snapshots under `test/authoring_lowerings/`.
