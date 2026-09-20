# Defunctionalized hyperfunctions and recursive interaction

Implementation of the user-authorized specification v1.1 (September 19, 2026).
This is an early, incomplete implementation. The production library and Agent
application are not yet implemented or accepted.

## Semantic contract

The pure core uses call-by-name demand, including endpoint values, with
`H(A,B) = H(B,A) -> B`. A delayed value is demanded explicitly; merely constructing
a callable or aggregate does not evaluate its contents. General recursion can
remain nonproductive. Observation-limit exhaustion is a scheduling/test outcome,
never a mathematical result or proof of divergence.

In lazy notation:

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

Composition has orientation H(B,C) × H(A,B) -> H(A,C). The independent
higher-order oracle in `test/hyperfunction_reference.mjs` executes these equations
using explicit lazy closures, without importing production code. Its six initial
checks include constant lift, unused peer/field/fault, bounded identity observation,
and adaptive multiple queries with number/string endpoints and non-tail return.
The finite examples do not prove universal laws or production agreement.

The effectful family uses suspended Boundary computations as endpoint values.
Constructing or sharing a pure task descriptor does not invoke it. Explicit task
calls execute sequentially in authored order; repeated calls are fresh executions.
Internal nominal partner demands are handled within the Program. Environmental
operations remain residual effects, with the real waiting continuation retained.
Owned running interactions cannot inherit unrestricted pure duplication laws.

## Initial representation decision

Begin with existing computation schemas, lambda lowering, indirect application,
and stable activations. Delay both peer and answer computations; a strict
coroutine-style alternation fails the constant-lift discriminator. A source
closure should become ordinary code identity plus checked environment; reciprocal
invocation should become normal first-order transfer with a retained return path.
World remains the sole production evaluator. The oracle is test-only.

No new opcode, schema, format, or host evaluator is selected. Production support
for the recursive callable construction is still to be established. Existing
schema references and greatest-fixed-point capture traits are promising facilities,
not proof that all required recursive contracts already pass admission.

## Integrated foundation and admission gap

The foundation PRs Boundary #152, World #54, Agent #32 are merged. Follow-on bases:

- Boundary: c7a08ed7c1e15732fc7373dd1f149cbe7da82e7b
- World: 374ed712c2a2ab5041c28befa38bb3c3a859bd26
- Agent: e1b56f06ce0d91a8d7f324198a541f0b16b55a00

The normal foundation manifests still bind Boundary production 1b00c8c159f0cb490a1223fac8d3d208cef41cb1;
its recorded World production dependency is 02846a4c8d535c60956874aba5fd30f579207c20.
The foundation's published results retain the accepted named native latency,
peak-memory, image, and checkpoint costs. Those are inherited costs, not an
allowance for additional regressions. No feature performance measurement exists yet.

At the Agent base, `src/compiled_tool.zig:declare` requires effect-only imports,
portable input/output, read/simulation roles, and rejects model invocation and
multi-shot resumption schemas. Its linking path uses the component borrow checker.
It does not supply the required internal participant path. Tool restrictions must
remain effective; the new path must validate actual linked authority, including
indirect calls and assessment isolation, through normal Agent compilation.

## Current evidence and next slice

`node --test test/hyperfunction_reference.test.mjs`: six passing oracle checks.
No existing checks were deleted or weakened. Production pure agreement, checked
Agent participants, transfer, parser synthesis, structural economy, measurements,
and serial reviews are not run and remain required.

Next: compile the unused-divergent-counterpart witness through the ordinary
Boundary/World path, then independently compiled reciprocal Agent participants
with a scoped model/reference operation, fresh restore, both non-tail returns,
and nearby authority/capture rejection cases. Expand these same witnesses to
the complete v1.1 requirements. Publish linked drafts throughout; never promote
or merge them under this task's authority.

## First compiled demand witness

`library.hyper` now supplies initial capture-free recursive callable pairs,
pure delayed computation schemas, `invoke`, and `force`. This is a deliberately
incomplete public surface, not the completed general hyperfunction library.
`examples/lazy_hyper.zig` compiles a constant participant applied to a delayed
peer whose body recursively calls itself. The result is explicitly forced.
Ordinary lowering removes unused work and emits a 178-byte BPI3 Program.

Executed with Zig 0.16.0, native Debug emission, and the unchanged World baseline
ReleaseSafe kernel (SHA-256
`7a27d64295431c960046439353a158e378f14d4686fac47b61b1406cf1753663`):

- `zig build check --summary all`: 223 steps / 234 Zig tests pass; six Node
  hyperfunction reference tests also pass.
- `zig build emit-lazy-hyper > /tmp/lazy-hyper.bpi3`: passes.
- `node test/hyperfunction_world.mjs WORLD_ENTRY KERNEL /tmp/lazy-hyper.bpi3`:
  returns 42 after seven actual fresh WASM-instance transfers at quantum 1.
  Each transferred source handle is invalidated and releases its working memory.
  The destination resumes the actual checkpoint bytes returned by World.

Build the unchanged baseline kernel with `zig build build-kernel
-Doptimize=ReleaseSafe` in the World baseline checkout. `WORLD_ENTRY` is its
`src/embedding/index.mjs`; `KERNEL` is `zig-out/world-kernel.wasm`.
This proves the narrow constant/non-demand case on Node/WASM. Native execution,
browser/Wasmtime, recursive retained interaction, full constructors and Agent
positive admission remain unexecuted requirements. Image size is an observation,
not a performance comparison or the required fusion/scaling result.

## Capturing invocation and state-based recursion

The current interface has six mutually recursive callable schemas, cached per
endpoint/capture signature. `pairWith` admits explicit capture bounds. All six
schemas refer to the finite group; construction does not unfold recursion.
Normal use analysis rejects an exclusive resource hidden in the group's reusable
capture bound. Each actual environment still contains only the captures used by
its authored body.

`invoke` now constructs a delayed invocation rather than calling the participant
while constructing its result descriptor. Its thunk first calls the participant,
then forces the returned delayed answer. `make` accepts an arbitrary checked
staged body; `ana` builds a participant from runtime state and a staged step.
`Query.ask(next_state)` constructs a delayed counterpart contribution, including a
delayed reconstruction of this participant at that successor state. The staged
step may emit any number of runtime queries and non-tail operations. Its native
builder is never serialized or used by World.

`examples/reciprocal_hyper.zig` uses the same public `ana` operations for producer
and consumer. The consumer's first query enters the producer; the producer's
query enters the consumer's successor. That successor returns 19, the producer
adds 10, and the original consumer adds 13. A separate higher-order reference
executes the same equations and asserts the five-event nested call/return order.

On the unchanged World kernel named above, actual Node/WASM execution gives:

| Compiled witness | Program bytes | Fresh transfers at quantum 1 | Result |
| --- | ---: | ---: | ---: |
| Constant with divergent peer | 268 | 11 | 42 |
| Unused invocation of divergent participant | 247 | 3 | 42 |
| Reciprocal state-based non-tail calls | 735 | 60 | 42 |

Emit with `zig build emit-lazy-hyper`, `emit-unused-hyper-invocation`, or
`emit-reciprocal-hyper`, redirecting stdout to an image; run each image using
`test/hyperfunction_world.mjs`. These are observed sizes and finite execution
checks, not benchmark improvements or the complete structural-economy evidence.
The constant image grew from 178 to 268 bytes when invocation itself became
properly suspended; no shared kernel change was required.

`zig build check --summary all`: 225/225 steps, 236/236 Zig tests pass.
The independent Node oracle now has seven passing tests. The latest additional
oracle case was run directly after the aggregate; it changes no production code.
General lifting/composition, lazy aggregates, effect-handler translation,
use-qualified owned interactions, source-free library reuse and full Agent
reciprocal synthesis remain unfinished.
