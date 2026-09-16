# Compositional execution: implementation status

This is an incomplete Boundary 3 / World 6 implementation milestone. The accepted
September 16, 2026 specification remains the completion contract, including Agent
migration, measured performance, legacy retirement, linked draft PRs and serial
review closeout. Nothing has been merged or released.

The dedicated `feat/compositional-execution` worktrees start at Boundary
`42a09b92c2870ab3eab923fe68ca2645eb710000`, World
`d075169a4805d999ceba4c37b3e1c925b78c3bf9`, and Agent
`1f3297b8cd7eeb7638bd1bb2a81c9ba609e2e311`. Remote heads were fetched and matched
these inputs. Toolchains are Zig 0.16.0 and Node 26.8.2.

## Stable activation construction

`data/activation.zig` represents function-local slots, ordered call inputs,
instruction destinations, and changed-only continuation assignments. It has no
block parameter catalogs or pass-through argument vectors. Destinations obtain
their types from the function layout. Branch assignments have simultaneous
predecessor-view semantics; admission now checks source consumption before any
writes. Each function also has an acyclic lexical custody tree; each block names
its active scope. Normal scope exits transfer surviving owners into their parent
before an edge establishes new bindings. This is separate from nominal regions.
Runtime execution of these contracts remains pending.

`source/activation_lower.zig` lowers staged terms directly into those records.
It does not call the predecessor compiler or translate an old Program. Real
function arguments and lexical closure captures remain explicit. A persistent
indexed lexical scope avoids copying live environments or searching binding
history. Its search path is bounded by the number of source variable names.
Safe expression sharing reuses the existing source rules; operations with
observable effects and noncopyable results do not acquire new sharing rights.
The returned construction owns copied result records; source AST and analysis
scratch are released before return. The construction also owns its derived flow
facts. Allocation failures destroy partial results.

The representation decision retains Boundary's static contract and World's
dynamic activation ownership. Wire compression alone does not eliminate the
incumbent's repeated interfaces. A mutable whole-function frame would not satisfy
retained-version isolation or dead-value reclamation; the static layout does not
authorize retaining all its slots. The runtime must implement delimited views.

`data/activation_structure.zig` checks slot references, unique destinations,
function-local edges and result-site types. It deliberately grants no trusted
executable status. `data/activation_flow.zig` separately derives initialization,
availability after moves, and liveness at every instruction/terminator position.
Its worklists converge before reachable reads and ownership transfers are checked.
Definite initialization/availability meet at joins, while possible nondroppable
custody joins by union. A conditional cleanup obligation therefore survives even
when the slot cannot be read on every path. Simultaneous edges reject duplicate
unique sources, unique returned results and omitted nondroppable returned values;
existing nondroppable owners cannot be overwritten. Unreachable continuations have
no entry state and cannot be mistaken for initialized code.

Backward liveness retains nondroppable custody even after its last ordinary read.
Ordinary dead slots stop belonging to the live map. This is static root analysis,
not evidence that the runtime has reclaimed memory.

`data/activation_types.zig` now applies the existing instruction, signature, effect,
resource-authority and region-dependency rules directly to stable records. Function
call interfaces are views of ordered input destinations and their layout types;
no old block interfaces or schema vectors are reconstructed. Existing semantic
rules are shared with the predecessor during migration.

`data/activation_ownership.zig` derives its own facts from the same input and checks
continuation capture bounds, multi-shot clone safety and ordinary-return custody.
It does not accept caller-provided analysis claims. Normal return with a remaining
nondroppable owner rejects; failure retains that owner for authored unwinding.
The twelve existing custody-edge scenarios now retain this normal/failure distinction
under stable lowering. A successor handler's answer remains distinct from the
captured resumption's answer.

These layers still do not confer executable status. Dynamic borrow/context
provenance, canonical image/State admission and actual runtime custody transitions
remain required. Stable direct-clause flags reject until their own CFG proof and
selective execution implementation exist; they do not enter the predecessor path.

## Evidence and limits

Run from this worktree with an isolated global cache:

```sh
zig build check-stable-lowering check-v2-data check-v2-authoring \
  --global-cache-dir .zig-global-cache --summary all
zig build check-stable-lowering check-v2-data check-v2-authoring \
  -Doptimize=ReleaseSafe --global-cache-dir .zig-global-cache --summary all
```

The installation test uses the unchanged public construction at 1/8/64/128/256.
For `n` installations its entry function has `4n+1` slots, `3n+1` instructions,
`2n+1` blocks and exactly `n` returned-value assignments. All checked additions
remain in the final result block, after all handlers. There is no unchanged-value
edge assignment. These are target construction counts, not full compiler or
runtime performance results.

The source checker now shares canonical interval/tree sets rather than copying
flat value/term free-variable vectors. Only actual function captures are enumerated.
Contiguous prefixes add at most two set nodes per insertion, and queries descend
by a strictly decreasing bit rather than replaying previous versions. Exhaustive
comparisons cover every union, intersection and single-member removal on eight-bit
sets, with separate full-width and allocation-failure witnesses. The installation
checker has `2n+4` nodes and `18n+58` set-operation visits in the measured matrix;
regression tests enforce linear bounds through 1,024 installations. Recursive
closures still use a monotone least fixed point and preserve lexical binding.

The predecessor lowering temporarily enumerates term sets to build its old block
interfaces. The stable compiler never calls that adapter. This adapter leaves with
the predecessor backend; it is not an accepted successor path.

Construction and structure checks cover 36 existing generalized-effect examples,
heterogeneous join destinations, shadowed names, expression DAG sharing, malformed
slot/edge references, permutations, repeated copyable inputs, answer transformation,
source-owner release and allocation-failure sweeps. New adversarial cases reject
forged operation types, missing arithmetic failure contracts, hidden effects,
weakened callable capture bounds, unauthorized resource elimination and corrupted
custody trees. The nested-scope witness records exit into the parent before a
sibling binding scope begins. Flow tests additionally cover
partially initialized joins, use after move, loop fixed points, dead ordinary data,
retained cleanup custody and unreachable continuations. The existing data/authoring
expectations remain enabled. These checks do not establish behavior under World.

## Source-checker measurements

`zig build profile-source-facts --global-cache-dir .zig-global-cache` runs the
checker probe. The baseline executable was built before the checker change from
`0db0224`, using the same staged installation inputs. The probe can also be built
in that immutable checkout. It includes three warmups and nine measured checks per
process. The reported values are medians of six process medians, from two windows
of three rotating baseline/candidate pairs on the same M2 Pro, Zig 0.16.0 native
build (source/probe module ReleaseSafe; pure data dependency Debug in both).
Authoring, native compilation and diagnostic enumeration
of logical memberships occur outside the timed interval.

| Installations | Baseline checker | Current checker | Baseline arena | Current arena |
|---:|---:|---:|---:|---:|
| 1 | 1.625 us | 1.063 us | 5,342 B | 6,478 B |
| 8 | 5.000 us | 2.729 us | 17,330 B | 13,778 B |
| 64 | 104.126 us | 17.250 us | 146,126 B | 92,626 B |
| 128 | 516.125 us | 35.063 us | 454,626 B | 183,698 B |
| 256 | 3,383.230 us | 74.188 us | 1,436,818 B | 651,896 B |

At 256, candidate process medians ranged from 73.375 to 80.750 us. Every observed
set-content digest and logical membership count matched the baseline. Arena values
are backing capacity, not peak RSS; the tiny input has an explicit memory cost.
Raw samples, measured source hashes and configuration are in
[the measurement file](measurements/source-facts.json). This is an isolated checker
improvement, not completion of the cold-build, full compiler, runtime, Agent,
compact-image-size or end-to-end performance requirements.

## Remaining work

World now executes the native stable-control slice through `source.construct`,
including deep multi-shot/reentrant cases and retained loop-slot versions. The
analysis owner now keeps its arena at a stable address so runtime-derived set
operations cannot allocate through an escaped stack pointer. The next seam is
remaining borrow/context provenance, cleanup and shallow-control support, and
portable codec integration. The M1
runtime slice must include non-tail handling, an external request, a join, escaping
one-shot control, retained loop versions and reentrant multi-shot behavior before
the main migration is accepted. Static admission is not a substitute for that slice.

BPI3/PST3/current protocols, independently checked BMO1 linking, selective execution,
efficient values, prepared/resident transactions, browser byte embedding, Agent's
complete migration and compiled-tool transfer, performance comparisons, retirement,
package validation and publication/review closeout remain mandatory. The current
public compiler/runtime still use the predecessor. The internal construction is
not a second supported production pipeline or a completed successor.
