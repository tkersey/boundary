# Resumption Normal Form

Resumption Normal Form (RNF) represents one portable continuation state as a
bounded nonempty stack:

```text
State = Header x NonEmptyList(Frame)
Frame = sum constructor_id . Environment(constructor_id)
```

Each constructor identifies one future computation. Its environment contains
only values required by that future computation, local validation, semantic
identity, or deterministic resource accounting.

Every non-root constructor also carries a distinct activation context: the
parent-selected call-entry constructor id and exactly the callee entry
parameters live when that invocation began. The compiler initializes this
product only at the call edge and preserves it through every callee transition.
Activation-owned parameters are omitted from the immediate call-entry future
environment. After progress, a loop-carried current value may coexist because
it no longer means the immutable invocation argument; backedges can therefore
rebind entry value ids without erasing invocation identity.

Compiler classifications include entry, segment entry, loop header, await
effect, call return, after handler, caller-fuel yield, and terminal handoff.
Canonical state encodes only the dense constructor id and its typed
environment; classifications and source names are compile-time/debug metadata.

Branches that reach different futures normally become different constructors.
When a constructor is reachable only under a path fact, the compiler projects
that fact onto its environment and emits a bounded local invariant. Decode
validates that constructor schema and invariant. It does not reconstruct the
program's historical control path.

The invariant algebra refers to source values rather than cached predicate
results. It includes fixed-width integer relations and algebraic sum cases;
tagged-union cases and optional presence share the same canonical sum-case
rule. Consequently, a branch on a sum or optional persists the discriminated
value and its constructor-local case requirement, not a redundant Boolean
condition history.

Helper calls that can suspend use explicit return constructors. Recursive calls
push the same statically known frame schemas and are bounded by
`maximum_frames`. Tail and nonsuspending calls may be lowered without a
persisted frame. Stack validation equalizes each waiting parent's selected call
entry and live call arguments with its child's activation context, including
after the child has advanced beyond the call-entry constructor.
