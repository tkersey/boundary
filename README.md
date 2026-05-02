# ability

`ability` lets Zig programs write effectful bodies and provide typed handlers
for state, reader, writer, exceptions, resources, choices, and custom effects.
Use `ability.with` for ordinary one-shot runtime execution; use
`ability.program` when a lexical body should be compiled once into a reusable
ProgramPlan execution and ArtifactV1 namespace; use `ability.compile` when a
runtime-owned `ProgramPlan` must be emitted as an ArtifactV1 payload. The
supported package surface is intentionally small: effect bindings, runtime
execution, compile-once lexical programs, ProgramPlan-first artifact
compilation, and a retained compatibility module for ArtifactV1 execution.

Start with `ability.with` when a Zig program needs to run an effectful body with
typed handlers in the same process. Reach for `ability.program` when the caller
wants a named compiled surface it can run repeatedly, inspect as
`runtime_plan`, or package as ArtifactV1. Reach for `ability.compile` only when
a caller already owns a `ProgramPlan` and needs to package it as ArtifactV1 for
the retained agent-VM compatibility path.

## Shipped Surface

The public root export set is intentionally narrow:

- `ability.effect`
- `ability.Runtime`
- `ability.RuntimeError`
- `ability.sourceHash`
- `ability.with`
- `ability.program`
- `ability.CompileOptionsV1`
- `ability.CompilePlan`
- `ability.compile`

Everything else in the repo is outside the `@import("ability")` root contract.
Maintainer-facing lowering and interpreter scaffolding are not a second public
front door.

The package also exports a retained `ability_agent_vm` module for compatibility
artifact execution. It is source-path stable and covered by smoke/freshness
tests, but it is a separate package module rather than part of the
`@import("ability")` root API.

`ability.with` is the public one-shot lexical entrypoint. `ability.program` is
the public compile-once lexical entrypoint: call
`ability.program("label", @TypeOf(handlers), Body, .{})` to get a namespace that
exposes `runtime_plan`, `ir_hash`, `run`, `encodeArtifactV1`,
`decodeArtifactV1`, `disasmArtifactV1`, and the shorter `encode`/`decode`/
`disasmAlloc` aliases. `ability.compile` remains the public ProgramPlan-first
ArtifactV1 entrypoint for callers that already own a `ProgramPlan`.
Downstream packages that want lexical execution or compiled lexical packaging
for ordinary local body structs must make the source witness part of the body
type itself:

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
zig fetch --save-exact=ability git+https://github.com/tkersey/ability.git#v0.1.0
```

That command writes a dependency entry with the package hash into the consuming
project's `build.zig.zon`:

```zig
.dependencies = .{
    .ability = .{
        .url = "git+https://github.com/tkersey/ability.git#v0.1.0",
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

Consumers that need the retained ArtifactV1 compatibility module import it as a
separate package module:

```zig
const ability_agent_vm_mod = ability_dep.module("ability_agent_vm");
exe.root_module.addImport("ability_agent_vm", ability_agent_vm_mod);
```

For local dependency development, prefer Zig's package override flag:

```bash
zig build --fork=/absolute/path/to/ability
```

## Examples

The ordinary user-facing examples live under `examples/`.

| Command | Demonstrates | Expected output includes |
| --- | --- | --- |
| `zig build run-state-basic` | Additive state handling | `before=5`, `after=6`, `final_state=6`, `value=11` |
| `zig build run-reader-basic` | Environment lookup through a reader effect | `env=21`, `value=42` |
| `zig build run-optional-basic` | Optional early return and resume branches | `branch=return_now` and `branch=resume_with` transcripts |
| `zig build run-exception-basic` | Caught and normal exception branches | `branch=pass` and `branch=throw` transcripts |
| `zig build run-resource-basic` | LIFO resource acquisition and release | `acquire=a`, `use=a`, `acquire=b`, `use=b`, `release=b`, `release=a`, `final=done` |
| `zig build run-writer-basic` | Writer output collection | `item=a`, `item=b`, `value=done` |
| `zig build run-custom-approval-workflow` | Custom generated effects with approval choice and abort branches | `approve=...`, `deny=...`, and `invalid=...` summary lines |

`examples/custom_approval_workflow.zig` is the package-like custom-effect proof
example. It defines separate generated families for directory lookup,
approval choice, and invalid-request abort, then pairs the public root surface
with ProgramPlan-first ArtifactV1 emission in the `custom-effect-workflow`
test suite. Same-source lowering remains in that suite only as a maintainer
oracle for producing and comparing the runtime-owned ProgramPlan.

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
agent-vm-artifact-report
source-ownership-probe
custom-effect-workflow
comptime-contract
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
- `zig build agent-vm-artifact-report` to build
  `./zig-out/bin/agent-vm-artifact-report`
  (`./zig-out/bin/agent-vm-artifact-report --help` prints report-tool help)
- `zig build run-agent-vm-artifact-report -Dagent-vm-artifact=<path>` to classify
  one ArtifactV1 payload under the fixed no-host conformance profile. The
  report is runtime-only: it reads user-provided ArtifactV1 bytes, executes
  through `ability_agent_vm.runtime.runArtifactWithOptions`, rejects host-call
  artifacts and artifacts that declare output snapshots as unsupported, and
  applies the fixed v1 budget profile
  (16 MiB artifact cap, zero host/log allowance, DataValue depth 64, nodes 4096,
  bytes 1 MiB). For a clean machine-readable stream, build the tool and run
  `./zig-out/bin/agent-vm-artifact-report --json --artifact <path>` or
  `./zig-out/bin/agent-vm-artifact-report --format json --artifact <path>`;
  those direct invocations print a stable `schema_version`, `status`, `code`,
  and `detail` verdict object with strict exit statuses. Build-step runs use
  report-only mode, may add `-Dagent-vm-artifact-format=json`, and emit verdicts
  without turning non-compatible classifications into build failures; input and
  artifact-read errors still fail the build.
  Artifact-size and log-budget envelope expansion are deferred follow-up
  surfaces, not part of this conformance report.
- `zig build check-ability-agent-vm-fixture` to verify the committed
  compatibility artifact fixture is current
- `zig build generate-ability-agent-vm-fixture` to regenerate the committed
  compatibility artifact fixture
  (`zig build generate-ability-agent-vm-fixture -- --help` prints generator help)
- `zig build generate-agent-vm-conformance-fixtures` to build the internal
  Agent VM conformance fixture generator helper
  (`./zig-out/bin/generate-agent-vm-conformance-fixtures --help` prints helper
  usage after the build step installs the binary)
- `zig build bench`
- `zig build bench-first-suspend`
- `zig build bench-state-effect`
- `zig build bench-family-matrix`
- `zig build bench-runtime-backends`
- `zig build zprof-hotspots`
