# shift

## Purpose

`shift` exists to be a semantics-first Zig implementation of direct-style typed
`shift/reset`.

In the repo's current state, that means two things:

- the public front door is rooted in `shift.Row(.{ ... })` / `shift.mergeRows(.{ ... })`,
  `shift.effects.*`, `shift.handlers.*`, `shift.bind(...)`, and
  `shift.run(&runtime, closed)`
- the runtime remains explicit, thread-affine, and user-owned, without exposing
  a public continuation handle

The open-row front door is the only documented public authoring surface.
Retired root spellings are gone from the shipped root and are only guarded by
tombstone proofs.

The repo therefore treats runtime code as the last rung of a semantics ladder,
not as the source of truth:

1. law
2. executable reference witness
3. executable reference machine
4. CPS account
5. authored-body lowered runtime

The shipped runtime backend is the canonical authored-body lowered runtime.

The current public product claim is:

- structural rows are authored through `shift.Row(.{ ... })` and
  `shift.mergeRows(.{ ... })`
- built-in row fragments are exposed through `shift.effects.state`,
  `shift.effects.reader`, `shift.effects.optional`, `shift.effects.exception`,
  and `shift.effects.writer`
- builtin handler bridges are exposed through `shift.handlers.state`,
  `shift.handlers.reader`, `shift.handlers.optional`, `shift.handlers.exception`,
  and `shift.handlers.writer`
- `shift.Transform`, `shift.Choice`, and `shift.Abort` are the open-row leaf builders
- `const closed = shift.bind(BodyOrStage, handlers); try shift.run(&runtime, closed)` is the open-row execution story
- `shift.Decision(...)` remains the public choice-decision type
- prompt descriptors, `PromptMode`, `ResumeOrReturn`, `reset`, and `frontend`
  no longer live at the top level; repo-owned proof surfaces now reach them
  only through direct imports of `src/internal/prompt_support.zig`
- no public continuation handle is exported

## Semantic Commitments

- static `shift/reset`, not `control/prompt`
- one open-row front-door story with no public retired spellings
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
zig build source-lowering-gauntlet
zig build source-lower
zig build source-lowering-error-witness-check
zig build source-lowering-coverage-matrix-write
zig build source-lowering-coverage-check
zig build witness-admission-matrix-write
zig build witness-admission-matrix-check
zig build runtime-route-matrix-write
zig build runtime-route-matrix-check
zig build runtime-obligation-matrix-write
zig build runtime-obligation-matrix-check
zig build runtime-contract-suite
zig build public-error-api-ban
zig build retired-lane-inventory-check
zig build runtime-error-surface-matrix-write
zig build runtime-error-surface-matrix-check
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
zig build bench-family-matrix
zig build bench-family-matrix-stability
zig build bench-family-matrix-write
zig build bench-family-matrix-check
zig build bench-runtime-backends
zig build bench-runtime-backends-stability
zig build bench-runtime-backends-write
zig build bench-runtime-backends-check
zig build bench-state-effect
zig build bench-state-effect-write
zig build bench-state-effect-check
```

## Executable Contract

The repo's public claims are only considered shipped when they are backed by
one of these proof surfaces:

- `zig build test` for the combined runtime, witness, compile-fail, README, and
  formal-core gates
- `zig build effect-construction-boundary` for the generalized construction boundary
- `zig build public-root-contract-snapshot-check` for the open-row root tombstone snapshot
- `zig build public-error-api-ban` for the fail-closed proof that retired root spellings stay out of shipped docs/examples/root surfaces
- `zig build retired-lane-inventory-check` for the fail-closed proof that retired vocabulary stays out of proof-facing files
- `zig build compile-fail` for hidden continuation/context surfaces and forged
  capability misuse
- `zig build example-proof` for the exact-output open-row example corpus
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
- `zig build source-lowering-gauntlet` for the internal source-lowering corpus
- `zig build source-lowering-coverage-check` for the checked source-lowering
  coverage matrix that proves every current witness/example/declaration target
  is covered by the internal source-lowering track
- `zig build runtime-route-matrix-check` for the checked execution-route matrix
  that records whether supported cases are still replayed or now run through
  the shared lowered machine
- `zig build runtime-obligation-matrix-check` for the checked obligation matrix
  that records which public-runtime obligations still depend on the stackful
  backend
- `zig build runtime-contract-suite` for executable public-runtime contract
  cases that still guard the final stackful-backed behaviors
- `zig build runtime-error-surface-matrix-check` for the checked retained-vs-retired
  public runtime error surface
- `zig build source-lowering-error-witness-check` for the checked source-lowering-tool witness
  JSON surface over the canonical example corpus
- `zig build error-witness-equivalence-check` for the checked witness equivalence
  of the exported public runtime/setup witness surface across canonical source-lowering
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
- `zig build bench-family-matrix-check` for full shipped-family benchmark coverage
- `zig build bench-state-effect-check` for the checked benchmark artifact on a
  clean tree

The current open-row contract is now:

- rows are authored with `shift.Row(.{ ... })` and composed with `shift.mergeRows(.{ ... })`
- built-in row fragments come from `shift.effects.*`
- handlers are supplied explicitly through `shift.handlers.*`
- roots execute through `shift.bind(...)` plus `shift.run(&runtime, closed)`
- retired root spellings are checked by tombstone proofs instead of compatibility narratives

## Examples

### `open_row_state_writer`

```bash
zig build run-open-row-state-writer
```

Expected output:

```text
item=queued
final_state=6
value=done
```

The shipped public example corpus is open-row-only. Retired root spellings are
guarded by tombstone proofs instead of compatibility narratives.

The generalized construction boundary is checked by:

```bash
zig build effect-construction-boundary
```

The current hidden internal control-class coverage at the effect layer is:

- transform-style (`.resume_then_transform` internally): `state`, `reader`,
  `writer`
- choice-style (`.resume_or_return` internally): `optional`
- abortive (`.direct_return` internally): `exception`

## Benchmark Contract

Family coverage lives at:

```bash
zig build bench-family-matrix
zig build bench-family-matrix-stability
zig build bench-family-matrix-write
zig build bench-family-matrix-check
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
zig build bench-family-builder-decompose
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
zig build bench-family-matrix-stability
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

`docs/source_lowering_contract.md` is the versioned contract for the internal
source-lowering track. `zig build source-lowering-gauntlet` is the
green-only gate for the currently promised source-lowering wave, and
`tools/render_source_lowering_coverage_matrix.zig` renders the checked
`docs/source_lowering_coverage_matrix.json` matrix that records the current
source-lowering coverage for witnesses, examples, built-in declarations, and
user-defined effect rows.

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
operation, binding, and prompt machinery used beneath the open-row surface.
`zig build public-root-contract-snapshot-check` and `zig build public-error-api-ban`
are the tombstone truth gates for retired root spellings.

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

`tools/render_shipped_surface_frontier_matrix.zig` renders the checked
shipped-vs-reference routing map, which lives at
`docs/shipped_surface_frontier_matrix.json`.

`tools/render_surface_truth_scorecard.zig` renders the machine-readable
scorecard used by the final hidden-backend recommendation gate. The generated
artifact lives at `docs/surface_truth_scorecard.json`.

## Minimal Example

```zig
const shift = @import("shift");
const std = @import("std");

pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const WorkflowRow = shift.mergeRows(.{
        shift.effects.state(i32),
        shift.effects.writer([]const u8),
    });

    const Workflow = struct {
        pub const Uses = shift.Uses(WorkflowRow);

        pub fn body(eff: anytype) ![]const u8 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            try eff.writer.tell("queued");
            return "done";
        }
    };

    const closed = shift.bind(Workflow, .{
        .state = shift.handlers.state(@as(i32, 5)),
        .writer = shift.handlers.writer([]const u8, std.heap.page_allocator),
    });
    const result = try shift.run(&runtime, closed);
    defer std.heap.page_allocator.free(result.outputs.writer);

    for (result.outputs.writer) |item| {
        std.debug.print("item={s}\\n", .{item});
    }
    std.debug.print("value={s} state={d}\\n", .{ result.value, result.outputs.state });
}
```

See `src/root.zig` for the public surface, `src/witnesses.zig` for executable
witnesses, `test/witness_corpus_test.zig` and `test/semantic_manifest.zig` for
the locked semantic evidence, `FORMAL_CORE.md` for the implementation-derived
law anchors, and `examples/` for runnable usage.
