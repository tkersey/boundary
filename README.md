# shift

`shift` is a Zig 0.15.2 library for fully linear delimited control over explicit first-order machine data.

The live product is an explicit machine DSL:

- `Prompt(Request, Resume)` defines typed routing points
- `run(Machine, &runtime, initial_frame)` drives a machine from an initial frame
- `Machine.step(frame, resume)` returns either `.complete` or `.@"suspend"`
- `Pending` and `EscapedOwner` own first-order continuation data, not arbitrary Zig stacks

The previous native-body stackful runtime is archived under [`archive/experimental-control-runtime`](archive/experimental-control-runtime).

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
