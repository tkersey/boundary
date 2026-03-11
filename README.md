# shift

## Purpose

`shift` now ships a checked effect language, not a runtime-first prompt API.
Authors write `*.shift` modules, `shiftc` typechecks one-shot linear resumption rules, and the repo checks in generated Zig, source maps, and linearity certificates.

In practice, the package now exists to:

- express effectful programs in a dedicated DSL with real checker-owned linearity
- compile those programs into plain Zig functions and types
- keep the old first-order continuation runtime only under `shift.legacy`

The public happy path is `shift.generated.*`, not `shift.Prompt` / `shift.run`.

## Build

```bash
zig build
zig build test
zig build lint -- --max-warnings 0
zig build size-check
zig build compile-fail
zig build check-generated
zig build regen-linear
zig build docs-sanity
```

## Examples

```bash
zig build run-basic-resume
zig build run-workflow
zig build bench
zig build bench-basic-effect
zig build bench-workflow
```

The checked DSL inputs live under `effects/`. Generated Zig and proof artifacts live under `generated/`.

See [docs/api.md](docs/api.md) for the live DSL and generated-surface contract.
