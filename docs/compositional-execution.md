# Boundary 3 successor status

Boundary 3.0.0-dev.0 provides stable-slot authoring, checked BMO1 component linking,
and the current BPI3/PST3/invocation data contracts. World interprets these records;
Agent is the required consumer. The successor remains incomplete and its PRs remain
drafts. Implementation has resumed after the authorized archive cleanup.

Current contracts: [components](bmo1-components.md), [Program images](bpi3-wire.md),
[State](pst3-wire.md), and [invocations](invocation-wire.md).

The current data check passes 101 tests, including large-image ownership and
allocation failure. Full-suite coverage includes ownership, nominal separation,
borrow contracts, native/wasm32 codecs and independent linking.
World passes 75 source tests, 257 native/Node boundaries, 23 transfers,
extracted-runtime and capacity/retry checks. The 13 Agent diagnostic scenarios
preserve outcomes, work counts, authority and cleanup.

## Current results and unresolved work

Private analysis indexes use checked u32 while member IDs remain u64. Flow analysis
now releases work queues, reverse edges and temporary traits before returning its
facts. Each FIFO holds at most one entry per block instead of retaining processed
visit history. Entries, position facts, liveness and set nodes retain their owner.
Canonical set nodes now use 24 bytes instead of 32: their payload and bounds
determine the kind and exact cardinality, so no cached count is needed. Type
validation reuses its existing schema exportability table for the borrow check,
removing one repeated fixed-point derivation without changing ownership or APIs.

Across 13 unchanged Agent scenarios, the current triad's native inquiry/ReAct
Session peaks are 2,049,764 / 3,534,020 bytes, including World's contract-scratch
reclamation. Outcomes and work counts agree; no latency improvement is claimed
for that change.

ReAct's decoded-record arena reserves 1,320,484 bytes for 704,399 accounted bytes
in the diagnostic replay. An exact-allocation prototype for arrays of at least
4 KiB reduced that storage to 836,339 bytes, but slowed every one of seven paired
control256 timing windows (median increase 1.9%). It was reverted; production
allocation is unchanged. The large-image mutation and allocation-failure
regression remains useful independently of that rejected technique.

Native control64 is about 360 microseconds and 214,595 working bytes, versus about
238 microseconds and 121,956 bytes for optimized BPC1: that gap remains unresolved.
Control128/256 peaks are 353,313 / 715,953 bytes, below the preceding successor
and BPC1's 435,558 / 1,324,938. Compact predecessor storage is selected only for
64-bit hosts; the 32-bit predecessor builder remains unchanged after all-target
compact construction regressed guest timing. The smaller set nodes apply on both
targets. These are requested working
allocations, not RSS. The current kernel passes Wasmtime and real Chromium/Firefox
transfer checks, including the compiled Agent tool witness. The remaining performance
matrix is still required before completion.

Agent's measured inquiry/ReAct native Session peaks remain above BPC1. Remaining
work includes primary-workload performance, the rest of the accepted workload
matrix, coordinated final qualification, serial reviews and
a requirement-by-requirement audit. No performance failure has been waived.

Current tests and the small source/compiler probes under `test/` and
`docs/performance/cold-guard.mjs` remain available for reproduction. Generated
measurement dumps and experimental patches are no longer maintained or packaged.
Existing defect records retain their original historical provenance; their old
artifact paths refer to the recorded Git revisions, not the current tree.

Linked drafts: [Boundary #152](https://github.com/tkersey/boundary/pull/152),
[World #54](https://github.com/tkersey/world/pull/54),
[Agent #32](https://github.com/tkersey/agent/pull/32).
No merge, promotion or release is authorized. Current-tree deletion does not purge
historical Git objects.
