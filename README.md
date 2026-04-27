# ability

`ability` is a Zig library for generalized algebraic effects over a typed
`shift/reset` substrate. The longer-term direction is still a defunctionalized,
data-oriented interpreter model for agentic systems and other programmable
control systems, but the shipped surface today is smaller and simpler than the
repo's historical proof scaffolding suggested.

## Shipped Surface

The public root export set is intentionally narrow:

- `ability.effect`
- `ability.Runtime`
- `ability.RuntimeError`
- `ability.with`

Everything else in the repo is outside the `@import("ability")` root contract.
Maintainer-facing lowering and interpreter scaffolding are not a second public
front door.

The package also exports a retained `ability_agent_vm` module for compatibility
artifact execution. It is source-path stable and covered by smoke/freshness
tests, but it is a separate package module rather than part of the
`@import("ability")` root API.

`ability.with` is the only public lexical entrypoint. Downstream packages that
want compiled lexical execution for ordinary local body structs must make the
source witness part of the body type itself:

```zig
const Body = struct {
    fn sourceBytes() []const u8 {
        return @embedFile(std.Io.Dir.path.basename(@src().file));
    }

    fn sourceLocation() std.builtin.SourceLocation {
        return @src();
    }

    pub const source = sourceBytes();
    pub const source_hash = ability.sourceHash(sourceBytes());
    pub const source_file = "main.zig";
    pub const source_location = sourceLocation();
    pub const source_identity = "main.Body";

    pub fn body(eff: anytype) anyerror!i32 {
        return try eff.state.get();
    }
};

const result = try ability.with(&runtime, .{
    .state = ability.effect.state.use(@as(i32, 9)),
}, Body);
```

The source witness is raw file bytes plus the hash/file/location identity that
owns those bytes. For source-backed external bodies, keep `pub const source` and
`pub const source_hash` generated from the same file rather than hand-writing
them or importing bytes from a different same-named body. `@src()` must be
evaluated from a function scope, so examples use tiny comptime helpers to keep
the public witness fields as `pub const` declarations. Source-backed body
structs declare `pub const source_file` matching the owning `@src().file` value
and `pub const source_location` from a function inside the body declaration.
Named body structs also declare `pub const source_identity` matching the
top-level declaration selected from those bytes.
Bodies without a complete source witness, bodies whose source does not contain
the matching body declaration/file/location, and unsupported helper/import shapes
fail at compile time instead of falling back to interpreted execution.

## Dependency

Pin a release tag or exact commit rather than an unqualified branch:

```bash
zig fetch --save-exact=ability git+https://github.com/tkersey/ability.git#v0.0.2
```

That command writes a dependency entry with the package hash into the consuming
project's `build.zig.zon`:

```zig
.dependencies = .{
    .ability = .{
        .url = "git+https://github.com/tkersey/ability.git#v0.0.2",
        .hash = "<hash emitted by zig fetch>",
    },
}
```

Then import the package module from the consumer build:

```zig
const ability_dep = b.dependency("ability", .{
    .target = target,
    .optimize = optimize,
});
const ability_mod = ability_dep.module("ability");
```

For local dependency development, prefer Zig's package override flag:

```bash
zig build --fork=/absolute/path/to/ability
```

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

`zig build test` is the required executable test contract. Retained test
coverage must live under that default lane rather than under extra executable
test aliases. It keeps coverage on:

- the public lexical root
- the core semantic witness set
- fast source-ownership and source-backed body witnesses
- retained `ability_agent_vm` source-path consumer, fixture-freshness, and smoke checks
- source-lowering validation and execution
- source-lowering CLI safety checks
- interpreter behavior where it still underpins the lexical stack

Deleted child-build and package-export probes are not hidden behind opt-in test
steps; coverage that remains valuable is represented by fast default tests.

Manual run, tool, generator, and benchmark surfaces still exist for local
iteration, but they are not additional test contracts:

- `zig build run-*` for retained examples
- `zig build source-lower`
- `zig build generate-ability-agent-vm-fixture`
- `zig build bench*`
- `zig build zprof-hotspots`
