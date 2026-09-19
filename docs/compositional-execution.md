# Boundary 3 successor status

Boundary 3.0.0-dev.0 provides stable-slot authoring, checked BMO1 component linking,
and current BPI3/PST3/invocation contracts. World interprets these records; Agent
is the required consumer. The successor remains incomplete and all PRs are drafts.

Current contracts: [components](bmo1-components.md), [Program images](bpi3-wire.md),
[State](pst3-wire.md), and [invocations](invocation-wire.md).

## Current construction and checks

Linear functions whose control results remain needed in the final block place
control bindings before instruction temporaries when those bindings span multiple
64-slot words. This is a bijective renaming: slot counts, schemas, instructions,
simultaneous assignments, custody and call-argument order are preserved. Branching
and recycling lifetimes retain their layouts. Tests cover immutable, idempotent
renaming and those exclusions; full admission runs after transformation.

Empty jumps are threaded only within the same function and custody scope, without
assignments. Cycles and real handlers remain. Local product projections reuse
already-computed field slots only for copyable, droppable products. Every operand
and the product still evaluate in order; malformed projections remain rejectable.
The independent mutable/fault fixture returns 8 or fails with 77 as prescribed.

The full check passes 220 steps and 233 tests, including 42 independent source
fixtures, native/wasm32 byte agreement and source-free component linking. World
also passes 79 native source tests and all 42 source/native/WASM comparisons.

## Current results and limits

Two alternating windows use one runtime-only executable, comparing the slot-order
change with Boundary e6388d9 and identical World a609a1f production code. Each
process has three warmups and nine samples; these are complete fresh-invocation
medians, not tail-latency measurements. M2 Pro, macOS 27.2, Zig 0.16.0 ReleaseSafe.

| Installations | Confirmation before → after µs | Peak bytes before → after | Current BPI3 bytes / BPC1 limit |
| --- | --- | --- | --- |
| 64 | 295–301 → 273–279 | 190,649 → 179,719 | 2,241 / 2,805 |
| 128 | 643–667 → 554–583 | 296,055 → 274,031 | 4,559 / 5,574 |
| 256 | 1,396–1,458 → 1,155–1,175 | 462,039 → 400,643 | 9,551 / 12,102 |

Allocation calls rise 825/1,574/3,063 → 861/1,707/3,455 despite lower total
allocated bytes and peaks. Node 26.9.0 guest replay clearly improves
installation256; 64/128 are less decisive. File loading and JavaScript import
are outside those guest timers; fresh Kernel setup, invocation and outcome
decoding are included.

Inquiry/repeated/ReAct images remain byte-identical at 36,756/37,137/48,226 bytes.
Retained-loop, shallow and queens inputs also remain byte-identical. General slot
reordering is excluded: it increased inquiry admission set storage across an
allocation threshold. The existing exact block-catalog allocation and native
compact analysis nodes remain; rejected all-array allocation and immediate-root
trials have not returned.

Final matched BPC1 acceptance and serial reviews remain open. The preceding
baseline exposed scalar and installation1/8/64 gaps; no failure has been waived.
Agent's existing document records its qualified ReAct gains and remaining limits.

Maintained probes and regression tests remain under `test/` and
`docs/performance/cold-guard.mjs`. Generated samples, profiles and patches are not
maintained or packaged. Historical defect references refer to their recorded Git
revisions. The Agent adequacy obstruction and minimal reproducer remain intact.

Linked drafts: [Boundary #152](https://github.com/tkersey/boundary/pull/152),
[World #54](https://github.com/tkersey/world/pull/54),
[Agent #32](https://github.com/tkersey/agent/pull/32).
No merge, promotion or release is authorized. Current-tree deletion does not purge
historical Git objects.
