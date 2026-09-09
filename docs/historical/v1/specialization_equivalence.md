# Specialization equivalence

For Program `P`, canonical State `S`, command input `I`, and caller fuel `F`:

```text
KernelV2(BPI1(P), Profile, S, I, F) == DirectV2(P, Profile, S, I, F)
```

Equality covers the complete observable transition: outcome, remaining fuel,
canonical State bytes, request site and payload, every RequestIdentity field,
terminal result/failure bytes, and accepted-versus-rejected operational input.

The Program Image owns computation meaning. Both v2 adapters share the separate
MachineV2Profile, stable wire/current tag mapping, authored failure roles, and
v2 fuel/resource-shape law. The kernel keeps
actual canonical values separate from conservative preflight sizes because the
direct specializer propagates those bounds independently.

Canonical State is the engine-switch boundary. No translation is permitted.
`check-boundary-specialization-equivalence` and
`check-boundary-engine-switch` own this claim; final-outcome-only comparison is
insufficient.

Separately, the direct unmetered reducer clause and the internal BPI1 clause
evaluator must agree before Machine v2 policy is applied. The clause evaluator
is a repository-internal seam, not a package-root API. Process ABI v1 evaluates
the same clauses through `boundary.process_v1.CapacityStorage(...).advance`;
its native/WASM parity is proved separately by `check-boundary-process-v1`.
