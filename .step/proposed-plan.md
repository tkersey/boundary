# Minimal Schema-First Custom Protocol Families

## Summary
Build a minimal custom protocol-family authoring API under `ability.ir.schema`
by extending the existing schema/lowering path, not by adding a new runtime
surface. First implement constructors plus `Protocol`/`Rows`/op descriptors in
`src/ir_api.zig`, then rewrite the approval workflow and prove `Program.contract`
and `Program.protocol` see ordinary ProgramPlan facts.

Done means custom approval uses the new API, sync and session paths prove the
same behavior, trace fingerprint version remains compatible when identity inputs
are unchanged, and every requested Zig/lint/example proof passes.

## Non-Goals
- Do not widen the public root.
- Do not expose `effect.Define`, `effect.ops`, or old public
  `generated_family` APIs.
- Do not add direct-style custom effects, automatic host-driver execution,
  generated visitor DSLs, trait-style host implementations, VM, Artifact,
  parser/compiler/source-language APIs, async runtime, network/LLM integration,
  durable session snapshots, cross-thread resume, serializable request tokens,
  new value codecs, or `ProgramValue` widening.
- Do not change `Program.run` or `Program.Session` semantics.
- Do not change trace fingerprint contents or bump fingerprint version unless
  dynamic identity inputs actually change.

## Acceptance
- `ability.ir.schema.transform`, `.choice`, `.abort`, plus explicit transform
  and choice after-intent constructors, create custom op schemas.
- `ability.ir.schema.Protocol(spec)` validates non-empty label, non-empty unique
  op names, default lifecycle/output tags, and exposes a Binding-shaped family.
- `Protocol.Rows(HandlerType, offsets)` lowers through existing `LowerBinding`
  with caller-owned requirement/op/output/schema indexes.
- Scalar payload/resume/output refs lower without schema refs; product/sum refs
  require explicit `SchemaRefs` and fail closed when missing or duplicated.
- Rows-bound descriptors expose ordinal/name/mode/types/refs, `opRef`, and
  `call` helpers so examples avoid manual op-name/op-index duplication.
- Custom protocol rows appear in `Program.contract`; reachable custom operation
  and after sites appear in `Program.contract.session` and `Program.protocol`.
- Dynamic custom requests bind to matching descriptors, reject mismatched
  descriptors, and use existing typed resume/return/trace helpers.
- `examples/custom_approval_workflow.zig` uses the new API, demonstrates
  transform/choice/abort, sync behavior, deterministic session/protocol
  handling, coverage witnesses, and fingerprint stability.
- Docs mark minimal schema-first custom protocol authoring available while
  preserving the non-goals.

## Proof
```sh
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-custom-approval-workflow
zig build run-agent-loop
zig build test --summary all
zig build test --summary none -- --test-filter "custom"
zig build test --summary none -- --test-filter "protocol"
zig build test --summary none -- --test-filter "schema"
zig build test --summary none -- --test-filter "site"
zig build test --summary none -- --test-filter "session"
zig build lint -- --max-warnings 0
```

## Implementation Brief
1. step=baseline_and_surface_map; owner=implementer; success_criteria=confirm
   latest main, import this custom protocol plan into `$st`, map current
   `ability.ir.schema`, `LowerBinding`, `SchemaRefs`, approval workflow,
   Program.contract/session/protocol tests, docs, and proof lanes.
2. step=protocol_constructors_and_descriptor; owner=implementer;
   success_criteria=add `ability.ir.schema` custom op constructors and
   `Protocol` descriptor validation with no public-root change. (deps:
   baseline_and_surface_map)
3. step=protocol_rows_and_op_helpers; owner=implementer;
   success_criteria=lower custom Protocol through existing `LowerBinding` and
   expose rows-bound operation descriptors with refs, `opRef`, and `call`
   helpers using caller-owned offsets and schema refs. (deps:
   protocol_constructors_and_descriptor)
4. step=schema_protocol_tests_and_compile_fail; owner=implementer;
   success_criteria=focused tests and compile-fail fixtures cover empty label,
   empty op, duplicate op, abort-after rejection, transform/choice/abort rows,
   scalar refs, product/sum refs, missing structured refs, and duplicate
   `SchemaRefs`. (deps: protocol_rows_and_op_helpers)
5. step=custom_approval_rewrite; owner=implementer; success_criteria=rewrite
   `examples/custom_approval_workflow.zig` to use the new custom protocol
   descriptor and layout builder helpers, while preserving approve/deny/invalid
   synchronous behavior. (deps: schema_protocol_tests_and_compile_fail)
6. step=custom_approval_session_protocol; owner=implementer;
   success_criteria=upgrade/add approval session path using `Program.protocol`
   descriptors, coverage helpers, typed payload/resume/returnNow, bind/reject
   checks, and deterministic trace/fingerprint replay. (deps:
   custom_approval_rewrite)
7. step=contract_protocol_docs; owner=implementer; success_criteria=add
   `Program.contract`, `Program.contract.session`, and `Program.protocol` tests
   for custom protocol sites and update `docs/custom_effect_authoring.md` plus
   `docs/program_plan.md`, with README only if needed. (deps:
   custom_approval_session_protocol)
8. step=fixed_point_review; owner=implementer; success_criteria=de novo
   fixed-point review, negative-ledger handoff, and one-change challenge find no
   unresolved material soundness, invariant, hazard, complexity, or verification
   gaps. (deps: contract_protocol_docs)
9. step=full_proof_and_ship; owner=implementer; success_criteria=all requested
   proof commands pass, branch is pushed, and `$ship` opens a PR summarizing the
   new API, lowering path, schema ref handling, descriptor helpers, approval
   workflow changes, Program.protocol integration, and unchanged non-goals.
   (deps: fixed_point_review)
