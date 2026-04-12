# shift

`shift` is a Zig library for generalized algebraic effects over a typed
`shift/reset` substrate. The longer-term direction is still a defunctionalized,
data-oriented interpreter model for agentic systems and other programmable
control systems, but the shipped surface today is smaller and simpler than the
repo's historical proof scaffolding suggested.

## Shipped Surface

The ordinary public root is intentionally narrow:

- `shift.effect.*`
- `shift.effect.Define(...)`
- `shift.with(...)`
- `shift.Runtime`
- `shift.RuntimeError`

The repo also contains maintainer-facing specialist surfaces for explicit IR,
lowering, ArtifactV1, HostAdapterV1, durable replay, and interpreter stepping.
Those remain executable and tested, but they are not documented here as a
second public story.

## Examples

Representative examples live under `examples/`.

- `zig build run-state-basic`
- `zig build run-optional-basic`
- `zig build run-exception-basic`
- `zig build run-resource-basic`

## Verification

The ordinary verification contract is:

```bash
zig build
zig build test
zig build lint -- --max-warnings 0
```

`zig build test` is the required executable guardrail bar. It keeps coverage on:

- the public lexical root and compile-fail misuse boundaries
- the core semantic witness set
- source-lowering validation and execution
- ArtifactV1, HostAdapterV1, durable replay, and interpreter behavior

Focused suites still exist for local iteration when you are touching a specific
area:

- `zig build compile-fail`
- `zig build kernel-source-lowering-check`
- `zig build artifact-v1-api-check`
- `zig build artifact-vm-runtime-check`
- `zig build host-adapter-conformance-check`
- `zig build durable-session-resume-check`
- `zig build interpreter-portability-check`

Performance checks are no longer part of the ordinary contract. Use them for
perf or release work:

```bash
zig build bench-state-effect-check
zig build bench-runtime-backends-check
```
