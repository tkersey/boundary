# shift

`shift` is a Zig library for generalized algebraic effects over a typed
`shift/reset` substrate. The longer-term direction is still a defunctionalized,
data-oriented interpreter model for agentic systems and other programmable
control systems, but the shipped surface today is smaller and simpler than the
repo's historical proof scaffolding suggested.

## Shipped Surface

The public root export set is intentionally narrow:

- `shift.effect`
- `shift.Runtime`
- `shift.RuntimeError`
- `shift.with`

Everything else in the repo is outside the `@import("shift")` root contract.
That includes sibling modules such as `shift_agent_vm` along with maintainer-facing
lowering and interpreter scaffolding.

## Examples

The ordinary user-facing examples live under `examples/`.

- `zig build run-state-basic`
- `zig build run-optional-basic`
- `zig build run-exception-basic`
- `zig build run-resource-basic`

Retained lowering, hosted-runtime, and proof fixtures also live under `examples/`
for maintainer workflows. Those files are executable and tested, but they are not
the ordinary public API story and should not be read as a second supported front
door.

## Verification

The ordinary verification contract is:

```bash
zig build
zig build test
zig build lint -- --max-warnings 0
```

`zig build test` is the required executable guardrail bar. It keeps coverage on:

- the public lexical root
- the core semantic witness set
- source-lowering validation and execution
- interpreter behavior where it still underpins the lexical stack

It no longer proves downstream package-boundary publication, retired/public-root
export bans, or compile-time misuse fixtures as part of the default contract.

Manual run, tool, and benchmark surfaces still exist for local iteration:

- `zig build run-*` for retained examples
- `zig build published-module-contract` for retained sibling-module/package checks
- `zig build source-lower`
- `zig build bench*`
- `zig build zprof-hotspots`
