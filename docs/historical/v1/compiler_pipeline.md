# Compiler pipeline

Boundary compiles in one direction:

```text
source -> portable types -> Control IR -> algebraic lowering
       -> CPS and suspension splitting -> liveness and invariants
       -> RNF canonicalization -> direct Machine reducer
```

1. Source admission validates program ownership, typed effects, failures,
   structure, and resource limits.
2. Portable type lowering rejects values without canonical target-neutral
   semantics.
3. Control normalization makes values, branches, calls, effects, returns, and
   failures explicit.
4. Algebraic lowering replaces declared built-in effect handlers with typed
   helper calls, computes root reachability, applies declared type-preserving
   effect morphisms, removes unreachable control and its effect authority,
   eliminates unreferenced effect declarations, densely canonicalizes the
   residual row, and compiles statically known local after behavior before
   runtime.
5. Suspension splitting creates persisted boundaries only where a continuation
   must survive an effect, call, recursive return, explicit yield, or fuel
   checkpoint.
6. Backward liveness computes each continuation's exact ordered future
   environment and, for non-root continuations, the distinct function-entry
   parameters live at invocation. The latter form immutable activation context
   and are the sole persisted authority at immediate call entry. A progressed
   loop may additionally retain a semantically distinct current value.
7. Path facts become bounded constructor-local invariants. Synthesis uses a
   deterministic successor worklist so only facts downstream of a changed
   predecessor are recomputed; the fixed point and canonical output are
   unchanged.
8. RNF canonicalization hash-conses exact equivalent futures, then assigns
   dense constructor ids and static reducer entries. Equivalence requires the
   same reducer class, source/target, ordered future environment, activation
   schema, and local invariant.
9. Machine generation emits direct constructor dispatch, canonical codecs,
   typed effect metadata, and the SHA-256 contract digest.

The production reducer never decodes a runtime instruction array and never
searches a module or provider registry. A switch over RNF constructor ids is the
program-specific defunctionalized apply function.

Unreachable source blocks remain subject to source validation, but they do not
receive RNF constructors, contribute residual effects, alter executable
identity, or become decodable Machine states.

Semantic identity canonicalizes reachable blocks, functions, and values by
deterministic root traversal. It hashes structural portable schemas and only
constants used by reachable instructions. Source ordinals, unused schema
declarations, unused constants, and dead-control layout are diagnostic input,
not executable identity.

Each source Body may declare `compiler_limits: boundary.ir.CompilerLimits`.
Those ceilings bound values, blocks, constructors, constructor environment
fields, invariant terms, and the generated-reducer operation proxy. They may
lower but cannot exceed Boundary's implementation ceilings. Exceeding a limit
produces a named compiler blocker such as `TooManyEnvironmentFields` or
`GeneratedReducerLimitExceeded`; the compiler never falls back to an
interpreter. Activation entry identity, activation values, and future values
share the environment-field ceiling. Limits are compiler-resource policy and
do not alter Machine identity when they generate the same RNF.

An authored `effect_morphisms` tuple is resolved entirely at comptime. Each
morphism replaces one source site's residual contract with a target typed site;
payload and resume types must match exactly. The generated request row and
Machine identity contain only the target contract. No morphism object, closure,
or dispatch step survives into Machine execution.

An authored `effect_handlers` tuple binds one source site to one typed Control
IR helper function. Before reachability or RNF synthesis, every suspension at
that site becomes an ordinary direct call whose argument is the effect payload
and whose result is the resume value. The source site therefore contributes no
residual authority, and no handler object, callback, or runtime dispatch
survives normalization.

The release performance proof exports the immutable Boundary v0.7.0 tag into a
temporary tree and builds its focused StaticMachine witness with the same Zig
toolchain as the RNF witness. It records compile time and peak compiler memory,
then compares paired native lifecycle and decode medians, import-free WASM
lifecycle medians, canonical parked-state size, one-effect WASM size, and
runtime-semantic source-role count against the specified hard gates. The
current role count comes from an exhaustive build-owned classification and is
only a source-complexity measurement; public Program/Machine reflection plus
the deletion and no-interpreter gates own normative reducer singularity. Both
WASM exports accept the same changing `i32` response and expose the same
response-plus-lifecycle checksum through one unconditional adapter. This
bounded reference is conformance-only: no legacy runtime source or reducer is
imported into the production module graph. Because the proof authenticates and
exports the historical tag, it runs only from a tagged Boundary source checkout
with local `.git` metadata. Extracted package consumers retain the
current-version focused proofs but cannot reproduce or claim the historical
release comparison.
