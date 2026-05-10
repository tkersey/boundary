Iteration: 6

# Semantic Program Authoring for Defunctionalized Effects

## Round Delta
- Converted the spec-pipeline handoff into an execution campaign with dependency-ordered waves, named API choices, done-state, rollback triggers, and proof gates.
- Locked `ability.ir.builder.semantic` and `ability.ir.schema.Registry` as the additive public surfaces under `ability.ir`.
- Added convergence closure: last two refinement passes found no material deltas; remaining concerns are implementation preferences only.

## Summary
Build a construction-only semantic ProgramPlan authoring layer for custom defunctionalized effect protocols. The chosen path is to add `ability.ir.schema.Registry` for deterministic typed schema tables, add `ability.ir.builder.semantic` on top of the existing layout builder, project optional site labels through `Program.contract`, `Program.protocol`, and traces without fingerprint drift, then rewrite the custom approval and agent loop examples. First execution wave is registry plus semantic builder core; completion requires all requested example, schema, protocol, session, trace, replay, and lint proof commands to pass with `trace_fingerprint_version == 2`.

The central invariant: semantic authoring emits ordinary validated `ability.ir.ProgramPlan`; no second executable IR, source language, VM, public-root widening, value-codec widening, or runtime behavior fork is introduced.

## Non-Goals/Out of Scope
- No parser, source language, compiler concept, VM, Artifact API, automatic host runtime, generated visitor DSL, trait-style host implementation, async runtime, network or LLM integration.
- No public root widening beyond existing `ability.effect`, `ability.ir`, `ability.program`, `ability.Runtime`.
- No `ProgramValue` widening, new value codecs, durable session snapshot/restore, cross-thread session resume, serializable request tokens, or required trace serialization format.
- No removal of `ability.ir.plan.*`, `ability.ir.builder.layout`, `ability.ir.builder.typed`, or raw ProgramPlan examples/tests that intentionally prove escape-hatch behavior.
- Stretch goals are deferred unless the core lands cleanly: helper functions, nested-with target authoring, output authoring, and exception/resource example rewrites.

## Interfaces/Types/APIs Impacted
- Add `ability.ir.schema.Registry(.{ ... })` returning `value_schemas`, `value_fields`, `value_variants`, `schema_refs`, `schema_refs_type`, `schema_refs` compatible with `LowerBinding`, `schema_refs.valueRef(T)`, and `value_schema_types`.
- Add `ability.ir.builder.semantic` returning ordinary `ProgramPlan` through `finish(spec)` and optionally `{ .plan, .site_metadata }` when semantic labels are present.
- Semantic builder supports typed `param`, `local`, `result`, named `block`, named branch targets, raw escape instruction insertion, and helpers for the required instruction set.
- Protocol calls use `schema.Protocol.Rows(...).op(name)` descriptors, not raw op indexes, and fail closed on payload/destination/resume type mismatch.
- `Body.site_metadata` is optional. `ability.program` may project nullable `semantic_label` fields on static operation sites, after sites, protocol descriptors, request traces, and after traces.
- `semantic_label` is display/debug metadata only: not a durable id, not a source location, not part of plan hash, site fingerprint, request fingerprint, response fingerprint, or value fingerprint.

## Data Flow
1. Author declares Zig product/sum/scalar types.
2. `ability.ir.schema.Registry` derives value schema tables and schema refs deterministically from the tuple order.
3. Author declares `schema.Protocol` ops and lowers rows through `Protocol.Rows(Handlers, .{ .schema_refs = Schemas.schema_refs, ... })`.
4. Author declares semantic functions, typed params/locals/results, named blocks, protocol calls, branches, and optional site labels.
5. `builder.semantic.finish` validates semantic refs, resolves names to function-local handles, and lowers into `builder.layout.finish`.
6. `builder.layout.finish` computes table spans and branch targets, then existing `ProgramPlan.validate` remains the final validation boundary.
7. `Body.compiled_plan = compiled.plan`, `Body.value_schema_types = Schemas.value_schema_types`, and optional `Body.site_metadata = compiled.site_metadata`.
8. `ability.program` executes via existing `Program.run` or `Program.Session`; contract/protocol/trace projections are derived from validated plan plus optional metadata.

## Tests/Acceptance
- Registry tests: product schema rows, sum variant rows, scalar no-schema behavior, tuple-order indexes, nested structured refs, `SchemaRefs` accepted by protocol rows.
- Semantic builder tests: scalar plan, product plan, sum branch plan, transform call, choice call, abort call, span computation, invalid branch target, local type mismatch, protocol payload mismatch, protocol destination/resume mismatch.
- Metadata tests if implemented: static yield/after labels appear; dynamic request/after traces expose labels; fingerprints remain version 2 and replay-stable.
- Example tests: custom approval approve/deny/invalid behavior preserved; custom approval session replay verifies; agent loop replay verifies; typed ProgramPlan example still runs.
- Regression tests: existing `Program.run`, `Program.Session`, `Program.protocol`, trace, site, replay, schema, and raw ProgramPlan tests remain green.

## Proof Commands
```sh
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-custom-approval-workflow
zig build run-agent-loop
zig build run-typed-program-plan
zig build test --summary all
zig build test --summary none -- --test-filter "semantic"
zig build test --summary none -- --test-filter "custom"
zig build test --summary none -- --test-filter "protocol"
zig build test --summary none -- --test-filter "schema"
zig build test --summary none -- --test-filter "site"
zig build test --summary none -- --test-filter "session"
zig build test --summary none -- --test-filter "trace"
zig build test --summary none -- --test-filter "replay"
zig build lint -- --max-warnings 0
```

## Implementation Brief
1. step=baseline_and_surface_map; owner=implementer; success_criteria=confirm latest main, import this semantic authoring plan into `$st`, map current `ability.ir.schema`, `ValueSchemaRegistryForTypes`, `SchemaRefs`, `LowerBinding`, `builder.layout`, `builder.typed`, custom approval workflow, agent loop, typed ProgramPlan example, `Program.contract.session`, `Program.protocol`, trace metadata, docs, and proof lanes.
2. step=schema_registry_helper; owner=implementer; success_criteria=add `ability.ir.schema.Registry(.{ ... })` with deterministic product/sum schema indexes from tuple order, scalar no-schema behavior, `value_schemas`, `value_fields`, `value_variants`, `schema_refs`, `schema_refs_type`, `schema_refs.valueRef(T)`, and `value_schema_types`; reject duplicate explicit structured types, unsupported types, and missing nested structured refs. (deps: baseline_and_surface_map)
3. step=semantic_builder_core; owner=implementer; success_criteria=add `ability.ir.builder.semantic` construction-only API for typed functions, params, locals, results, named blocks, and required scalar/product/sum instruction helpers, lowering through `builder.layout.finish` to an ordinary validated `ProgramPlan`. (deps: schema_registry_helper)
4. step=semantic_protocol_calls; owner=implementer; success_criteria=semantic protocol call helpers accept `Protocol.Rows(...).op(name)` descriptors, use descriptor refs instead of raw op indexes, attach optional semantic site labels, and reject payload/destination/resume type mismatches before plan escape. (deps: semantic_builder_core)
5. step=semantic_site_metadata_projection; owner=implementer; success_criteria=optional `Body.site_metadata` projects nullable semantic labels to `Program.contract.session.yield_sites`, `after_sites`, `Program.protocol` descriptors, operation request traces, and after request traces without changing plan hash, site fingerprints, request fingerprints, response fingerprints, value fingerprints, or `trace_fingerprint_version == 2`. (deps: semantic_protocol_calls)
6. step=semantic_builder_tests; owner=implementer; success_criteria=focused positive and compile-fail tests cover registry product/sum/schema refs, semantic scalar/product/sum/protocol transform/choice/abort plans, span computation, invalid branch target, local type/ref mismatch, protocol payload mismatch, protocol destination/resume mismatch, label projection, and fingerprint stability. (deps: semantic_site_metadata_projection)
7. step=custom_approval_rewrite; owner=implementer; success_criteria=`examples/custom_approval_workflow.zig` uses `schema.Protocol`, `schema.Registry`, semantic builder, protocol op descriptors, semantic site labels, and `Program.protocol` for session hosting; it no longer hand-authors ordinary FunctionPlan, LocalPlan, BlockPlan, Terminator, raw Instruction arrays, `first_*`/`*_count` spans, raw op rows, or raw requirement rows while preserving approve/deny/invalid behavior and replay checks. (deps: semantic_builder_tests)
8. step=agent_loop_and_typed_program_rewrite; owner=implementer; success_criteria=`examples/agent_loop.zig` and `examples/typed_program_plan.zig` use semantic authoring for ordinary control flow, preserve deterministic record/replay and typed `Program.protocol` descriptors, keep no network/LLM/async dependency, and show semantic site labels in output where available. (deps: custom_approval_rewrite)
9. step=docs_update; owner=implementer; success_criteria=`docs/program_plan.md`, `docs/custom_effect_authoring.md`, and README make semantic authoring the preferred custom effect path, explain registry/protocol/builder composition, source/site labels, raw ProgramPlan escape hatches, and unchanged non-goals. (deps: agent_loop_and_typed_program_rewrite)
10. step=fixed_point_review; owner=implementer; success_criteria=run fixed-point de novo review, negative-ledger handoff, and one-change challenge; close all material soundness, invariant, hazard, complexity, and verification gaps before final proof. (deps: docs_update)
11. step=full_proof_and_ship; owner=implementer; success_criteria=all requested proof commands pass, branch is pushed, and `$ship` opens a PR summarizing semantic builder API, schema.Protocol composition, registry behavior, rewritten examples, table-authoring reduction, semantic site metadata, trace fingerprint version status, contract/protocol/session parity tests, raw ProgramPlan availability, and explicit non-goal exclusions. (deps: fixed_point_review)

Iteration: 6
