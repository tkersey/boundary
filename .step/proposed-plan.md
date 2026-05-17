Iteration: 6

# Linear Effect Sessions Implementation Plan

## Summary
Add Linear Effect Sessions as a deterministic usage calculus under the existing `Program.Exchange` surface. The milestone makes capability-routed exchanged effects safe around reusable capsules by recording usage mode, capability instance state, obligations, branch policy, replay class, response transitions, cancellation, journal events, and ledger validation. The implementation must preserve `Program.Session` as the primitive host-driven execution machine and keep the public root unchanged.

Chosen strategy: implement this as typed validation metadata over Exchange, Capability, Capsule, MailboxRunner, Journal, and Pipeline surfaces. This is not cryptographic security, transport, async, network, persistence, workflow, VM, parser, or host-handler serialization.

## Non-Goals/Out of Scope
No changes to `Program.run` semantics, `Program.Session` primitive stepping semantics, existing Session/Capsule/Journal/Exchange/Capability/Handler/Interpreter/Morphism/Residualize/Pipeline APIs removals, parser/source language, public VM API, Artifact API, async runtime, network or LLM integration, persistence backend, cryptographic signing/encryption, public root widening, `ProgramValue` widening, serializable request tokens, cross-thread sessions, arbitrary host handler serialization, host context serialization, or allocator/thread state serialization.

## Interfaces/Types/APIs Impacted
- `Program` version constants: add `exchange_effect_session_format_version`, `exchange_effect_session_fingerprint_version`, `exchange_capability_instance_format_version`, `exchange_capability_instance_fingerprint_version`, `exchange_obligation_format_version`, `exchange_obligation_fingerprint_version`, and `exchange_obligation_transition_fingerprint_version`.
- `Program.Exchange` enums: `Usage`, `ResponseUse`, `BranchPolicy`, obligation/session statuses and structured blocker types.
- `Program.Exchange.EffectSessionSpec`: Zig-friendly deterministic descriptor for externalized effect state transitions, default usage, branch policy, replay policy, allowed response kinds/refs, provider/capability constraints, and stable fingerprinting.
- `Program.Exchange.CapabilityInstance`: consumable deterministic authority instance with parent capability/provider/manifest/spec fingerprints, current state, usage mode, branch id, opened/consumed/canceled/replay state, generation, parent instance, and path fingerprint.
- `Program.Exchange.Obligation`: ledger bridge from request envelope to world-effect usage with usage mode, branch id, open state, allowed responses, capsule image fingerprint, lifecycle status, consumed/replay fingerprints, and stable fingerprinting.
- Request envelope metadata: optional session spec, capability instance, obligation, usage, branch id, branch policy, replay policy, ephemeral, and cancelability metadata without serializing request tokens.
- Response authorization result: obligation transition metadata for provider/capability/instance/obligation/spec/route/request/response validation.
- `MailboxRunner` and `Session.Journal`: optional obligation open/consume/replay/cancel/reject events and duplicate affine/linear response rejection.
- `Program.Exchange.ObligationLedger`: validation pass for duplicate consumption, unresolved linear obligations, replay/fresh branch violations, canceled/consumed misuse, state mismatch, and provider/capability mismatch.
- Pipeline certificates/effect row metadata: expose usage/session policy summaries enough for future stages to inspect residual linear effects.

## Implementation Brief
1. step=core-linear-session-types; owner=implementation; success_criteria=usage/replay/branch enums, version constants, session spec, blocker, fingerprint, and transition APIs compile with stable fingerprint tests.
2. step=capability-instances-and-obligations; owner=implementation; success_criteria=instance create/split/consume/cancel and obligation open/consume/replay/cancel APIs reject illegal affine/linear/ephemeral states and have stable fingerprint tests.
3. step=request-authorization-metadata; owner=implementation; success_criteria=request envelopes carry optional obligation/session metadata without serializing tokens, response authorization transition metadata validates request/response/route/capability/instance/obligation/spec state.
4. step=branch-split-cancel-discipline; owner=implementation; success_criteria=unrestricted/replay_only/single_live_branch/split_required/no_branch/host_owned branch checks, split policy, cancel API, and capsule embedding checks enforce ephemeral and open-obligation rules.
5. step=mailbox-journal-ledger-integration; owner=implementation; success_criteria=MailboxRunner opens/consumes/replays/cancels obligations when configured, Journal encodes/decodes new events, and ledger validation catches duplicate consumption, unresolved linear obligations, response-after-cancel, wrong branch/provider/capability, and replay/fresh violations.
6. step=pipeline-examples-docs-build; owner=implementation; success_criteria=pipeline summaries expose usage metadata, examples `linear_effect_sessions.zig` and `linear_branch_safety.zig` plus run steps work, docs/README explain the model, and repo path/lint manifest is updated.
7. step=full-proof-and-ship; owner=implementation; success_criteria=all requested proof commands pass, durable `$st` proof is recorded, fixed-point review reaches no actionable findings, branch is pushed, and PR is opened with a proof-rich summary.

## Proof Commands
```bash
zig version
zig fmt --check build.zig src examples test bench
git diff --check
zig build --summary all
zig build run-linear-effect-sessions
zig build run-linear-branch-safety
zig build run-effect-capability-routing
zig build run-effect-capability-attenuation
zig build run-effect-exchange-mailbox
zig build run-effect-exchange-restart
zig build run-durable-capsule-replay
zig build run-journal-replay
zig build run-effect-pipeline
zig build run-residualized-approval-policy
zig build run-protocol-reinterpretation
zig build run-interpreter-branching
zig build run-continuation-branching
zig build run-custom-approval-workflow
zig build run-agent-loop
zig build run-typed-program-plan
zig build test --summary all
zig build test --summary none -- --test-filter "linear"
zig build test --summary none -- --test-filter "obligation"
zig build test --summary none -- --test-filter "usage"
zig build test --summary none -- --test-filter "branch policy"
zig build test --summary none -- --test-filter "capability instance"
zig build test --summary none -- --test-filter "replayable"
zig build test --summary none -- --test-filter "affine"
zig build test --summary none -- --test-filter "exchange"
zig build test --summary none -- --test-filter "capability"
zig build test --summary none -- --test-filter "journal"
zig build test --summary none -- --test-filter "mailbox"
zig build test --summary none -- --test-filter "capsule image"
zig build lint -- --max-warnings 0
```
