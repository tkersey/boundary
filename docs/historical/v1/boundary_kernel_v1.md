# Machine ABI v2 Kernel v1

`boundary.machine_v2.kernel` is the fixed compatibility evaluator of validated
BPI1, `ABL_MV2P1` MachineV2Profile, and canonical `ABL_RNF2` bytes. It retains
no authoritative State and invokes no callback. It is not the future generic
Boundary Process kernel; that separate import-free artifact is
`boundary-process-kernel-v1.wasm`.
The raw clause evaluator beneath it is internal and has no package-root alias.

The profile carries only v2 policy deltas: hard limits, segment costs, and the
constructor/transition classifications needed to preserve synthetic caller
checkpoints. When semantic RNF quotients multiple legacy constructors, the
profile also carries the authenticated v2-to-BPI1 constructor mapping and v2
transition constructor identities. Binding recomputes the frozen
`boundary-rnf-compiler-semantics-v4` digest from BPI1 plus those deltas before
accepting the Machine contract. Changing a cost or checkpoint annotation
without changing the v2 semantic and contract identities is rejected.

Native `BoundProgram` values are binding certificates, not persistent validated
views. The caller retains the exact BPI1 and profile byte storage for the
certificate lifetime. Every command verifies both artifact hashes, rebuilds
schema indexes in the supplied workspace, and repeats structural and semantic
binding before execution. Post-bind artifact mutation, workspace reuse, and
mutable output aliasing with authenticated backing fail closed.

Native operations are `initial`, `validateState`, `current`, `step`, and
`resume`. Every raw operation that may validate a computed constructor
invariant receives an explicit caller-owned invariant scratch slice; a default
`ValidationWorkspace` carries no hidden evaluator capacity. The typed adapter
owns bounded scratch sized from BPI1, and the WASM adapter supplies its fixed
value workspace. A funded segment executes atomically. Insufficient caller
fuel yields before the segment, preserving State and fuel. Ordinary transitions
remain internal to one call; external effect requests park a canonical await
constructor and include RequestIdentity v2.

The legacy unfunded short path validates only the `ABL_RNF2` envelope and top
constructor needed to select the compiler-known minimum cost. Environment,
invariant, and stack-pair validation is intentionally deferred until that cost
is funded, matching direct Machine-v2 scheduling. Call `validateState`
explicitly at an untrusted-State ingress that requires deep validation
independently of caller fuel.

`boundary-machine-v2-kernel-v1.wasm` targets `wasm32-freestanding`, imports nothing,
exports memory, and exposes Kernel ABI v1:

```text
boundary_machine_v2_kernel_abi_version
boundary_machine_v2_kernel_input_ptr / boundary_machine_v2_kernel_input_capacity
boundary_machine_v2_kernel_execute
boundary_machine_v2_kernel_output_ptr / boundary_machine_v2_kernel_output_len
boundary_machine_v2_kernel_error_ptr / boundary_machine_v2_kernel_error_len
boundary_machine_v2_kernel_reset
```

The input carries BPI1 bytes and separate MachineV2Profile bytes before State
and auxiliary data. The public artifact admits 16 MiB images, 1 MiB profiles,
4 MiB States, 2 MiB auxiliary values,
64 MiB kernel scratch, 24 MiB input, 8 MiB output, and at most 128 MiB linear
memory. Commands validate image, initialize, validate State, inspect current
request, step, and resume. Semantic outcomes are successful ABI outputs;
malformed/resource failures are result codes.

Kernel output outcomes `7` and `8` carry Machine-owned
`execution_budget_exceeded` and `frame_depth_exceeded` results respectively.
They preserve remaining caller fuel and the canonical State selected by the
Machine law; they are semantic outcomes, not kernel result-code failures.
