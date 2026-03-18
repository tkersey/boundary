# shift

## Purpose

`shift` exists to be a semantics-first Zig implementation of direct-style typed
`shift/reset`.

In the repo's current state, that means two things:

- the canonical authored-body surface is source-validated and rooted in
  `shift.ordinary` / `shift-ordinary-lower`
- the public API still preserves direct-style ordinary Zig without exposing a
  public continuation handle

The lexical runtime surfaces remain public, but they now serve as
compatibility/runtime entrypoints beneath the canonical ordinary story:

- `shift.with(...)`
- `shift.effect.*`
- `shift.effect.Define(.{ ... })`
- `shift.algebraic`

The repo therefore treats runtime code as the last rung of a semantics ladder,
not as the source of truth:

1. law
2. executable reference witness
3. executable reference machine
4. CPS account
5. authored-body lowered runtime

The shipped runtime backend is the canonical authored-body lowered runtime.

The current public product claim is:

- `shift.ordinary` and `shift-ordinary-lower` are the canonical source-backed
  authoring entrypoints for the repo-owned ordinary, witness, generated,
  algebraic, and built-in effect corpus
- `shift.with(&runtime, handlers, Body)` remains the explicit compatibility
  runtime entrypoint
- built-in families still install lexical handlers through `shift.effect.state`,
  `shift.effect.reader`, `shift.effect.optional`, `shift.effect.exception`,
  `shift.effect.resource`, and `shift.effect.writer`
- `shift.effect.Define(.{ ... })` and `shift.algebraic` add user-defined and
  closed-world operation surfaces over the same lowered runtime
- `shift.With(...).Result` returns the body answer plus family outputs
- `shift.effect.choice.Decision(...)` is the public choice-decision type for
  lexical optional and generated choice handlers
- prompt descriptors, `PromptMode`, `ResumeOrReturn`, `reset`, and `frontend`
  no longer live at the top level; repo-owned proof surfaces now reach them
  only through direct imports of `src/internal/prompt_support.zig`
- no public continuation handle is exported

## Semantic Commitments

- static `shift/reset`, not `control/prompt`
- ordinary-first source-backed authoring with lexical/algebraic compatibility surfaces
- internal typed prompt discipline beneath that story
- one-shot continuation use
- honest answer-type pressure if the kernel requires it
- typed user errors in the host-language embedding

The first two hard witness families are:

- re-delimitation and static-vs-dynamic extent
- multi-prompt separation

## Proof Surface

`zig build test` is the default proof path. It includes the root tests,
transcript-locked witnesses, public-surface size checks, compile-fail misuse
fixtures, the current one-shot survey contract, exact-output example proof, the
README contract check, and the generated formal-core stale check.

```bash
zig build
zig build test
zig build lint -- --max-warnings 0
zig build size-check
zig build compile-fail
zig build one-shot-survey
zig build example-proof
zig build backend-parity
zig build proof-fixtures-write
zig build proof-fixtures-check
zig build authoring-lowering-write
zig build authoring-lowering-check
zig build structured-program-suite
zig build direct-style-bridge-parity
zig build direct-style-boundary
zig build ordinary-zig-gauntlet
zig build ordinary-lower
zig build ordinary-error-witness-check
zig build surface-replacement-matrix-write
zig build surface-replacement-check
zig build witness-admission-matrix-write
zig build witness-admission-matrix-check
zig build runtime-route-matrix-write
zig build runtime-route-matrix-check
zig build runtime-obligation-matrix-write
zig build runtime-obligation-matrix-check
zig build runtime-contract-suite
zig build public-error-api-ban
zig build runtime-error-surface-matrix-write
zig build runtime-error-surface-matrix-check
zig build root-surface-migration-matrix-write
zig build root-surface-migration-matrix-check
zig build error-witness-equivalence-check
zig build shipped-surface-frontier-matrix-write
zig build shipped-surface-frontier-matrix-check
zig build frontend-feature-matrix-write
zig build frontend-feature-matrix-check
zig build no-raw-repo-refs-check
zig build shipped-backend-check
zig build surface-truth-scorecard-write
zig build surface-truth-scorecard-check
zig build effect-construction-boundary
zig build readme-contract
zig build formal-core-write
zig build formal-core
zig build bench
zig build bench-first-suspend
zig build bench-effect-matrix
zig build bench-effect-matrix-stability
zig build bench-effect-matrix-write
zig build bench-effect-matrix-check
zig build bench-runtime-backends
zig build bench-runtime-backends-stability
zig build bench-runtime-backends-write
zig build bench-runtime-backends-check
zig build bench-state-effect
zig build bench-state-effect-write
zig build bench-state-effect-check
zig build shared-algebraic-engine-boundary
```

## Executable Contract

The repo's public claims are only considered shipped when they are backed by
one of these proof surfaces:

- `zig build test` for the combined runtime, witness, compile-fail, README, and
  formal-core gates
- `zig build effect-construction-boundary` for the generalized construction boundary
- `zig build shared-algebraic-engine-boundary` for the checked claim that public `shift.algebraic` and `shift.effect.*` now share one internal algebraic engine
- `zig build compile-fail` for hidden continuation/context surfaces and forged
  capability misuse
- `zig build example-proof` for exact-output public example transcripts
- `zig build backend-parity` for the hidden lowered proof engine over the
  canonical scenario IR, kept strictly beneath the canonical public
  `shift/reset` surface
- `zig build proof-fixtures-check` for generator-owned exact-output fixture
  artifacts derived from the canonical lowered scenario registry
- `zig build authoring-lowering-check` for checked lowered snapshots from the
  internal structured-program front end into the canonical lowered IR
- `zig build structured-program-suite` for internal scaffolding coverage of the
  lowered proof engine
- `zig build direct-style-bridge-parity` for unchanged-body parity checks over
  the supported direct-style bridge corpus
- `zig build direct-style-boundary` for explicit boundary checks around
  unsupported unchanged direct-style shapes
- `zig build ordinary-zig-gauntlet` for the canonical ordinary-backed corpus
- `zig build surface-replacement-check` for the checked canonical replacement
  ledger that proves every current witness/example/effect target is ordinary-backed
- `zig build runtime-route-matrix-check` for the checked execution-route matrix
  that records whether supported cases are still replayed or now run through
  the shared lowered machine
- `zig build runtime-obligation-matrix-check` for the checked obligation matrix
  that records which public-runtime obligations still depend on the stackful
  backend
- `zig build runtime-contract-suite` for executable public-runtime contract
  cases that still guard the final stackful-backed behaviors
- `zig build public-error-api-ban` for the fail-closed proof that banned legacy
  public error spellings are gone from shipped docs/examples/root surfaces
- `zig build runtime-error-surface-matrix-check` for the checked retained-vs-retired
  public runtime error surface
- `zig build root-surface-migration-matrix-check` for the checked canonical-root
  migration map during the lowered-first runtime cut
- `zig build ordinary-error-witness-check` for the checked ordinary-tool witness
  JSON surface over the canonical example corpus
- `zig build error-witness-equivalence-check` for the checked witness equivalence
  of the exported public runtime/setup witness surface across canonical ordinary
  example cases
- `zig build shipped-surface-frontier-matrix-check` for the checked shipped-vs-lowered
  routing truth surface
- `zig build frontend-feature-matrix-check` for the checked matrix that records
  which authored-body frontend capabilities are covered across the canonical
  surface
- `zig build no-raw-repo-refs-check` for the fail-closed proof that the repo no
  longer references the deleted raw runtime tree
- `zig build shipped-backend-check` for the checked guarantee that the shipped
  path no longer depends on deleted stackful runtime components
- `zig build surface-truth-scorecard-check` for the machine-readable
  maintainers' scorecard that summarizes whether the lowered path can honestly
  stay hidden beneath the canonical public surface
- `zig build bench-runtime-backends-check` for checked lowered-vs-stack runtime
  backend comparison over the currently supported bridge corpus
- `zig build bench-effect-matrix-check` for full shipped-family benchmark coverage
- `zig build bench-state-effect-check` for the checked benchmark artifact on a
  clean tree

The additive effect-family contract is now:

- bodies are helper-shaped: `body(comptime Cap, ctx)`
- operations are capability-checked helpers:
  - `shift.effect.state.get(Cap, ctx)` / `shift.effect.state.set(Cap, ctx, value)`
  - `shift.effect.reader.ask(Cap, ctx)`
  - `shift.effect.optional.request(Cap, ctx)`
  - `shift.effect.exception.throw(Cap, ctx, payload)`
  - `shift.effect.resource.acquire(Cap, ctx)`
  - `shift.effect.writer.tell(Cap, ctx, item)`
- user-defined sealed families are available through `shift.effect.Define(.{ ... })`
  with `shift.effect.ops.Transform(...)`, `shift.effect.ops.Choice(...)`, and
  `shift.effect.ops.Abort(...)`
- generated families expose `Instance`, `computeProgram`, `handle`, `OpTag`,
  `definition`, `proof`, and `Op(.tag).perform(...)` / `Op(.tag).program(...)`.
  When installed through the lexical front door, generated transform, choice,
  and abort families also expose named op fields such as
  `eff.counter.get.perform(...)`, `eff.picker.pick.perform(...)`, and
  `eff.guard.fail.abort(...)`
- forged or cross-instance contexts fail at compile time; see:
  - `effect_exception_forged_context_throw_fails.zig`
  - `effect_state_forged_context_get_fails.zig`
  - `effect_reader_forged_context_ask_fails.zig`
  - `effect_optional_forged_context_request_fails.zig`
  - `effect_resource_forged_context_acquire_fails.zig`
  - `effect_writer_forged_context_tell_fails.zig`
  - `effect_define_forged_context_fails.zig`
  - `effect_define_cross_instance_context_fails.zig`

The additive public algebraic-builder contract is now:

- `shift.algebraic.TransformOp`, `shift.algebraic.ChoiceOp`, and `shift.algebraic.AbortOp` define closed-world operation descriptors
- `shift.algebraic.Program(Answer, .{ ...ops })` generates a typed runner surface
- `Program.handlers(.{ ... })` installs handlers in declaration order
- `Configured.Context.perform(Op, payload)` only accepts declared ops
- handlers are built with static `Impl` types via `handleTransform` / `handleChoice` / `handleAbort`
- the builder surface is currently proven by `zig build size-check`, `zig build compile-fail`, and `zig build example-proof`
- the public surface still does not export a continuation handle

## Examples

### `algebraic_abortive_validation`

```bash
zig build run-algebraic-abortive-validation
```

Expected output:

```text
validate=name
abort=missing-name
final=error=missing-name
```

### `algebraic_artifact_search`

```bash
zig build run-algebraic-artifact-search
```

Expected output:

```text
query=artifact-search
messages=1
tool_calls=0
memory_blocks=1
opencode_source=jsonl
total=3
```

### `direct_return`

```bash
zig build run-early-exit
```

Expected output:

```text
handler-direct-return
final=result=early
```

### `resume_or_return`

```bash
zig build run-resume-or-return
```

Expected output:

```text
branch=return_now
handler-return-now
final=result=early
branch=resume_with
handler-decide-resume
body-after-shift
handler-after-resume
final=answer=42
```

### `resume_then_transform`

```bash
zig build run-nested-workflow
```

Expected output:

```text
workflow=queued
audit=entered
audit=after
approval=publish
workflow=done
result=completed
```

### Extra `resume_then_transform` Example

```bash
zig build run-generator
```

Expected output:

```text
yield=1
yield=2
yield=3
done=3
```

### `define_basic`

```bash
zig build run-define-basic
```

Expected output:

```text
counter=6
```

### `reader_effect`

```bash
zig build run-reader-basic
```

Expected output:

```text
env=21
value=42
```

### `exception_effect`

```bash
zig build run-exception-basic
```

Expected output:

```text
branch=pass
body-pass
final=result=ok
branch=throw
body-before-throw
catch=result=boom
final=result=boom
```

### `optional_effect`

```bash
zig build run-optional-basic
```

Expected output:

```text
branch=return_now
policy-return-now
final=result=early
branch=resume_with
policy-resume
body-after-request
policy-after-resume
final=answer=42
```

### `resource_effect`

```bash
zig build run-resource-basic
```

Expected output:

```text
acquire=a
use=a
acquire=b
use=b
release=b
release=a
final=done
```

### `writer_effect`

```bash
zig build run-writer-basic
```

Expected output:

```text
item=a
item=b
value=done
```

### `state_effect`

```bash
zig build run-state-basic
```

Expected output:

```text
before=5
after=6
final_state=6
value=11
```

The strict effect families now use helper-based bodies of the form
`body(comptime Cap, ctx)` together with family operations such as
`shift.effect.reader.ask(Cap, ctx)` and
`shift.effect.state.get(Cap, ctx)` / `shift.effect.state.set(Cap, ctx, value)`
plus `shift.effect.optional.request(Cap, ctx)`,
`shift.effect.exception.throw(Cap, ctx, payload)`, and
`shift.effect.resource.acquire(Cap, ctx)`, plus
`shift.effect.writer.tell(Cap, ctx, item)`. User-defined sealed families are
declared with `shift.effect.Define(.{ ... })` and expose
`Op(.tag).perform(...)` or `Op(.tag).program(...)` over the same exact-context
boundary, while the lexical front door projects generated choice and abort
families as named op fields (`eff.<binding>.<op>.perform(...)` /
`eff.<binding>.<op>.abort(...)`), and generated transform families as named
op fields like `eff.<binding>.<op>.perform(...)`.

The generalized construction boundary is checked by:

```bash
zig build effect-construction-boundary
```

The current hidden internal control-class coverage at the effect layer is:

- transform-style (`.resume_then_transform` internally): `state`, `reader`,
  `resource`, `writer`
- choice-style (`.resume_or_return` internally): `optional`
- abortive (`.direct_return` internally): `exception`
- `shift.effect.Define(.{ ... })`: user-defined sealed families for one chosen
  non-resource mode per family (`.resume_then_transform`, `.resume_or_return`,
  or `.direct_return`)

## Benchmark Contract

Family coverage lives at:

```bash
zig build bench-effect-matrix
zig build bench-effect-matrix-stability
zig build bench-effect-matrix-write
zig build bench-effect-matrix-check
```

The checked matrix artifact is:

- `bench/baselines/effect_family_matrix_v2.json`

It now splits lanes into three classes:

- `micro`: fixed wrapper tax
- `amortized`: heavier representative work
- `investigation`: intentionally loose diagnostic lanes for still-suspicious ratios

The covered lanes are:

- `state_micro`
- `reader_micro`
- `reader_batch8`
- `optional_return_now_micro`
- `optional_return_now_prelude8`
- `optional_resume_with_micro`
- `optional_resume_with_batch8`
- `exception_throw_micro`
- `exception_throw_prelude8`
- `algebraic_transform_micro`
- `algebraic_choice_return_now_micro`
- `algebraic_abort_micro`
- `resource_normal_4`
- `resource_normal_32`
- `writer_micro`
- `writer_batch16`
- `writer_batch64`

The current performance model is:

- `direct_frame`: `state_micro`, `reader_micro`, `reader_batch8`
- `abortive_control`: `optional_*`, `exception_*`
- `storage_backed`: `resource_*`, `writer_*`

The decomposition benches are intentionally separate from the checked artifacts:

```bash
zig build bench-writer-decompose
zig build bench-resource-decompose
zig build bench-abortive-decompose
zig build bench-algebraic-decompose
```

Use them to localize storage/finalization/cleanup or abortive fixed-tax costs before changing code; they are investigative and do not define the checked public benchmark contract.

The checked state-effect artifact lives at
`bench/baselines/state_effect_v1.json`. Refresh it with:

```bash
zig build bench-state-effect-write
```

Validate it against the current clean tree with:

```bash
zig build bench-state-effect-check
```

The write/check workflow is fail-closed by default on dirty trees and records
the exact `git_rev`, `repo_state`, benchmark command, warmed sample arrays, lane classes, and the observed per-lane median ratios.

The clean-tree stability harness lives at:

```bash
zig build bench-effect-matrix-stability
```

It repeats the checked effect matrix on unchanged clean-tree code and reports
whether each lane is `stable_pass`, `stable_fail`, or `flaky`.

The lowered-vs-stack backend comparison harness lives at:

```bash
zig build bench-runtime-backends
zig build bench-runtime-backends-stability
zig build bench-runtime-backends-write
zig build bench-runtime-backends-check
```

It compares the current stack runtime baseline against the private lowered
runtime seam over the supported bridge corpus and records explicit per-case
ratio budgets in `bench/baselines/runtime_backend_matrix_v1.json`. The stack
side of that comparison is routed through `src/runtime_stack_baseline.zig`,
which preserves the current stack-runtime behavior as an internal benchmark
baseline while the lowered-only runtime branch is under construction.

## Formal Core

`FORMAL_CORE.md` is the small implementation-derived law surface, but it is now
generator-owned rather than hand-maintained. Refresh it with:

```bash
zig build formal-core-write
```

Check it for drift with:

```bash
zig build formal-core
```

The generated artifact preserves the live law anchors for semantic witnesses,
strict effect-capability claims, the additive public algebraic builders, and
the optional-resumption family without turning into a second README.

The hidden lowered proof engine is exercised by:

```bash
zig build backend-parity
```

The typed kernel in `src/parity_kernel.zig` now owns the hard witness core plus
the `nested_workflow` publish path, while `src/parity_machine.zig` continues to
route every untouched case through the legacy transcript-first proof path. This
remains proof infrastructure rather than a public fallback runtime.

The canonical lowered proof source now lives in `src/parity_scenarios.zig`.
`tools/render_proof_fixtures.zig` renders the checked exact-output fixture
artifacts from that registry, and `zig build proof-fixtures-check` verifies they
remain current before exact-output example proof runs.

The internal structured-program scaffolding layer is `src/program_frontend.zig`.
`tools/render_authoring_lowerings.zig` renders checked lowering snapshots, and
`zig build structured-program-suite` proves the chosen witness/example/effect
corpus lowers into canonical scenarios and executes correctly. The current raw
direct-style boundary is documented in `docs/direct_style_boundary.md` and
checked by `zig build direct-style-boundary`.

`docs/ordinary_zig_contract.md` is the versioned contract for the current
ordinary-Zig experimental track. `zig build ordinary-zig-gauntlet` is the
green-only gate for the currently promised ordinary-Zig wave, and
`tools/render_surface_replacement_matrix.zig` renders the checked
`docs/surface_replacement_matrix.json` ledger that tracks the long-horizon
ordinary-body replacement bar for current witnesses, examples, and effect
surfaces.

`tools/render_witness_admission_matrix.zig` renders the checked
`docs/witness_admission_matrix.json` ledger that separates lexical witness proof
from unchanged-body bridge admission.

`src/program_bridge.zig` is the current hidden-backend bridge for the supported
unchanged direct-style subset, and `src/private_lowered_runtime.zig` is the
internal lowered-runtime seam that executes that supported subset without
changing the public API. `zig build direct-style-bridge-parity` proves
that subset against the canonical lowered scenarios, and
`tools/render_runtime_route_matrix.zig` renders the machine-readable route
matrix showing that those supported cases now execute through the shared
lowered machine instead of direct scenario replay.
The generated artifact lives at `docs/runtime_route_matrix.json`.

`src/lowered_machine.zig` is now the shared executable machine core, while
`src/parity_kernel.zig` acts as a proof façade over that core.

`src/internal/algebraic_engine.zig` now owns the shared internal
operation/binding/prompt machinery used by both `src/algebraic.zig` and
`src/effect/algebraic.zig`. `zig build shared-algebraic-engine-boundary` is the
architectural truth gate for that claim.

`zig build runtime-route-matrix-check` is the architectural truth gate for that
claim, and
`zig build runtime-obligation-matrix-check` is the remaining-contract truth
gate for the parts of the public runtime surface that are now compat-only or
otherwise outside the shipped backend path.
`tools/render_runtime_obligation_matrix.zig` renders that artifact, which lives
at `docs/runtime_obligation_matrix.json`.

`zig build runtime-contract-suite` is the executable complement to that
artifact: it runs the remaining public-runtime contract cases through the
current public API so the remaining runtime obligations are tracked by tests,
not just by documentation.

`tools/render_runtime_error_surface_matrix.zig` renders the checked public
runtime error surface policy, which lives at
`docs/runtime_error_surface_matrix.json`.

`tools/render_frontend_feature_matrix.zig` renders the checked canonical
frontend capability matrix, which lives at
`docs/frontend_feature_matrix.json`.

`tools/render_root_surface_migration_matrix.zig` renders the checked canonical
root migration map, which lives at `docs/root_surface_migration_matrix.json`.

`tools/render_shipped_surface_frontier_matrix.zig` renders the checked
shipped-vs-compat routing map, which lives at
`docs/shipped_surface_frontier_matrix.json`.

`tools/render_surface_truth_scorecard.zig` renders the machine-readable
scorecard used by the final hidden-backend recommendation gate. The generated
artifact lives at `docs/surface_truth_scorecard.json`.

## Minimal Example

```zig
const shift = @import("shift");
const std = @import("std");

const NoError = error{};

pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(@as(i32, 5)),
        .reader = shift.effect.reader.use(@as(i32, 21)),
    }, struct {
        pub fn body(eff: anytype) !i32 {
            const env = try eff.reader.ask();
            const before = try eff.state.get();
            try eff.state.set(before + env);
            return try eff.state.get();
        }
    });

    std.debug.print("value={d} state={d}\n", .{ result.value, result.outputs.state });
}
```

See `src/root.zig` for the public surface, `src/witnesses.zig` for executable
witnesses, `test/witness_corpus_test.zig` and `test/semantic_manifest.zig` for
the locked semantic evidence, `FORMAL_CORE.md` for the implementation-derived
law anchors, and `examples/` for runnable usage.
