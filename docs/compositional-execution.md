# Boundary 3 successor status

Boundary 3.0.0-dev.0 provides stable-slot authoring, checked BMO1 component linking,
and current BPI3/PST3/invocation contracts. World interprets these records; Agent
is the required consumer. All PRs remain drafts; current review/readiness is recorded in the linked PRs.

Current contracts: [components](bmo1-components.md), [Program images](bpi3-wire.md),
[State](pst3-wire.md), and [invocations](invocation-wire.md).

## Current construction and checks

Unsupported forwarding constructors and handler fields are retired. Older-capability
dispatch remains the supported forwarding mechanism. Wire tag 14 rejects; the
retired handler position remains a required zero byte. Accepted BPI3/BMO1 bytes
retain their meaning, with independent golden coverage and byte-identical output
for all 42 current examples.

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

The full check passes 220 steps and 234 tests, including 42 independent source
fixtures, native/wasm32 byte agreement and source-free component linking. World
also passes 84 native source tests and all 42 source/native/WASM comparisons.

A reusable lambda with no lexical captures is constructed after its handler
arguments and state, next to the handler instruction. This moves only a pure
closed construction; argument/state effects, faults and cleanup retain their
order. The existing IR still independently admits the complete callable contract.
World may omit its allocation on qualified native execution when it has no other
use or retained edge source. Explicit stepping and work quanta retain their
original logical boundaries.

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

A catalog-reuse trial preserved all 128 fixed Agent invocation outputs but gave
only mixed sub-percent timing changes and unchanged consumer peaks. Directly
placing the derived arrays in retained storage raised shallow-handler peak memory
from 149,898 to 197,300 bytes; copying them avoided that regression but did not
justify the added retention APIs. Both variants are removed; admission still
derives and validates its facts through the existing qualified path.

The selected production tuple is Boundary 1b00c8c / World a20a285, consumed by
Agent 9cad6d0. World's later bb7a08c commit changes only its result document.
The [cumulative native results](https://github.com/tkersey/world/blob/feat/compositional-execution/docs/compositional-execution.md)
cover all 45 fixed cases; installation64 latency is now lower than BPC1. The
September 19 task amendment accepts the ten explicitly named small-workload native
latency tradeoffs as milestone costs, without waiving memory, guest, Agent,
structural or semantic requirements. Those costs are not reported as improvements.

Selected-tuple standalone guest, inquiry/ReAct/repeated and clarification
confirmations now pass. The user explicitly accepted the named memory, checkpoint
and ReAct-image costs on September 19. The requirement audit also led to Agent's
read-only Program/State inspector extension. Serial-review status is recorded in the linked PRs. Do not
restart architecture or optimize accepted cells merely to seek uniform dominance.
The established source-free component, compact installation-image and semantic
checks remain valid for this documentation-only update. Agent's result document
separately reports consumer gains and limits. The historical adequacy obstruction
belongs to its locked release tuple, not an established successor defect.

Maintained probes and regression tests remain under `test/` and
`docs/performance/cold-guard.mjs`. Generated samples, profiles and patches are not
maintained or packaged. Historical defect references refer to their recorded Git
revisions. The Agent adequacy obstruction and minimal reproducer remain intact.

Linked drafts: [Boundary #152](https://github.com/tkersey/boundary/pull/152),
[World #54](https://github.com/tkersey/world/pull/54),
[Agent #32](https://github.com/tkersey/agent/pull/32).
No merge, promotion or release is authorized. Current-tree deletion does not purge
historical Git objects.
