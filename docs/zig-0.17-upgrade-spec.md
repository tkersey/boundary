# Boundary · World · Agent — Zig 0.17.0 upgrade specification

**Document ID:** BWA-Z17-1  
**Version:** 1.0  
**Prepared:** 2026-10-03  
**Target toolchain:** Zig 0.17.0, the exact tagged release  
**Repositories:** `tkersey/boundary`, `tkersey/world`, `tkersey/agent`  
**Status:** Implementation specification. No repository was modified, compiled, or benchmarked while preparing this document. Requirements below are work to perform, not claims that the upgrade has passed.

> Upgrade the toolchain, reduce the cost of producing and qualifying portable programs, and strengthen the implementation's safety diagnostics—without weakening the calculus, changing portable contracts, duplicating the runtime, or manufacturing performance claims.

This is a single, self-contained execution contract. An implementer does not need the preceding chat to understand scope, sequencing, invariants, evidence, or completion. Repository source and the pinned toolchain remain the authorities for actual APIs and executable behavior. Source references at the end identify the inspected baseline; they are not replacements for the requirements restated here.

## Contents

1. [Outcome and decision policy](#1-outcome-and-decision-policy)
2. [Inspected baseline and authority](#2-inspected-baseline-and-authority)
3. [Architectural invariants and exclusions](#3-architectural-invariants-and-exclusions)
4. [Toolchain and dependency identity](#4-toolchain-and-dependency-identity)
5. [Complete migration census](#5-complete-migration-census)
6. [Language, reflection, and representation migration](#6-language-reflection-and-representation-migration)
7. [Build graph, configuration cache, and package storage](#7-build-graph-configuration-cache-and-package-storage)
8. [Boundary implementation work](#8-boundary-implementation-work)
9. [World implementation work](#9-world-implementation-work)
10. [Agent implementation work](#10-agent-implementation-work)
11. [Structured build information and incremental development](#11-structured-build-information-and-incremental-development)
12. [Performance attribution and promotion](#12-performance-attribution-and-promotion)
13. [Compatibility, platforms, and delivered artifacts](#13-compatibility-platforms-and-delivered-artifacts)
14. [Required acceptance and mutation cases](#14-required-acceptance-and-mutation-cases)
15. [Evidence contract](#15-evidence-contract)
16. [Implementation packages and landing order](#16-implementation-packages-and-landing-order)
17. [Execution procedure and commands](#17-execution-procedure-and-commands)
18. [Failure, rollback, and release procedure](#18-failure-rollback-and-release-procedure)
19. [Definition of done](#19-definition-of-done)
20. [Source register](#20-source-register)

---

## 1. Outcome and decision policy

### 1.1 Required outcome

Deliver a coordinated Zig 0.17.0 successor of the existing stack with:

- All maintained source, build entrypoints, fixtures, package consumers, scripts, and CI migrated to the selected toolchain.
- The existing portable authoring, compilation, linking, execution, state transfer, ownership, cancellation, and authority contracts preserved.
- A newly produced and independently acquired World runtime bundle, with Agent bound to the exact qualified compiler/runtime tuple.
- Native safety diagnostics around real borrowing and allocation boundaries, without replacing the bounded production allocator architecture.
- Measured evaluation of build caching, emitter reuse, reflection demand, incremental development, structured build information, alternate WASM code generation, and the existing optimizer's economics.
- One concise retained acceptance report, machine-readable measurements, and reproducible commands identifying exactly what passed and what did not.

The upgrade is not complete when the three top-level manifests merely say `0.17.0`, when a local `zig build` succeeds, or when one synthetic benchmark improves.

### 1.2 Required implementation versus required investigation

**Mandatory implementation:** compatibility repairs; correct compiler propagation; complete dependency/profile migration; package-path correctness; retained authentication; appropriate borrowing diagnostics; new regression tests; exact-artifact qualification; documentation and CI updates.

**Mandatory evaluated opportunities:** each experiment in Section 12 must be performed to a deciding result. A useful change is implemented and qualified. A candidate that is slower, redundant, unsafe, or unsupported is rejected with evidence and no dormant production implementation. A technically unavailable experiment remains explicitly blocked unless a platform exclusion is approved; inability to run is not a successful experiment.

**Conditional promotion:** alternate WASM backend, production optimizer retuning, a resident Agent path, and an incremental workflow become defaults only after their specific gates pass. They are not prerequisites for obtaining a usable compatibility-only 0.17 successor. They are prerequisites for claiming this entire specification has been evaluated.

This distinction prevents both shallow “upgrade completed” claims and permanent accumulation of speculative code.

### 1.3 Decision rules

**Z17-D01 — Preserve observations.** Correctness, authority, cleanup, canonical interchange, and failure atomicity outrank speed.

**Z17-D02 — Preserve attribution.** Distinguish native tool compilation, execution of Boundary's compiler, execution in World, and complete Agent consumer behavior.

**Z17-D03 — Prefer deletion and reuse.** Extend an existing owner before adding a helper; add a helper only when it removes demonstrable duplication or encapsulates a real invariant. Do not build a new migration framework, repository coordinator, compiler service, or performance database.

**Z17-D04 — No automatic budget inflation.** Keep optimizer work bounds, memory allowances, parser/worker limits, stack size, interruption rules, and security ceilings unchanged in the compatibility comparison.

**Z17-D05 — Costs need fresh decisions.** Historical acceptance of earlier optimization costs does not authorize new upgrade regressions. Necessary compatibility costs must be disclosed and explicitly accepted before production promotion when material under Section 12.

**Z17-D06 — Evidence rather than ceremonial counts.** Reuse existing tests that prove the requirement. Add missing discriminating cases, not redundant wrappers. Review scope follows the changed invariants; this specification adds no arbitrary number of review rounds.

## 2. Inspected baseline and authority

### 2.1 Observed repository heads

These exact default-branch heads were observed while preparing this specification:

| Repository | Observed commit | Declared package version | Minimum Zig |
|---|---|---|---|
| Boundary | `93340dade30b7d27a1e139f107359f91fb66fad3` | `3.0.0-dev.0` | `0.16.0` |
| World | `4b5e312152499d2cc4cc19b723df10918ad5d71b` | `6.0.0-dev.0` | `0.16.0` |
| Agent | `b1f9d2866b5717d16339e7022a3b4d08951f0770` | `4.0.0-dev.0` | `0.16.0` |

Sources: [B0], [W0], [A0], [B1], [W1], [A1]. These are observation anchors, not instructions to reset newer work. At execution, inspect current branches, outstanding relevant changes, repository instructions, and the current Zig skill. Rebase the work onto the selected current baseline; do not merge old assumptions into it.

### 2.2 The stack has more than one Boundary identity

At the observed heads, World pins Boundary `511fe388587b36ae37307d277e04c22b0bb6f6d9`; Agent pins Boundary `65f46131f366bdd21aa98701f4110ecb801d2c8d`. Agent's dependency lock names World source `a48d5fd0cb2d4fcbe79bc3188f354d7d036d29f5`, not the observed World head. The lock's kernel SHA-256 is `9627eb1e66239119bccb4ddcd43b4f6c757180dab930a9feb276671262f735d1`. [W1] [A1] [A4]

**Z17-B01.** Record separately: Boundary's authoring/compiler source, World's Boundary-data dependency, World's runtime source, the delivered kernel, Agent's source, and Agent's authenticated consumer lock. A valid dependency tuple need not use the same Boundary commit for authoring and runtime data.

**Z17-B02.** Do not ascribe benefits from adopting newer World resident changes to Zig. Preserve two comparisons where needed:

- **C0:** Agent's actual pre-upgrade locked consumer tuple, as delivered.
- **U0:** The coherent, qualified 0.16 tuple selected as the immediate source-level predecessor of the migration.

If current-source reconciliation is needed to obtain U0, measure and describe `C0 → U0` separately. The compiler migration is `U0 → U1`, where U1 has only necessary 0.17 compatibility changes. Later experiments derive from U1. Do not silently substitute repository heads for locked consumer inputs.

### 2.3 Concrete implementation surfaces

The inspected code supplies these starting points:

| Owner | Existing surfaces | Upgrade focus |
|---|---|---|
| Boundary | `build.zig`, `build.zig.zon`, `src/data/root.zig`, `src/source.zig`, `src/authoring.zig`, `tools/component_link.zig` | Pure-data imports, native emitters, source-independent linking, reflection, independent checking |
| World | `build.zig`, `src/interpreter_v2/store.zig`, `src/interpreter_v2/activation_slots.zig`, `src/kernel/main.zig` | Host/guest module graphs, retained storage, rollback, generic kernel |
| World delivery | `src/node/runtime-prepare.mjs`, `runtime-bundle.mjs`, `runtime-acquire.mjs`, `runtime-smoke.mjs` in the same directory | Compiler identity, package resolution, verified-byte execution, profile admission |
| Agent | `build_agent4.zig`, `src/contracts.zig`, model codec/catalog/authoring files | Reflection-based portable contracts, authoring-only dependency admission |
| Agent integration | `runtime/world.mjs`, `tools/agent4/dependencies.mjs`, `tools/agent4/economy.mjs`, `conformance/agent4/dependencies.lock.json` | Actual fresh path, replay, exact compiler/runtime identities |

Sources: [B2]–[B5], [W2]–[W7], [A2]–[A6]. Follow imports and invocations from these files. The list is not an exhaustive census.

### 2.4 Release facts versus implementation authority

The release notes identify reflection and optimization-name changes; logical-bit casts; declaration visibility and syntax changes; allocator updates; build argument/path APIs; configuration caching; package-path controls; a build protocol; Linux incremental compilation; and alternate WASM progress. They also record ZLS incompatibility, a Run response-file regression, and disabled LLVM loop vectorization. [Z1]

**Z17-B03.** Use the exact release distribution's standard library and command help to settle signatures. Do not copy development-branch APIs or treat an earlier assistant example as executable authority. The preparation environment did not run Zig; all snippets and new entrypoints below require implementation and execution before being declared available.

**Z17-B04.** Discover new applicable release issues at implementation time. A compiler defect must get a minimal reproducer and an isolated response; it must not be “fixed” by weakening a semantic assertion.

## 3. Architectural invariants and exclusions

### 3.1 Ownership of responsibilities

**Z17-I01 — Boundary remains the portable construction/compiler owner.** Typed authoring, source terms, checking, transformations, component linking, pure data, and canonical encodings stay in Boundary. No production evaluator, host loop, parser for a new source language, environmental I/O runtime, or application-specific native driver is added there. The current README explicitly places production execution in World. [B6]

**Z17-I02 — World remains the execution owner.** Preserve one generic interpreter and its native/WASM implementations of the same contract. Do not create an application-specific WASM module, second guest execution semantics, per-agent opcode family, or second state model.

**Z17-I03 — Agent remains an authoring and consumer layer.** Preserve authoring without a World runtime dependency. Provider/tool effects remain explicit host responsibilities. Native Zig closures, function addresses, pointers, and native stack frames must not become portable continuation representations.

**Z17-I04 — Public surface is constrained.** Do not widen Boundary's public root or portable program/value representation simply to accommodate compiler API churn. Do not revive retired raw authoring facades or duplicate an existing exchange/custody implementation.

### 3.2 Semantic obligations

The successor must preserve all applicable existing distinctions:

- Structural versus semantic compilation contracts; exact stepping where promised and external-observation equivalence where that is the contract.
- Nominal operation/capability identity, handler scope and depth, dynamic installation, and authority boundaries.
- Ordered evaluation, first failure, checked arithmetic, lazy demand, memo identity, and independent mutable cells.
- Linear/one-shot continuation use and every already supported multi-shot or cloning case; do not introduce or remove a continuation mode as part of migration.
- Capture schemas, retained environments, lifetime and escape restrictions, owned resources, pending bindings, cleanup ordering, and suspending disposal.
- Valid state restoration relative to the same image, rejection relative to a wrong image, deterministic canonical serialization, and unchanged retries after rejected operations.
- Existing optimizer admission, independent validation, no-growth obligations where applicable, fallback/no-op behavior, and deterministic bounded work.

These are retained obligations of the existing implementation, not a demand to prove arbitrary programs correct or support previously rejected constructions. Boundary's consolidated acceptance identifies the current checker and interaction surfaces. [B5]

### 3.3 Non-goals

No agent-travel architecture implementation; no new persistence system or database; no runtime relocation ABI; no new repository; no universal reflection adapter; no speculative allocator replacement; no unrelated provider SDK upgrade; no new GPU path; no arbitrary integer-width redesign; no permanent remote build infrastructure.

Do not bump BMO1, BPI3, PST3, invocation grammars, or World ABI 3 merely because the compiler changed. A package/toolchain version and a wire/ABI version are separate decisions. Any genuine wire-contract change is outside this compatibility migration and requires a separately approved specification.

### 3.4 Three different compatibility obligations

Keep these distinctions explicit throughout implementation and reporting:

**Encoding compatibility:** encoding the same logical record under an unchanged wire contract produces the same canonical bytes. Codecs do not optimize records while reading or writing them.

**Compatibility-only compilation:** U0 and U1 use the same compiler policies and authored inputs. Deterministic published program/component/descriptor bytes are expected to agree. An unexplained difference blocks a compiler-only claim even when a few executions happen to agree.

**Deliberately retuned compilation:** a separately qualified E08/F optimization may intentionally produce a different valid program image without changing its wire format. Record the new image identity, independently validate the transformation, and compare according to the structural or semantic observation contract. Never restore old-image state into a different optimized image merely because both came from equivalent source. A new image does not imply a new wire version.

## 4. Toolchain and dependency identity

### 4.1 Select once and propagate

**Z17-T01.** Resolve the compiler at the outermost repository-owned entrypoint to an absolute executable path. Verify its reported version is exactly `0.17.0` for qualification. Record the executable digest and the distribution/archive identity. Include the standard-library distribution identity: hashing only the executable does not identify a mutable library tree.

**Z17-T02.** In a Zig build, derive child compiler invocations from the running build's compiler identity using the verified release API. In JavaScript/shell entrypoints, propagate that same selected executable explicitly. Never rediscover `zig` from `PATH` halfway through a run.

**Z17-T03.** Extend the existing producer/qualification CLIs with `--zig-exe ABSOLUTE_PATH` where an explicit selection is absent. This is a proposed repository-owned option, not a claim that it exists today. Standalone invocation may resolve a default once; strict qualification rejects a nonabsolute explicit path or unexpected version. A nested build's selected compiler is authoritative. Reject conflicting selections rather than choosing silently.

**Z17-T04.** Freeze the complete compiler distribution for the run. Symlink resolution alone is insufficient if the target can change. Use the existing trusted immutable tool installation or an owned verified copy; record pre/post identity. A changed toolchain invalidates the run. Do not claim resistance to a hostile same-user process beyond what this mechanism actually provides.

**Z17-T05.** Test a poisoned `PATH` containing a fake or alternate `zig`: direct builds, Node wrappers, nested fixture generation, package hashing, and runtime preparation must use the selected compiler or fail before publishing artifacts.

### 4.2 Package and source identities

**Z17-T06.** Update maintained `.minimum_zig_version` declarations to `0.17.0`; pin exact 0.17.0 in qualification setup and CI. The manifest minimum is not an exact-version enforcement mechanism. Reject unqualified development versions in the producer. Do not add cross-version compatibility branches to production just to keep U0 runnable; use separate worktrees and binaries.

**Z17-T07.** Preserve package names and fingerprints. Compute new package hashes with the selected toolchain. Retain separately the source commit/tree, source archive digest, complete source inventory, Zig package hash, extracted package inventory, runtime inventory, kernel digest, and delivery descriptor digest. Do not reuse an old hash after changing package contents.

**Z17-T08.** Keep the distinct `zig-managed` and `archive-extracted` inventories where Agent currently requires them. Different mode bits or packaging behavior must be measured, not normalized away to force equality. Recompute against the actual selected package representation. [A4]

**Z17-T09.** Maintain existing source cleanliness and raw Git-object rules. Disable replacement refs when deriving source identity and exporting archives. Branch names and local paths are locators, not authorities.

### 4.3 Canonical optimization profile

**Z17-T10.** Use one closed internal profile definition to drive compilation and describe the newly produced artifact. The target semantics remain native safe/debug test lanes and a size-oriented production WASM kernel; spelling changes must not accidentally select a different behavior.

Use the release's `std.lang.Optimize` values `debug`, `safe`, `fast`, and `small` in live Zig code and verified CLI options. [Z1] Record the actual compiler arguments and resolved backend/linker/CPU features in qualification evidence.

For newly produced World manifests, retain the existing manifest format where its schema permits the new closed values; encode the actual new compiler and mode names. Update producer, verifier, tests, and Agent consumer policy together. Reject unknown modes and inconsistent combinations. Historical manifests remain immutable and are verified with their matching historical verifier for rollback. Do not make a new verifier accept arbitrary old/new profiles through permissive string normalization.

World currently hard-codes the old compiler and mode profile on both sides of delivery. This must be repaired as a coordinated admission change, not a README edit. [W5] [W6]

### 4.4 Artifact trust

The selected source/compiler can produce a candidate, but cannot certify its own bytes by emitting an untrusted expected hash next to them. Expected artifact identities must enter the consumer through the existing trusted lock/delivery selection. Preserve verification of bounded bytes before execution, private verified copies where used, extraction limits, destination ownership, and ready-directory publication only after successful qualification.

## 5. Complete migration census

**Z17-C01.** Before patching, produce a machine-readable census using tracked files, import reachability, build graphs, and script invocation discovery. Classify each hit as `maintained`, `frozen-evidence`, `historical`, or `unreachable-awaiting-removal`. Every exclusion requires a path and rationale. Historical text is not active compatibility debt.

Inspect all nested `build.zig` and `build.zig.zon` files, generated fixture source, templates, tool scripts, workflow/setup files, examples, exported modules, installed package paths, negative-compilation harnesses, source inventories, benchmark drivers, and runtime producer/verifier inputs.

### 5.1 Search families

The following are census seeds, not proof of completeness:

| Family | Search seeds / places to inspect | Required disposition |
|---|---|---|
| Toolchain | `0.16.0`, version gates, tool installers, caches, executable discovery | Migrate live ownership; preserve dated evidence |
| Optimization | `OptimizeMode`, legacy mode tags/strings, builtin optimize checks | Migrate live API/CLI and exact delivery admission |
| Reflection | `@typeInfo`, `std.meta.fields`, `.fields`, field defaults/alignment/comptime metadata, type construction | Review by type kind and consumer contract |
| Declaration detection | `@hasDecl`, wrapper markers, internal reflection helpers | Preserve public protocol and internal intent |
| Representation | `@bitCast`, `@ptrCast`, `@alignCast`, packed/extern types, byte views, integer widths | Classify bit semantics versus memory layout versus wire encoding |
| Syntax/builtins | array repetition, `void{}`, captured `errdefer`, `i0`, C import, backing-integer conversions, ceiling division | Compile and behavior-check each applicable migration |
| Containers/allocators | ArrayList accessors, pointer locks, debug allocator, stack fallback, managed bit sets | Preserve ownership and allocation/failure behavior |
| Library APIs | allocated formatting, format escaping, ZON parsing, URI/host conversion, target builtins, float equality | Inspect API, ownership, and silent semantic differences |
| Build paths/args | artifact/file/directory/output/dependency arguments, root access, eager LazyPath resolution, `b.args`, format paths | Migrate graph semantics and arguments, not just method names |
| Configuration | filesystem reads, existence tests, environment use, program lookup, directory scans | Track every decision input or explicitly remain uncacheable |
| Package stores | `zig-pkg`, custom local roots, global caches, fetched paths, cleanup code | Resolve selected storage; prohibit unsafe cleanup |
| Integration | source overrides, copied dependencies, extracted archives, generated imports, authoring admission modules | Retain exact authentication and graph prerequisites |
| Regressions | response files, compiler panic paths, target-specific features, editor tooling | Applicability plus executed witness or documented exclusion |

For release-specific changes, consult the corresponding sections of [Z1] and the installed standard library. Do not use one textual substitution across heterogeneous reflection types or argument APIs.

### 5.2 Completeness and scope control

**Z17-C02.** A zero-result code search is only evidence about that search. Compile exported module consumers and instantiate generic APIs; Zig's lazy analysis can leave broken declarations unexamined in a top-level build.

**Z17-C03.** Do not rewrite frozen source-free producer fixtures to make the successor consume them. Preserve their bytes and original compiler provenance. When a historical producer must be rerun, use its original worktree/toolchain. Generate new successor fixtures separately.

**Z17-C04.** Remove truly dead live code rather than porting it mechanically, but prove it is not an exported contract, packaged consumer, negative witness, or reproducibility input.

**Z17-C05.** Finish with a reverse census: every remaining live old-toolchain/API occurrence is explained, every maintained build entrypoint is executed, and every skipped lane is visible. Do not gate on zero textual occurrences across historical documentation.

## 6. Language, reflection, and representation migration

### 6.1 Reflection is a semantic migration

**Z17-L01.** Migrate struct/union traversal to the new metadata representation; where only names and types are needed, traverse `field_names` and `field_types` directly. [Z1] Do not reconstruct legacy aggregate field objects globally. Do not assume enum, pointer, array, optional, and function reflection changed in the same way.

**Z17-L02.** Preserve declaration-order traversal, field-to-type correspondence, tuple field names, accepted field properties, and union payload correspondence. Distinguish a variant's declaration ordinal from its explicit numeric tag. Never replace the current encoding convention with a guessed tag scheme.

**Z17-L03.** For every generic encoding/checking path, retain positive and negative instantiations for empty and nonempty structs, tuples, nested products, optional values, arrays, slices, supported enums, and tagged unions. Include unusual explicit tag values and differently ordered declarations. The expected accepted set is the pre-upgrade contract, not a new convenience subset.

**Z17-L04.** Agent's compile-time-field, integer-width, pointer/sentinel, tagged-union, bounds, and text validation must remain enforced. Unsupported values must remain unsupported even if the new reflection APIs make them easier to represent. [A3]

**Z17-L05.** Preserve lexical nominal identity, independent mutable instances, recursive descriptors, and lifetime checking across source construction. Do not replace semantic identity with a type name or hash alone.

**Z17-L06.** Keep independent transformation validators independent. Sharing passive records is allowed where it already matches ownership; sharing candidate discovery, expected-output generation, or the same potentially faulty transformation is not an acceptable shortcut. A deliberately wrong-but-admissible candidate must still fail independent checking.

### 6.2 Declaration detection

**Z17-L07.** Audit each declaration-existence check. For external marker protocols, ensure intended markers are explicitly public. For same-file internal dispatch, use an explicit local mechanism rather than making internals public solely to preserve a lookup. Test same-file and imported use. Agent's inspected portable wrapper markers are already public; do not widen its whole namespace. [A3]

### 6.3 Bit representation and canonical encoding

**Z17-L08.** Classify each representation operation into exactly one purpose: logical-bit reinterpretation, in-memory/ABI inspection, or portable wire encoding. Migration must preserve that purpose. Do not fix a cast error by blindly substituting a pointer cast.

Logical-bit conversion is not a portable wire encoder. Use the existing explicit byte order and canonical encoder for wire bytes. For actual memory reinterpretation, prove alignment, bounds, lifetime, initialization, aliasing, and the intended host dependency.

**Z17-L09.** Test arrays/vectors and non-byte-width integers at compile time and runtime where used. Cover integer extremes, high bits, cross-element patterns, and zero lengths where legal. Inspect packed and extern structures separately. Do not assume `@sizeOf` is a logical-bit count or that host padding belongs in serialized data.

**Z17-L10.** Execute cross-engine byte goldens and byte-order tests. Compile a big-endian representation witness and execute it through a supported emulator when available; classify compile-only evidence accurately. A missing emulator does not license byte casts. Existing canonical little-endian or other protocol-specified bytes remain the authority on every target.

**Z17-L11.** Compare old/new codecs both directions on frozen valid and malformed bytes. Keep duplicate schema, unknown tag, noncanonical value, truncation, excess data, and wrong-image rejection witnesses. A successful round trip through two mutually wrong new functions is insufficient.

### 6.4 Syntax, cleanup, arithmetic, and library ownership

**Z17-L12.** Review formatter-generated migration patches. In particular, an array pattern with multiple repeated elements must preserve the full pattern; treating every repetition as a scalar fill is invalid. Check zero, one, and several repetitions.

**Z17-L13.** Error-handling repairs must preserve cleanup ownership and ordering, original error identity, cancellation behavior, and allocation-failure atomicity. Moving error reporting to an outer catch must not omit cleanup, report twice, or substitute a success result.

**Z17-L14.** If ceiling-division helpers are simplified, preserve zero-divisor rejection, overflow handling, signed rounding, and the caller's error contract. Do not replace checked arithmetic with a builtin whose preconditions are merely assumed on untrusted input. Exercise page/capacity values immediately below, at, and above allocation boundaries.

**Z17-L15.** When changing allocator, stack fallback, formatting, or parsing APIs, explicitly retain who owns outputs and diagnostics, when buffers die, and which allocation failures propagate. Preserve malformed-input limits and diagnostics bounds. Do not copy borrowed values out of a short-lived parsing arena without ownership transfer.

**Z17-L16.** Audit equality semantics independently of representation. Where floats occur, test NaNs, signed zero, and aliased versus distinct slices according to the declared contract. Do not turn numeric equality into byte identity, or add floats to Agent's portable types, merely to accommodate a library change.

**Z17-L17.** Audit formatting and URI changes wherever output is hashed, parsed, used as a path, or security-checked. A diagnostic string may change deliberately; authenticated canonical bytes may not change incidentally. Host validation must remain explicit at the proper network boundary.

**Z17-L18.** Update other applicable removals/deprecations from the census in live code. Do not add C translation, GPU, or platform machinery where no owned usage exists. Record absence rather than create a demonstration feature.

## 7. Build graph, configuration cache, and package storage

### 7.1 Preserve the graph while migrating its APIs

**Z17-G01.** Patch artifact/file/directory/output argument APIs using the installed release definitions. Preserve executable versus data argument roles, dependency edges, generated-path lifetimes, working directories, environment, captured output, output prefixes, and execution prerequisites. New calls must compile; a guessed options struct is not an implementation.

**Z17-G02.** Preserve pass-through argument order and quoting. Test empty arguments, spaces, Unicode, a leading dash after the separator, repeated arguments, and a changed value. Runtime arguments must not accidentally become configuration decisions or change unrelated compile steps.

**Z17-G03.** Separate host tools from target artifacts. Every generator and native test executable must run on the build host; guest modules must use the requested target, CPU features, optimization, and imports. Do not share one target-configured module instance between incompatible host/guest graphs. Test cross-target invocation on both required host platforms.

**Z17-G04.** Keep exported pure-module and authoring-only paths independent of browser tools and runtime downloads. Selecting a data-only or authoring-only target must not require unrelated runtime facilities. Preserve transitive admission prerequisites for downstream module consumers.

### 7.2 Configuration purity versus make-time verification

**Z17-G05.** Enumerate every input that affects graph construction. Declare file-content, file-metadata, directory-entry, or directory-metadata dependencies as appropriate using the release APIs. Environment values that affect decisions need an explicit tracked option or the supported dependency mechanism. Use lazy tool resolution when existence/output is not a configuration decision.

**Z17-G06.** Do not confuse a make-time side-effectful check with configuration side effects. A reusable graph may still need to execute authentication on every invocation. Preserve that distinction and prove it with a warm-cache mutation test.

**Z17-G07.** Do not force cache purity by ignoring untracked inputs, suppressing poisoning, or labeling an effectful command pure. If an unavoidable decision cannot be tracked, retain honest invalidation and document the residual cost.

**Z17-G08.** Test invalidation for source contents; imported build files; added, removed, and renamed source-inventory entries; dependency locks; selected compiler/distribution; target; optimization; source override; package root; output prefix; and tool selection. Test permission changes wherever executable intent is part of the graph or authentication.

A cache hit is accepted only when the successor output and required checks match a fresh build with the same declared inputs. A cache miss alone is not a defect; a false hit is.

### 7.3 Package-root resolution and cleanup

**Z17-G09.** Resolve the effective local package root explicitly for every producer/consumer. Support a controlled default and explicit alternate root; honor or deliberately override the selected package-path configuration with clear provenance. The producer must not fetch into one location and then authenticate a hard-coded sibling directory.

World currently locates its dependency under `source/zig-pkg/...`; its isolated source export and package discovery must be reconciled with the chosen root. [W5]

**Z17-G10.** Hermetic qualification uses run-owned local and global roots. Set those roots for all nested commands. Normal user-facing commands may use a supplied external store but must never erase, rewrite wholesale, or silently reinterpret it as run-owned scratch.

**Z17-G11.** Cleanup is confined to directories positively created and owned by the current run. Refuse the filesystem root, home, repository root, parent escapes, and unexpected symlink traversal. Never delete a custom store or follow a symlink to shared storage. Retain bounded failed evidence and remove only known disposable intermediates.

**Z17-G12.** Exercise: default local store, explicit external store, a path containing spaces, environment-selected store, symlinked store, empty global cache, prepopulated cache, missing dependency offline, and authenticated dependency available offline. Preserve the supported original local/global behavior; no success may depend on a developer's hidden cache.

### 7.4 Tool provenance and resource limits

**Z17-G13.** Keep Node, browser engines, Wasmtime, package-manager locks, and platform/tool versions fixed in compiler-only comparisons. Tooling upgrades required for compatibility are separate measured changes. Record environment differences; never attribute their benefits to Zig.

**Z17-G14.** Keep bounded subprocess output, timeouts, destination locking, and diagnostic storage. A missing tool is `blocked`, an executed nonzero check is `failed`, and an unselected check is `not-run`; do not collapse these states.

**Z17-G15.** Exercise long argument lists and any actual response-file use. A workaround must preserve exact arguments and generated dependencies without moving commands into an unbounded shell string. Minimize the workaround and retain a regression witness linked to the upstream issue.

## 8. Boundary implementation work

### 8.1 Compatibility surface

**Z17-BD01.** Migrate the complete maintained module graph, not just the root. Include `boundary_data` independently, typed authoring, compiler/optimizer machinery, standalone linking, all maintained emitters, native tests, WASM codec probes, public examples, and extracted package consumers.

**Z17-BD02.** Preserve the `data-only` path and ensure it cannot acquire a dependency on authoring, runtime execution, process APIs, or browser tooling. Compile a small external consumer importing only the published pure-data module. Compile separate consumers of the public authoring and linker contracts. [B2]

**Z17-BD03.** Apply Section 6 to structural equality, graph traversal, serialization, source ownership, typed declarations, and every optimizer traversal found by the census. Include `src/data/record_equal.zig` as a concrete starting point; its current structural recursion must not become pointer or raw-memory equality. [B3]

### 8.2 Reduce repeated native compilation

**Z17-BD04.** Attribute native compiler time by executable and its dependencies. Inventory emitter families that rebuild essentially the same compiler for different scalar configurations. Distinguish a genuinely different Zig type instantiation from an ordinary runtime construction argument.

**Z17-BD05.** Evaluate reuse of one emitter executable across ordinary construction inputs. A candidate is valid only when output, invalid-input behavior, source provenance, policy selection, and deterministic diagnostics remain correct. Retain compile-time negative tests and truly type-dependent emitters; do not replace them with runtime-only checks to make build numbers smaller.

**Z17-BD06.** Evaluate moving repeated non-type-dependent work behind existing ordinary record interfaces. Preserve typed construction at the boundary and use existing compiler/linker entrypoints. Do not introduce a generic trait layer, plugin system, bytecode frontend, shared-library ABI, or compiler daemon to obtain reuse.

**Z17-BD07.** Reused processes must reset per-invocation observations and diagnostics. No stale result, capture fact, policy, allocator ownership, budget consumption, or nominal identity may leak between independent emissions. Test valid→invalid→valid and two different configurations in one process against isolated executions.

### 8.3 Preserve independent checking and compilation economics

**Z17-BD08.** Keep the compatibility successor's optimization set, work bounds, candidate ordering, cost policy, and accepted semantics fixed. New compiler performance is measured before any optimizer tuning.

**Z17-BD09.** Use the existing corpus to compare phase costs: source construction, source validation, lowering, discovery, independent validation, candidate admission, final linking, and serialization. Do not infer a pass speedup from a smaller native executable or a faster Zig invocation.

**Z17-BD10.** Re-evaluate existing economic decisions only after the compiler-only baseline. Start with measured changes in frequently exercised passes, not a new optimization wishlist. A retuned policy must keep deterministic identity, explicit limits, malformed/stale-profile rejection, source-free final-link behavior, and the independent no-op fallback.

**Z17-BD11.** Retain source-free linking: independently produced component bytes must link with the installed linker after source and construction storage are unavailable. A thin authoring executable is not a substitute for this contract.

### 8.4 Required outputs

A migrated package; maintained public-consumer tests; a reflection/representation regression family; a migration-only baseline measurement; an emitter-reuse decision; a reflection-demand decision; and an optimizer-repricing decision. Keep results in the existing acceptance/performance documentation rather than introducing parallel histories.

## 9. World implementation work

### 9.1 Preserve the production kernel profile

**Z17-W01.** First rebuild the existing implementation with necessary compatibility changes only. Preserve `wasm32-freestanding`, the import-free execution contract, the existing export surface, nonshared memory, the 65,536-byte stack, and the 268,435,456-byte maximum memory. Preserve default input/working/output allowances of 65,536 / 1,048,576 / 65,536 bytes. These values are present in the inspected producer and verifier. [W4] [W5] [W6]

**Z17-W02.** Keep runtime budgets distinct from physical WASM memory, native allocator overhead, diagnostic allocator overhead, and retained backing capacity. Record all relevant measures without substituting one for another.

**Z17-W03.** The compatibility build must not change scalar-batch quantum behavior, frame-reuse compatibility, rollback work, pending identity, interruption/cancellation points, reclaim behavior, or allocation admission policy. Existing algorithmic improvements in the selected predecessor remain; no unrelated redesign is bundled into the compiler comparison.

### 9.2 Instrument real pointer-borrow boundaries

ArrayList pointer locks diagnose invalidating operations during a borrow, including certain element movements without buffer reallocation. They are not synchronization or an ownership type system. [Z2]

**Z17-W04.** Inventory raw element pointers and slices into growable storage, not just ArrayList declarations. For each retained borrow, identify owner, creation point, last use, possible alias mutations, growth/removal paths, and error exits.

**Z17-W05.** Add the release's pointer-stability diagnostics around actual bounded borrow intervals. Scope locks to the relevant container and lifetime; release them on success, failure, cancellation, and early return. Do not lock an entire resident session if the design legitimately mutates that container between uses.

**Z17-W06.** Keep logical handle validation and generation/lifetime checks. A raw pointer can remain stable while its logical object is retired or replaced. Conversely, a valid handle can survive storage relocation. Tests must distinguish these failures.

**Z17-W07.** If a diagnostic exposes a real bug, fix the ownership or borrowing interval at its owner. Do not suppress the lock, copy all resident state, preallocate an unbounded arena, or add an unconditional per-operation scan to silence it.

**Z17-W08.** Inspect interactions with container moves/copies, frame journals, imported backing, shared fields, and ownership transfer. A diagnostic lock must not itself become copied stale state. Native safety-enabled tests must detect invalidation before later use; production-mode tests must continue to prove actual behavior without depending on a diagnostic panic.

### 9.3 Diagnostic allocator and failure atomicity

**Z17-W09.** Adopt the release's diagnostic allocator in appropriate native owned-allocation tests. Keep it outside the import-free production kernel's allocation policy. Exercise explicit ownership and leak reporting on normal completion, rejection, rollback, cancellation, and suspended cleanup.

**Z17-W10.** Preserve a deterministic allocation-failure injector for operation-level failure sweeps. Do not assume changing the backing diagnostic allocator leaves allocation ordinals or allocator overhead unchanged. Sweep the successor's actual call sequence, retaining comparable semantic failure points rather than equating ordinal N across different implementations.

**Z17-W11.** Rollback must remain nonallocating where that is the existing contract. Test failures before first mutation, during metadata reservation, after first protected mutation, after a second mutation to the same object, and during successor ownership creation. Verify original values, live aliases, handles, and cleanup obligations after every failure.

**Z17-W12.** Preserve change-proportional behavior where the selected predecessor provides it. Measure N, 2N, and 4N residents at a fixed number of changed frames and pending observations. The diagnostics must not reintroduce whole-resident copying/scanning. Identify bounds for live borrow metadata and journal retention. The inspected store provides the transaction/ownership starting point. [W3]

### 9.4 Runtime-bundle migration

**Z17-W13.** Migrate `runtime-prepare.mjs` and `runtime-bundle.mjs` together. Remove duplicated live compiler/profile decisions where an existing closed policy can own them, while retaining independent verification of actual bytes and supplied metadata. Read the pinned dependency through the existing trusted source/lock path; never make a manifest's self-declared dependency the authority.

**Z17-W14.** The producer must build with the selected compiler, authenticate the actually consumed Boundary package, run the existing required checks, inspect the delivered kernel, and record its actual profile. The verifier must reject mismatched compiler/mode/target/limits/dependency and incomplete qualification, not merely validate hashes.

**Z17-W15.** Preserve verified-buffer parsing, private verified-byte smoke execution, raw Git source selection, bounded inventory/extraction, executable modes, output reservation, and publish-last ready directories. Changing compiler selection must not bypass any of these protections. [W5] [W6] [W7]

### 9.5 Alternate WASM backend

**Z17-W16.** Run a separate release-supported self-hosted WASM backend experiment after W01–W15. Derive the exact backend/linker flags from the distribution's help/source; record them. Do not claim availability, debug support, or parity for this codebase merely from an upstream milestone.

**Z17-W17.** Compare the candidate with the baseline kernel using frozen images/inputs and independent expected results across all required engines. Inspect imports, exports, memory declarations, features, stack behavior, trap/rejection behavior, canonical outcome/state bytes, and complete lifecycle costs.

**Z17-W18.** Keep production on its qualified backend unless the alternate passes full semantic, platform, delivery, and economic gates. A backend that builds faster but fails debugging requirements may remain a narrowly documented development option; it must not be the only supportable way to diagnose production behavior.

## 10. Agent implementation work

### 10.1 Portable value and model contracts

**Z17-A01.** Migrate `src/contracts.zig` and the census-discovered model/schema/catalog/invocation paths. Preserve descriptor identity, field order, variant encoding, declared tag behavior, text validation, bounds, decoding ownership, and compile-time rejection.

**Z17-A02.** Compare old and new descriptors and canonical value encodings independently. Test each supported family and near-miss unsupported shapes. Include malformed model responses, unknown/unoffered alternatives, overflowing integers, exceeded bounds, invalid UTF-8 where text is required, and cleanup on decoding failure. Use current contract decisions rather than expanding the accepted set.

**Z17-A03.** Preserve approvals, exact request/result binding, parser delivery authority, cancellation and disposal behavior, source-free compiled-tool delivery, and frozen reference producers. No test may replace a real admission path with a permissive mock in order to obtain a green upgrade.

### 10.2 Keep the authoring-only graph honest

**Z17-A04.** Preserve the dependency admission prerequisite that accompanies exported Agent modules. The inspected build uses a generated admission module to carry this prerequisite into downstream consumers. Warm graph reuse must not skip required source authentication. [A2]

**Z17-A05.** An external package importing Agent or pure Agent contracts must receive the same admission guarantees as an in-repository target. Test normal package resolution, explicit authenticated source override, relocated extraction, tampered dependency, and unavailable runtime tools during authoring-only work.

**Z17-A06.** Recompute all lock-bound identities through the existing dependency tooling. Verify correspondence among `build.zig.zon`, the dependency lock, source/archive inventories, selected final linker, World delivery record, and the installed package used by the actual consumer. Do not edit only the convenient subset of hashes.

### 10.3 Measure the actual existing runtime path

The inspected `runtime/world.mjs` bridge calls fresh `kernel.invoke(...)`; the economy tooling also contains a fresh-invocation path. [A5] [A6]

**Z17-A07.** Measure that actual path first with frozen model/tool responses. Include encode, invoke/admit/restore, execution, outcome decode, and the consumer's next action. Distinguish fresh module/process creation, fresh invocation on an existing kernel, prepared execution, and resident execution. They are not interchangeable benchmark labels.

**Z17-A08.** Preserve existing parser, document, repository-repair, inquiry, callable/model, and compiled-tool consumer coverage found in the current aggregate. Retain their limits, workload inputs, and positive/negative distinction. If a previously accepted workload regresses, disclose it individually.

Live provider/model calls and paid services are not required for these attribution experiments and must not be invoked without separate authorization. Frozen-response replay must exercise the actual admission and consumer code, not a permissive substitute.

### 10.4 Bounded resident-path experiment

**Z17-A09.** Evaluate whether an existing World resident API can reduce repeated preparation on one real replayable Agent workload. Reuse the canonical API; no new persistence, host loop, or provider-specific routing is authorized. Keep this experiment separate from the compiler migration.

**Z17-A10.** A valid resident candidate must include admission/setup, continuation, checkpoint creation, interruption, export, fresh-process restore, failure retry, cancellation, and retirement. Fresh and resident executions must produce the specified same observations at matching boundaries.

**Z17-A11.** A resident handle never becomes a portable identity or a substitute for the canonical checkpoint. Losing the resident must not lose semantics that the existing portable path preserves. Pending replies must remain bound to the correct request after export/restore.

**Z17-A12.** Promote only when the complete consumer lifecycle is favorable and memory/latency tradeoffs are accepted. Otherwise retain the existing bridge, delete prototype production branches, and keep only the minimal regression/measurement witness. Do not claim benefits from World resident work for an Agent path that never uses it.

## 11. Structured build information and incremental development

### 11.1 Narrow build-protocol integration

**Z17-P01.** Evaluate the release's structured build interface with a thin adapter in existing development/qualification tooling. It must discover configured step names and dependencies, request a named existing step, and associate success/failure and emitted paths with that run. Do not build an IDE, language server, general agent harness, or permanent service.

**Z17-P02.** Use the pinned protocol definition, not regexes over human logs presented as protocol support. A static configuration export may satisfy static discovery, but cannot stand in for executed step events. Unknown protocol versions must produce an explicit unsupported result and leave ordinary build execution available.

**Z17-P03.** Bound protocol messages, accumulated diagnostics, process lifetime, output storage, and cancellation cleanup. Handle partial reads, multiple messages per read, malformed/truncated frames, nonzero exit, missing terminal event, and a configuration change. Never treat a generated path event as proof that a file exists, is current, or passed qualification; verify the actual artifact.

**Z17-P04.** Use graph information to select candidate checks and collect artifacts. It is not a proof of semantic coverage. The repository's required final aggregate and relevant invariant tests remain mandatory. Record the selected graph/options identity so a result cannot be reused after configuration changes.

### 11.2 Linux incremental lane

The compiler implementer's account explains semantic dependency invalidation and the persistent-process development model; inline/type/comptime changes can affect a larger dependency set than private implementation changes. [Z3]

**Z17-P05.** Establish a controlled `x86_64-linux` development experiment with a persistent build process for selected expensive native tools. Preserve macOS arm64 as a primary native qualification platform. Do not sell a Linux-only result as a measured macOS improvement.

**Z17-P06.** Exercise at least: a private optimizer function edit; an authoring-helper body edit; an exported type/schema change; a build-configuration change; and a dependency-lock change. After each incremental build, compare the resulting behavior and relevant canonical outputs against a fresh build of the same edited tree.

**Z17-P07.** Record invalidated steps, time to checked output, retained compiler-process memory, and source/configuration identity. Compare equivalent optimization/backend/target lanes. Do not compare incremental debug output to a full safe production build and label the difference an incremental speedup.

**Z17-P08.** Use disposable worktrees for deterministic edit probes, then restore and verify them. Do not edit the developer's active files to drive benchmarks. Stop the watcher and all children on completion/failure; no background process is part of the delivered upgrade.

**Z17-P09.** A narrowly supported development path may be documented after correctness qualification. Full CI/release proof remains a fresh nonincremental build. Do not add remote infrastructure, mandatory containers, or editor dependencies solely to obtain this experiment.

### 11.3 Editor and diagnostic readiness

**Z17-P10.** Verify actual editor/tool compatibility at implementation time. Document a working compiler-driven build/test/diagnostic path even when an editor integration is unavailable. Do not rewrite dotfiles or the Zig skill within this three-repository scope; record any necessary external follow-up without claiming it completed here.

## 12. Performance attribution and promotion

### 12.1 Measurement subjects

Use these identities consistently:

| Subject | Definition |
|---|---|
| C0 | The original locked Agent consumer tuple, before source reconciliation |
| U0 | A coherent qualified 0.16 predecessor selected for the migration |
| U1 | U0's implementation with only necessary 0.17 compatibility changes |
| E1…En | Individual experiments derived from U1; each changes one independently attributable mechanism |
| F | Final selected 0.17 tuple with all promoted changes integrated |

**Z17-M01.** Report `C0 → U0`, `U0 → U1`, each local `U1 → Ei`, and cumulative `U0 → F` separately where they exist. If E2 builds on E1, name that predecessor explicitly. Do not use an old historical comparison to claim a current-head improvement.

### 12.2 Required experiments

Each row requires a correctness witness, cost measurements, and a promotion/rejection decision:

| ID | Experiment | Fixed controls | Deciding observations |
|---|---|---|---|
| E01 | Compiler-only upgrade | Algorithms, policies, inputs, profiles, budgets | Native build costs; Boundary phase costs; World complete-cycle costs; canonical correspondence |
| E02 | Configuration cache and graph migration | Compiler and output behavior | No-op cost; correct invalidation; required authentication still executes |
| E03 | Emitter executable reuse | Authored contracts, output corpus, independent checks | Number of compilations; full construction time; native size/RSS; state isolation |
| E04 | Reflection-demand reduction | Same accepted types and semantics | Relevant tool compile time/RSS; generated code size; no lost negative cases |
| E05 | Linux incremental development | Same edited tree/backend/mode | Time to checked artifact; invalidated steps; retained process memory; fresh-build agreement |
| E06 | Borrow/allocator diagnostics | Production storage semantics and budgets | Detected injected fault; complete cleanup; diagnostic overhead separated from production |
| E07 | Alternate WASM backend | Kernel source, inputs, explicit profile | Engine agreement; kernel size; build cost; lifecycle time/memory; diagnostic limitations |
| E08 | Existing optimizer repricing | Pinned 0.17 runtime and held-out workloads | Discovery/check/admission/execution costs; bounds; profile identity; no-growth constraints |
| E09 | Actual Agent replay and resident candidate | Frozen model/tool inputs, external semantics | Fresh baseline; full resident lifecycle; checkpoint/restore; consumer memory and latency |
| E10 | Structured build interface | Existing steps and terminal gates | Accurate discovery/events/artifacts; failure/cancellation behavior; adapter maintenance cost |

An experiment may establish that current code is already adequate. A measured no-change/rejection result completes that opportunity's decision; an unsupported assertion does not.

### 12.3 Separate all compilation and execution layers

For Boundary, report Zig compiling a native emitter separately from that emitter running the Boundary compiler. For World, report compiling the kernel separately from admission, execution, and serialization. For Agent, report framework/system time separately from external model/network/tool time.

If feasible, use the codec-compatible cross matrix:

| Program producer | Runtime kernel | Purpose |
|---|---|---|
| U0 compiler | U0 kernel | Baseline |
| U1 compiler | U0 kernel | Compiler/producer changes with old runtime |
| U0 compiler | U1 kernel | Runtime rebuild against frozen producer output |
| U1 compiler | U1 kernel | Integrated migration |

Use exactly the same program bytes for the runtime-only comparison. If program bytes unexpectedly differ in U1, resolve that difference before using the comparison as compiler-only evidence. Do not average away a failed compatibility cell.

### 12.4 Cache regimes

**Z17-M02.** Name the cache regime in every build result:

- **Bootstrap-cold:** isolated compiler-support/global cache and isolated project/configuration/compile cache. Include first-use tool-support compilation. State whether dependency archives were preacquired and whether network transfer is included.
- **Maker-warm/project-cold:** only a verified tool-support seed is reused; no project outputs/configuration are reused. Local package availability is stated separately. Do not call an arbitrary developer global cache a tool-support-only seed.
- **Warm no-op:** identical source, options, dependencies, tool identities, and successful prior outputs in the same cache set. Record which make-time checks still execute.
- **Incremental edit:** a live process, a recorded edit, and time until the edited artifact has passed the selected check. A no-change cache hit is not an incremental edit.

Never prime one side invisibly. A preparatory `zig fetch` can itself warm build-system support; perform provenance preparation outside the measured cache or count it. Never clear a user's shared cache to create a cold run.

### 12.5 Sampling and statistics

The following are default experimental policies, not predictions:

**Z17-M03.** Use at least three independent cold/bootstrap repetitions. For repeatable runtime/compiler-phase measurements, use at least five alternating paired windows with three warmups and nine measured samples per variant per window. Reuse an existing stronger protocol instead of weakening it. Persist sample order and raw values.

**Z17-M04.** Randomize or alternate order and record the seed. Keep host, power mode, CPU model/features, concurrency, engines, inputs, and instrumentation comparable. Reject or explicitly flag runs with thermal throttling, background load, clock anomalies, or failed checks. Do not silently discard inconvenient outliers.

**Z17-M05.** Report absolute deltas and ratios, medians, sample counts, variability, and uncertainty. For repeated windows, estimate uncertainty at the independent window/process level rather than treating every inner timing as independent. A bootstrap confidence interval is acceptable with its resampling method recorded.

**Z17-M06.** For shorter-than-resolution operations, batch a fixed amount of real work and report the normalization. Do not report p95/p99 from nine samples or present throughput medians as tail latency. Collect a separate sufficiently sized distribution before making a tail claim.

### 12.6 Cost vector and workloads

At minimum collect:

| Dimension | Required observations |
|---|---|
| CPU/time | Wall and CPU time; tool compilation; compiler phases; complete fresh/prepared/resident cycles; failure/cancellation cost |
| Memory | Native peak RSS; allocator live/peak; retained storage; WASM pages and peak growth; journal/borrow metadata |
| Disk | Tool/build/package cache bytes; generated executable/kernel bytes; artifact/archive size; significant read/write work |
| Network | Required fetches and bytes when measured; explicit offline runs; no attribution of external model latency to runtime improvements |
| Structure | Compilations performed; relevant operation/allocation counts; emitted image/state size; work-budget use; N/2N/4N scaling |

Distinguish logical byte counts from physical allocation rounding and diagnostic metadata. Record unavailable counters as unavailable, not zero.

Workloads must include a small authoring example, a large reflection-heavy authoring case, independent component linking, ordinary Agent consumers, and existing difficult ownership/continuation cases. Include demanded overflow, unused failing suffixes, shared versus independent state, cleanup suspension, low budgets, and replay across process/engine boundaries. Use real maintained fixtures; synthetic cases supplement them.

### 12.7 Promotion policy

**Z17-M07.** Correctness, authority, byte contracts, bounded work, and required platforms are hard gates. No performance benefit overrides a failure.

**Z17-M08.** Default materiality for triage is a reproducible regression exceeding 5% on a relevant latency/build metric and exceeding measured noise/resolution. This is a review trigger, not permission to ignore smaller costs. Report all observed positive memory growth, budget-cliff changes, binary growth, and lost debugging capability. Any workload that newly fails an unchanged capacity is blocking.

**Z17-M09.** Before promotion, publish the cost vector for intended and affected held-out consumers. No confirmed material regression is accepted without a named explicit decision describing the exact workload, values, scope, and rationale. Aggregate averages cannot hide individual regressions. If a necessary compatibility repair has such a cost, retain a candidate upgrade until the decision is recorded; do not fabricate acceptance.

**Z17-M10.** Safety diagnostics may justify development-only overhead; label that tradeoff. They must not be used to make an apples-to-oranges production benchmark or to expand the production budget without approval.

**Z17-M11.** A conditional optimization that does not earn promotion is removed from production, not left behind a permanent speculative flag. Preserve only an appropriately small witness and the decision record. A required infrastructure experiment with an external blocker must say blocked, not rejected for performance.

## 13. Compatibility, platforms, and delivered artifacts

### 13.1 Required platform matrix

**Native host lanes:** macOS arm64 and Linux x86_64. Run maintained native authoring/data/runtime suites in safety-enabled configurations and the existing safety-disabled witness lane. Verify the actual compiler's mode settings for each module; do not infer them from only the root command.

**Portable execution lanes:** the qualified production WASM kernel on Node, Wasmtime, Chromium Worker, and Firefox Worker, including native↔WASM and fresh-process transfers. Keep engine versions fixed in attribution experiments and bind versions to final qualification.

**Package lanes:** independent consumers of Boundary data, Boundary authoring/linking, Agent contracts/authoring, and the delivered World runtime. Test an extracted archive outside all source checkouts, alternate local package storage, and the existing source-independent consumer path.

**Additional maintained lanes:** preserve any currently required platform or workflow discovered during execution. This specification does not silently drop it. Windows or another target not currently promised is not made a new full product-support commitment solely by this migration.

**Diagnostic portability lane:** endian/layout witnesses as specified in L09–L10. State which are compiled and which are actually executed.

**Z17-Q01.** Missing required platform execution blocks full qualification. A bounded, explicit platform exclusion requires approval; silently skipping a browser or substituting a mock is not acceptable.

### 13.2 Interchange matrix

**Z17-Q02.** On the same frozen program image, transfer predecessor-created valid states into successor runtimes and successor-created states into predecessor runtimes where the unchanged contract allows it. Compare canonical outputs, pending requests, cleanup, final results, and failure classifications.

**Z17-Q03.** Repeat representative transfers at every relevant quantum/interruption cut, including before/after an effect, during retained control, at cleanup suspension, and around failure retry. Preserve wrong-image and wrong-request rejection. Equivalent source is not sufficient for a same-image restore: use the actual identical image bytes.

**Z17-Q04.** Compare imported/exported canonical value and component bytes against frozen independent goldens. Compiler diagnostics may have deliberate presentation changes; runtime semantics and canonical bytes do not get normalized away.

### 13.3 Delivered-byte and source-free qualification

**Z17-Q05.** Qualify what consumers receive, not only local build outputs. Reacquire the completed World archive through the existing owner CLI using externally selected expected hashes. Verify inventory, exact kernel profile, smoke, and actual consumer execution from extracted bytes.

**Z17-Q06.** Build independent public package consumers from authenticated package archives in a clean workspace. Remove access to original source, local sibling repositories, hidden global caches, and unneeded compiler tools for runtime-only execution. A runtime consumer must not compile/fetch on demand to hide a missing artifact.

**Z17-Q07.** Test tampering with kernel bytes, runtime modules, package metadata, lock, profile, required-check list, and inventory before verification; test the existing consumed-byte protection against replacement after selection. Preserve bounded extraction and destination-collision behavior.

**Z17-Q08.** Preserve archive and manifest identities after publication. A later rebuild is a new artifact, even if the source commit is unchanged. Do not overwrite or silently substitute an expired pinned artifact; record its durable location and selected digest.

## 14. Required acceptance and mutation cases

These are minimum distinguishing cases, not replacements for existing aggregates. In the principal-requirements column, `Z17-` is omitted for brevity; for example, `T06` there means requirement `Z17-T06`, whereas the first column identifies acceptance case `T06`. Extend existing test owners. For each case, record its executable witness, covered requirement IDs, exact subject, result, and log/artifact identity. A source search or prose review cannot stand in for an executed semantic case. Panic-intended diagnostics run in a child process so that the parent can distinguish the expected diagnostic from an unrelated crash.

### 14.1 Toolchain, census, and graph

| Case | Required witness | Principal requirements |
|---|---|---|
| T01 | Every maintained build entrypoint and exported generic consumer compiles under exact 0.17.0; exclusions distinguish frozen/historical material. | C01–C05, T06, BD01 |
| T02 | An alternate/fake `zig` placed first on PATH cannot intercept a nested build, producer, fixture, or hashing invocation. | T01–T05, G13 |
| T03 | Changed executable or library-distribution identity invalidates qualification; a reported version alone cannot bless an altered toolchain. | T01, T04 |
| T04 | Top-level, nested, and Node-driven builds report the same selected compiler and use the intended mode/target. | T02–T03, T10, G03 |
| T05 | A second no-op build reuses eligible graph/outputs while mandatory authentication still executes. | G05–G08, A04 |
| T06 | Editing an imported build file or a configuration-read file changes the graph/output appropriately. | G05–G08 |
| T07 | Adding, renaming, deleting, and changing executable intent in a tracked source-inventory directory invalidates the relevant decision. | G08, C01 |
| T08 | Changes to target, optimization, compiler, source override, package root, and output prefix cannot reuse incompatible results. | T10, G03, G08 |
| T09 | Pass-through arguments preserve empty, spaced, Unicode, separator, and repeated values without unrelated recompilation. | G01–G02 |
| T10 | Run/artifact/file/directory/output/dependency argument roles preserve execution and generation edges. | G01, G15 |
| T11 | Data-only and authoring-only public consumers succeed without browser/runtime tool availability. | I01, I03, G04, BD02, A05 |
| T12 | Package tests cover explicit/environment/custom/symlinked stores, offline availability, and absent dependencies. | G09–G12 |
| T13 | Cleanup cannot delete a preexisting/custom/symlink-target package store, checkout, home, or parent directory. | G10–G11 |
| T14 | Actual response-file/long-argument paths either execute correctly or produce a precise unqualified blocker without dropping arguments. | G15, B04 |

### 14.2 Language, reflection, values, and compiler independence

| Case | Required witness | Principal requirements |
|---|---|---|
| T15 | Empty/nested structs and tuples preserve field order, field/type correspondence, and canonical descriptors. | L01–L03, A01–A02 |
| T16 | Tagged unions and enums preserve their existing ordinal/numeric-tag conventions, including explicit nonconsecutive tags. | L02–L04 |
| T17 | Compile-time fields and unsupported portable widths/pointers/sentinels/untagged unions remain rejected at the appropriate boundary. | L04, A01 |
| T18 | Public wrapper markers work both locally and when imported; internal-only declarations do not become a public protocol accidentally. | L07 |
| T19 | Recursive descriptors, retained capture schemas, and independent nominal operations retain identity and rejection behavior. | I04, L05, A01 |
| T20 | Logical-bit, memory-layout, and explicit-wire cases have distinct expectations; array/vector and narrow-integer witnesses run at comptime and runtime. | L08–L10 |
| T21 | Native and WASM codecs match frozen canonical goldens; endian witness execution is reported separately from cross-compilation. | L09–L11, Q04 |
| T22 | Old→new and new→old value/component decode reject noncanonical, truncated, trailing, unknown-tag, and malformed inputs independently. | L11, A02 |
| T23 | Repeated multi-element array patterns preserve content for zero, one, and several repetitions after syntax migration. | L12 |
| T24 | Migrated error handling preserves original failure and exact cleanup order on early, late, and nested allocation failures. | L13, L15 |
| T25 | Capacity/ceiling arithmetic preserves checked behavior near zero, maximum, signed overflow, and allocation-page boundaries. | L14 |
| T26 | Parser/formatting/allocator ownership tests expose dangling output, diagnostic lifetime, malformed-input bounds, and failed allocations. | L15, L17 |
| T27 | Applicable floating-point equality distinguishes numeric semantics from representation for NaN, zero, and aliased slices. | L16 |
| T28 | A candidate with an admissible shape but deliberately wrong result/capture rewrite is rejected by the independent checker. | L06, BD08–BD10 |
| T29 | Existing first-failure, lazy-unused-suffix, state-cell separation, handler scope, memo, and ownership negatives still discriminate wrong transformations. | I01–I04, BD08 |
| T30 | Budget exhaustion and allocation failure roll back to the specified compiler fallback without stale observations. | D04, BD07–BD10 |
| T31 | Valid→invalid→valid and interleaved emitter configurations match isolated execution; no stale facts, policy, or nominal identity leak. | BD05–BD07 |
| T32 | Independently emitted components link through the installed linker after source and original construction memory are unavailable. | BD11, Q06 |

### 14.3 World storage and runtime

| Case | Required witness | Principal requirements |
|---|---|---|
| T33 | A forced reallocating mutation during a real element borrow triggers the intended diagnostic; the corrected path succeeds. | W04–W08 |
| T34 | A nonallocating element-moving/removing mutation is detected where it invalidates a borrow. | W05–W08 |
| T35 | Valid borrows release on every success/error/early-return path; container moves/copies do not duplicate lock state incorrectly. | W05, W08 |
| T36 | Stable raw pointers to retired/replaced objects remain protected by logical ownership/handle validation. | W06 |
| T37 | Borrow begun before transaction entry remains correct through mutation, rejected operation, and rollback. | W08, W11 |
| T38 | Multiple mutations of one original frame save the correct rollback state once; aliases and retained branches observe the proper version. | W11–W12 |
| T39 | Failure after successor ownership transfer restores original values, owners, pending bindings, and cleanup obligations without rollback allocation. | W10–W12 |
| T40 | Complete normal/cancelled/rejected lifecycle releases all expected allocations; failure sweeps cover the successor's actual allocation sites. | W09–W11 |
| T41 | N/2N/4N retained-state tests with fixed mutations preserve the predecessor's change-proportional behavior and bounded live metadata. | W12 |
| T42 | Scalar batching/frame reuse agrees with the reference at every applicable quantum cut, demanded arithmetic failure, and cancellation point. | W03, Q03 |
| T43 | Deep/shallow/dynamic handlers, owned exchange, suspending disposal, and already supported cloning/multi-shot cases survive transfer. | I02–I04, Q02–Q03 |
| T44 | Unchanged-capacity failure permits the same retry behavior and exposes no partially committed state. | D04, W01–W03, Q03 |
| T45 | Same-image states transfer old↔new and native↔WASM; wrong-image and wrong-request cases reject. | Q02–Q04 |
| T46 | Production kernel preserves import/export, memory maximum, unshared memory, stack/default budget, and ABI profile. | W01–W03, W14 |
| T47 | Alternate backend runs the required engine/semantic/negative matrix before any promotion; differences are not normalized away. | W16–W18 |
| T48 | Diagnostic-enabled and production-mode tests retain actual explicit guards; safety-disabled execution does not rely on allocator/lock panics. | W08–W10, M10 |

### 14.4 Authenticated delivery and Agent consumers

| Case | Required witness | Principal requirements |
|---|---|---|
| T49 | Changing one of compiler, host mode, kernel mode, target, limits, dependency, or required-check metadata makes the new verifier reject. | T10, W13–W15 |
| T50 | Producer and verifier bind the actual selected compiler/distribution, consumed package, and delivered kernel rather than hard-coded stale values. | T01–T10, W13–W14 |
| T51 | Kernel/module/package/lock/inventory tampering fails before execution; existing verified-copy substitution protection remains effective. | Q05–Q07, W15 |
| T52 | Archive traversal, excessive inventory/input, executable-mode changes, and destination collisions preserve the existing fail-closed behavior. | G11, W15, Q07 |
| T53 | Missing tool, failed qualification, interrupted producer, and corrupted archive never publish a ready bundle. | G14, W15, Q08 |
| T54 | Independently reacquired runtime runs source-free and offline without compiler or sibling-checkout fallback. | Q05–Q06 |
| T55 | Agent lock, package manifest, source/archive/package inventories, final linker, and delivered runtime resolve to one exact qualified tuple. | B01–B02, T07–T09, A06 |
| T56 | Warm authoring cache plus a tampered dependency still fails through the exported admission prerequisite. | G06, A04–A05 |
| T57 | Packaged Agent/contracts consumers exercise the same portable positives/negatives as in-repository tests. | A01–A06, Q06 |
| T58 | Original maintained parser/document/repository/inquiry/model/tool consumers pass with unchanged external inputs, bounds, approval, and negative cases. | A03, A07–A08 |
| T59 | Fresh-invocation replay uses the actual bridge, reports all boundary costs, and is not mislabeled as resident execution. | A07–A08, M01 |
| T60 | Resident experiment preserves setup, effect resume, checkpoint export, fresh recovery, cancellation, pending binding, and final retirement. | A09–A12 |
| T61 | Source-free frozen producers and unchanged independent goldens remain unchanged; successor fixtures are separately identified. | C03, Q04–Q06 |
| T62 | A source/lock/profile change after an earlier qualification prevents reuse of that result for a new final tuple. | T07–T10, Q08 |

### 14.5 Development tooling and economic evidence

| Case | Required witness | Principal requirements |
|---|---|---|
| T63 | Structured discovery lists real configured steps/options/dependencies; requested step events and emitted files match the actual run. | P01–P04 |
| T64 | Truncated/malformed/oversized protocol input, unknown version, missing terminal event, nonzero exit, and cancellation cannot produce success. | P02–P04 |
| T65 | A graph-informed narrow check never substitutes for the final required aggregate or independent semantic witnesses. | P04, Q01 |
| T66 | Each incremental edit class agrees with a fresh build of the same edited source and identifies its actual invalidated steps. | P05–P07 |
| T67 | Incremental/watch failure and termination leave no child process and do not alter the user's active worktree. | P08–P09 |
| T68 | Bootstrap-cold, maker-warm/project-cold, no-op, and incremental measurements have distinct reproducible cache manifests. | M02–M04 |
| T69 | Compiler-only, source-reconciliation, isolated experiments, and final cumulative comparisons retain their correct identities and attribution. | B02, M01, M07–M11 |
| T70 | A rejected candidate leaves no speculative production branch; accepted candidates retain per-workload costs and explicit exceptions. | D03–D05, M07–M11 |

### 14.6 Applicability and failure interpretation

“Not applicable” is permitted only where the subject truly does not exist in maintained code, such as a URI API with no owned caller. It requires the census evidence and cannot exempt a principal stack contract, platform lane, required experiment, or protected consumer.

For a mutation test, record the mutation and expected rejection point. A generic crash, timeout, unrelated compile failure, or removed fixture does not prove the intended guard. For a diagnostic test, also execute a valid neighboring case. For a regression repaired during migration, retain the smallest witness at the real production seam.

## 15. Evidence contract

### 15.1 One owner, no parallel accounting system

**Z17-E01.** Extend existing qualification/measurement owners. Boundary's consolidated acceptance page and performance record can own the cross-stack upgrade summary; World and Agent retain their existing delivery and dependency evidence. Link exact records rather than copying evolving manifests into several documents.

A small new upgrade-specific evidence file is acceptable if the existing schema cannot represent the comparison cleanly. It must have one owner and be linked from the existing report. This is not authorization for a new ledger service, database, package manager, or orchestration layer.

**Z17-E02.** Raw logs, sample files, and large archives may live in the existing immutable evidence-artifact mechanism. Retain their digests and acquisition locations. Persist enough information to reproduce every decisive claim. Do not put secrets, provider keys, unrelated personal data, or an entire developer environment in evidence.

### 15.2 Required run record

Each deciding run must include:

| Field group | Required content |
|---|---|
| Identity | Unique run ID; timestamp/timezone; repository commits/trees; dirty/patch status; baseline/candidate relationship |
| Toolchain | Exact version; resolved executable; executable digest; distribution/source identity; actual commands; stdlib override policy |
| Build | Host/target/CPU features; per-module mode; backend/linker; options; configured graph identity where available |
| Dependencies | Boundary compiler/data identities separately; package hashes/inventories; source overrides; World source/archive/manifest/kernel identities; Agent lock digest |
| Environment | OS, CPU, engines, Node, package-manager/browser locks, concurrency, resource controls; only relevant nonsecret environment values |
| Cache | Regime; isolated roots; tool-support seed identity; package availability; whether network/bootstrap costs are included |
| Workload | Fixture/input/program/state/profile digests; process/session mode; interruption settings; limits; held-out versus selection role |
| Execution | Command, cwd, required-check selection, start/end, exit status, stdout/stderr artifact and digest, measured/not-run/blocked distinction |
| Measurements | Raw samples, order/seed, counters and units, memory definitions, uncertainty method, local/cumulative cost tables |
| Decision | Pass/fail/blocked/not-applicable; deciding test IDs; promotion/rejection/accepted-cost decision and scope |

No completed field may contain `TBD`, a fabricated digest, an illustrative placeholder, or a falsely implied zero. Before execution, fields may be absent/null with an explicit `not-run` status. A final required run must supply actual values.

### 15.3 Compact machine-readable shape

The following is a schema outline, not a completed result:

```text
upgrade:
  document_id: BWA-Z17-1
  target_zig: 0.17.0
  status: not-run | compatibility-qualified | experiments-qualified | landing-qualified
  subjects:
    C0?: exact original consumer tuple
    U0: exact pre-upgrade tuple
    U1: exact compatibility-only tuple
    experiments[]: id + predecessor + candidate tuple
    F?: exact final tuple
  runs[]:
    id, subject, test_ids[], command[], cwd, timestamps
    toolchain, dependencies, host, target, modes, backend, linker
    cache_regime, workload_digests, limits
    execution_status, exit_code, evidence_digests
    raw_measurements, derived_comparisons
  decisions[]:
    experiment_id, status, deciding_run_ids[], rationale
    promoted_changes[], rejected_changes[]
    accepted_costs[]: metric + workload + delta + authority + scope
  outstanding[]:
    requirement_id, blocking_reason, evidence, next_deciding_action
```

Use existing JSON formats where possible. Any new parser must be bounded and tested. A record's status must be derived from actual required results, not supplied as an unchecked claim by the candidate.

### 15.4 Human acceptance report

The report must answer, with exact subjects:

1. What code/API/build changes were necessary?
2. Which compiler/runtime/package tuple was actually qualified?
3. What improved in native compilation, Boundary compilation, World execution, and Agent replay separately?
4. What regressed, remained unchanged, or could not be measured?
5. Which experiments were promoted, rejected, or blocked, and why?
6. Which canonical contracts and negative cases were preserved?
7. What are the actual dependency/landing order and rollback artifacts?
8. Which claims, platforms, or release actions are still unauthorized or incomplete?

A history of many passing test counts is not a substitute for these answers. Do not report this specification's preparation as an implementation run.

## 16. Implementation packages and landing order

The labels below are proposed work packages, not existing pull-request numbers. Use draft PRs while dependencies or qualification are unsettled. Preserve the user's rebase-based workflow. Opening implementation PRs does not authorize merging or publishing releases.

### 16.1 Work-package map

| Package | Repository / owner | Required contents | Dependency |
|---|---|---|---|
| WP0 — Freeze and reproduce | All three, existing qualification owners | Census, C0/U0 identity, original artifacts, executed baseline, scope/limits | None |
| WP1 — Boundary compatibility | Boundary | Language/reflection/build migration, public consumers, no policy retuning, package/CI updates, T15–T32 coverage | WP0 |
| WP2 — World compatibility and diagnostics | World | Compatible data pin, build/kernel migration, producer/verifier selection, storage diagnostics, unchanged budgets, delivery tests | Qualified WP1 package |
| WP3 — Agent compatibility and consumer cutover | Agent | Reflection/contracts, exported admission, compiler propagation, exact lock regeneration, actual consumer qualification | Qualified WP1 package and WP2 bundle |
| WP4 — Build/authoring economics | Relevant existing owners | E02–E05 evaluations; measured graph/emitter/reflection improvements; incremental witness | U1 from WP1–WP3 |
| WP5 — Runtime/backend/consumer economics | World and Agent, Boundary where policy changes | E06–E09 evaluation, isolated candidates, rejected-code removal, explicit cost decisions | U1; any precisely named local predecessor |
| WP6 — Structured development interface | Existing tooling owner | E10 bounded adapter/witness and non-substitution for semantic gates | Migrated build graphs |
| WP7 — Final integrated qualification | All three | Cumulative F comparison, final archives/locks, independent reacquisition, final-head checks, reports and rollback | All mandatory decisions complete |

WP4–WP6 may run in parallel in isolated worktrees when their inputs are immutable. Do not combine their changes before local attribution exists. A package may be split into smaller PRs for review, but this must not create new public APIs or permanent configuration modes merely to support the split.

### 16.2 Required landing dependency order

The functional order is:

```text
Boundary source/package
        |
        +----> World source + authenticated Boundary-data pin
        |              |
        |              +----> qualified World runtime bundle
        |                                  |
        +----------------------------------+----> Agent compiler/runtime lock
                                                       |
                                                       +----> final consumer qualification
```

**Z17-S01.** Land or otherwise immutably select the final Boundary source first. Recompute its package hash/inventory from the exact source. World and Agent may use different qualified Boundary revisions, but neither may refer to mutable branch URLs or guessed package hashes.

**Z17-S02.** Land or immutably select World next with its exact compatible data pin. Produce a bundle from that source through the migrated producer. Independently acquire and verify it before binding Agent.

**Z17-S03.** Update Agent last to the selected Boundary compiler package and delivered World runtime. Recompute the entire consumer lock, run the actual packaged consumer, and execute the final protected integration/browser suites.

**Z17-S04.** Repeat the same dependency order for promoted improvements that change an upstream package/runtime. Pure tooling changes with no package or runtime effect need only their actual dependencies; do not manufacture a lock cascade where authenticated contents did not change.

### 16.3 Squash/rebase and final identity

Source-bound artifacts cannot be claimed for a different commit after a rebase or squash. The final source identity, package hash, and runtime manifest must name the actual selected result.

**Z17-S05.** After final commit identities settle, rebuild/rebind affected artifacts and rerun the required delivered-byte/consumer checks. Prior measurements may be reused only with an explicit, verified correspondence showing the measured executable/workload/profile bytes are the same; update provenance and do not call an old candidate a final-head run.

**Z17-S06.** Do not introduce a circular lock: Agent source is not required to build World, and World runtime is not required to author Boundary. Integration proof can depend on both as test inputs without making them production imports.

## 17. Execution procedure and commands

### 17.1 Procedure

1. Read current repository instructions and the current `$zig` skill, inspect outstanding relevant work, and record actual branches/heads. Respect existing workflow and review policies without adding ceremony.
2. Acquire and authenticate the exact 0.16 predecessor toolchain/artifacts and exact 0.17 distribution. Keep them isolated. Record identities before any upgrade edits.
3. Complete the migration census and establish C0/U0. Reproduce the selected baseline's existing required checks and preserve frozen inputs.
4. Implement Boundary compatibility and its independent consumer witnesses. Use the resulting immutable package as input to World/Agent; do not bypass dependency admission for convenience.
5. Implement World migration and diagnostics, including producer/verifier agreement. Produce and independently acquire a candidate runtime with unchanged production limits.
6. Implement Agent compatibility and regenerate the authenticated tuple. Establish U1 through full current consumer qualification.
7. Run every Section 12 experiment with local attribution. Promote justified changes; reject and remove the others. Record genuine external blockers separately.
8. Form F and run cumulative, cross-engine, byte-compatibility, packaged-consumer, capacity, failure, and delivered-artifact gates.
9. Prepare the work-package PRs and report actual dependency/merge order. After any final source-ID changes, complete S05. Merge/release only when separately authorized.
10. Leave final evidence, rollback artifacts, and no migration-only production switches or lingering watcher processes.

### 17.2 Existing targets to preserve

The inspected graphs expose these useful starting targets; rediscover the actual current graph before execution. Do not omit another required aggregate merely because it is not listed here. [B2] [W2] [A2] [B5]

| Repository | Existing targets / checks |
|---|---|
| Boundary | `check`, `check-data`, `check-authoring`, `check-components`, `check-program-image-wasm`, `check-state-image-wasm`, `check-invocation-wasm`, `build-compiler` |
| World | `check`, `check-storage`, `check-activation-storage`, `check-native`, `check-kernel`, `check-source`, `check-capacity`, `check-transfer`, `check-browser`, `check-package`, `check-codecs`, `build-runtime` |
| Agent | `check-agent4`, `check-agent4-integration`, `check-compiled-tool-browser`, plus protected consumer-specific and runtime-negative checks selected by its existing aggregate |

**Z17-X01.** Add a thin `check-zig17` target in each current build owner only to collect genuinely new migration witnesses not already covered. Make the normal aggregate include those witnesses, avoiding duplicate execution. Agent may expose `check-zig17-integration` for the cross-version/package/backend witnesses. These are proposed names; the implementation must create them before these commands can succeed.

Do not add a new orchestration service behind these targets. Reuse existing Node/qualification/measurement scripts, adding the smallest helper only where there is no appropriate owner.

### 17.3 Representative invocation contract

The following POSIX-shell snippets are command templates for the implemented successor, not results from this document's preparation. `ZIG017`, source/package inputs, and cache roots must be real, previously authenticated selections. The initial guards make missing selections fail rather than silently pick defaults.

```sh
set -eu
: "${ZIG017:?absolute path to the verified Zig 0.17.0 executable}"
case "$ZIG017" in /*) ;; *) echo "ZIG017 must be absolute" >&2; exit 2 ;; esac
[ "$("$ZIG017" version)" = "0.17.0" ]

# In the selected Boundary checkout, after implementing the new witness target:
"$ZIG017" build check check-zig17 -Doptimize=safe --summary all

# In the selected World checkout:
"$ZIG017" build check check-zig17 -Doptimize=safe --summary all
"$ZIG017" build check-storage -Doptimize=fast --summary all

# In the selected Agent checkout with its authenticated dependencies installed:
"$ZIG017" build check-agent4 check-agent4-integration \
  check-compiled-tool-browser check-zig17 check-zig17-integration \
  -Doptimize=safe --summary all
```

Run each repository command from its own selected checkout. Supply explicit source/archive/runtime/browser paths through the existing options wherever required by that checkout's authenticated setup. Record the complete actual argv; do not treat these abbreviated templates as evidence that setup is unnecessary.

```sh
# New producer option required by T03; implement it in the existing World CLI.
# Run from the exact clean, selected World source.
: "${WORLD_BUNDLE_OUT:?new absolute run-owned output path}"
node bin/world.mjs runtime prepare \
  --source "$PWD" --output "$WORLD_BUNDLE_OUT" --zig-exe "$ZIG017"
```

Acquisition and source-free smoke use the existing World owner CLI and externally selected archive/manifest hashes. Never populate those hashes by trusting the acquired archive itself.

```sh
# Development-only Linux probe, after compiler and graph qualification:
"$ZIG017" build check-zig17 -Doptimize=debug -fincremental --watch
```

Use a finite controller for that watcher in tests; do not leave it running. Discover structured-interface flags and protocol definitions from the pinned release. Do not assume a compiler server protocol and a build server protocol share framing.

### 17.4 No invented command evidence

**Z17-X02.** Replace every template in the final run record with the actual executed command, options, cwd, environment selection, exit status, and artifacts. A copied command line is not a test result. Unsupported flags, unavailable tools, missing source archives, or failed downloads must remain visible blockers.

## 18. Failure, rollback, and release procedure

### 18.1 Failure response

**Compiler failure:** reduce to a small reproducer while preserving the affected contract. Determine whether the code relied on unsupported behavior or exposed a toolchain defect. Keep a targeted compatibility repair only when it has its own witness. Do not patch installed compiler libraries silently or report a patched compiler as the official distribution.

**Canonical-byte mismatch:** stop compatibility promotion. Identify whether the cause is representation, reflection ordering, arithmetic, serialization, or accidental optimizer-policy drift. Do not regenerate every golden or accept a same-new-code round trip as proof.

**Memory/capacity regression:** preserve the failing limits and investigate changed layout, container metadata, allocator behavior, or whole-state work. Do not raise budgets in the measured migration. Escalate a necessary cost with exact evidence.

**Authentication failure:** fail closed. Verify source/package/manifest/kernel correspondence from original trusted inputs. Do not disable a verifier, normalize inventory differences away, or select a newer unpinned artifact.

**Missing platform/tool:** label the lane blocked with the attempted command and available evidence. Produce useful completed portions, but do not call the full upgrade qualified. No repeated clarification is needed to execute independent available work.

**Experiment loses:** keep the qualified compatibility path, remove the speculative production change, and retain a small decisive report/witness. Losing an experiment is useful evidence, not justification for an unbounded search or a new framework.

### 18.2 Rollback unit

**Z17-R01.** Retain C0 and U0 source identities, toolchains, package archives, runtime bundles, manifests, and locks before promotion. Rollback selects a complete known tuple; it is not “install Zig 0.16 and hope the new source still builds.”

**Z17-R02.** Preserve the ability to restore predecessor-compatible canonical states where the unchanged protocol permits it. A newer runtime's private resident handles are never part of rollback data. Export the canonical state through the supported path before retiring a resident.

**Z17-R03.** Rollback must not mutate or delete the failed candidate's immutable evidence. Mark it rejected/superseded and preserve the reason. Remove only run-owned disposable scratch according to G11.

### 18.3 Release versus qualification

**Z17-R04.** A passed candidate, an opened PR, a merged source commit, and a published release are distinct statuses. This specification authorizes none of those external actions merely by being downloaded.

**Z17-R05.** If release is subsequently authorized, publish in dependency order, bind exact version/source/artifacts, and independently download the public artifacts without relying on the producer's credentials. Verify archive/package/runtime inventories and run source-free smoke and the packaged Agent consumer from those downloaded bytes.

For nonpublic repositories, use an independent least-privilege consumer identity and state that anonymous acquisition was not demonstrated. Do not claim public release availability from a private Actions artifact.

**Z17-R06.** Record retention/expiry and a durable selected copy for nonrelease artifacts. An expired URL is not permission to substitute new bytes under an old lock. Keep the last complete rollback tuple accessible.

## 19. Definition of done

### 19.1 Compatibility-qualified

All mandatory live source/build/API migrations are complete; exact compiler propagation is proven; no maintained exported generic contract is left uninstantiated; current aggregates and new migration witnesses pass; producer/verifier and all dependent locks agree; required native/WASM/browser/package lanes execute; canonical interchange and negative cases pass; the delivered runtime is independently acquired and consumed; no unaccepted material compatibility regression remains.

This status may be achieved before every optional promotion decision, but it is not the final completion of this specification.

### 19.2 Experiments-qualified

Every E01–E10 has an executed deciding result. Promoted changes have local evidence and held-out consumer qualification. Rejected changes leave no unnecessary production code. Diagnostic and development costs are labeled separately. Unsupported or unmeasured required opportunities are not disguised as rejection decisions. All accepted costs identify the actual decision and scope.

### 19.3 Landing-qualified

The final F tuple is immutable and matches the final source/package/runtime/Agent identities. All affected final-head/delivered-byte checks pass. The cumulative U0→F comparison is recorded separately from C0→U0 and local experiments. Rebased/squashed commits are rebound. Rollback artifacts are retained. Reports name the actual dependency order and remaining release authorization.

### 19.4 Final checklist

- [ ] The census covers all maintained entrypoints, nested manifests, packaged examples, generated inputs, and scripts.
- [ ] Exact Zig 0.17.0 executable and distribution identities govern every invocation.
- [ ] Distinct Boundary compiler/data pins and World's delivered artifact are recorded, not conflated.
- [ ] C0 and U0 are frozen; U1 is a genuinely compatibility-only successor.
- [ ] Reflection, bit representation, cleanup, arithmetic, and ownership migrations preserve contract-level positives and negatives.
- [ ] Host/guest module graphs, generated paths, pass-through arguments, and configuration invalidation are correct.
- [ ] Required authentication still runs on warm graphs and external module-consumer paths.
- [ ] Custom/symlinked package stores survive all cleanup and failed qualification.
- [ ] World retains its production profile, allocation budgets, exact stepping where required, pending bindings, and failure-atomic rollback.
- [ ] Borrow and allocator diagnostics expose intended injected faults and preserve valid neighboring behavior.
- [ ] Frozen codecs/components/programs/states pass independent old/new and cross-engine correspondence.
- [ ] Agent's real fresh path is measured; any resident promotion has full lifecycle and recovery evidence.
- [ ] All ten opportunities have deciding experiments; no unsupported speedup or platform claim remains.
- [ ] Every required T01–T70 case has a witness or a legitimate, reviewed applicability exclusion.
- [ ] New aliases are thin, existing aggregates retain the witnesses, and no duplicate orchestration system is introduced.
- [ ] Final archives/packages are independently acquired and source-free consumers pass.
- [ ] No unknown hashes, illustrative metrics, not-run gates, or stale-head results appear as completed evidence.
- [ ] Final costs and any necessary regressions are explicitly decided at their actual scope.
- [ ] Documentation is current; historical evidence is unchanged and correctly labeled.
- [ ] Rejected experiments, temporary migration shims, and watcher processes are removed.
- [ ] The complete rollback tuple exists, and no merge/release is misrepresented as authorized or executed.

**Final deliverable:** the implementation PRs and their dependency order, a qualified exact compiler/runtime/consumer tuple, a concise evidence-linked account of gains and costs, and a clean codebase retaining only justified changes. The intended result is a better-supported and economically improved existing architecture—not a second architecture attached to it.

## 20. Source register

Sources were inspected on 2026-10-03. Repository references below are pinned to the observed commits rather than mutable branch names. Release observations inform migration targets; all project-specific acceptance rules and experimental policies in this specification are proposed implementation requirements. No source is cited as evidence that these repositories already pass on Zig 0.17.0.

### Zig primary sources

- **[Z1]** Zig 0.17.0 release notes. Primary release-level migration inventory and known limitations. Individual standard-library signatures must be checked against the downloaded release before implementation.
- **[Z2]** Zig development log, 2026. Primary implementation accounts of pointer-stability diagnostics, bit semantics, and build-system work. Development-time details are subordinate to the tagged release.
- **[Z3]** Matthew Lugg, *Inside Zig's Incremental Compilation*. Primary implementer explanation of dependency tracking and the incremental workflow.

### Boundary source anchors

- **[B0]** Observed Boundary source commit.
- **[B1]** Package manifest: current minimum, package identity, packaged paths.
- **[B2]** Build graph: pure data, authoring, emitters, linking, and codec witnesses.
- **[B3]** Structural equality implementation: reflective traversal and recursive equality.
- **[B4]** Source-independent component-link tool.
- **[B5]** Consolidated optimization acceptance: existing independent checks, invariants, historical costs, and cross-package evidence.
- **[B6]** README: current architecture and production evaluator boundary.

### World source anchors

- **[W0]** Observed World source commit.
- **[W1]** Package manifest: distinct Boundary-data pin and minimum toolchain.
- **[W2]** Build graph: native/guest profiles and qualification targets.
- **[W3]** Store implementation: arrays, ownership, transaction journal, and rollback.
- **[W4]** Kernel entrypoint: generic ABI, workspace/budgets, and resident state.
- **[W5]** Runtime producer: exact toolchain gate, package discovery, source snapshot, build profile, and publish sequence.
- **[W6]** Runtime verifier: strict profile/dependency admission and consumed-byte validation.
- **[W7]** Runtime-bundle documentation: authenticated delivery and source-free acquisition.

### Agent source anchors

- **[A0]** Observed Agent source commit.
- **[A1]** Package manifest: authoring compiler pin and minimum toolchain.
- **[A2]** Build graph: authoring-only admission, exported modules, integration targets.
- **[A3]** Portable contracts: reflective schemas, supported type restrictions, canonical encoding, and owned decoding.
- **[A4]** Dependency lock: original compiler/runtime tuple and separate inventory profiles.
- **[A5]** Runtime bridge: the actual fresh-invocation path.
- **[A6]** Existing economy/replay tooling.

[Z1]: https://ziglang.org/download/0.17.0/release-notes.html
[Z2]: https://ziglang.org/devlog/2026/
[Z3]: https://mlugg.co.uk/posts/incremental-compilation-internals/
[B0]: https://github.com/tkersey/boundary/commit/93340dade30b7d27a1e139f107359f91fb66fad3
[B1]: https://github.com/tkersey/boundary/blob/93340dade30b7d27a1e139f107359f91fb66fad3/build.zig.zon
[B2]: https://github.com/tkersey/boundary/blob/93340dade30b7d27a1e139f107359f91fb66fad3/build.zig
[B3]: https://github.com/tkersey/boundary/blob/93340dade30b7d27a1e139f107359f91fb66fad3/src/data/record_equal.zig
[B4]: https://github.com/tkersey/boundary/blob/93340dade30b7d27a1e139f107359f91fb66fad3/tools/component_link.zig
[B5]: https://github.com/tkersey/boundary/blob/93340dade30b7d27a1e139f107359f91fb66fad3/docs/optimization-acceptance.md
[B6]: https://github.com/tkersey/boundary/blob/93340dade30b7d27a1e139f107359f91fb66fad3/README.md
[W0]: https://github.com/tkersey/world/commit/4b5e312152499d2cc4cc19b723df10918ad5d71b
[W1]: https://github.com/tkersey/world/blob/4b5e312152499d2cc4cc19b723df10918ad5d71b/build.zig.zon
[W2]: https://github.com/tkersey/world/blob/4b5e312152499d2cc4cc19b723df10918ad5d71b/build.zig
[W3]: https://github.com/tkersey/world/blob/4b5e312152499d2cc4cc19b723df10918ad5d71b/src/interpreter_v2/store.zig
[W4]: https://github.com/tkersey/world/blob/4b5e312152499d2cc4cc19b723df10918ad5d71b/src/kernel/main.zig
[W5]: https://github.com/tkersey/world/blob/4b5e312152499d2cc4cc19b723df10918ad5d71b/src/node/runtime-prepare.mjs
[W6]: https://github.com/tkersey/world/blob/4b5e312152499d2cc4cc19b723df10918ad5d71b/src/node/runtime-bundle.mjs
[W7]: https://github.com/tkersey/world/blob/4b5e312152499d2cc4cc19b723df10918ad5d71b/docs/runtime-bundles.md
[A0]: https://github.com/tkersey/agent/commit/b1f9d2866b5717d16339e7022a3b4d08951f0770
[A1]: https://github.com/tkersey/agent/blob/b1f9d2866b5717d16339e7022a3b4d08951f0770/build.zig.zon
[A2]: https://github.com/tkersey/agent/blob/b1f9d2866b5717d16339e7022a3b4d08951f0770/build_agent4.zig
[A3]: https://github.com/tkersey/agent/blob/b1f9d2866b5717d16339e7022a3b4d08951f0770/src/contracts.zig
[A4]: https://github.com/tkersey/agent/blob/b1f9d2866b5717d16339e7022a3b4d08951f0770/conformance/agent4/dependencies.lock.json
[A5]: https://github.com/tkersey/agent/blob/b1f9d2866b5717d16339e7022a3b4d08951f0770/runtime/world.mjs
[A6]: https://github.com/tkersey/agent/blob/b1f9d2866b5717d16339e7022a3b4d08951f0770/tools/agent4/economy.mjs