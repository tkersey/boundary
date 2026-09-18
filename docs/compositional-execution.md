# Compositional execution: Boundary status

Boundary `3.0.0-dev.0` implements the authoring, checking, linking and pure-data
portion of the accepted Boundary 3 / World 6 / Agent successor. The milestone is
incomplete: primary-workload performance gaps, remaining measurements and consumer
retirement, serial reviews and the final requirement audit remain open.

Delivery is limited to linked drafts: [Boundary #152](https://github.com/tkersey/boundary/pull/152),
[World #54](https://github.com/tkersey/world/pull/54), and
[Agent #32](https://github.com/tkersey/agent/pull/32). No merge, promotion or release
is authorized. The fixed comparison anchors are Boundary `42a09b9`, World `d075169`
and Agent `1f3297b`; each measurement retains its actual immutable subjects.

## One current compilation path

`boundary.program.compile`, `compileObserved` and staged `program.lower` use the
stable-activation compiler. The returned construction owns its Program and flow
facts independently of the source builder. Encoding revalidates the current
records; possession of a construction or caller-supplied facts does not confer
trusted execution. Diagnostics and phase observers remain caller-owned.

Source bindings have function-local stable slots. Real inputs, changed edge
assignments and lexical captures remain explicit; unchanged live values are not
re-enumerated into block interfaces. The persistent lexical scope avoids copying
binding history. Source expression sharing preserves effect and ownership rules.
A Module receiver reads its builder by reference, including declarations created
while evaluating its arguments.

Structure, instruction types/effects, borrow contracts and ownership remain
separate checks. Forward flow derives initialization, availability and nondroppable
obligations; backward flow derives liveness at every instruction and terminator.
Worklists reach a fixed point. Position facts are recorded during those visits;
final reads, consumption, overwrite checks and successor validation retain their
checking order. A successor change refreshes internal liveness even when the entry
root does not change.

Conditional cleanup obligations survive joins independently of permission to read
a value. Edges read sources simultaneously, reject duplicate unique transfers and
preserve nondroppable custody. Syntactically present unreachable continuations have
no initialized entry state. Function-local custody trees encode scope transitions;
physical reclamation is distinct from authored disposal.

Borrow analysis uses stable slots at exact instruction positions. A later rebinding
cannot hide an earlier invalid store. Function summaries use input ordinals, which
need not equal slot numbers. Generative context, return-clause reference bounds,
resource authority and capture/use obligations remain checked.

## Selective lowering and closed catalogue pruning

An immediately applied known lambda with copyable lexical captures lowers to an
ordinary call. Captures precede explicit arguments in the callee's input layout.
Argument evaluation order remains source order. Noncopyable captures and retained
callable values keep their closure/custody boundary. Original target admission
checks the declared callable contract before specialization.

Eligible deep linear total-tail clauses use a distinct `tail` strategy. Independent
target admission requires copyable inputs, total instructions, ordinary returns
and an acyclic CFG; suspension, calls, authored failures, loops, shallow handling
and incompatible effects reject. General source functions remain available when
referenced by ordinary code. World uses its existing evaluator and keeps the
selected delimiter active for checkpointing and cleanup.

After complete source/target checks, closed compilation and linking retain the
entry/result/failure typed reference closure. Discovery and rewriting use the same
relocator field inventory, including resource introducer/eliminator authority.
Retained declarations preserve relative order and nominal distinction. Final target
admission checks the remapped result. Unused invalid source still rejects, and
compiler diagnostics translate retained function IDs back to their source origin.
Unlinked BMO1 components retain their interfaces and declarations.

World's general-handler and deliberate malformed-State fixtures now construct
records through component compilation before closed admission. They no longer
assume closed output retains arbitrary source catalogue IDs. Original expected
outcomes, capture counts, cleanup and error assertions remain. Agent's static-code
cost witness separately checks nominal source separation and final byte equality
when immediate-call lowering removes the unused runtime declaration.

## Components and portable data

[BMO1](bmo1-components.md) contains independently checked, defunctionalized,
relocatable first-order objects. The data-only linker needs no authoring source or
emitter. Interfaces bind actual implementations while preserving private nominal
instances; shared primitive schema structure does not merge private authority.
Imports carry explicit borrow assumptions and exports carry code-derived guarantees
for provenance, cell writes and outlives requirements. Linking checks those against
the relocated implementations, including functions reached through handler and
constructor imports, before admitting the closed Program. The format document
states the whole-result precision limit.

[BPI3](bpi3-wire.md) directly encodes stable records, owns admitted input, enforces
physical expansion limits and hashes canonical bytes in `boundary.program/v3`.
Re-emission validates compressed/default spellings without constructing predecessor
interfaces. Opaque admitted owners retain immutable Program, schema, effect and
flow facts. World may share that owner across Sessions; mutable analysis operations
use one private overlay over its read-only base, never a chain of prior versions.

[PST3](pst3-wire.md) carries graph aliases/cycles, stable activation views and
lexical owner order. Canonical projection removes unreachable State and restoration
checks bindings, exact positions, effects, borrows, ownership and cleanup against
the matching Program. Private analysis indexes and World allocation layouts are
not portable State or authority.

[Invocation envelopes](invocation-wire.md) are PKI3/PKO3 and ERQ3/ERS3. Each decoder
owns an exact-sized copy, and decoded slices borrow only from that owner. Request
identity binds the actual pending execution and typed interface. Caller overwrite,
malformed framing, capacity failure and stale-response cases retain explicit tests.

The production predecessor compiler, old executable records, raw graph State,
BPI1/BPI2/BPC1/PST2 and old invocation codecs, migration helpers, versioned public
aliases and legacy-only proof wrappers are retired. Current framing rejects old
families. Published releases and Git history remain intact. Existing saved
executions require their original pinned pair; no automatic migration is claimed.

## Analysis storage

Canonical sets use interval nodes, aligned 64-member bitmap leaves and shared
binary subtrees. Constructors normalize equivalent sets; the interner stores root
IDs and derives equality/hash information from the node owner. Hash equality still
checks the complete logical node. All fallible reservation precedes publication.
Pool buffers use the parent allocator so replaced growth buffers can be released;
Facts owns both those buffers and its stable-address arena.

Private root indexes now use checked `u32`; member IDs remain `u64`. A base plus
its overlay can contain at most 4,294,967,295 interned nodes. Existing roots remain
reusable at capacity; new-root exhaustion returns `OutOfMemory` before publication.
This limit exceeds the qualified runtime budgets and does not restrict the values
represented by a compressed interval or bitmap. Native nodes shrink from 40 to
32 bytes; hash keys and position facts also shrink. wasm32 index/node widths are
unchanged. The public low-word projection still describes only members 0 through 63.

The [root-width comparison](measurements/analysis-root-width.json) records paired
native control/value samples and Agent preparation measurements. Control64 medians
fall from 374/376 to 359/361 microseconds and peak allocation from 282,999 to 241,495
bytes; optimized BPC1 still takes roughly 238–244 microseconds and 121,956 bytes.
Control128 peak falls to 415,111 bytes and control256 to 788,285 bytes. Every measured
value peak falls, while some small value timing increases remain disclosed.

Native paired inquiry Session peak falls from 3,107,532 to 2,847,222 bytes; ReAct
falls from 5,201,096 to 4,239,618. Both still exceed the BPC1 baselines. Preparation
alone falls from 2,327,004 to 2,063,574 for inquiry and 5,201,096 to 3,977,974 for ReAct;
these preparation figures exclude subsequent Session/State work. Native index-width
results do not establish wasm32 memory or guest latency gains.

The [wider-leaf experiment](measurements/analysis-leaf-widths.json) retains rejected
128/256-bit variants, exact patches, successful set-law tests and adverse samples.
Fewer nodes did not guarantee lower allocated capacity: the uniform 256-bit variant
raised several guarded peaks and value timings. `NEG-000010` excludes that exact
unchanged route on its bound workloads, not other bitmap representations.

## Verification and measurement scope

The current root-width source passes:

```sh
zig build check -Doptimize=ReleaseSafe -j4 \
  --global-cache-dir .zig-global-cache --summary all
```

The result is 216/216 steps and 221/221 Zig tests, with the source oracle,
source-independent BMO1 linking, independent native/wasm32 codec/identity witnesses,
malformed records, nominal separation, borrow/resource authority, ownership,
allocation failure, overlays and full-width member tests. World passes its 32-step
aggregate against the immutable candidate, including 74 source tests,39 storage
tests,30 host tests,6,755 independent oracle observations, Node/Wasmtime,
Chromium/Firefox Worker transfer and extracted-package checks. All 13 paired Agent
comparison scenarios preserve their original semantics and work counts with the
new native build. Final normal-pin qualification and guest timing for this update
remain separate pending gates.

The unchanged installation family retains its delayed checked sum and actual
handlers. Native/wasm32 image checks cover installation, mixed and irregular
Programs, with current image budgets checked against the optimized compact
predecessor. Source conformance covers deep/shallow, one-shot/multi-shot, injection,
retained/reentrant computation, nominal capabilities, generative regions, borrowed
resources, abandonment, yielded/suspending cleanup and cancellation. None of these
static checks substitutes for World's executed and portable-state witnesses.

Earlier measurements remain useful with their original limits:

- [Source facts](measurements/source-facts.json): isolated source-checker timings,
  logical-set agreement and arena capacity; not full compiler/runtime latency.
- [Shared fixture emitter](measurements/shared-emitter.json): all 82 fixture outputs
  remained byte-identical; one cold pair fell 250.4→19.6 seconds and warm medians
  fell 2.863→0.277 seconds. The cold observation is one pair, not a distribution.
- World retains control, value, admission-buffer, solver and continuation-transfer
  measurements; Agent retains actual inquiry/ReAct, repeated-task and producer/
  build/edit/link measurements. Their results do not silently extend to later code.

The source fixture build uses one reusable emitter. The formal project remains
independently runnable through `check-formal`; it is not a production dependency.
Earlier prose milestones remain in Git history rather than a second maintained
status timeline. Completion still requires the full accepted performance matrix,
resolution of primary-workload regressions, the final coordinated dependency and
package checks, remaining retirement, serial reviews and a requirement-by-requirement
audit.
