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
World's native stable controller now executes these contracts.

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

The shared borrow/context solver now reads stable slots at explicit instruction
positions. A later rebinding cannot change the provenance of an earlier store.
Incoming control edges transport only changed assignments; unchanged bindings keep
their identity. Function-input ordinals are distinct from slot numbers, including
non-prefix and permuted inputs. Reachability uses a worklist over actual edges.
No predecessor block interfaces are materialized for this analysis.

Function summaries retain input ordinals, while explicit position queries now
describe actual stable slots at a checkpoint. Completed writes are excluded;
reachable loop reentry still contributes future requirements. The compiler and
native State checker enforce declared borrow/resource contracts. BPI3 now
performs full stable image admission. Stable clauses use their own strategy record and independent CFG admission;
the predecessor direct-clause flag never enters the successor path.

## Immediate callable selection

An immediately applied source lambda with copyable lexical captures now lowers
to the existing stable `call` terminator. Captures precede the explicit arguments
in the callee's normal input layout. No `computation` instruction or runtime
closure is created. Callable constructor metadata remains for independent target
admission of the original signature, effects, regions, use and capture bound;
specialization cannot erase a falsely declared capture contract.

Argument evaluation remains in source order before the call. Noncopyable captures
retain closure construction because moving an owner into the closure before
evaluating later arguments is a custody boundary. Retained callable values also
keep the general `apply` representation. Tests cover the direct scalar capture,
invalid capture annotations, and an immediately applied lambda capturing a linear
resumption. This is a bounded selection rule, not general escape analysis.

World's `immediate lexical calls` test runs both direct and retained forms of the
same checked addition, including overflow and yield/checkpoint/restore. With
Zig 0.16.0 native ReleaseSafe on an Apple M2 Pro, the unchanged compiler at
`adf3c7e102fead43f32f1c850fa7d27ac417fdb6` added five graph nodes during either
execution. This lowering adds one for the immediate form and five for the
retained form. Both return 42 for input 40. These are deterministic Store node
counts after Session initialization, not allocator counts or latency measurements.
The branching tail-resumptive witness is described below.

## Total branching clauses

Stable Handler/Clause records now belong to `activation`, with a distinct
`tail` strategy (wire tag 2). The compiler retains the general source function
for ordinary calls and creates a specialized function with no token input.
Both conditional branches return the operation result; the actual handler return
clause and the suspended body's checked arithmetic remain in their original
positions. Region, effect and callable contracts continue through final admission.

`data/total_clause.zig` independently checks the selected function: copyable slots,
total instructions, ordinary returns, and an acyclic branch/jump/sum/product CFG.
It rejects suspension, calls, resumption operations, authored failures and loops.
The existing contract checker also requires deep linear handling, no operation
bodies, the exact state/payload inputs and operation result, and no residual
clause effects. Effects belonging to the resumed body stay on the original
resumption interface; they are not effects of this total function.

World executes the selected function through its existing evaluator with an
ordinary saved continuation. The delimiter remains active, so checkpointing and
cancellation retain body cleanup without a first-class resumption. The branching
fixture returns 60 or 100 after body/return arithmetic. Its general form creates
one one-shot token and 14 graph nodes; the selected form creates zero tokens and
11 graph nodes (native ReleaseSafe, Zig 0.16.0, same inputs, excluding Session
initialization). These are work counts, not a latency or peak-memory claim.

Checks cover every instruction checkpoint, cancellation at multiple clause
positions with one external cleanup, BMO1 encode/link/relocation, rejection of
cycles and yielding/shallow forgeries, and the independently specified wire tag.
Non-tail, shallow, escaping-generator and reentrant examples retain general
clauses. Node/native and independent Wasmtime run the branching fixture through
fresh/resident checkpoints; broader workload performance acceptance remains open.

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

Construction and structure checks cover 37 existing generalized-effect examples,
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

Opaque admitted BPI3 owners now retain immutable Program facts for World
preparation. Each execution or State admission gets a private set overlay over
one read-only base; lookups never follow a chain of earlier versions. Exhaustive
eight-bit set operations, allocation failures and sibling-overlay tests preserve
the base. Schema/use/effect views are read-only. This removes repeated Program
admission from prepared starts/restores, without adding a caller-supplied proof flag.
The earlier checker timings above remain bound to their recorded source revisions;
they are not measurements of these later representation changes.

The [current invocation envelopes](invocation-wire.md) define PKI3/PKO3 and
ERQ3/ERS3 with owned decoding and State-bound typed replies. Fresh native invocation
uses the stable evaluator and agrees with resident/restored execution at matching
quanta. Independent wasm32 fixtures cover envelope bytes and request identity.
World's generic ABI 3 and browser-neutral embedding now exercise these envelopes;
the ordinary public cutover remains pending.

The Builder's Module receiver now reads by reference: adding a declaration while
evaluating a module argument no longer captures a stale catalog. The former
`builder.module(main, try builder.scalar(void))` failure is covered by an authoring
regression and the explicit-yield invocation case.

The [PST3 graph codec](pst3-wire.md) now owns canonical stable activation views
and lexical owner order with each control node. It preserves graph aliases and
cycles, removes unreachable state, and validates canonical numbering without a
second decoded graph copy. World exports these records at its native safepoints.
Program-relative State admission now checks actual stable slots, instruction
positions, dynamic effects, borrow provenance, ownership and cleanup against the
matching Program. Native executable restoration passes the source corpus at
matched quanta. World also exercises the current envelopes across native, Node,
Wasmtime and real browser Workers.

The [BPI3 codec](bpi3-wire.md) now writes stable records directly, admits owned
input, enforces a physical expansion budget and hashes the canonical bytes in
the new `boundary.program/v3` domain. Goldens and allocation-failure sweeps pass;
all 37 staged semantic examples round-trip with exact record/identity equality.
The source construction exposes this encoder, and World's stable source suite
now loads it and destroys the input bytes before execution. The default public
compiler still awaits the coordinated cutover.

`zig build check-program-image-wasm -Doptimize=ReleaseSafe` compares native and
import-free, unshared wasm32 decoding/re-encoding and identity for 12 installation,
mixed and irregular images. All agree. On the unchanged installation inputs,
complete BPI3 sizes for 64/128/256 are **2,640 / 5,462 / 11,350 bytes**, versus
freshly emitted BPC1 **2,805 / 5,574 / 12,102 bytes**. This is a byte-count result,
not execution, preparation-memory or compiler-time acceptance. The probe emits
every size and image identity; it includes the actual native emitter and WASM
codec, with no predecessor expansion in the successor codec.

World now executes the native stable-control slice through `source.construct`,
including deep multi-shot/reentrant cases and retained loop-slot versions. The
analysis owner now keeps its arena at a stable address so runtime-derived set
operations cannot allocate through an escaped stack pointer. World now
also executes borrowed/resource cases using the stable borrow/context admission.
The current source conformance includes 24 older/fresh return-clause cases,
pre-instruction rebind counterexamples, loop/permutation summaries, clause payload
rejections, and protected-loan escape rejection. Runtime witnesses include
non-tail handling, external requests, joins, escaping one-shot control, retained
loop versions and reentrant multi-shot behavior. Static admission is not a
substitute for those executed witnesses.

The [BMO1 component path](bmo1-components.md) now compiles independent effectful
objects and links from first-order artifacts using a data-only executable. Tests
cover nominal sharing/separation, interface mismatches, capture bounds, forged
resource authority, allocation failures and mutually recursive implementations.
World executes the linked private-state/owned-suspension composition in two
Programs and transfers their checkpoints through Wasmtime. Local imported-borrow
contract checking still needs completion; queries that do not reach an import
now run locally, including independent definitions in an object with unresolved
calls. Full closed-link admission is mandatory.

Public protocol cutover, completion of component contracts, selective execution,
efficient values, transaction performance qualification, Agent's
complete migration and compiled-tool transfer, performance comparisons, retirement,
package validation and publication/review closeout remain mandatory. The current
public compiler/runtime still use the predecessor. The internal construction is
not a second supported production pipeline or a completed successor.
