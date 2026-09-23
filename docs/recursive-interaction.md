# Defunctionalized hyperfunctions and recursive interaction

Implementation of the complete user specification v1.1 (September 19, 2026).
The milestone remains incomplete. Boundary draft:
https://github.com/tkersey/boundary/pull/153. Agent companion:
https://github.com/tkersey/agent/pull/33.

## Pure meaning and public operations

The pure core uses explicit call-by-name delays, including endpoint values.
The rest of Boundary remains strict. Native Zig builders construct source; no
native closure is serialized or called by World. Runtime recursion may remain
nonproductive, and work-quantum exhaustion is never an authored result.

In lazy semantic notation:

```
invoke(make(body), peer) = body(peer)
invoke(base(value), peer) = value
invoke(push(f, tail), peer) = f(invoke(peer, tail))
invoke(compose(left, right), peer) = invoke(left, compose(right, peer))
lift(f) = push(f, lift(f))
identity = lift(id)
run(h) = invoke(h, identity)
project(h, x) = invoke(h, base(x))
invoke(ana(step, s), peer) = step(s, next -> invoke(peer, ana(step, next)))
```

`library.hyper` supplies:

| Operation | Staged meaning |
| --- | --- |
| `pair`, `pairWith` | Checked reciprocal interfaces with explicit capture bounds |
| `group`, `Group.get` | Compatible interfaces for a finite monomorphic endpoint cohort |
| `deferValue`, `delayed`, `force` | Construct a typed delay and demand one result layer |
| `make`, `invoke` | General checked body and suspended invocation |
| `base`, `push`, `lift`, `identity` | The non-strict constructors above |
| `compose` | H(B,C) × H(A,B) → H(A,C), retaining reciprocal return paths |
| `run`, `project` | Observe through identity or a constant counterpart |
| `ana`, `start`, `Query.ask` | Runtime-state construction with arbitrary staged queries |
| `demand.family/request/interpret/handle` | Lexical internal Need effects interpreted as counterpart tasks |
| `lazyProduct`, `lazySum` | Observe fields/tags without forcing unused delayed payloads |
| `stream`, `cons`, `emptyStream` | Delayed elements and successor spines |

IDs refer to checked source values/functions/schemas. Operations that execute a
source call return a source term yielding the delayed value or participant;
`make`, `base`, and value constructors return source values. Bind terms using the
normal Builder before referring to their values. `push` and `lift` take a source
function `Delayed<A> -> Delayed<B>`; a strict function must explicitly force its
argument in its authored body. The library does not silently perform that force.
`run`/identity require equal endpoint types; `project` permits distinct endpoints.
Composition with lifted maps supplies checked endpoint adaptation.

`ana` gives `Step.emit` source values for state and a query builder. Each authored
call emits the current step configuration; the Zig step type is not a cache key.
Keep the returned `Ana` and call `start` to reuse that definition. Runtime queries
reuse its maker without emitting code. The step may emit zero, one, or several
adaptive runtime queries and non-tail work. It is not a
fixed stream schedule. Only finitely authored code is generated; successor states
and repeated interactions are runtime values.

The `ana_config` and `ana_capture` regressions construct two definitions using
the same step type, selecting constants and captured bindings respectively. The
former reproduced the old type-only cache returning 38 instead of 42. Both now
return 42 through fresh World transfers (33 and 31 transfers). The unit regression
also starts each retained definition 100 times without adding function bodies.

## Composition and capture contracts

The compiler's existing computation contracts admit captures by schema. A
composition retains H(B,C), H(A,B), and its reciprocal H(C,A), and the nested call
rotates those endpoints. Independently declared narrow pair capture bounds need
not permit that rotation. `group` declares the shared finite type cohort before
participants are authored or independently compiled. It enumerates endpoint type
pairs, never endpoint values, runtime states, or exchange histories. A component
must share a compatible contract; unrelated contracts are not silently coerced.

Each pair has ordinary callable and delay schemas. Composition uses three
mutually referring maker functions, declared before their bodies are defined.
There is no recursive native expansion, new opcode, wire format or interpreter.
Actual environments contain only the captures used by their bodies. Existing
fixed-point trait analysis and constructor checking remain authoritative; reusable
recursive wrapping cannot hide an exclusive capture. Group construction checks
schema IDs, arithmetic, declaration counts and the total capture-reference budget
before reserving its graph. Oversized groups fail with Capacity.

Constructor equations give the local source-to-target correspondence: each delay
is a zero-argument source computation; invocation's thunk calls the selected body
and then forces its answer; push constructs an argument thunk without demanding
it; lift ties its tail through code references; composition's three functions
implement the same reciprocal rotation; ana's query thunk defers both counterpart
lookup and successor construction. Normal selective lowering turns these closures
into code IDs and checked environments. World retains actual non-tail callers and
serializes their reachable finite state without executing delayed code.

The intended pure identity, associativity and lifting laws are scoped to the
supported non-strict interface and corresponding observations. In particular,
`project(lift(f), x) = f(x)` and `run(lift(f)) = fix(f)` follow by unfolding the
constructor equations. Equal Program hashes do not establish extensional equality.
Current finite tests distinguish these constructions but are not a universal
proof about partial terms. No unrestricted fold/build rewrite or effectful
commutativity is claimed.

## Executed pure evidence

`test/hyperfunction_reference.mjs` is an independent test-only higher-order
closure oracle; it imports no production compiler or dispatcher. Eight tests cover
partial demand, checked failures, adaptive multiple queries, different endpoints,
reciprocal non-tail return order and concrete projection/composition observations.

Zig 0.16.0 native Debug emission and the unchanged World ReleaseSmall WASM kernel
(SHA-256 `7a27d64295431c960046439353a158e378f14d4686fac47b61b1406cf1753663`)
executed these current `examples/hyper_algebra.zig` Programs on Node/WASM:

| Case | Image bytes | Fresh transfers, quantum 1 | Observation |
| --- | ---: | ---: | --- |
| run(lift(constant 42)) | 660 | 16 | 42; unused infinite argument not demanded |
| Projection through lifted addition | 505 | 33 | 42 |
| Boolean/integer endpoints | 483 | 16 | 42 |
| Boolean → integer → record composition | 1,479 | 91 | Expected record fields |
| Lazy product | 132 | 6 | 42; divergent other field unused |
| Lazy sum | 134 | 7 | Tag observed; divergent payload unused |
| Stream prefix | 192 | 9 | First element; divergent suffix unused |
| Unused checked overflow | 507 | 16 | 42 |
| Demanded checked overflow | 527 | 33 | Authored failure, no cleanup failures |

The 666-byte identity Program exhausted eight quanta of eight operations, with
fresh transfer after each. It produced no semantic result. Separate operational
cancellation ended that observation. The earlier state-based reciprocal example
also remains: consumer → producer → consumer-successor, followed by both callers'
non-tail additions, yielding 42 through 60 fresh transfers (735-byte Program).
These are finite execution/size observations, not timing improvements or the
required fusion/scaling comparisons.

```
zig build check --summary all
zig build emit-hyper-algebra
node --test test/hyperfunction_reference.test.mjs
node test/hyperfunction_world.mjs WORLD_ENTRY KERNEL zig-out/hyper/ana_config.bpi3
node test/hyperfunction_world.mjs WORLD_ENTRY KERNEL zig-out/hyper/ana_capture.bpi3
node test/hyperfunction_world.mjs WORLD_ENTRY KERNEL zig-out/hyper/compose.bpi3
node test/hyperfunction_world.mjs WORLD_ENTRY KERNEL zig-out/hyper/fault.bpi3 failed
node test/hyperfunction_partial.mjs WORLD_ENTRY KERNEL zig-out/hyper/identity.bpi3
```

The current aggregate passes 247/247 steps and 238/238 Zig tests. All ten emitted
algebra cases were executed after final generation. `WORLD_ENTRY` is the baseline
World's `src/embedding/index.mjs`; `KERNEL` is its `zig-out/world-kernel.wasm`, built
with `zig build build-kernel -Doptimize=ReleaseSafe`. Formatting, diff and source
inventory checks pass. No existing rejection assertion was removed or weakened.

## Generated pure-construction agreement

The test-only `hyper_generated.zig` emitter constructs bounded depth-three terms
through the public library: base, constant lift, raw make, push, composition and
identity. Six observation/law variants across 16 fixed seeds give 96 separately
compiled Programs. The independent higher-order closure reference interprets the
same generated choices without importing Boundary lowering or World dispatch.
It compares run/project results, left/right identity and associativity with lifted
additions. Distinct endpoints, adaptive ana, partial demand and demanded failures
remain covered by the separate witnesses above and below.

All 96 cases completed and agreed under the current generic World kernel, with
63 actual fresh State transfers and a largest image of 2,065 bytes. Generation is
bounded to at most 15 tree nodes; reference and runtime observation allowances
are explicit. Exhaustion is a test limitation/failure, never semantic equality.
These finite cases do not prove universal laws over partial terms.

```sh
zig build build-hyper-generated -Doptimize=ReleaseSafe
node test/hyper_generated.mjs zig-out/bin/hyper-generated WORLD_ENTRY KERNEL
```

## Foundation and Agent integration

Foundation Boundary #152, World #54 and Agent #32 are merged. Immutable bases:
Boundary c7a08ed7c1e15732fc7373dd1f149cbe7da82e7b,
World 374ed712c2a2ab5041c28befa38bb3c3a859bd26,
Agent e1b56f06ce0d91a8d7f324198a541f0b16b55a00.
The foundation's accepted named latency, memory, image and checkpoint tradeoffs
remain inherited costs, not waivers for this feature. No World code change has
been required. BPI3/BMO1/PST3 retain their existing meanings.

Agent's separate internal participant path inspects object code and actual helper
bindings without weakening compiled-tool restrictions. Its task-valued `ana`
witness reuses unchanged producer bytes with two consumers, performs real reference
reads and checked synthetic-model calls, retains an idle owned computation, rejects
stale replies, and transfers actual bytes across native, Node, Wasmtime, Chromium
and Firefox. Separate enclosing cancellation stops ordinary sibling/model work.
Agent also has real isolated parser acceptance with two valid implementations and
five independently rejected invalid implementations. Its current dependency is
Boundary b604ae828650a9be176b103552942adaafc983c0; integration of this later pure
algebra revision remains to be performed through the normal authenticated lock.

## Remaining requirements

Broader generated reference agreement and law discrimination, independently
compiled support-library isolation, three-part compositional closure, broader effectful ownership and demand-handler integration, owned exchange/disposal APIs with suspending
cleanup, multi-shot custody, allocation-failure sweeps, multi-input fold/fusion
and required structural economy remain unfinished. The model-directed incremental
parser synthesis, consumer-supplied recursive assessment, exact approval/delivery,
credible strategy comparison, opt-in live-model path, matched measurements and
serial reviews also remain required. No complete-milestone or live-quality claim
is made; all publication remains draft.

## Internal demand translation

The task-valued family now has an explicit effect interpretation in
`library.hyper.demand`. A nominal `Need<S,A>` request carries a lexical capability
and successor state. Its ordinary deep-handler clause uses the current ana maker
to construct that successor, invokes the counterpart task, and resumes the actual
waiting one-shot continuation with its result. Step bodies contain ordinary effect
requests rather than manually emitting counterpart invocation machinery. Constructing
the task descriptor performs no environmental work. Each later request executes
a fresh task; descriptor sharing does not share its execution.

The handled body is linear, and caller-supplied capture/region/obligation bounds
still cross the existing source/object checks. This is not an exemption from
ownership checks or automatic support for every resource-bearing shape.

`examples/hyper_demand.zig` nests consumer and producer requests with non-tail
additions, while the inner consumer requests one residual reference operation.
Both internal families deliberately share the display name `hyper/need`; their
nominal IDs and lexical capabilities remain distinct. A wrong-family capability
rejects at source checking.

`zig build check --summary all` passes 249 steps / 239 tests.
`zig build emit-hyper-demand > IMAGE`, followed by the ordinary
`test/hyperfunction_world.mjs WORLD_ENTRY KERNEL IMAGE effect` driver, returns
42 through 89 fresh Node/WASM transfers at quantum 1. The Program is 1,234 bytes.
Only the single declared external `hyper/reference` request reaches the host;
the fixture supplies its explicitly synthetic echo response. This tests handler
translation and suspension, not a real empirical Agent tool. The existing Agent
real-reference/model witness will be migrated onto this handler path next.

## Owned bidirectional exchange substrate

The existing generator owner now also provides `defineExchange`, `begin` and
`exchange`. A definition has distinct input, offered-output and completion schemas.
Beginning supplies the first input; exchanging consumes the old owned package,
accepts the supplied input, and advances to the next output or completion. It does
not return the previous yield. The original unit-input/unit-completion generator
API delegates to this construction; its existing checks remain intact.

The implementation uses the existing deep handler, linear resumption and suspension
package representation. Local `close` disposes only the selected owner and returns
to its caller. It does not use enclosing World cancellation. Captures, regions,
obligations and consumed-package rejection remain owned by the existing validators.
No opcode, interpreter or wire-format change is made.

`examples/owned_exchange.zig` retains two independent owned endpoints. Ordinary
exchanges verify input 7 produces the next output 17, and input 9 produces completion
109. Both endpoints retain cleanup obligations that perform residual release
operations. A separate ordinary-work operation makes premature or post-cancellation
execution observable. Fresh Node/WASM recovery gives:

| Execution | Observed order | Transfers | Result |
| --- | --- | ---: | --- |
| Local disposal | release 5; work on 50; release 50 | 12 | Caller completes |
| Normal exchanges | work on 5; release 5; work on 50; release 50 | 15 | Typed outputs/completion match |
| Enclosing cancellation | release 5; release 50; no ordinary work | 9 | Cancelled |

The local-disposal and global-cancellation cases are separate executions. Cleanup
suspends and transfers in both. The caller of local disposal remains active and
can resume its retained sibling; globally cancelled execution cannot do so.
The release/work responses are explicit synthetic mechanism-test leaves, not
claims about cancellation of arbitrary external operations.

`zig build check --summary all` passes 256 steps / 240 tests, including an allocation
failure sweep of exchange construction. The duplicate-disposal source case rejects
with UnavailableSlot before publishing an image. `zig build emit-owned-exchange`
and `node test/owned_exchange.mjs WORLD_ENTRY KERNEL` reproduce the runtime cases.
The disposal image is 894 bytes; the normal-exchange image is 1,098 bytes. These are
finite observations, not scaling or timing claims. Composing owned exchanges over
the hyperfunction/task interface, application integration, additional failure
sweeps and the full cleanup-transfer engine matrix remain required.

The demand interpreter also exposes `hyper.demand.interpretWith`: a staged
completion receives the actual linear requester and the counterpart contribution.
It must resume or dispose that requester under ordinary use/effect checking.
`interpret` remains the resume-only specialization. This permits local abandonment
at the lexical owner without pretending that an external request lacking a
capability can be intercepted by a surrounding handler. No runtime callback or
kernel operation is added. Aggregate validation passes 256 steps / 240 tests;
Agent's nondefault disposal/transfer witness is the next integration check.

## Runtime multi-input map/zip/fold witness

`examples/hyper_fold.zig` supplies two independently authored transforms, a
producer over one runtime sequence and a consuming participant over another.
The endpoints differ: `u64` versus a function from a delayed `u64` to a delayed
`u64`. Both participants use public `ana`, reciprocal query, invocation and
explicit forcing. The consumer checks its length and stopping limit before
forcing the supplied element. Neither list length nor demand count emits code.
Their explicit cursor state contains sequence descriptors, an index and a limit;
reciprocal control and non-tail return values are retained separately. Transformed
pairs are not assembled into an intermediate sequence.

The independent direct path checks the same termination conditions, evaluates the
right map then left map, and performs the same right-associated checked addition.
The materialized comparator builds only that demanded prefix of transformed pairs,
then reduces it in reverse. It does not eagerly map an unused suffix. The test-only
JavaScript oracle independently computes these operations with bounded integers;
it does not call the staged transforms or World dispatcher.

Reproduce with `zig build emit-hyper-fold`, then
`node test/hyper_fold.mjs WORLD_ENTRY KERNEL`. Zig 0.16.0 Debug emission and the
unchanged ReleaseSmall World WASM kernel were used with Node 26.9.0 on macOS arm64.
All three paths agree on 81 cases: 66 results and 15 demanded overflow failures.
Cases cover empty and unequal inputs, zero demand, unused overflowing suffixes,
seeded inputs (`0x61c88647`), and lengths 31/127/128/255/256/512. The first eleven
cases also recover through actual fresh Node/WASM checkpoints (153 hyperfunction,
56 direct and 75 materialized transfers). They issue no external effects.

| Realized Program | Functions | Constructors | Sequence-building instructions | Image bytes |
| --- | ---: | ---: | ---: | ---: |
| Hyperfunction | 18 | 15 | 0 | 1,233 |
| Direct | 2 | 0 | 0 | 347 |
| Materialized | 4 | 0 | 2 | 498 |

The same image is used for every input length. The two materialized instructions
create the empty buffer and append each demanded pair. Their absence in the
hyperfunction path follows from staging each map inside a demanded computation and
passing its delayed value directly to the independently authored consumer. This is
a construction fact checked against the actual first-order instructions, not a
new general fold/build rewrite or a timing claim.

Observed costs are unfavorable for this deliberately non-tail hyperfunction fold:

| Path, 512 pairs | World peak working bytes | Largest sampled checkpoint bytes | 256-work quanta |
| --- | ---: | ---: | ---: |
| Hyperfunction | 3,057,476 | 48,174 | 173 |
| Direct | 1,311,193 | 28,135 | 75 |
| Materialized | 175,718 | 20,378 | 97 |

Working high-water measurements include preparation and execution; checkpoint
samples are taken at quantum boundaries and need not hit the exact maximum logical
state. Host JavaScript allocations are excluded. Input encoding is 8,212 bytes in
these rows. All runs release World working ownership to zero after completion.
The materialized path uses tail loops around its buffer; the other two retain
non-tail return contexts. Avoiding a sequence therefore does not establish lower
memory or eliminate required control. No throughput, native-runtime, overall memory
improvement, universal scaling proof or foundation-consumer regression claim is made.
The history-free tail-control bound, separate-component fold reuse and broader
structural/measurement obligations remain open.

`zig build check --summary all` passes 270 steps / 240 tests. The World execution
command above is additional evidence, not implicitly included in that aggregate.

## History-free reciprocal tail control

`examples/hyper_tail.zig` is the distinguishing history-free case: two public ana
participants delegate without post-return work, using a runtime countdown. It emits
one 783-byte Program; the direct recursive comparator is 107 bytes. Run
`zig build emit-hyper-tail` and `node test/hyper_tail.mjs WORLD_ENTRY KERNEL`.
All counts 0/1/7/31/127/512/1,024 return 42, under work quantum 97.

The immutable foundation kernel previously used by these witnesses accumulates
indirect return controls even in tail position. Its sampled checkpoint grows from
599 bytes at count 7 to 73,672 bytes at 1,024. World follow-on PR #55 applies the
existing direct-call tail predicate to indirect application. It retains the actual
callee environment/evidence/region but omits an empty return-only parent. On the
same image and inputs, checkpoint size reaches 125 bytes at count 31 and stays
there through 1,024; peak World working memory at 1,024 falls from 3,009,769 to
111,688 bytes. The direct comparator remains 93 bytes / 8,490 working bytes.
The native World regression independently tests captured data, actual fresh restore
and a non-tail neighbor that must retain its post-return additions.

Candidate kernel SHA256:
`df7fe1ae0ed0de7b2976c98b1534d1d55f4c341b7148837ce32f42ed8d011084`.
Its bytes increase from 462,629 to 462,730 (+101). Both kernels were compiled as
ReleaseSmall: World's build hardcodes the WASM optimization level even when the
host option is ReleaseSafe. Earlier labels in this document have been corrected;
actual kernel identities and prior measurements remain unchanged.

The existing 81-case fold comparison also passes on the new kernel without changing
any Program bytes. At 512 pairs the hyperfunction path now observes 1,435,599 peak
working bytes and 29,742 sampled checkpoint bytes; direct and materialized paths
retain their earlier numbers. This does not remove meaningful non-tail state or
make the hyperfunction fold superior to its comparators. The identity witness still
exhausts eight bounded quanta without a semantic answer, and remains cancellable.

These results establish this finite history-free workload and the specific tail
transfer mechanism; they are not throughput measurements or a general productivity
proof. Final normal dependency integration and broader matched economic evidence
remain required. Boundary aggregate: 276 steps / 240 tests passed.

## Adaptive distinct-endpoint invocation and source-denied linking

`examples/hyper_adaptive.zig` supplies a general pure `ana` body at
`H(bool, u64)`, with a complementary `H(u64, bool)` consumer. The producer's first
counterpart result chooses which second state to query. It retains the first
Boolean through that second query and performs non-tail work afterward. The
consumer likewise performs checked arithmetic after its own reciprocal query.
This is not a fixed one-input/one-output stream schedule.

Producer, normal consumer, inverted consumer, invocation support and the entry
wrapper are emitted independently as BMO1. The unchanged producer and support
objects link with either consumer through the existing data-only `boundary-link`.
A separate well-typed producer has the same state parameter but reversed endpoints;
binding it to the original import rejects with IncompatibleInterface. Missing
bindings reject with UnresolvedImport. Object bytes are compared before and after
both successful links; no component is re-defunctionalized by the linker.

Reproduce with `zig build emit-hyper-adaptive` and:

```sh
node test/hyper_adaptive.mjs zig-out/bin/boundary-link zig-out/adaptive WORLD_ENTRY KERNEL
```

The macOS test transports only the linker and objects to a fresh directory before
linking. No emitter is transported. The existing OS sandbox denies all reads and
execution under the original Boundary repository; a denied read of the actual
authoring file is checked explicitly. Linking and subsequent execution both run
under that denial. The runtime receives only the linked images plus the independently
implemented higher-order test oracle. This source-access test for trusted tooling
is not a new candidate-code sandbox or a production evaluator.

Both Programs agree with hand-derived discriminators and 71 higher-order reference
cases (seed `0x71c3a19f`): 69 results and two demanded arithmetic failures each. The
reference's observation limit is never treated as an answer. Each Program resumes
through 1,353 actual fresh Node/WASM State transfers. An ignoring consumer returns
normally even when the unused reciprocal arithmetic would overflow. The original
consumer produces 11/21/22 on the three distinguishing cases; its replacement
produces 21/11/12 without changing producer bytes.

Normal image: 1,301 bytes; inverted-consumer image: 1,305 bytes. Producer object SHA256
`6f3c24036ccbb6aab87a57b7e260d7c4b0d400a510b03bbda153e6043ad84f76`;
invocation-support object SHA256
`d7eb01e46b6cafba71cfbdd1b4b97dbb3e632c659bbaba31ad0ed5feb94dc27b`.
World kernel remains `df7fe1ae0ed0de7b2976c98b1534d1d55f4c341b7148837ce32f42ed8d011084`.
Aggregate: 291 steps / 240 tests pass; the source-denied execution command above is
additional explicit evidence. This does not claim universal law verification or
complete the owned three-part channel/composition and broader remaining requirements.

## Derived owned exchange composition

`generator.compose` emits a reusable composition definition with its own ordinary
Generator interface and a `start` function. Starting consumes two live packages and
the first supplied input. Left outputs feed right inputs; a yielded right output
returns one owned composite successor. That successor uses the existing `exchange`
and `close` operations and can itself be composed with another compatible endpoint.
The left output/right input and completion types must agree. Either completion path
closes the other retained endpoint before returning the actual completion value.

Composition is guest code over existing handlers, typed packages, calls and local
disposal. No host phase enum, kernel primitive or wire format is added. Compilation
of the definition performs no environmental work; starting it is an explicit
execution, not an effect-free join of running participants. This is a derived
sequential pipeline operator, not a replacement for general hyperfunction invocation
or a claim that arbitrary coroutine composition satisfies the pure hyperfunction laws.
Declared residual effects and region bounds are combined; ordinary source/object
admission still checks actual capture, use, borrow and lifetime obligations.

The witness builds A and B, observes their output, then combines that running
composite with C through the same interface. New inputs produce 120 and 122 rather
than replaying an earlier yield. A fourth owned participant remains outside the
composite. Local close disposes C/B/A, returns to the active caller, then permits the
fourth participant's real observation and final cleanup. Left completion and right
early completion also dispose the remaining peers. These outcomes retain the
foundation's unwind order rather than imposing an invented global cleanup order.

All four executions pass fresh native/Node/Wasmtime/Chromium transfer using actual
destination outcomes (170 destroyed Workers). Local disposal has 51 transfers;
normal completion 53; right early completion 34; separate whole-execution cancellation
28. Cancellation begins at a pending observation before the test adapter executes
it; only cleanup then runs, including the unrelated retained participant. This is
not a general claim that an already executed external operation can be cancelled.
Completion/disposal image sizes are 3,337 / 3,245 bytes; early-right completion is
3,093 bytes. Kernel remains df7fe1ae0ed0de7b2976c98b1534d1d55f4c341b7148837ce32f42ed8d011084.

`zig build emit-composed-exchange` emits the witnesses; `test/composed_exchange.mjs`
executes them against supplied World inputs and optional existing peer/Worker harnesses.
Duplicate composite-owner use rejects before image publication. Type incompatibility
and allocation-failure construction checks pass. Aggregate: 300 steps / 241 tests.
This does not finish all owned hyperfunction/Agent strategy integration or the wider
borrowed-region, comparison and serial-review requirements.

## Multi-shot recursive values and reentrant execution

`examples/hyper_multishot.zig` composes the existing hyperfunction and scoped
choice APIs. It constructs a lifted function capturing 37 before one multi-shot
capture. Both activations mutate their own captured local cell from 0 to 1; the
outer cell is deliberately shared and advances from 0 to 1 to 2. Projecting the
captured hyperfunction yields rows `(false,1,1,39)` and `(true,1,2,40)`. Sharing the
private cell or deep-copying the outer cell would produce different observations.
Each branch parks at a declared observation fulfilled by a real fixture-file read.
These are two activations of the same template, not two fresh one-shot captures.

The separate `reentrant` mode uses the existing reentrant fixture owner, extended
with a checked pure result function. It converts one capture to a multi-shot
template and resumes that template while the first activation remains live. The
nested return runs `project(lift(x -> x + 37), 5)`; the original return paths then
perform their non-tail additions, producing 145. Existing fixture entry points
retain their original result. This is ordinary compiled code, not another evaluator.

Reproduce with `zig build emit-hyper-multishot`, then:

```sh
node test/hyper_multishot.mjs WORLD_ENTRY KERNEL NATIVE_FIXTURES WASMTIME_PEER BROWSER_MODULE BROWSER_TOOLS
node test/hyper_multishot.mjs WORLD_ENTRY KERNEL NATIVE_FIXTURES WASMTIME_PEER BROWSER_MODULE BROWSER_TOOLS reentrant
```

The supplied browser module may be the existing generic
`agent/test/agent4/recursive_browser.mjs` harness. It is a test-driver argument,
not a production dependency. Both paths continue actual destination State bytes
across native World, Node/WASM, independent Wasmtime and Chromium Workers under
the same kernel. Terminal working-live storage is zero after closing each run.
This establishes the stated finite clone/reentry witnesses; it does not make
resource-bearing Agent interactions or compiled participant imports unrestricted
multi-shot values, or establish a universal lifetime/leak theorem.

Measured fixture sizes/outcomes: clone image 1,132 bytes, two fixture reads,
11 fresh transfers and 12 destroyed Workers; reentrant image 998 bytes, one
authored yield, eight transfers and nine destroyed Workers. Both used kernel
`df7fe1ae0ed0de7b2976c98b1534d1d55f4c341b7148837ce32f42ed8d011084`.
Boundary `zig build check` passed 306 steps and 241 tests. This slice changes
fixture authoring/support only; Agent's authenticated Boundary dependency remains
at `5a8aa24bb179bc8defaa896ea776605261ed6539` until an explicit integration update.

## Matched native timing procedure

`test/hyper_economy.mjs` uses World's existing Zig `replay-bench` clocks rather
than timing process launch. The immutable runtime baseline is World
`374ed712c2a2ab5041c28befa38bb3c3a859bd26`; the candidate is
`5c3dea1c0443f026b2451581de77ec2e51085e57`. Both benchmark binaries use the same
Boundary data source at `b40befad3fa214431961e60c375c012995817aac`, ReleaseSafe
host builds, identical BPI3/PKI3 bytes, and the existing 256-MiB test workspace.

Before inspecting timings: compare tail hyper/direct inputs 0,31,127,512 and
fold hyper/direct/materialized inputs 0,31,128,512. Measure fresh initial execution
and fresh recovery from an identical complete initial State. Verify completed
bytes against an independently calculated numeric result. For each cell alternate
baseline/current order across three processes per variant, each with three warmups
and nine measurements. Summarize process medians, retain all outcomes, and inspect
any consistently adverse control result rather than changing the workload or gate.
There is no new optimization or universal percentage target in this pass.

The timed native invocation includes decode, preparation, execution and complete
outcome encoding; allocation counters run separately. Initial-State recovery
includes admission/restore, but does not by itself measure resident operation or
checkpoint encode cost. The existing Zig `bench_stats` and `perf_report` 0.2.16
CLIs were executed on a known sample and report template before using their output.
Do not reinterpret these finite process samples as service p95/p99 or WASM timings.

Native results cover 40 cells; [all medians/ranges and input identities](recursive-interaction-timings.csv)
are retained with the six unchanged-control and 27 WASM cells. At tail count 512,
initial native execution falls from 9.970 to 4.542 ms (0.456x); fresh initial-State
recovery falls from 9.974 to 4.490 ms (0.450x). Direct initial execution stays at
0.270 ms. The hyperfunction construction therefore still costs about 16.8x the
direct loop on this workload; the runtime improvement is not comparator dominance.
For the non-tail fold at 512, hyper/direct/materialized candidate medians are
80.076/47.521/31.679 ms. The structural intermediate elimination does not establish
a speed advantage over either simpler comparator.

Six existing foundation fixtures (scalar, deep handler, reentrant, cleanup,
generator, retained-loop 128) use the existing `execution-bench`, three paired
processes, identical input hashes and its independent event oracle. Candidate /
baseline median ratios range from 0.968 to 1.013. Small differences are not accepted
as wins or regressions from these samples. Boundary data sources are byte-unchanged
between the foundation and B40; using the same data input isolates the World delta.

The separate WASM procedure (`test/hyper_wasm_economy.mjs`) uses three warmups and
five alternating paired samples in one Node process. It includes generic-kernel
admission/creation, preparation and execution. Resident and fresh modes both encode
one complete checkpoint after each quantum of 97; fresh additionally creates a
new kernel and restores that checkpoint. Their checkpoint counts/bytes match
within each runtime variant. Uninterrupted mode has a different durability policy
and is reported separately. V8 warmup, GC and embedding setup remain in these
end-to-end observations; no cold compilation or service-tail claim is made.

For tail hyperfunctions at 512, baseline/candidate WASM medians are 27.58/9.51 ms
uninterrupted, 191.85/17.65 ms resident with checkpoints, and 612.32/104.25 ms fresh
with checkpoints. Large effects have separated observed ranges. Setup-dominated
and direct-control ranges overlap substantially (including the only adverse WASM
median, direct-127 resident at 1.048x); their apparent changes are inconclusive,
not attributed to tail application. On the candidate, direct-512 resident/fresh
costs 1.56/14.47 ms, still substantially below the hyperfunction path. Every run
returns its independently specified value and releases final working ownership.
No optional optimizer was added and no unfavorable cell was discarded.

Reproduction (use immutable source directories and distinct output prefixes):

```sh
# From World; repeat with the candidate World source and another prefix.
zig build --build-file test/v2/build_replay_bench.zig \
  -Dboundary-source=BOUNDARY_SOURCE -Dworld-source=BASELINE_WORLD \
  --prefix BASELINE_REPLAY_OUTPUT
# From Boundary after emit-hyper-tail and emit-hyper-fold:
node test/hyper_economy.mjs WORLD_ENTRY CURRENT_KERNEL BASELINE_REPLAY CURRENT_REPLAY OUTPUT
node test/hyper_wasm_economy.mjs WORLD_ENTRY BASELINE_KERNEL CURRENT_KERNEL OUTPUT
```

Foundation controls use `test/v2/build_execution_bench.zig` with the same source
pair options, then `execution-bench bpi3 FIXTURE COUNT`; the fixture/count list is
above. Native replay binary SHA256s were
`9e8624edbe234bf681e69c4a19b1b853ef48ca002e23c86d70466f1f736a93cd` and
`8c2a0cbae060dc931a88271c3d46e5d850879f10c8e44fe822ad774d697eafae`.
Kernels were `7a27d64295431c960046439353a158e378f14d4686fac47b61b1406cf1753663`
and `df7fe1ae0ed0de7b2976c98b1534d1d55f4c341b7148837ce32f42ed8d011084`.
Runtime timings are new evidence; the preceding structural/source-oracle checks
are reused because their executable inputs did not change. Cold native emitter
build cost and source/component compilation attribution remain separate unmeasured
lanes; no old cold-build target is reintroduced by this timing pass.

## Native emitter and compiler attribution

`test/build_hyper_compiler.zig` builds the normal fold emitter separately from a
stage-observed compiler. `emitWorkload` exposes exactly the existing staged bodies;
instrumented and ordinary outputs are checked byte-for-byte against the admitted
images. No timing callback enters a Program. The observer uses the compiler's
existing stage interface; it changes only the benchmark's native timing record.

Nine rotated compiler-process samples follow three warmups per mode. Median
staged-authoring / compilation / image-encoding times are 32.1/212.8/60.7 us for
hyperfunctions, 21.6/86.5/23.7 us direct, and 24.9/106.5/30.7 us materialized.
For hyperfunctions, source checking is 25.8 us, lowering 29.1 us, target checks
combined 105.1 us, direct optimization 7.5 us and canonicalization 37.3 us.
Stage medians are separate statistics and need not sum to the total median.
Observed phase clocks have instrumentation overhead; they are attribution, not
an uninstrumented latency improvement claim. Whole uninstrumented command medians,
including process startup, are 2.507/2.327/2.332 ms respectively.

The existing adaptive producer/consumer/support/entry component emitters take
2.20–2.40 ms per already-built CLI command (startup included). Source-free linking
of those objects takes 3.873 ms normally and 3.810 ms with the alternate consumer.
These are command-level component/link measurements, not isolated link CPU time.
The measured emitted objects then passed the independent source-denied oracle:
71 cases per consumer, 69 completions and two demanded overflows each, with 1,353
fresh transfers per Program. Output identities and all sample ranges are retained
in [the compiler table](recursive-interaction-compiler.csv).

Building the combined **uninstrumented native emitter** with three fresh local and
global Zig caches took 16.524, 16.463 and 16.515 seconds. This is one executable
containing all three workload modes, not a per-mode cost or a comparison against
a historical cold-build target. OS filesystem caches and host load were not
controlled. Warm emitter execution and portable runtime timing remain distinct.
No optional compiler optimization was added in response to these costs.

Reproduce from Boundary:

```sh
zig build --build-file test/build_hyper_compiler.zig profile emitter components linker \
  -Dsource=BOUNDARY_SOURCE --prefix OUTPUT
node test/hyper_compiler_economy.mjs OUTPUT/bin RESULTS --cold-builds
```

The driver creates fresh cache directories for every cold sample. The recorded
first run used new empty `build-0/1/2` directories; the driver subsequently made
that precondition explicit with unique directory creation. That naming-only
safeguard does not change the measured compiler inputs. Zig 0.16.0, ReleaseSafe,
Node 26.9.0 and Darwin 27.2 arm64 were used. Boundary check passed 306 steps and
241 tests; production workload images are unchanged, so prior runtime evidence
is retained. These measurements fill compiler/build attribution, not final review
or requirement-audit credit.

The actual hyper-fold authoring/lowering/encoding/image-admission path now has
an allocation-failure sweep in `test/hyper_allocation.zig`. Every injected failure
releases partial owners under the testing allocator; successful publication still
admits and preserves the function count. Run it with
`zig build --build-file test/build_hyper_compiler.zig allocation -Dsource=BOUNDARY_SOURCE`.
The ReleaseSafe sweep passed. This adds verification only; workload images and
compiler/runtime measurements retain their preceding executable inputs.
