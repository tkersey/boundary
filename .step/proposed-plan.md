Iteration: 4
# Durable Capsule Images and Interaction Journals Plan

## Round Delta
- Converted the durable-continuation spec into a dependency-ordered implementation campaign: canonical codec first, capsule image restore second, journal replay third, examples/docs/proof last.
- Added the byte-authority firewall decision: one private canonical reader/writer/value-image layer with mutation tests becomes the only source of durable bytes for capsules and journals.
- Locked the acceptance bar so scaffold examples cannot substitute for real decode, restore, negative replay, token freshness, leak, and regression proof.

## Summary
Implement durable continuation images and host interaction journals as a narrow Program-owned v1 codec. The chosen path is to build one deterministic binary codec and schema-guided value-image layer first, then use it for `Program.Session.Capsule.Image`, journal entries, replay helpers, interpreter/pipeline recording, examples, and docs. The first execution wave is the private codec firewall plus value round trips; the done state is all requested proof commands passing with no public-root widening and no serializable request tokens.

Execution waves:
- Wave 1: Add format/version constants, private canonical byte writer/reader, checksum/fingerprint framing, and value-image encode/decode for all existing capsule-supported `ProgramValue` shapes.
- Wave 2: Add `Program.Session.Capsule.Image` encode/decode, restore validation integration, deterministic metadata exposure, and corruption/wrong-program negative tests.
- Wave 3: Add `Program.Session.Journal`, deterministic entry/journal encoding, pairing validation, replay from start and from capsule image, and additive recorder hooks for interpreter/pipeline flows.
- Wave 4: Add durable capsule and journal replay examples, build steps, docs, path manifest updates, and the full proof-command closure.

## Iteration Change Log
- iteration=1; focus=1 baseline decisions; round_decision=continue; delta_kind=material; evidence=repo exposes in-process capsules and trace fingerprints but no durable image or journal API; what_we_did=converted user milestone into API, codec, replay, docs, and proof boundaries; change=selected Program-scoped v1 capsule/journal codecs with no public-root widening; sections_touched=Summary,Interfaces/Types/APIs Impacted,Implementation Brief
- iteration=2; focus=2 architecture and interfaces; round_decision=continue; delta_kind=material; evidence=existing restore is the authority for capsule metadata, shape validation, and token retokenization; what_we_did=hardened the plan around decode-as-owned-candidate plus restore-as-final-validation; change=added byte-authority firewall, schema-guided value images, and mutation-negative tests before feature integration; sections_touched=Data Flow,Edge Cases/Failure Modes,Decision Log,Rollback/Abort Criteria
- iteration=3; focus=3 operability and risk; round_decision=continue; delta_kind=none; evidence=operability pass found the host-owned persistence boundary, recorder hooks, and replay validations already cover the material restart and inspection risks; what_we_did=rechecked rollout, monitoring, assumptions, and stakeholder readiness; change=no material delta; sections_touched=Rollout/Monitoring,Assumptions/Defaults,Stakeholder Signoff Matrix
- iteration=4; focus=5 press verification and convergence; round_decision=close; delta_kind=none; evidence=press pass verified Summary, Requirement-to-Test Traceability, Rollback/Abort Criteria, and Contract Signals against the requested milestone and repo constraints; what_we_did=ran final feasibility, operability, and risk critique; change=no material delta; sections_touched=Convergence Evidence,Contract Signals,Implementation Brief

## Non-Goals/Out of Scope
- Do not add a VM, Artifact API, ProgramPlan package format, parser, compiler, source language, persistence backend, async runtime, network or LLM integration.
- Do not widen the public root beyond `ability.effect`, `ability.ir`, `ability.program`, and `ability.Runtime`.
- Do not change `Program.run`, primitive `Program.Session` stepping semantics, existing manual Session/Capsule APIs, Handler/Interpreter APIs, Morphism, Residualize, or Pipeline APIs.
- Do not widen `ProgramValue`, serialize arbitrary host handlers or host contexts, serialize runtime allocator/thread state, make sessions cross-thread, or make request tokens serializable.
- Do not promise compatibility beyond the explicit v1 capsule image and journal format/fingerprint version policy.

## Scope Change Log
- scope_change=spec-to-plan conversion only; reason=user invoked `$plan` after the durable capsule and journal spec was completed; approved_by=user
- scope_change=add byte-authority firewall as implementation ordering control; reason=prevents duplicated or divergent durable byte encoders across capsules and journals; approved_by=planner

## Interfaces/Types/APIs Impacted
- Add Program constants: `Program.capsule_image_format_version = 1`, `Program.capsule_image_fingerprint_version = 1`, `Program.journal_format_version = 1`, and `Program.journal_fingerprint_version = 1`; leave existing trace/request/response/site/value/capsule/continuation/reinterpretation/residualization/pipeline versions unchanged unless implementation truly changes their contents.
- Add `Program.Session.Capsule.Image` with owned `bytes`, image fingerprint, image version, capsule version, continuation fingerprint version, trace fingerprint version, program label, plan label, ProgramPlan hash, capsule fingerprint, continuation fingerprint, parked kind, current request fingerprint, optional semantic site label, and metadata summary.
- Add `capsule.encode(allocator)`, `Program.Session.Capsule.Image.fromCapsule(allocator, &capsule)`, and `Program.Session.Capsule.decode(allocator, image_bytes)` as the public durable capsule surface under `Program.Session.Capsule`.
- Add `Program.Session.Journal`, `Program.Session.Journal.Entry`, and `Program.Session.Journal.Recorder` with deterministic entry encode/decode, bounded in-memory journal encode/decode, journal fingerprinting, and request/response pairing validation.
- Add `Program.Session.replayJournal(runtime, handlers, journal)` or an equivalent `Program.Session.Journal.Replayer` under `Program.Session`; it must replay by fingerprints and decoded typed values, not by request tokens.
- Add interpreter/pipeline recorder integration as an additive option such as `.journal_recorder` while preserving existing trace recorder options and all existing handler/interpreter/pipeline APIs.
- Keep the canonical reader/writer, checksum framing, and value-image codec private to the Program/lowering implementation; they are implementation details, not a broad Artifact format.

## Data Flow
- Capsule image flow: host captures `Program.Session.Capsule`, encode produces deterministic owned bytes, host stores bytes by any backend it chooses, decode validates bytes into an owned in-process capsule candidate, and `Program.Session.restore` performs final program/plan/hash/fingerprint/site/runtime/thread validation while minting fresh request tokens.
- Journal flow: a yielded request appends a request entry, the host response appends a response entry with encoded typed response value when replayable, capsule capture appends a capsule-image entry when requested, completion appends a done entry, the journal encodes to deterministic bytes, decode reconstructs entries, and replay compares each yielded request fingerprint before applying decoded typed responses.
- Value image flow: encode values recursively from existing value/schema metadata, including unit, bool, i32, usize, string bytes, string lists, products, sums, nested product/sum values, and string-bearing product/sum values; fail closed on unsupported tags or malformed schema references.
- Canonical bytes exclude pointer addresses, allocator addresses, runtime addresses, thread IDs, and request tokens; include only deterministic field ordering, length-prefixed byte slices, little-endian integers, explicit magic, explicit versions, and a canonical image/journal fingerprint over the payload.

## Edge Cases/Failure Modes
- Reject malformed capsule images and journals for bad magic, unsupported format version, unsupported capsule or continuation fingerprint version, checksum/fingerprint mismatch, truncated field, length overflow, invalid enum tag, structural inconsistency, and trailing garbage.
- Reject capsule restore for wrong program label, wrong plan label, wrong ProgramPlan hash, wrong trace fingerprint version, wrong capsule/continuation/current request fingerprint, invalid site index, schema mismatch, frame shape mismatch, after stack shape mismatch, or runtime liveness/thread affinity violation.
- Reject value images for invalid schema index, field count mismatch, unknown product field, invalid sum variant ordinal/name policy, missing non-unit payload, unexpected payload for unit variant, malformed nested value, and unsupported value kind.
- Reject replay for missing response after a request entry, response entry whose matching request fingerprint differs from the current yielded request, unused response entries after terminal done, duplicate terminal done, malformed capsule-image entry, or final result fingerprint mismatch.
- Preserve existing stale-token misuse guards: decoded/restored sessions get fresh in-process request tokens, and durable bytes never authorize an old request token.
- Use testing allocator coverage to catch leaked decoded strings, lists, product/sum payloads, journal entries, capsule images, and failed partial-decode cleanup paths.

## Tests/Acceptance
- Capsule image tests: encode/decode operation-parked and after-parked capsules; scalar, string, string_list, product, sum, nested, and string-bearing value images; deterministic same-capsule bytes; restore/capture determinism where semantic continuation is identical; different local value changes image fingerprint; request fingerprint stable across encode/decode/restore; restored tokens are fresh.
- Capsule negative tests: malformed magic, unsupported version, truncation, trailing garbage, checksum mismatch, wrong program, wrong plan hash, bad schema/value refs, bad parked kind, bad frame/after/local shape, failed partial-decode cleanup, and no leaks under the testing allocator.
- Branching tests: decode the same capsule image twice, restore both, resume different approve/deny branches, verify both complete correctly, and verify image bytes remain reusable.
- Journal tests: encode/decode request, response, capsule, and done entries; stable journal fingerprint; replay operation request transcript; replay after request transcript; replay from capsule image; replay custom approval workflow; reject wrong response fingerprint, missing response, unused response, malformed entry, and final-result mismatch.
- Integration tests: interpreter-driven journal recording/replay and pipeline residual run recording/replay when feasible; if pipeline replay needs a narrower proof, add a focused compatibility test that records pipeline request/response/capsule/done entries without changing pipeline semantics.
- Examples and build steps: add `examples/durable_capsule_replay.zig` with `run-durable-capsule-replay` and `examples/journal_replay.zig` with `run-journal-replay`; update the repo Zig path/lint manifest if required.
- Proof commands to run before completion: `zig version`; `zig fmt --check build.zig src examples test bench`; `git diff --check`; `zig build --summary all`; all existing requested `zig build run-*` examples; `zig build test --summary all`; filtered test commands for `capsule image`, `journal`, `replay`, `durable`, `capsule`, `continuation`, `pipeline`, `session`, and `trace`; `zig build lint -- --max-warnings 0`.

## Requirement-to-Test Traceability
- requirement=capsule image deterministic bytes; acceptance=same capsule encodes twice to byte-identical output and same image fingerprint, while a changed local value changes the image fingerprint.
- requirement=capsule image decode/restore; acceptance=decoded operation and after capsules restore into fresh sessions, yield the same request fingerprint, and reject wrong program and wrong plan hash.
- requirement=value image coverage; acceptance=scalar, string, string_list, product, sum, nested product/sum, and string-bearing product/sum round trips pass and malformed variants fail closed.
- requirement=request tokens not serializable; acceptance=image byte scan/metadata tests prove tokens are absent, stale old tokens remain rejected, and restored request tokens are fresh.
- requirement=journal entry and journal codec; acceptance=request/response/capsule/done entries and bounded journals round trip with stable journal fingerprints and malformed bytes rejected.
- requirement=replay by fingerprint and typed decoded values; acceptance=replay rejects wrong/missing/unused responses and succeeds for operation, after, capsule-start, approval workflow, interpreter, and feasible pipeline scenarios.
- requirement=docs and examples prove crash-like use; acceptance=durable capsule example prints capsule image fingerprint, request fingerprint, approve result, and deny result; journal example prints journal fingerprint and replayed final result; docs state non-goals and version policy.

## Rollout/Monitoring
- Roll out as an additive local library feature on the current branch; no feature flag, persistence backend, or public root change is required.
- Monitor implementation health through deterministic fingerprints printed by the two examples, negative codec/replay tests, testing allocator leak checks, `repo_zig_paths.txt` or equivalent manifest validation, and unchanged existing example behavior.
- PR summary must state the capsule image API, journal API, canonical byte guarantees, value encoding policy, decode/restore validation split, request-token versus fingerprint distinction, examples, added versions, unchanged primitive Session APIs, and all explicit non-goals.

## Rollback/Abort Criteria
- abort_trigger=canonical codec requires widening `ProgramValue`, serializing host handlers, serializing request tokens, or changing public root; rollback_action=stop implementation and return to a plan/spec revision instead of shipping a partial format.
- abort_trigger=restore can succeed without validating program label, plan label, ProgramPlan hash, capsule fingerprint, continuation fingerprint, current request fingerprint, site indexes, runtime liveness, and thread affinity; rollback_action=remove decode/restore exposure until validation is complete.
- abort_trigger=journal replay applies responses by in-process tokens or ordering alone instead of request fingerprints plus decoded typed values; rollback_action=disable replay helper and retain only codec tests until replay is corrected.
- abort_trigger=examples pass but negative decode/replay tests or leak checks fail; rollback_action=do not publish examples as proof, fix codec ownership and validation first.
- abort_trigger=existing Program.run, Session, Capsule, Handler/Interpreter, Morphism, Residualization, or Pipeline regression appears; rollback_action=bisect within the four waves and revert only the offending wave while preserving unrelated user changes.

## Assumptions/Defaults
- confidence=high; assumption=as of 2026-05-12 the working tree is on `main` at the explored Ability baseline with Zig 0.16.0; verification plan=rerun `git status --short --branch`, `git rev-parse HEAD`, and `zig version` at implementation start.
- confidence=high; assumption=exact type and method names may follow local Zig style if signatures preserve the specified capabilities under `Program.Session.Capsule` and `Program.Session.Journal`; verification plan=compile public tests and inspect generated docs/API call sites.
- confidence=high; assumption=no external serialization dependency is allowed or needed; verification plan=review dependency diff and ensure codec code is in-library and deterministic.
- confidence=medium; assumption=pipeline replay is feasible without changing pipeline semantics; verification plan=attempt focused pipeline residual replay test and, if infeasible, record request/response/capsule/done entries through existing pipeline trace surfaces without changing public behavior.

## Decision Log
- decision_id=D1; supersedes=n/a; decision=keep all durable APIs under `Program` and `Program.Session` without widening public root.
- decision_id=D2; supersedes=n/a; decision=use fixed magic, explicit v1 versions, little-endian integers, length-prefixed slices, deterministic ordering, and in-library checksum/fingerprint framing instead of JSON or external serialization.
- decision_id=D3; supersedes=n/a; decision=decode creates an owned capsule candidate, while `Program.Session.restore` remains final validation and retokenization authority.
- decision_id=D4; supersedes=n/a; decision=encode values through existing schema/value metadata and fail closed on unsupported or malformed product/sum/value shapes.
- decision_id=D5; supersedes=n/a; decision=journals replay by request fingerprints and decoded typed values, never by serialized request tokens.
- decision_id=D6; supersedes=n/a; decision=implement the byte-authority firewall first so capsule and journal encoders share one canonical durable byte boundary.
- decision_id=D7; supersedes=n/a; decision=interpreter and pipeline journal recording is additive and must not replace existing trace recorder behavior.

## Decision Impact Map
- decision_id=D1; impacted_sections=Interfaces/Types/APIs Impacted,Non-Goals/Out of Scope,Implementation Brief; follow_up_action=place new public types under existing `Program` namespaces only.
- decision_id=D2; impacted_sections=Data Flow,Tests/Acceptance,Rollback/Abort Criteria; follow_up_action=write codec mutation tests before exposing capsule image decode.
- decision_id=D3; impacted_sections=Data Flow,Edge Cases/Failure Modes,Tests/Acceptance; follow_up_action=add wrong-program, wrong-plan, shape, fingerprint, and fresh-token restore tests.
- decision_id=D4; impacted_sections=Data Flow,Tests/Acceptance,Requirement-to-Test Traceability; follow_up_action=round-trip every currently capsule-supported value kind and reject malformed schema refs.
- decision_id=D5; impacted_sections=Data Flow,Journal Tests,Rollback/Abort Criteria; follow_up_action=make wrong/missing/unused response replay tests mandatory.
- decision_id=D6; impacted_sections=Implementation Brief,Tests/Acceptance,Adversarial Findings; follow_up_action=complete private codec and mutation harness before feature examples.
- decision_id=D7; impacted_sections=Interfaces/Types/APIs Impacted,Rollout/Monitoring,Tests/Acceptance; follow_up_action=preserve trace recorder tests while adding journal recorder coverage.

## Open Questions
None.

## Stakeholder Signoff Matrix
| stakeholder | owner | status | signoff basis |
| --- | --- | --- | --- |
| product | Ability maintainer | ready-by-spec | meets requested durable capsule, journal, replay, example, and docs scope without excluded platform features |
| engineering | implementer | ready | dependency-ordered waves and validation gates are explicit |
| operations | host application owner | ready | persistence remains host-owned and no backend/runtime/thread state is serialized |
| security | reviewer | ready | request tokens, pointers, allocator/runtime addresses, thread IDs, handlers, and host contexts are excluded from durable bytes |

## Adversarial Findings
Taxonomy markers: errors=0 active; risks=0 open after mitigation; preferences=1 accepted non-blocking.

| lens | type | severity | section | decision | status | probability | impact | trigger |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| feasibility | risk | high | Data Flow | D3,D6 | mitigated | medium | high | decode path restores executable state before complete shape, fingerprint, and plan validation |
| operability | risk | medium | Tests/Acceptance | D5 | mitigated | medium | medium | examples demonstrate happy path while replay pairing, missing response, and unused response failures remain untested |
| risk | risk | high | Non-Goals/Out of Scope | D1,D5 | mitigated | low | high | durable bytes accidentally include request tokens, pointers, runtime addresses, thread IDs, or host handler state |
| feasibility | preference | low | Interfaces/Types/APIs Impacted | D7 | accepted | low | low | final option field name differs from `.journal_recorder` but remains additive and source-local |

## Convergence Evidence
- clean_rounds=2
- press_pass_clean=true
- new_errors=0
- last_two_no_delta=iterations 3 and 4
- press_verified_sections=Summary,Requirement-to-Test Traceability,Rollback/Abort Criteria,Contract Signals
- implementation_ready=true because APIs, byte format, value coverage, validation split, replay semantics, examples, docs, proof commands, rollback triggers, and non-goals are decision-complete.
- remaining_minor_concerns=exact Zig field names can adapt to local style without changing the locked capabilities.

## Contract Signals
contract_version=2
strictness_profile=balanced
blocking_errors=0
material_risks_open=0
clean_rounds=2
press_pass_clean=true
new_errors=0
rewrite_ratio=0.00
external_inputs_trusted=false
improvement_exhausted=true
stop_reason=none

## Implementation Brief
- step=confirm baseline and recall local constraints; owner=lead implementer; success_criteria=`git status --short --branch`, `git rev-parse HEAD`, and `zig version` confirm the current implementation baseline before edits.
- step=build byte-authority firewall and version constants; owner=codec implementer; success_criteria=private canonical writer/reader, fingerprint framing, capsule/journal version constants, and mutation tests reject corrupt bytes before capsule/journal features depend on them.
- step=implement schema-guided value images; owner=codec implementer; success_criteria=all scalar, string, string_list, product, sum, nested, and string-bearing values round trip and malformed schema/value refs fail closed with no leaks.
- step=implement capsule image encode/decode; owner=session implementer; success_criteria=`Program.Session.Capsule.Image`, encode/fromCapsule/decode APIs, deterministic metadata, restore integration, fresh-token proof, wrong-program/plan/hash negative tests, and branch replay tests pass.
- step=implement journal entries and replay; owner=session implementer; success_criteria=request/response/capsule/done entries encode/decode deterministically, bounded journals fingerprint stably, replay succeeds by fingerprint and typed values, and wrong/missing/unused responses fail.
- step=wire interpreter and pipeline recording; owner=integration implementer; success_criteria=journal recorder is additive to existing trace recording and focused interpreter/pipeline tests pass without changing semantics.
- step=add examples, build steps, manifest entries, and docs; owner=examples/docs implementer; success_criteria=`run-durable-capsule-replay` and `run-journal-replay` demonstrate save/decode/restore/branch and record/decode/replay, while README and docs state version policy, host-owned persistence, token exclusion, and non-goals.
- step=run closure proof and prepare PR summary; owner=lead implementer; success_criteria=all requested fmt, diff, build, example, test-filter, full-test, and lint commands pass, and PR summary covers APIs, byte guarantees, value encoding, validation, token/fingerprint distinction, examples, versions, preserved APIs, and excluded features.

Iteration: 4
