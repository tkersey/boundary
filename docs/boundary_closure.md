# Boundary Closure Certificates

Boundary Closure proves what is inside Boundary and what must be supplied by
World.

`Program.BoundaryClosure` is an evidence/certificate surface over an already
configured Boundary system. It performs a static/dry-run pass over root program
effect sites, provider offers, program-backed provider handlers, morphism offers,
capability grants, defunctionalization policy, and explicit world ports. It does
not execute providers, start a scheduler, perform IO, persist data, or implement
World.

## What Is A Boundary Closure Certificate?

A Boundary Closure Certificate is a stable proof artifact that says whether the
configured effect graph is closed under effect handling. Closed means every
reachable root operation or after site has a statically planned handling path,
and every selected provider or adapter body is either Boundary-native,
declarative, residualized, pipeline-backed, a kernel primitive, or an explicitly
allowed host intrinsic exposed as a world port.

The certificate binds the closure graph fingerprint, report fingerprint, root
refs, provider refs, selected static treaty-plan refs, world-port refs,
intrinsic refs, blocker refs, and summary counts. Its `Evidence.CertificateView`
lets adjacent systems cite the same proof without depending on runtime pointers
or concrete request tokens.

## Why Closure Matters For World

World should not rediscover Boundary's static graph. It needs a contract:

- which root programs are being interpreted
- which effect sites can be yielded
- which providers or morphisms can handle each shape
- which provider handlers are Boundary programs
- which provider programs yield nested effects
- which host intrinsics remain
- which open effects are explicit world ports
- which blockers prevent interpretation

Boundary Closure is that contract. World consumes the certificate, static treaty
plans, world-port declarations, policy summary, and evidence refs; it still owns
scheduling, storage, transport, provider lifecycle, retries, cancellation,
identity, signing, encryption, and actual host-intrinsic execution.

## EffectShape Vs RequestEnvelope

`BoundaryClosure.EffectShape` is a static witness. It describes a program
operation site, after site, protocol operation, nested provider site, residual
site, intrinsic boundary, or world-port shape using program labels, plan hashes,
exchange manifest fingerprints, site indexes, site fingerprints, requirement/op
names, mode, value refs, semantic labels, and an `Evidence.Ref`.

It is not a request envelope. It contains no concrete payload bytes, no request
token, no provider handle, no allocator, and no thread/runtime identity. Runtime
payload validation, byte-size limits, response authorization, and linear
obligation checks remain request-time guards.

## Static Treaty Planning Vs Concrete Treaty Resolution

`Program.Exchange.TreatyResolver.planShape` and
`Program.BoundaryClosure.planTreatyForShape` perform dry-run treaty planning for
an `EffectShape`. A static treaty plan records direct provider candidates,
morphism candidates, the selected provider or adapter when deterministic,
semantic-body classification, capability evidence when statically known,
runtime-guard flags, and structured blockers.

A static treaty plan is not a concrete `Treaty.Certificate`. Concrete treaty
resolution still binds a real request envelope, concrete payload fingerprint,
provider manifest, offer, route, capability, usage metadata, and response guards.
The static plan proves that a request from this site has a valid route under the
configured catalogs and policies, subject to those runtime guards.
When `BoundaryClosurePolicy.require_static_treaty_plans` is false, closure still
emits one static treaty-plan ref per effect shape, but a missing provider offer,
capability grant, or static route is no longer a closure blocker.

## BoundaryGraph Nodes And Edges

`BoundaryClosure.Graph` is deterministic and pointer-free. Node kinds include
root programs, provider programs, operation and after sites, protocol
operations, provider harnesses, provider offers, capability grants, morphism
offers, residualization or pipeline adapters, treaty shape plans, semantic
bodies, host intrinsics, world ports, and blockers.

Edges record relationships such as root yields, provider-program yields,
handled-by-provider, adapted-by-morphism, residualized-by, pipeline-by,
authorized-by-capability, treaty-planned, classified-as, intrinsic-boundary,
world-port-exposes, and blocked-by. Node and edge ordering is sorted before the
graph fingerprint is computed.

## WorldPort Declarations

`BoundaryClosure.WorldPort` is an explicit open boundary that World must
implement. It declares a label, kind, effect-shape ref, the exact exposed
host-intrinsic ref, expected protocol/site/op shape, usage/branch/replay
summaries, required evidence refs, tags, and metadata. Built-in kinds cover host
tools, models, files, humans, randomness, clocks, foreign systems, test
fixtures, and custom ports.

A world port is not an implementation. It is a typed declaration that an allowed
host intrinsic or open effect is intentionally outside Boundary.

## Strict Closed Vs World-Boundary Policy

`BoundaryClosure.Policy.strictClosed()` requires all effect shapes to be closed
inside Boundary. It rejects host intrinsics, unknown bodies, unresolved
ambiguity, and world ports.

`BoundaryClosure.Policy.worldBoundary()` allows explicit world ports and
allowlisted host intrinsics while still rejecting unknown bodies and implicit
open effects. `testFixture()` admits declared test-fixture intrinsics for test
surfaces. `auditOnly()` records evidence and blockers with minimal rejection.

Policy also controls runtime-guard acceptance, provider-program preference,
declarative morphism requirements, ambiguity rejection, kernel primitive
allowance, maximum morphism hops, and maximum nested provider depth.

## Nested Program-Backed Providers

Program-backed providers are Boundary-native provider bodies. A closure pass can
include the handler program ref and inspect the handler program contract for
nested operation and after sites. Those nested shapes are then planned with the
same provider, morphism, capability, policy, and world-port rules as root sites.

Closure uses depth and cycle bounds to avoid pretending mutually recursive or
unbounded provider graphs are proven closed. Exceeding those bounds yields
machine-readable blockers.

## Host Intrinsics

Function-backed providers, dynamic mapper functions, host tools, host humans,
host models, files, randomness, clocks, and foreign systems are host intrinsics.
They may remain in a configured graph only when policy permits them and the
specific intrinsic is allowlisted or exposed through a matching world port.

Unknown semantic bodies are blockers under strict and world-boundary policies.
Kernel primitives are classified separately from host intrinsics.

## Blockers

Closure blockers lower to `Program.Evidence.Blocker` with source subsystem
`boundary_closure`. Blockers cover missing roots or catalogs, unhandled effect
shapes, missing capabilities, ambiguous static treaty plans, rejected intrinsics,
unallowlisted intrinsics, unknown bodies, dynamic mappers, unsupported
residualization or pipeline shapes, missing or mismatched world ports, runtime
guards forbidden by policy, depth limits, and cycles.

Reports and certificates keep blocker refs so failed analyses remain
machine-readable.

## How World Consumes Certificates

An adjacent World interpreter should read:

- root program refs
- effect-free root refs, when a referenced root intentionally has no yield sites
- provider harness/provider refs
- static treaty plan refs
- world-port declarations
- intrinsic allowlist evidence
- closure policy summary
- graph/report/certificate fingerprints
- blockers and evidence dependencies

World should not treat the certificate as cryptographic authorization. It is a
deterministic semantic witness that the Boundary portion is closed, or that the
only open parts are explicit world ports.

A root ref by itself is not a proof. If a root program is included, closure must
also include its extracted effect shapes, or list that same ref in
`effect_free_root_refs` to make the absence of yield sites explicit.

## Examples

The executable examples cover the three intended proof surfaces:

- `zig build run-boundary-closure-strict` proves a root approval effect is
  closed by a program-backed provider under strict policy.
- `zig build run-boundary-closure-nested` proves root and nested provider
  effects with separate closure certificates.
- `zig build run-boundary-closure-world-port` shows strict host-intrinsic
  rejection and world-boundary acceptance through an explicit world port.

## Non-Goals

Boundary Closure does not add scheduling, async runtime behavior, storage,
networking, transport, provider lifecycle management, service discovery, actual
host intrinsic execution, retries, a parser, source language, public VM API,
Artifact API, signing, encryption, security claims, new effect semantics,
receipts, membranes, settlement, public-root widening, `ProgramValue` widening,
serializable request tokens, cross-thread sessions, arbitrary host serialization,
host context serialization, allocator serialization, or thread serialization.
