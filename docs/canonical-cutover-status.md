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

Boundary `65f4613` and Agent `20362f1` qualify the retained-argument repair.
World head is `9e2956a`; actual runtime remains `cb52f4f`, kernel `9356b126`.
Boundary passes **319 steps / 852 tests**, the committed public-package check,
and **582** native/Node/Wasmtime comparisons. Agent emission passes **259 steps**;
A02 and **3/3** archive-command tests pass with no skips. All **123** generated
output files, including the 67-file distribution and its inventory, match the
previously qualified artifacts byte-for-byte.

Known-variant and callable specialization now check replacement schemas against
continuation captures observed during original ownership analysis. Compatible
replacements still specialize. Independent validation and original/candidate
admission remain required. Ten execution cases cover both carriers, permitting
and excluding bounds, multiple captures, indirect effects and effects after last
use. The bounded nontermination checks do not claim unbounded liveness proof.

The historical full integration remains Boundary `42c089c` / Agent `db48ebc` /
World `cb52f4f`: **411 steps / 202 Zig tests / 95 Node tests**. Reuse is limited to
identical runtime inputs and unchanged hosts/kernel. Historical measurements keep
their original subjects. The new compiler check adds one allocation / 144 total
allocated bytes in four small fixtures; timing is inconclusive.

The complete P/T/G/L obligations, accepted costs, repair history and exact evidence
are in [optimization acceptance](optimization-acceptance.md). Cleanup is retained;
repetitive review-follow-up narratives are consolidated there, with the original
versions preserved in Git history. All six initial predecessor review outcomes
were folded before repair. Review credit is zero; fresh final serial reviews
remain required before the goal is complete.
