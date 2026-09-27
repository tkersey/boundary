# Canonical cutover and optimization status

Authority: [complete September 27 specification](canonical-cutover-and-optimization-spec.md).

## Current scope

Stage A finishes the existing canonical authoring/P01/runtime-delivery cutover in
[Boundary #161](https://github.com/tkersey/boundary/pull/161),
[World #59](https://github.com/tkersey/world/pull/59), and
[Agent #39](https://github.com/tkersey/agent/pull/39).
Stage B follows the validated/reviewed checkpoint on focused successor drafts and
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

## Finite selected caller closure

Inspect actual contracts and migrate ordinary callers of Generator/exchange,
Inquiry, structural equality and broker/policy/controller. Retain genuine expert
IR, admission, component and invalid-IR test boundaries. Do not rewrite every
source-IR use. The initial affected consumer inventory is:

- Agent production: `src/inquiry_broker.zig`, `src/parser_delivery.zig`,
  `src/clarification.zig`, `src/inquiry.zig`, `src/approval.zig`; `src/agent4.zig`
  contains the relevant public re-exports.
- Agent agent4 tests: `recursive_participant`, `approval_equality`, `text_link`,
  `approval_build`, `dialogue_probe`, `multi_probe`, `inquiry_probe`,
  `inquiry_broker_probe`.
- Agent consumer tests: repository `completion`/`replacement`; document
  `consequence_live`/`critic`; incremental-parser `main`; inquiry
  `react`/`intent`/`investigator`/`main`/`policy`/`live`.
- Boundary Generator implementation and its direct library tests.

This is a call-site disposition inventory, not an instruction to rewrite every
listed file. Expand only for a demonstrated dependency of selected closure.

## Remaining Stage A acceptance

F01 scope correction is published. F02 product/diff inspection found no introduced
persistence subsystem; recheck if production inputs change. F03–F12 still require
a coherent final qualification: P01 entrypoint and independent sharing evidence,
validation/cost/rollback obligations, selected adapter retirement, existing Agent
behavior, World source-free/runtime checks, authenticated final tuple, cumulative
and local costs, semantic/custody/cleanup tests and frozen serial reviews.
No corrected-scope serial review campaign has completed.

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
baseline or timing/private-memory acceptance. Other selected adapters remain.

## Stage B

All Part II P01–P31, T01–T42, G01–G45 and L01–L20 obligations remain. Reuse applicable
Stage A proof. Start M2 (P02/P03 and early P04/P05/P07/P08), then M2.5 affine
synthesis, with P31 source-free integration throughout. Preserve structural versus
semantic contracts and exact same-image World observations. No merge, release,
paid inference, user-data changes or global configuration changes are authorized.
