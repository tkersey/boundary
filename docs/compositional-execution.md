# Boundary 3 successor status

Boundary 3.0.0-dev.0 provides stable-slot authoring, checked BMO1 component linking,
and the current BPI3/PST3/invocation data contracts. World interprets these records;
Agent is the required consumer. The successor remains incomplete and its PRs remain
drafts. Implementation has resumed after the authorized archive cleanup.

Current contracts: [components](bmo1-components.md), [Program images](bpi3-wire.md),
[State](pst3-wire.md), and [invocations](invocation-wire.md).

The current full check passes 216 build steps and 228 tests, including 103 pure
data tests, source semantics, ownership, nominal separation, allocation failures,
native/wasm32 codecs and source-independent linking.

## Current results and unresolved work

Large top-level block catalogs now use an exact allocation owned by Decoded;
nested records and small catalogs keep their existing arena. The existing block
reader, budget checks, canonical re-emission and identity remain unchanged. Errors
release the catalog even when parsing stops partway through it. Tests cover caller
mutation, malformed trailing bytes and every allocation failure. No decoder
reparses or relocates live pointers, and no standard-library arena internals change.

Across 13 fixed Agent scenarios and 128 paired native invocations, canonical
outcomes and transition/control/copy counters match. Inquiry/ReAct Session peaks
fall 1,952,780 / 3,084,054 → 1,866,916 / 2,739,154 bytes. Two native replay windows
and two guest initial-invocation windows show small mixed timing changes; no
latency improvement is claimed. Control64/128/256 peaks fall to 193,195 / 303,637 /
575,249 bytes; tiny controls add 16 bytes for the catalog ownership slice. The
kernel grows 915 bytes. BPC1 inquiry/ReAct peaks (1,853,961 / 2,061,220) remain
lower, so those gaps and final performance acceptance remain open.

The following measurements preceded this catalog ownership change:

On 64-bit hosts, analysis-set pools select a 16-byte node layout when their declared
member limit fits in 32 bits; larger domains retain 24-byte nodes. wasm32 keeps
its previous untagged 24-byte storage. Public members remain
u64 and roots remain checked u32 indexes. Both layouts expand to the same exact
node before hashing, equality and set operations. Overlays inherit their base's
limit and preserve immutable roots. Tests retain exhaustive eight-bit operations,
full-width high IDs, allocation failure and buffer accounting, and add cases at
the 32-bit representation boundary. Wire bytes and identities are unchanged.

Using the unchanged Agent images, native preparation retains 1,168,868 /
1,178,378 / 2,485,154 bytes for inquiry/repeated/ReAct, down from 1,265,868 /
1,275,378 / 2,812,770. Preparation peaks fall by 161,728 bytes for inquiry and
repeated inquiry, and by 546,088 bytes for ReAct (3,534,020 → 2,987,932).
These preparation measurements exclude execution and invocation framing.

Final rotating native windows support modest control128/ReAct gains. Tiny scalar
invocations cost roughly 40–80 ns more; other control timing differences are mixed.
Control64/128/256 working peaks are 201,927 / 320,429 / 608,169 bytes. Scalar and
one-installation peaks rise by 38 / 66 bytes from the layout selector overhead.
Across 128 fixed invocations from 13 Agent scenarios, canonical outcomes match.
Whole-invocation reset-inquiry/ReAct peaks fall from 2,147,127 / 3,676,006 to
2,050,143 / 3,226,040 bytes. The Session-only counter falls from 2,049,764 /
3,534,020 to 1,952,780 / 3,084,054; transitions, control and copy counters match. Two final rotating native replay windows show no material
latency regression; inquiry differences are below 1%, with modest ReAct gains.
Final matched BPC1 acceptance, the remaining workload matrix and serial reviews
remain open. No performance failure has been waived.

The all-target tagged layout slowed the sampled fresh wasm32 inquiry/ReAct
invocations by about 3% / 7% in two rotating windows. It is rejected on wasm32;
the retained host selection produces the byte-identical previously qualified
460,161-byte kernel. No guest performance or memory gain is claimed.

The prior exact-allocation trial for large decoded arrays reduced retained
storage but repeatedly slowed control256; it remains rejected. Its independent
large-image ownership/allocation-failure regression is retained. The decoded
arena's unused capacity remains a concrete optimization opportunity.

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
