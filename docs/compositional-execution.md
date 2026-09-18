# Boundary 3 successor status

Boundary 3.0.0-dev.0 provides stable-slot authoring, checked BMO1 component linking,
and the current BPI3/PST3/invocation data contracts. World interprets these records;
Agent is the required consumer. The successor remains incomplete and its PRs remain
drafts. Implementation has resumed after the authorized archive cleanup.

Current contracts: [components](bmo1-components.md), [Program images](bpi3-wire.md),
[State](pst3-wire.md), and [invocations](invocation-wire.md).

The full Boundary check passes, including allocation failure, ownership, nominal
separation, borrow contracts, independent native/wasm32 codecs and source-independent
linking. The latest flow-storage change also passes World's 74 source tests and
52 storage tests, 257 native/Node boundaries and extracted runtime checks.

## Current results and unresolved work

Private analysis indexes use checked u32 while member IDs remain u64. Flow analysis
now releases work queues, reverse edges and temporary traits before returning its
facts. Each FIFO holds at most one entry per block instead of retaining processed
visit history. Entries, position facts, liveness and set nodes retain their owner.

Across 13 unchanged Agent scenarios, native inquiry/ReAct Session peaks fall from
2,847,222 / 4,239,618 to 2,408,588 / 3,841,782 bytes with identical outcomes and work
counts. Five paired guest runs overlap substantially; guest speed is indeterminate.

Native control64 is about 362 microseconds and 219,987 working bytes, versus about
238 microseconds and 121,956 bytes for optimized BPC1: that gap remains unresolved.
Control128/256 peaks are 417,163 / 881,349 bytes, up from 415,111 / 788,285 in the
preceding successor but below BPC1's 435,558 / 1,324,938. These are requested working
allocations, not RSS. Wasmtime/browser requalification and the remaining performance
matrix are still required for the final candidate.

Agent's measured inquiry/ReAct native Session peaks remain above BPC1. Remaining
work includes primary-workload performance, the rest of the accepted workload
matrix, consumer retirement, coordinated final qualification, serial reviews and
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
