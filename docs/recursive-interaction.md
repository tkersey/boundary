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

`ana` gives `Step.emit` source values for state and a query builder. The step may
emit zero, one, or several adaptive runtime queries and non-tail work. It is not a
fixed stream schedule. Only finitely authored code is generated; successor states
and repeated interactions are runtime values.

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

Zig 0.16.0 native Debug emission and the unchanged World ReleaseSafe kernel
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
node test/hyperfunction_world.mjs WORLD_ENTRY KERNEL zig-out/hyper/compose.bpi3
node test/hyperfunction_world.mjs WORLD_ENTRY KERNEL zig-out/hyper/fault.bpi3 failed
node test/hyperfunction_partial.mjs WORLD_ENTRY KERNEL zig-out/hyper/identity.bpi3
```

The current aggregate passes 247/247 steps and 238/238 Zig tests. All ten emitted
algebra cases were executed after final generation. `WORLD_ENTRY` is the baseline
World's `src/embedding/index.mjs`; `KERNEL` is its `zig-out/world-kernel.wasm`, built
with `zig build build-kernel -Doptimize=ReleaseSafe`. Formatting, diff and source
inventory checks pass. No existing rejection assertion was removed or weakened.

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
