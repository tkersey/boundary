# API

`shift` now has three public layers:

1. `*.shift` source modules in `effects/`
2. generated Zig modules under `generated/`
3. the deprecated legacy runtime under `shift.legacy`

## DSL Contract

Each `*.shift` module is a single `(module ...)` form with:

- zero or more `(effect name request-type response-type)` declarations
- one `(export ...)` declaration
- one `(handlers ...)` block inside the export
- one `(program ...)` block inside the export

The bootstrap DSL currently supports:

- value types: `i32`, `bool`, `string`, `unit`
- expressions: identifiers, literals, `(add lhs rhs)`, `(perform effect request)`
- program statements: `(let name expr)`, `(return expr)`, terminal `(if cond (block ...) (block ...))`
- handler statements: `(let name expr)`, `(resume expr)`, `(discard expr)`, terminal `(if cond (block ...) (block ...))`

## Linearity Rules

- Handler resumptions are one-shot and checker-owned.
- A handler must `resume` or `discard` exactly once on every path.
- Statements after a terminal `resume`, `discard`, or terminal `if` are rejected.
- Exported programs may only `perform` effects that appear in the export's handler block.
- Exported programs must return on every path.

The proof artifacts are:

- `generated/<module>.zig`
- `generated/<module>.map.json`
- `generated/<module>.linear.json`

## Generated Zig Contract

Generated modules expose plain Zig functions only.

Examples in the current tree:

- `shift.generated.basic_resume.basicResume() -> i32`
- `shift.generated.no_capture.noCapture(value: i32) -> i32`
- `shift.generated.workflow.workflow(job: []const u8) -> []const u8`

Generated handler lowering is intentionally internal. Callers do not manipulate prompts, pending owners, or resumption tokens.

## Build Surfaces

- `zig build check-generated` fails if checked-in generated artifacts are stale.
- `zig build regen-linear` refreshes generated Zig, source maps, and linearity certificates.
- `zig build compile-fail` runs negative DSL fixtures.
- `zig build test` runs the generated-surface smoke checks plus the compile-fail harness.

## Legacy Surface

The old first-order machine runtime still exists behind `shift.legacy`.
It is no longer the documented front door.

## Non-Goals

- no ordinary Zig-only route to public type-level linearity
- no multi-shot continuations in the checked DSL
- no promise that `shift.legacy` remains the long-term product surface
