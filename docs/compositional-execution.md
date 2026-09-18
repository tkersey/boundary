# Boundary 3 successor status

Boundary 3.0.0-dev.0 provides stable-slot authoring, checked BMO1 component linking,
and the current BPI3/PST3/invocation data contracts. World interprets these records;
Agent is the required consumer. The successor remains incomplete and its PRs remain
drafts. Implementation is paused for the authorized archive cleanup.

Current contracts: [components](bmo1-components.md), [Program images](bpi3-wire.md),
[State](pst3-wire.md), and [invocations](invocation-wire.md).

The last implementation qualification passed 216 build steps and 221 Zig tests,
including allocation failure, ownership, nominal separation, borrow contracts,
independent native/wasm32 codecs and source-independent linking. Cleanup does not
change executable source or test expectations; it does not repeat that full matrix.

## Current results and unresolved work

Private analysis indexes use checked u32 while member IDs remain u64. The separate
index-space bound is needed only when narrowing the pointer width. The final guest
runtime remains byte-identical to its preceding qualified version.

On the measured native control64 workload, medians were 363/359 microseconds and
working peak was 241,495 bytes. Optimized BPC1 was about 238 microseconds and
121,956 bytes: the regression remains unresolved. Control128/256 peaks were
415,111/788,285 bytes. Value peaks decreased, with small timing increases in some
cases. These are workload-specific requested-allocation observations, not RSS or
universal performance claims.

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
