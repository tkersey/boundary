# Generalized effects proof core

This is the in-progress replacement defined by [CONTRACT.md](CONTRACT.md).
Lean 4.33.1 with bundled Std checks a signature-parametric symbolic source and
its separately defined first-order representation. The complete five-contract
milestone remains unfinished; passing the current proof build does not establish
all of its acceptance requirements.

The source represents authored computations, lexical environments, effectful
clauses, and higher-order continuation functions. The target represents code,
closure environments, handler attachments, and return stacks as inspectable
first-order data. Its control fields contain no source-evaluator callbacks.
The translation is total over the typed source syntax. Pure leaf data and
primitive value-or-fault outcomes remain an explicit abstract interface;
internal control, resource, region, and ownership references are structural.

## Checked laws and their current scope

| Contract | Main proof surfaces | Checked content and limits |
| --- | --- | --- |
| D: defunctionalization | `GeneralizedValues`, `GeneralizedReification`, `GeneralizedOwnedOperandLowering`, `GeneralizedProgramSimulation`, `GeneralizedProgramObservations` | Closure/environment and context laws, recursive call unfolding, positive finite operand drains, and preservation/reflection of finite **ordinary** observations. Open requests retain related typed futures under every accepted response. Full stateful observation composition remains open. |
| H: handlers | `GeneralizedSelection`, `GeneralizedForwarding`, `GeneralizedHandlerEntry`, `GeneralizedControlExecution`, `GeneralizedSuccessor`, `GeneralizedInjectionExecution`, `GeneralizedFreshHandlerExecution` | Nominal selection and forwarding, deep/shallow capture, effectful clause entry, distinct body/answer types, successor handling, non-tail resumption, and use-site injection have local correspondence laws. Installation computes fresh support-aware identities. Remaining scoped and multi-use composition is unfinished. |
| U: use and scope | `GeneralizedFields`, `GeneralizedOwnership`, `GeneralizedControlStore`, `GeneralizedScopes`, `GeneralizedScopeCapture`, `GeneralizedResources`, `GeneralizedTemplates`, `GeneralizedStateExecution` | Actual owning occurrences preserve multiplicity across control stores, closures, cells, and retained containers. Local transfer, one-shot consumption, packaging, release, scope/borrow, resource-authority, and computed template-instantiation laws are checked. Stateful region entry is connected to cell allocation. Full lifetime closure and remaining activation/composition laws are open. |
| X: exits | `GeneralizedOperandPrefix`, `GeneralizedExit`, `GeneralizedStatefulCleanup`, `GeneralizedExitCompletion`, `GeneralizedUnwinding`, `GeneralizedRegionRetirement` | Ordered handoff, retained cleanup cursors, single initiation, first cancellation reason, failure precedence, cleanup completion, and finite outer-unwinding order are checked. Cell-held control can transfer into saved-context disposal; plain cells remain readable for later cleanup. Final region/resource lifetime closure remains open. |
| O: observation and relocation | `GeneralizedInteraction`, `GeneralizedObservations`, `GeneralizedCodeRelocation`, `GeneralizedOwnedRelocation`, `GeneralizedExitRelocation`, `GeneralizedRuntimeSupport` | Local laws distinguish logical request openings from polling, preserve typed response reentry, and transport finite supported identities through values, code, captures, and control stores. Full composition over the remaining stateful mechanisms is unfinished. |

`BoundaryV2.lean` exports the generalized modules and their distinguishing
examples. The older `Lowering`, `Control`, `ControlLowering`, `Ownership`,
`Regions`, and `Effects*` models are retired from the active tree. Their single
operation family, pure-clause/shared-dispatcher interpretation, and sole-token
custody model are not used to justify the generalized claims. Their source
remains available at baseline commit
`55e8feedcae0b9ee1492da11f9fbd4a1ac7ff328` and in the donor history. The ordinary
production regressions remain active, including State/Choice, recursive calls,
non-tail handlers, and disposal/transfer cases.

Local capture/support and lifetime premises delimit the claims. The core does
not prove that every production source checker or saved-state validator
establishes them. Borrowed references remain distinct from physical owners;
copyability of a computation does not grant permission to duplicate exclusive
captures or exit obligations. Consistent relocation is a logical renaming law,
not a codec or hash-injectivity theorem.

Package and unpackage now execute in the common control/cell state through
`GeneralizedPackages` and `GeneralizedPackageExecution`. Packaging transfers the
operand's actual owning fields into a fresh-grant container; unpacking consumes
only that outer grant before returning its contents. The package and cell
operations share `GeneralizedValueHandoff`. Borrow retention and lifetime checks
remain separate scope obligations; sealing a value does not extend its lifetime.

## Verification commands

From the repository root:

```sh
zig build check-v2-formal -Doptimize=ReleaseSafe -j2 --summary all
zig build check-v2 -Doptimize=ReleaseSafe -j2 --summary all
zig build check-v2-conformance -Dworld-source="$WORLD_CHECKOUT" -Doptimize=ReleaseSafe -j2 --summary all
```

For focused proof development, run `lake --wfail build` in this directory.
`check-v2-formal` discovers project modules, enforces logical trust, runs trust
mutations, and performs fresh kernel replay. `check-v2` includes that gate and
the existing Boundary-only checks. World is required only by the explicit
conformance command. Ordinary compiler/data imports continue to require only Zig.

`check.mjs` discovers every project `.lean` file except generated `.lake`
contents. Explicit Lake roots build orphan files even outside `BoundaryV2`.
`Trust.lean` uses Lean's declaration provenance and follows types, bodies, and
inductive constructors transitively. Private declarations and unused definitions
are included. The only permitted axioms are `propext`, `Quot.sound`, and
`Classical.choice`. Unsafe or partial logical definitions reject; recognized
executable companions of safe recursive definitions contribute no logical
permission to depend on unsafe code. The checker is executable tooling and
cannot become a semantic dependency.

Fresh replay uses Lean 4.33.1's `Lean.Environment.replay` API with an empty
kernel environment at trust level zero. The isolated mutation suite accepts a
valid orphan and rejects private unfinished proofs, hidden axioms, unfinished
definitions, native-evaluation dependencies, unsafe definitions, and partial
definitions. The final five exported claim types and claim-weakening mutations
are still open; this logical trust gate is not a statement-meaning review.

## Production correspondence

The ordinary bridge uses public-builder programs, the normal compiler and
encoding path, an independent source oracle, and the user-approved unmodified
World commit `87698f92ca7be4d5442e97ba27a2468aa3ff6a7c`. It compares complete
native/WASM outcomes in fresh instances, preserves observable event order,
checks polling and response rejection, and alternates the restored backend.

The suite includes a [reproducible generated sample](../../test/v2/generated_programs.md)
with an explicit core-to-production mapping. Additional fixture mappings remain
to be completed. The [Linux workflow](../../.github/workflows/lean.yml) pins the
tools and World dependency and records clean proof-build and test costs.

These are kernel-checked laws about the Lean core and executable tests of the
production implementation. They are not universal Zig/World refinement,
verified BPI bytes, complete borrow inference, environmental correctness,
universal termination, or global replay protection. Whole-profile operational
replicas, codec/hash/schema theories, and production certification tooling are
excluded from this milestone, not deferred prerequisites.
