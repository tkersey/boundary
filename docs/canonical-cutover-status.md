# Canonical cutover and optimization status

Authority: [current specification](canonical-cutover-and-optimization-spec.md),
including its pre-review repository cleanup section. Keep one existing branch
and draft PR per repository: Boundary #161, World #59, Agent #39. No merges, releases,
new worktrees, skills/global-configuration changes or paid inference.

## Closed Stage A scope

Mandatory checked P01 is retained in every closed compile and final link.
SQLite/durable-session/recovery work is cancelled; no replacement persistence
system was introduced. Existing runners, tools, approvals, allowances, locks,
cleanup, storage, checkpoints and authentication remain required.

| Exact predecessor | Owned callers | Completed closure | Deciding validation |
| --- | --- | --- | --- |
| Agent `src/value_equality.zig:define`, private `adapted`, and `compare` source-ID migration adapters | `test/consumers/inquiry/live.zig` (policy and three evidence comparisons); `document/consequence_live.zig` (policy/evidence); `repository/completion.zig` (membership and final digest); `repository/replacement.zig` (policy/path/digest); `incremental-parser/main.zig` (candidate revalidation); equality module's own adapter tests; `inquiry/main.zig:admitTask`. All are closed. | Migrated these comparison/control sites to the existing typed equality constructor, keeping their domain algorithms, protected owners and source/component responsibilities. Deleted the three adapters and their source-adapter specialization; retained the no-code portability check. No relocated generic source-ID adapter remains. | Typed equality/schema/foreign-context tests and native independent equality oracle; affected Inquiry, document, repository and parser runtime/negative checks. Then integrated qualification at the coherent tuple. |

Closed in Agent `6e43faf`: adapters and specialization deleted; listed callers
migrated. The callback retains UnsupportedEqualitySchema-to-TypeMismatch behavior.
The historical parser producer and four component objects remain independent
frozen fixtures; current emissions are tested separately. Source-denial and
package-stub integration defects were repaired. No additional authoring family
is admitted; uniform frontend syntax is excluded from Stage A.

## Current technical checkpoint

Boundary `42c089c` / Agent `db48ebc` / World `cb52f4f` kernel `9356b126` is qualified:
Boundary 319 steps / 842 tests; Agent 411 steps / 202 Zig tests / 95 Node tests; all 18 Agent images
unchanged by the latest repair; 288 Node/Wasmtime variant comparisons pass.
The user explicitly accepted all recorded costs. Current evidence and the full
P/T/G/L scope are consolidated in [optimization acceptance](optimization-acceptance.md).

Initial review findings identified input-demand, payload-transfer and profile
forwarding defects;42c089c repairs them. No clean credit survives that invalidated
subject. Complete the specified cleanup and affected reference/package checks,
then freeze corrected scope and run the installed final serial-review contract.
Historical narratives are archived at their exact original commits, not rewritten
as current results. The goal remains incomplete until final review closure.
