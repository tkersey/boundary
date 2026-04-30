# ability

`ability` is a Zig library for writing typed effect handlers through the
`ability.with` lexical entrypoint. The supported package surface is intentionally
small: effect bindings, runtime execution, source-backed lexical bodies, and a
retained compatibility module for ArtifactV1 execution.

## Shipped Surface

The public root export set is intentionally narrow:

- `ability.effect`
- `ability.Runtime`
- `ability.RuntimeError`
- `ability.sourceHash`
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

For a copy-runnable starting point inside this checkout, use
`examples/state_basic.zig` or run it with `zig build run-state-basic`. In a
downstream package, use a named body that carries its own source witness. This is
a complete `src/main.zig` shape after the build imports `ability` as shown below:

```zig
const std = @import("std");
const ability = @import("ability");

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

pub fn main(init: std.process.Init) !void {
    var runtime = ability.Runtime.init(init.gpa);
    defer runtime.deinit();

    const result = try ability.with(&runtime, .{
        .state = ability.effect.state.use(@as(i32, 9)),
    }, Body);

    var stdout_buffer: [64]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try stdout_writer.interface.print("{d}\n", .{result.value});
    try stdout_writer.interface.flush();
}
```

The source witness is raw file bytes plus the hash/file/location identity that
owns those bytes. For source-backed external bodies, keep `pub const source` and
`pub const source_hash` generated from the same file rather than hand-writing
them or importing bytes from a different same-named body. `@src()` must be
evaluated from a function scope, so examples use tiny comptime helpers to keep
the generated source and location fields as `pub const` declarations.
Source-backed body structs declare `pub const source_file` as the exact
`@src().file` string for the source owner; for the build shape above Zig reports
`main.zig`, even though the file is stored at `src/main.zig`. Named body structs
also declare `pub const source_identity` matching
the top-level declaration selected from those bytes.
Bodies without a complete source witness, bodies whose source does not contain
the matching body declaration/file/location, and unsupported helper/import shapes
fail at compile time instead of falling back to interpreted execution.

## Dependency

Requires Zig 0.16.0 for the commands below.

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
exe.root_module.addImport("ability", ability_mod);
```

For local dependency development, prefer Zig's package override flag:

```bash
zig build --fork=/absolute/path/to/ability
```

## Examples

The ordinary user-facing examples live under `examples/`.

- `zig build run-state-basic`
- `zig build run-reader-basic`
- `zig build run-optional-basic`
- `zig build run-exception-basic`
- `zig build run-resource-basic`
- `zig build run-writer-basic`
- `zig build run-custom-approval-workflow`

`examples/custom_approval_workflow.zig` is the package-like custom-effect proof
example. It defines separate generated families for directory lookup,
approval choice, and invalid-request abort, then pairs the public root surface
with a same-source maintainer lowering check in the `custom-effect-workflow`
test suite.

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
- retained `ability_agent_vm` source-path consumer, fixture-freshness, smoke,
  and no-host budget conformance checks
- source-lowering validation and execution
- source-lowering CLI safety checks
- interpreter behavior where it still underpins the lexical stack

For focused local iteration, `zig build test -Dtest-suites=<ids>` accepts a
comma-separated list of exact suite ids. Supported ids are:

```text
root
ability-agent-vm-consumer
ability-agent-vm-freshness
ability-agent-vm-smoke
ability-agent-vm-conformance
artifact-vm-runtime-build-host-log-budget
frontend
admitted-body-v1
program-plan-review
program-bridge
witness-corpus
runtime-contract
prompt-token
portability-contract
program-frontend-boundary
source-lowering-corpus
source-lowering-boundary
source-lowering-promoted
source-lowering-completion
source-lowering-tool
agent-vm-artifact-report
open-row-lowering
source-ownership-probe
custom-effect-workflow
comptime-contract
source-lowering-witness
lexical-witness
lexical-with
```

The focused custom-effect proof lane is:

```bash
zig build test -Dtest-suites=custom-effect-workflow --summary none
```

The regression bundle for the generalized effects path is:

```bash
zig build test -Dtest-suites=custom-effect-workflow,comptime-contract,source-ownership-probe,lexical-with,program-plan-review --summary none
```

Deleted child-build and package-export probes are not hidden behind opt-in test
steps; coverage that remains valuable is represented by fast default tests.

Manual run, tool, generator, and benchmark surfaces still exist for local
iteration, but they are not additional test contracts:

- `zig build run-*` for retained examples
- `zig build source-lower` to build `./zig-out/bin/ability-source-lower`
  (`./zig-out/bin/ability-source-lower --help` prints the tool contract)
- `zig build agent-vm-artifact-report` to build
  `./zig-out/bin/agent-vm-artifact-report`
- `zig build run-agent-vm-artifact-report -Dagent-vm-artifact=<path>` to classify
  one ArtifactV1 payload under the fixed no-host conformance profile. The
  report is runtime-only: it reads user-provided ArtifactV1 bytes, executes
  through `ability_agent_vm.runtime.runArtifactWithOptions`, rejects host-call
  artifacts as unsupported, and applies the fixed v1 budget profile
  (16 MiB artifact cap, zero host/log allowance, DataValue depth 64, nodes 4096,
  bytes 1 MiB). Artifact-size and log-budget envelope expansion are deferred
  follow-up surfaces, not part of this conformance report.
- `zig build check-ability-agent-vm-fixture` to verify the committed
  compatibility artifact fixture is current
- `zig build generate-ability-agent-vm-fixture` to regenerate the committed
  compatibility artifact fixture
  (`zig build generate-ability-agent-vm-fixture -- --help` prints generator help)
- `zig build bench`
- `zig build bench-first-suspend`
- `zig build bench-state-effect`
- `zig build bench-family-matrix`
- `zig build bench-runtime-backends`
- `zig build zprof-hotspots`
