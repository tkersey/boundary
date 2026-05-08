Iteration: 7

# Typed Sum Matching and Contract Projection Plan

## Round Delta
- Converts the completed `$grill-me` answers into a release-impacting architecture wave, not the prior narrow audit task list.
- Locks the executable shape: all sum schemas get tag-test branching plus payload extraction, mirrored through `ProgramPlan`, `effect_ir`, public builder helpers, interpreter, contract projection, docs, and tests.
- Adds a proof spine: focused witness tests first, then full local gates.

## Summary
Goal: make typed sum values executable beyond pass-through by adding exact sum matching to the schema-rich executable subset. Chosen path: add two wire-shaped instructions, `.sum_variant_is` and `.sum_extract_payload`, with schema-local variant ordinals; mirror them in `effect_ir`; execute them in both interpreter paths; and expose declaration-level schema metadata in `Program.contract`. First wave is core `ProgramPlan` + interpreter + public builder, proven by direct `ability.program` witnesses. Done means optional, enum, and tagged-union sum matches execute or fail closed, `Program.contract` reflects schema declarations without leaking plan tables, README documents the boundary, and `zig build`, `zig build test --summary none`, and `zig build lint -- --max-warnings 0` pass.

## Non-Goals/Out of Scope
- Do not replace `ProgramValue`; it remains the scalar public carrier.
- Do not expose full `functions`, `blocks`, `instructions`, VM internals, or Artifact-style host maps through `Program.contract`.
- Do not add a legacy plan upgrade path; bump `ProgramPlan.current_schema_version` only.
- Do not add a compile-fail harness in this wave.
- Do not broaden to every fixture producer beyond public builder plus effect-ir/open-row lowerer paths needed for real integration proof.

## Interfaces/Types/APIs Impacted
- `ProgramPlan`: bump `current_schema_version` from `8` to `9`; add `InstructionKind.sum_variant_is` and `InstructionKind.sum_extract_payload`.
- Instruction wire semantics: `sum_variant_is`: `dst` is bool local, `operand` is sum local, `aux` is schema-local variant ordinal. `sum_extract_payload`: `dst` is payload local, `operand` is sum local, `aux` is schema-local variant ordinal; valid only for non-unit variants.
- `effect_ir`: mirror both instruction tags and add exact parameter/local refs for structured locals, preserving legacy scalar `parameter_codecs` and `local_codecs` as compatibility input.
- Public builder: add `ability.ir.builder.sumVariantIs(caller, dst_bool, source_sum, variant_ordinal)` and `ability.ir.builder.sumExtractPayload(caller, dst_payload, source_sum, variant_ordinal)`.
- `Program.contract`: add `schemas`, `fields`, `variants`, `entry_parameters`, `nested_with_targets`, and unique `return_error_names`; preserve negative assertions that `functions`, `instructions`, `ArtifactV1`, and `VM` are absent.
- README: document sum matching, variant ordinal convention, runtime wrong-variant behavior, and contract projection limits.

## Data Flow
1. A `Body.value_schema_types` entry supplies exact Zig type identity for a sum schema.
2. Builder/lowerer emits locals with `.sum` refs and matching `schema_index`.
3. `sum_variant_is` reads the runtime structured value, computes active schema-local variant ordinal using the Zig type behind the schema, writes bool, and updates the existing branch condition path.
4. `branch_if` uses the bool condition without a new terminator kind.
5. `sum_extract_payload` checks the active variant at runtime, writes the payload as scalar or structured value into `dst`, and returns `ProgramContractViolation` on wrong variant.
6. `Program.contract` projects declarations from schema tables and public declarations, not control-flow tables.

## Edge Cases/Failure Modes
- Source local is not `.sum`: validation error.
- Source local has missing or out-of-range schema index: validation error.
- Variant ordinal exceeds `schema.variant_count`: validation error.
- `sum_variant_is.dst` is not bool: validation error.
- `sum_extract_payload` targets a unit variant: validation error.
- `sum_extract_payload.dst` does not exactly match the variant ref: validation error.
- Runtime value schema index differs from local ref: `ProgramContractViolation`.
- Runtime active variant differs from requested payload variant: `ProgramContractViolation`.
- Enum variants are matchable but not payload-extractable.
- Optional ordinal convention is stable: `0 = none`, `1 = some`.

## Tests/Acceptance
- Add direct `ProgramPlan.validate` tests for invalid sum source, bool destination mismatch, variant ordinal out of range, unit payload extraction, and payload destination ref mismatch.
- Add interpreter witnesses in `test/program_api_test.zig`: optional branch on `some`, enum branch on one case, tagged-union payload extraction returning payload.
- Add wrong-variant runtime test expecting `error.ProgramContractViolation`.
- Add effect-ir/lowerer tests proving mirrored tags lower to the same `ProgramPlan` instructions and schema refs.
- Strengthen scalar preservation: existing scalar plans still run and contract metadata remains unchanged except for additive fields.
- Strengthen contract projection tests for schemas/fields/variants/entry params/nested targets/return errors plus continued absence of plan tables.
- Add capability ledger tests: supported sum-match plans have zero blockers; unsupported malformed sum-match shapes report capped blockers.
- Add output cleanup failure-path test covering `collectOutputs` failure after result allocation and asserting result cleanup still runs.
- Run `zig build`, `zig build test --summary none`, and `zig build lint -- --max-warnings 0`.

## Requirement-to-Test Traceability
| requirement | acceptance check |
|---|---|
| all sum shapes executable | optional, enum, tagged-union witness tests |
| payload extraction binds all payload types | tagged-union scalar payload and optional `some` payload tests |
| wrong-variant extraction fails closed | runtime `ProgramContractViolation` test |
| public builder supports new ops | builder helper materialization tests |
| effect_ir/lowerer produces new ops | mirrored instruction lowering test |
| contract is richer but not leaky | contract projection and `!@hasDecl` negative tests |
| capability ledger remains an obligation surface | supported/unsupported ledger tests |
| scalar behavior preserved | scalar run and scalar contract tests |

## Rollout/Monitoring
- Land as one branch wave with one public API note in README.
- Monitor local breakage only through Zig compile/test/lint gates; no runtime service rollout exists.
- Treat any downstream compile break on `effect_ir.InstructionKind` exhaustive switches as intentional API impact requiring same-branch updates.

## Rollback/Abort Criteria
- Abort if adding structured refs to `effect_ir` requires replacing the scalar compatibility API instead of adding an additive path.
- Abort if `Program.contract` needs to expose instruction/function tables to prove sum matching.
- Roll back the entire wave by reverting the schema-version bump, new op tags, builder helpers, interpreter cases, contract additions, README edits, and tests together.
- Do not partially retain the wire bump without executable interpreter support.

## Assumptions/Defaults
- assumption=Plan target is the same objective clarified by `$grill-me`; provenance=user reaffirmation; confidence=high; verification=compare final decisions against grill answers before editing.
- assumption=Current date is 2026-05-08 for planning metadata only; provenance=system date; confidence=high; verification=no release-date behavior depends on it.
- assumption=No legacy upgrade path is acceptable; provenance=user selected "bump only"; confidence=high; verification=test old schema still rejects as unsupported.
- assumption=Full local gates are available; provenance=user selected full proof bar; confidence=medium; verification=run gates after implementation and report any environmental blocker.

## Decision Log
- D1: Treat this as a release-impacting implementation wave, not a doc-only audit.
- D2: Add `.sum_variant_is` and `.sum_extract_payload` as the complete sum-match core.
- D3: Use schema-local variant ordinals; optional ordinals are `none=0`, `some=1`.
- D4: Wrong-variant payload extraction is runtime `ProgramContractViolation`.
- D5: Mirror new ops through `effect_ir` and public builder helpers.
- D6: Add additive exact structured parameter/local refs to `effect_ir` while preserving scalar compatibility fields.
- D7: Expand `Program.contract` only as a declaration projection.
- D8: Bump `ProgramPlan.current_schema_version`; do not write a migration.
- D9: Prove with focused witnesses and full Zig gates.

## Decision Impact Map
| decision_id | impacted_sections | follow_up_action |
|---|---|---|
| D1 | Summary, Scope Change Log, Implementation Brief | execute as one branch wave |
| D2 | Interfaces, Data Flow, Tests | implement validator and interpreter cases |
| D3 | Data Flow, Edge Cases, README | document ordinal convention |
| D4 | Edge Cases, Tests, Rollback | add runtime failure test |
| D5 | Interfaces, Tests | update public re-exports and lowering |
| D6 | Interfaces, Data Flow | add compatibility validation |
| D7 | Interfaces, Tests | add contract view arrays and negative leak tests |
| D8 | Rollback, Tests | assert old schema rejects |
| D9 | Tests, Contract Signals | run full gates after edits |

## Open Questions
None.

## Stakeholder Signoff Matrix
| product | engineering | operations | security |
|---|---|---|---|
| owner=user; status=scope locked by grill answers | owner=implementer; status=ready for implementation | owner=implementer; status=local gates only | owner=implementer; status=no new external I/O or auth surface |

## Adversarial Findings
- lens=feasibility; type=risk; severity=high; section=Interfaces; decision=D6; status=mitigated_by_additive_refs; probability=medium; impact=high; trigger=effect_ir structured locals cannot be represented without schema refs.
- lens=operability; type=risk; severity=medium; section=Rollback; decision=D8; status=mitigated_by_single_wave_revert; probability=low; impact=medium; trigger=schema version bump lands without interpreter support.
- lens=risk; type=risk; severity=high; section=Program.contract; decision=D7; status=mitigated_by_negative_leak_tests; probability=medium; impact=high; trigger=contract exposes plan tables instead of declaration views.
- lens=feasibility; type=preference; severity=low; section=Tests; decision=D9; status=accepted; probability=low; impact=low; trigger=compile-fail harness would add stronger negative proof but was explicitly out of scope.

## Convergence Evidence
blocking_errors=0
material_risks_mitigated=3
clean_rounds=2
press_pass_clean=true
new_errors=0
press_sections_checked=Summary,Interfaces/Types/APIs Impacted,Tests/Acceptance,Implementation Brief
implementation_ready=true

## Contract Signals
contract_version=2
strictness_profile=balanced
blocking_errors=0
material_risks_open=0
clean_rounds=2
press_pass_clean=true
new_errors=0
rewrite_ratio=0.00
external_inputs_trusted=true
improvement_exhausted=true
stop_reason=none

## Implementation Brief
1. step=core_wire; owner=implementer; success_criteria=`ProgramPlan.current_schema_version=9`, new instruction tags exist, hash/JSON/validation switches compile, old schema rejection remains.
2. step=validation; owner=implementer; success_criteria=`ProgramPlan.validate` enforces source sum refs, bool dst, schema-local ordinal bounds, non-unit payload extraction, and exact payload dst refs.
3. step=interpreter; owner=implementer; success_criteria=both interpreter loops execute `sum_variant_is` and `sum_extract_payload`; wrong-variant extraction returns `ProgramContractViolation`.
4. step=public_builder_and_effect_ir; owner=implementer; success_criteria=builder helpers produce valid instructions; `effect_ir` mirrored tags and structured refs lower into exact ProgramPlan refs without breaking scalar callers.
5. step=contract_projection; owner=implementer; success_criteria=`Program.contract` exposes schema/field/variant/entry/nested/return-error declarations and still hides full plan/VM internals.
6. step=tests_and_docs; owner=implementer; success_criteria=README documents the public boundary; witness, ledger, scalar preservation, contract, and cleanup tests pass.
7. step=full_gates; owner=implementer; success_criteria=`zig build`, `zig build test --summary none`, and `zig build lint -- --max-warnings 0` pass or any environmental blocker is reported with exact command output.
