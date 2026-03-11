# shift

## Purpose

`shift` exists to let Zig code express delimited control as explicit, first-order, fully linear machine data. Instead of capturing arbitrary Zig stacks or hiding control flow behind a stackful runtime, it makes suspension, resumption, and escape explicit through typed prompts, machine steps, `Pending`, and `EscapedOwner`.

In practice, the library's job is to:

- provide typed routing points with `Prompt(Request, Resume)`
- drive user-defined machines through `run(Machine, &runtime, initial_frame)`
- return owned continuation state as `Pending` or `EscapedOwner` instead of implicit stack capture

It is not a live native-body `reset` / `shift` runtime.

## Build

```bash
zig build
zig build test
zig build lint -- --max-warnings 0
zig build size-check
zig build compile-fail
zig build docs-sanity
```

## Examples

```bash
zig build run-basic-resume
zig build run-multi-prompt
zig build run-delayed-escape
zig build run-workflow-linear
```

See [docs/api.md](docs/api.md) for the live machine contract.
