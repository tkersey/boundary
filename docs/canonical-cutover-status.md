# Canonical cutover and optimization status

> Latest user instruction: **No code review is needed before moving onto the optimization phase.** Stage A requires the exact removals and execution/package/economic qualification below, but no CAS/code-review campaign. Do not delay M2 for review or change installed skills/global configuration. This overrides pre-optimization review requirements in this document.

Authority: [complete September 27 specification](canonical-cutover-and-optimization-spec.md).

## Current scope

Stage A finishes the existing canonical authoring/P01/runtime-delivery cutover in
[Boundary #161](https://github.com/tkersey/boundary/pull/161),
[World #59](https://github.com/tkersey/world/pull/59), and
[Agent #39](https://github.com/tkersey/agent/pull/39).
Stage B follows the validated checkpoint on focused successor drafts and
implements all of Part II, starting with M2 and M2.5. Neither stage is complete.

SQLite, replacement databases/journals, new durable application sessions and
recovery orchestration, including former D01–D36/C01–C12, are **superseded by scope
correction**. Former K01–K12 are replaced by F01–F12. No persistence subsystem was
present in the inspected product changes or clean task worktrees; its pending
requirement is cancelled. Existing stores/checkpoints, runners, CLI, locks,
cleanup and domain policies remain required.

## Correction entry

| Repository | Head | Base |
| --- | --- | --- |
| Boundary | `48f36c11f2400bbd69d2b6284a278c86dc9b71e5` | `63137689bf788bc408ba638f47256f2a8f219b44` |
| World | `0ba21202353a24b5ba88bd6a2ce810863916138b` | `c20695e00056186a4b74564da6e4ca1c368cb33b` |
| Agent | `117866d3c3ff2b527dd11ad90309b54945577eb5` | `dd336f0c3833b233978c103caf73b3bcad1daf47` |

Historical reports:
[Boundary](https://github.com/tkersey/boundary/pull/161#issuecomment-5856508884),
[World](https://github.com/tkersey/world/pull/59#issuecomment-5856509388),
[Agent](https://github.com/tkersey/agent/pull/39#issuecomment-5856509842).
Their checks apply only to the recorded inputs, not fresh corrected-scope review.
Agent's ReleaseSafe `check-agent4 check-native agent4-images` aggregate terminated
successfully at the correction-entry head.

## Exact closeout list

The latest user correction removes the previous family-wide Generator/Inquiry/
broker authoring gate. It does not reverse completed migrations. The refresh found
Boundary at `9d7dba2`, World at `0ba2120`, Agent at `4d96815`, all open drafts
assigned to tkersey. The only uncommitted product edit was Inquiry task admission;
its already-running aggregate subsequently exited successfully. Preserve that edit.

| Exact predecessor | Actual remaining callers | Minimum closure | Deciding validation |
| --- | --- | --- | --- |
| Agent `src/value_equality.zig:define`, private `adapted`, and `compare` source-ID migration adapters | `test/consumers/inquiry/live.zig` (policy and three evidence comparisons); `document/consequence_live.zig` (policy/evidence); `repository/completion.zig` (membership and final digest); `repository/replacement.zig` (policy/path/digest); `incremental-parser/main.zig` (candidate revalidation); equality module's own adapter tests. `inquiry/main.zig:admitTask` is already edited in flight. | Migrate only these comparison/control sites to the existing typed equality constructor, keeping their domain algorithms, protected owners and source/component responsibilities. Delete the three adapters and their source-adapter specialization. Keep the no-code recursive portability admission check. Do not create relocated generic source-ID comparison adapters. | Typed equality/schema/foreign-context tests and native independent equality oracle; affected Inquiry, document, repository and parser runtime/negative checks. Then integrated qualification at the coherent tuple. |

The deletion exposed one necessary integration dependency: incremental-parser’s
`experimentAndContinue` is a Source-error callback consumed by Boundary hyper
construction. Removing equality’s adapter exposed typed errors at that callback.
Translate them at this existing callback boundary, preserving its prior
`UnsupportedEqualitySchema -> TypeMismatch` behavior; do not widen hyper’s API.

Final integration also exposed a retained fixture defect: parser consumer-swap
tests asserted historical producer hash `672efdd6…` against the newly emitted
producer `5d687522…` after earlier frontend normalization. Preserve the actual
historical 2,094-byte producer as a frozen input and link both current consumers
against it; keep normal current-producer images separately. Do not regenerate the
expected hash from the candidate. Deciding check: `check-parser-consumers` and
final parser/source-free integration. This repairs the existing witness, not an
additional authoring family. The source-denial harness transports that same frozen
producer and the matching linked image names. Two other existing qualification
fixtures also need alignment: the authentication-only synthetic Boundary stub
must expose `source.Compiled` (not the removed `computation` facade), and component
comparison tests must retain their four actual frozen BMO1 inputs while separately
exercising current emitter outputs. No historical hash or expected behavior is
regenerated from the candidate.

**Closed in Agent `6e43faf`:** all listed comparison sites migrated, the three
source-ID adapters and their specialization key are deleted, and the callback
error contract and frozen-producer witness are repaired. No additional authoring
retirement remains. The initial aggregate exposed the callback error-set mismatch;
the corrected `check-agent4 check-native agent4-images` aggregate passed. The
corrected `check-parser-consumers` lane passed with the preserved producer bytes.

This was the remaining deletion list, not a new repository-wide inventory. No
additional authoring family is admitted. A later dependency must identify this
specific deletion or a concrete retained defect it blocks.

Already retired product predecessors remain retired: public P01 mode selection,
standalone coalescing manifest selection, Agent's duplicate dialogue implementation,
and replaced Generator composition/convenience entrypoints. Final qualification
must verify their absence and meaningful canonical-path witnesses.

The remaining Generator/Inquiry source construction interfaces and broker source
callback boundary are **not** new deletion targets: their callers still construct
or admit the authoritative source graph, and their implementation already uses
the retained canonical emitters. No second generator, custody algorithm or evaluator
has been identified there. This does not rename any listed migration adapter or
certify every existing interface; a concrete defect still requires repair. Further
uniform conversion of these callers is **removed from Stage A scope**, not complete.

## Review brief

Review the actual base-to-head cutover, mandatory P01, preserved runtime/source
verification and authenticated acquisition, the exact removal above, retained
semantic/authority behavior, and final cumulative economics. Do not turn raw IDs,
source construction or frontend uniformity into findings without a violated
accepted requirement. Code reviews are separate from executed qualification.
The user waived code review before optimization; no Stage A review campaign will be started.

## Remaining Stage A acceptance

Boundary `zig build check -Doptimize=ReleaseSafe` passed at `7a1c18a`; later
Boundary changes are task documentation only. World’s full check passed all
non-browser lanes; the missing local locked browser dependency was installed and
`check-browser` then passed on Chromium and Firefox. No new kernel was published.

Agent’s initial integration campaign ended with five fixture-alignment failures.
All affected lanes then passed after repair: parser consumers, source-denied
link/execution, component comparisons on frozen and current inputs, and the
source-override authentication test. The corrected authoring/native/images
aggregate passed; the original failed aggregate is not relabeled a pass.

The user explicitly accepted the measured cutover tradeoffs: six native
admission-memory increases, ReAct execution-memory growth of about 22.7 KiB
(1.21–1.26%), native admission slowdowns of 6.3–19.7%, and WASM review-model
admission slowdown of 17.2%. See Agent’s
`conformance/agent4/canonical-cutover-admission.json`. These accepted costs are
part of the cutover checkpoint, not new defects to reopen during M2. Unmeasured
execution/checkpoint timing is not reported as passing; preserve it in the
optimizer baseline account.

A Boundary M2 worktree/branch was prepared from `aea29fc`, with no optimizer
implementation claimed yet. Proceed to M2 from this qualified Boundary input without another authoring or
code-review prerequisite. The user accepted the reported cutover costs.

F01 scope correction is published. F02 product/diff inspection found no introduced
persistence subsystem; recheck if production inputs change. F03–F12 still require
a coherent final qualification: P01 entrypoint and independent sharing evidence,
validation/cost/rollback obligations, the exact adapter deletion above, existing Agent
behavior, World source-free/runtime checks, authenticated final tuple, cumulative
and local costs, semantic/custody/cleanup tests and final execution qualification.
Code review before optimization is waived by the user.

Agent's runtime is World production `f8a1597d4ff62ae691dfca12f7ce3a2b4e6c0727`,
built with Boundary `511fe388587b36ae37307d277e04c22b0bb6f6d9`, distinct from
World's fixture-only successor and Agent's authoring dependency. Existing artifact
`10923323364` was available at correction entry (expires October 27, 2026).
Reuse authenticated executable bytes where applicable; do not relabel them.

The user withdrew the erroneous `st` and `fixed-point-driver` instructions.
The currently installed `actuating serial-reviews` workflow owns planning, task
tracking, implementation and reviews. No skill restoration, recreation or global
configuration change is required or authorized. Engineering requirements remain
unchanged.

## Selected closure progress

Agent `cc1200c` migrated parser delivery to typed equality/control while retaining
protected observation/approval ownership. ReleaseSafe `parser-delivery-images`
and all 11 runtime cases passed against the existing authenticated World bundle.
The added cases cover mismatched/failed read evidence, zero-principal authority
and wrong approval challenge. Local image size is 2,582 → 2,577 bytes; maximum
observed parked-State sizes are unchanged (569 or 1,958 bytes across the original
seven scenarios). This is a local comparison, not the cumulative pre-cutover
baseline or timing/private-memory acceptance. The exact closeout list above controls remaining authoring work.

## Stage B

All Part II P01–P31, T01–T42, G01–G45 and L01–L20 obligations remain. Reuse applicable
Stage A proof. Start M2 (P02/P03 and early P04/P05/P07/P08), then M2.5 affine
synthesis, with P31 source-free integration throughout. Preserve structural versus
semantic contracts and exact same-image World observations. No merge, release,
paid inference, user-data changes or global configuration changes are authorized.
