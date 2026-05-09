# Custom effect authoring design

Custom effect authoring is intentionally a later public surface. The current
authoring path for reusable effect-shaped workflows is explicit ProgramPlan
construction through `ability.ir`, executed by `ability.program`.

This document records the intended shape of custom effects so the plan-native
built-in work can converge on one target without re-opening the public root.

## Current boundary

The public root remains:

- `ability.effect`
- `ability.ir`
- `ability.program`
- `ability.Runtime`

`ability.effect` does not expose `Define` or `ops`. Custom generated effects are
not public. Users who need a custom workflow today should build a ProgramPlan,
provide handlers, and run it through `ability.program`.

`ability.ir.schema.LowerBinding` is public-adjacent infrastructure for built-in
schemas. It lowers an `effect_schema.Binding`-shaped type to ordinary
ProgramPlan requirement, op, and output rows, and is the preferred route for
built-in plan-native metadata. It is not a custom effect authoring API, does not
expose `effect.Define`, and does not add parser, compiler, VM, Artifact, source
language, value-codec, or execution semantics.

`examples/custom_approval_workflow.zig` is the current public pattern. It
declares a workflow requirement with transform, choice, and abort operations in
the plan tables, then supplies ordinary Zig handlers at the `ability.program`
front door.

## Future public shape

Custom effect authoring should be schema-first:

1. Define requirement metadata with a stable label and lifecycle tag.
2. Define operations with explicit mode, payload ref, resume ref, and after-hook
   intent.
3. Define value schemas before referencing typed product or sum values.
4. Define outputs with ownership and cleanup expectations.
5. Lower the description to `ability.ir.ProgramPlan`.
6. Execute only through `ability.program`.

The future authoring surface may add helpers under `ability.ir` for this
schema-first shape, but it should still emit the existing ProgramPlan. It must
not introduce a second IR, a source parser, a public VM, a public Artifact
surface, or a public compiler layer.

Current built-in schemas already prove the intended direction at a smaller
scope: schema lowering owns requirement/op/output metadata, while
`ability.ir.builder.layout` owns function, local, block, instruction, and
terminator layout. Raw ProgramPlan rows remain available for exact-table tests
and unsupported shapes.

## Required semantics

A custom effect description must lower to ordinary ProgramPlan facts:

- Requirements become `ProgramPlan.requirements` rows with stable labels and
  source metadata.
- Transform operations become `.transform` ops with exact payload and resume
  refs.
- Choice operations become `.choice` ops whose handlers either resume with the
  declared resume ref or return the declared terminal result.
- Abort operations become `.abort` ops whose handlers return the declared
  terminal result.
- After hooks become `has_after = true` op metadata and execute only on resumed
  paths.
- Product and sum payloads use `Body.value_schema_types` for exact Zig type
  matching.
- Sum control flow uses `sum_variant_is` and `sum_extract_payload`; extraction
  destinations must match the schema-local variant payload ref.
- Outputs materialize through `Program.Result.outputs` and are released by
  `Body.deinitOutputs` when ownership requires it.
- Result ownership is released by `Body.deinitResult`; output cleanup remains
  independent.
- Nested lexical-with behavior is available only through explicit
  `Body.nested_with_targets`.
- `return_error` literals are part of the reachable executable contract and must
  be declared in `Body.Error`.

## Contract projection

Every custom effect helper must be testable through `Program.contract`. A caller
or test should be able to assert:

- requirement labels and lifecycle metadata
- op names, modes, payload refs, resume refs, and after flags
- output labels and output refs
- value schema, field, and variant declarations
- nested-with target declarations
- unique reachable `return_error` literals
- executable capability-ledger blocker metadata

This keeps custom authoring honest: if a helper cannot prove its output through
the same contract projection as a raw ProgramPlan, it is not ready to be public.

The current schema lowerer is scalar-first for payload, resume, and output refs.
Structured product and sum refs need an explicit caller-provided ProgramPlan
schema-index map before they become a public custom-authoring feature.
Writer accumulator output rows use the accumulator item ref; the final collected
slice remains owned by the program body `Outputs` contract.

## Approval workflow target

The first custom authoring example should remain an approval workflow because it
uses all core control modes without requiring lifecycle machinery:

- `exists`: transform from a request id to a lookup result
- `request`: choice that resumes on approval or returns a denial result
- `invalid`: abort that returns an invalid-request result

The schema-first helper should produce the same contract metadata as the raw
`examples/custom_approval_workflow.zig` ProgramPlan before it becomes a public
recommendation.

## Non-goals

- Do not expose `effect.Define`.
- Do not expose `effect.ops`.
- Do not add public generated custom effects.
- Do not widen the public root.
- Do not widen `ProgramValue`; it remains scalar-only.
- Do not add source-like syntax.
- Do not add a public Artifact, VM, compile, or parser API.
