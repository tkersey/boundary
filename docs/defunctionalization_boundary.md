# Defunctionalization Boundary

Boundary-native effect semantics should be Boundary programs or declarative Boundary
data. Boundary does not pretend opaque host callbacks are algebraic-effect
semantics. It marks them as host intrinsics.

`Program.Evidence.SemanticBody` classifies semantic execution bodies:

- `boundary_program`: represented by an Boundary `Program` or `ProgramPlan`.
- `declarative`: represented by deterministic declarative Boundary data.
- `residualized_program`: transformed into a residual `ProgramPlan`.
- `pipeline`: produced by a proof-carrying `Program.Pipeline`.
- `kernel_primitive`: Boundary's own interpreter/kernel machinery.
- `host_intrinsic`: opaque host code or external-world behavior.
- `unknown`: incomplete or invalid classification.

Host intrinsics are necessary at the world boundary: tool calls, model calls,
file writes, human approval, randomness, clocks, foreign systems, test fixtures,
function-backed ProviderHarness handlers, `Program.run` handler functions,
`Program.Interpreter` handler functions, and dynamic morphism mapper functions.
They are not inspectable Boundary semantics.

Certified Boundary Targets keep that split intact. Boundary can link or
residualize supported Boundary-native routes, but explicit `WorldPort` sites
remain residual operations described by `WorldSurface`; World chooses the ABI and
executes the host side.

`Program.Evidence.HostIntrinsic` gives each declared intrinsic a deterministic
descriptor and evidence ref. Its fingerprint is based on declared labels, kind,
policy summaries, refs, tags, and metadata. It excludes function pointer
addresses, allocator pointers, runtime addresses, thread IDs, request tokens, and
other nondeterministic host identity.

`Program.Evidence.DefunctionalizationReport` summarizes a scope such as a
provider harness, provider offer, treaty, resolver result, interpreter, run
handler set, morphism offer, pipeline, journal, or catalog. Reports count each
semantic body kind and expose intrinsic and unknown refs where available.

`Program.Evidence.DefunctionalizationPolicy` can reject host intrinsics, reject
unknown bodies, allowlist host intrinsics by fingerprint, kind, or label, reject
dynamic mappers, require program-backed providers, require declarative/static
morphisms, and prefer less opaque routes.

ProviderHarness now reports:

- program-backed provider declarations as `boundary_program`
- function-backed declarations as `host_intrinsic`
- provider-program mapping fingerprints in the derived provider manifest
- derived provider offers with `semanticBodyWithProvider`, `hostIntrinsicRef`,
  and `programBodyRef`

TreatyResolver can apply defunctionalization policy while selecting routes. With
preference enabled, provider offers rank as program-backed only when their
mapping fingerprint is backed by the provider manifest; those routes rank ahead
of function-backed host intrinsics, and static residualized or pipeline
morphisms rank ahead of dynamic host mapper functions. With strict policy,
intrinsic providers and intrinsic morphism mappers are blocked during both
treaty resolution and later treaty-response validation.

`Program.BoundaryClosure` applies the same classifications across a configured
effect graph. It turns root program effect sites, provider offers, program-backed
provider programs, morphism offers, capability grants, and explicit world ports
into static treaty plans, a deterministic graph, a report, and a certificate.
Strict closure rejects host intrinsics and unknown bodies. World-boundary closure
accepts only explicit allowlisted intrinsics and surfaces them as
`WorldPort` declarations for an adjacent `world` interpreter.

`Program.BoundaryClosure.Elaboration` and target normalization are the next
algebraic steps for checked closure outputs. They treat Boundary-native handlers
as program transformations: program-backed providers, residualized morphisms,
pipeline adapters, and declarative routes can be represented in a residual
`ProgramPlan` where the first-version lowering supports them. The normalization
trace records redexes, rewrite rules, rewrite steps, eliminated provider routes,
residual world ports, unsupported blockers, and the final normal form. Host
intrinsics are not executed during elaboration or normalization; allowed ones
remain explicit residual `WorldPort` requests.

This layer does not add a parser, source language, VM, Artifact API, async
runtime, network layer, persistence backend, provider scheduler, service
discovery system, security layer, public root widening, `ProgramValue` widening,
serializable request tokens, cross-thread sessions, arbitrary host-handler
serialization, or runtime allocator/thread serialization.

`Program.Session` remains the primitive host-driven defunctionalized execution
machine. Program-backed providers are the canonical Boundary-native provider
handler form. Declarative morphisms, residualization, and pipelines are the
canonical Boundary-native transformation forms. Host functions remain available
as explicit host intrinsics at the world boundary.
