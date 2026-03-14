# shift

## Purpose

`shift` exists to be a semantics-first Zig implementation of direct-style typed
`shift/reset`.

In the repo's current state, that means two things:

- the public surface is prompt-value-based, ATM-bearing, and protocol-driven
- the public API preserves direct-style ordinary Zig without exposing a public
  continuation handle

The repo therefore treats runtime code as the last rung of a semantics ladder,
not as the source of truth:

1. law
2. executable reference witness
3. executable reference machine
4. CPS account
5. fiber-backed stackful runtime

The current runtime backend is stackful and supported on `x86_64` and
`aarch64` hosts only. Unsupported hosts fail at compile time; this repo does
not ship a fallback backend.

The current public product claim is:

- `const P = shift.Prompt(.resume_then_transform, InAnswer, OutAnswer, ErrorSet); var prompt = P.init();`
- `shift.reset(&runtime, &prompt, body)`
- `shift.shift(Resume, &prompt, Handler)`
- `shift.algebraic` adds closed-world builder types `TransformOp`, `ChoiceOp`, `AbortOp`, `Program`, and `handleTransform` / `handleChoice` / `handleAbort` over the same runtime
- the handler protocol is selected by `PromptMode` at comptime
- `.resume_or_return` handlers may return `shift.ResumeOrReturn(Resume, OutAnswer)` and still provide `afterResume`
- protocol methods may return either plain values or `ResetError(ErrorSet)!...`

## Semantic Commitments

- static `shift/reset`, not `control/prompt`
- explicit typed prompt values
- comptime-selected handler protocols
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
zig build effect-construction-boundary
zig build readme-contract
zig build formal-core-write
zig build formal-core
zig build bench
zig build bench-first-suspend
zig build bench-effect-matrix
zig build bench-effect-matrix-write
zig build bench-effect-matrix-check
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
- `zig build compile-fail` for hidden continuation/context surfaces and forged
  capability misuse
- `zig build example-proof` for exact-output public example transcripts
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
- forged or cross-instance contexts fail at compile time; see:
  - `effect_exception_forged_context_throw_fails.zig`
  - `effect_state_forged_context_get_fails.zig`
  - `effect_reader_forged_context_ask_fails.zig`
  - `effect_optional_forged_context_request_fails.zig`
  - `effect_resource_forged_context_acquire_fails.zig`
  - `effect_writer_forged_context_tell_fails.zig`

The additive public algebraic-builder contract is now:

- `shift.algebraic.TransformOp`, `shift.algebraic.ChoiceOp`, and `shift.algebraic.AbortOp` define closed-world operation descriptors
- `shift.algebraic.Program(Answer, ErrorSet, .{ ...ops })` generates a typed runner surface
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
`shift.effect.writer.tell(Cap, ctx, item)`.

The generalized construction boundary is checked by:

```bash
zig build effect-construction-boundary
```

The current prompt-mode coverage at the effect layer is:

- `.resume_then_transform`: `state`, `reader`, `resource`, `writer`
- `.resume_or_return`: `optional`
- `.direct_return`: `exception`

## Benchmark Contract

Family coverage lives at:

```bash
zig build bench-effect-matrix
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

## Minimal Example

```zig
const shift = @import("shift");
const std = @import("std");

const DemoError = error{};
const DemoPrompt = shift.Prompt(.resume_then_transform, i32, i32, DemoError);

const demo = struct {
    var prompt_ptr: ?*const DemoPrompt = null;

    const Handle = struct {
        pub fn resumeValue() i32 {
            return 41;
        }

        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };

    fn body() shift.ResetError(DemoError)!i32 {
        const value = try shift.shift(i32, prompt_ptr.?, Handle);
        return value + 1;
    }
};

pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;

    const answer = try shift.reset(&runtime, &prompt, demo.body);
    _ = answer;
}
```

See `src/root.zig` for the public surface, `src/witnesses.zig` for executable
witnesses, `test/witness_corpus_test.zig` and `test/semantic_manifest.zig` for
the locked semantic evidence, `FORMAL_CORE.md` for the implementation-derived
law anchors, and `examples/` for runnable usage.
