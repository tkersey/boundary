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
