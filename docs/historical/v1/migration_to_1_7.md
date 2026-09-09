# Migration to Boundary 1.7

Boundary 1.7 adds the open Process ABI v1 and the fixed import-free Process
kernel while retaining BPI1 v1, Machine ABI v2, MachineV2Profile, and the fixed
Machine-v2 kernel as compatibility surfaces.

Boundary 1.7 also adds direct authored instruction-failure values. A fallible
Control IR instruction may append one canonical `Body.Failure` constant for
each Boundary-defined failure role, in role order, without changing the BPI1
container format. This release does not add a component linker, World system
linker, capability host, or host runtime.

New portable execution should use `boundary.process_v1` with BPI1 plus initial
arguments or canonical `ABL_PST1` Process State. One `advance` invocation
performs exactly one finite reducer segment and carries no caller fuel,
cumulative fuel, frame ceiling, or process-lifetime budget. Existing bounded
callers may continue using `Program.compile`, `Program.machineV2Profile`, and
`boundary.machine_v2.kernel` unchanged.

Effect semantic identities are now rejected at source-program admission unless
they are non-empty valid UTF-8. This matches the existing BPI1 validator and
prevents a typed Program from emitting an image that the canonical byte
validator rejects. No BPI1, Process State, EffectRequest, EffectResult, Capsule,
or Machine-v2 wire version changes.
