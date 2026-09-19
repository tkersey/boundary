# Boundary 3 successor status

Boundary 3.0.0-dev.0 provides stable-slot authoring, checked BMO1 component linking,
and current BPI3/PST3/invocation data contracts. World interprets these records;
Agent is the required consumer. The successor remains incomplete and its PRs
remain drafts. Implementation has resumed after the authorized archive cleanup.

Current contracts: [components](bmo1-components.md), [Program images](bpi3-wire.md),
[State](pst3-wire.md), and [invocations](invocation-wire.md).

## Current results and unresolved work

Within a block, projections from a just-constructed copyable, droppable product
reuse its already-computed field slot. Every operand and the product itself still
execute in order. Fresh instruction destinations cannot be overwritten inside
that block; no cross-block cache or consumed owner is forwarded. Malformed
projection types, indices, arities and fault mappings remain for target admission
to reject. An independent source/native/WASM fixture checks mutable reads across
a write (result 8) and an overflowing unselected field (failure 77).

Compared with Boundary 2cf8d55 / World 6f29529 / Agent e64697b, ReAct loses
2,192 instructions and temporary slots. Two rotating native replay windows over
128 captured invocations from 13 unchanged Agent scenarios show about 29% lower
ReAct time. Complete reset-ReAct invocation peaks fall 2,863,966 → 1,993,377
bytes; inquiry timing is essentially unchanged. All protected observations match.
The measurement is a sum of per-input medians (three warmups, nine samples),
including byte admission/execution/output, not whole-scenario elapsed time.
Two corresponding Node 26.9.0 guest windows improve ReAct about 26%, including
fresh Kernel creation, invocation and outcome decoding. The kernel remains
byte-identical. File loading and JavaScript module import are outside the timer.

The compiler threads empty jumps only when they carry no assignments and stay
within one function and custody scope. Cycles remain executable; values, real
handlers and effectful boundaries are preserved. The existing reachability pass
removes the resulting unreachable blocks. Installation lowering now has n + 1
blocks, 3n + 1 instructions and n real handlers, with the checked sum still after
all installations. Components retain checked linking and function identities.

The full Boundary check passes 220 build steps and 232 tests, including the
42-fixture independent source oracle, native/wasm32 byte agreement, source-free
component linking, custody/assignment/cycle fences and a 10,000-block path.

Compared with Boundary 3dc3413 using World e995dc9, four alternating native
ReleaseSafe windows (three warmups and nine samples per process) show roughly
6–7% lower complete fresh-invocation time for 64/128/256 installations. Image
bytes fall 2,629/5,451/11,339 → 2,303/4,683/9,803; working peaks fall
193,195/303,637/575,249 → 190,649/296,055/462,039 bytes. Shallow handling improves
about 12%; retained-loop timing is essentially unchanged. Queens DFS/BFS improve
about 11%/4%, but BFS peak working memory rises 230,376 → 244,736 bytes. These are
per-process medians on an M2 Pro, Zig 0.16.0, macOS 27.2, not a service p99 claim.

Current Agent inquiry/repeated/ReAct images are 36,756/37,137/48,226 bytes,
down from 36,861/37,242/63,151 before projection forwarding. This does not close the ReAct image gap against
BPC1 (43,394 bytes). Final matched predecessor timing/memory acceptance,
small-control regressions, coordinated qualification and serial reviews
remain open. No performance failure has been waived.

Runtime preparation retains the exact top-level block-catalog allocation and
native compact analysis nodes. Large catalogs are owned separately from nested
arena records; malformed input and allocation failure release both. Native pools
use 16-byte nodes within the 32-bit member bound, with full-width fallback.
wasm32 retains its untagged layout: the tagged trial regressed inquiry/ReAct
latency by about 3%/7%. The all-large-array exact-allocation trial and immediate
small-set roots remain rejected after repeated large-control slowdowns.

Small standalone compiler probes and substantive regression tests remain under
`test/` and `docs/performance/cold-guard.mjs`. Generated samples, profiles and
experimental patches are not maintained or packaged. Existing defect records keep
their historical provenance; old artifact paths refer to their recorded Git
revisions. The Agent adequacy obstruction and minimal reproducer remain intact.

Linked drafts: [Boundary #152](https://github.com/tkersey/boundary/pull/152),
[World #54](https://github.com/tkersey/world/pull/54),
[Agent #32](https://github.com/tkersey/agent/pull/32).
No merge, promotion or release is authorized. Current-tree deletion does not purge
historical Git objects.
