# Boundary 2

Boundary checks staged Zig computations and handlers and compiles them into
complete, portable BPI2 program data. World 5 executes that data with one generic
native/WASM interpreter. Boundary contains no production evaluator.

Boundary `2.0.0` uses Zig `0.16.0`.

## Author and compile

Import the Zig build module `boundary`. Its public namespaces are `effect`,
`computation`, `handler`, `region`, `program`, `data_v2`, `image_v2`,
`snapshot_v2`, `protocol_v2`, and `library`.

An application implements `emit(builder)` using the checked staged builder.
`boundary.program.lower(allocator, Application)` checks and lowers that source;
`compiled.encode(allocator, destination)` emits BPI2 into caller-owned storage.
Arbitrary native Zig function bodies and closures are not translated.

`program.compileObserved(allocator, module, .{ .diagnostic = &diagnostic })`
uses the same compiler with caller-owned diagnostic storage. Errors identify
the source function, term, capture variable or target call edge when applicable.
An optional phase observer measures checking and lowering without changing
the emitted program.

[`examples/one_effect.zig`](examples/one_effect.zig) is a complete compiler-only
program. Build and emit it with:

```sh
zig build emit-one-effect -Doptimize=ReleaseSafe > example.bpi2
```

Its initial argument and result are canonical little-endian `u32` values. A
World runtime returns the typed `example.lookup.v2` request; the environment
supplies the result. Application handlers, search, scheduling and cleanup
policies compile into ordinary program data rather than host callbacks.

`library` provides State, Reader/local, Writer, Raise/catch, answer-transforming
choice, first/all results, DFS/BFS search, owned generators, protect/bracket,
and FIFO cooperative scheduling with joins. Executable examples are under
`src/v2/source/`; the four-queens examples retain alternatives across transfers
and clean up acquired resources through typed external requests.

Owned operands remain in their source scope until all operands of the receiving
control operation have evaluated. A later operand failure cleans them up in
lexical order: inner scopes first, then active owners in creation order within
each scope. Closure captures use ascending source-variable order. The compiler
preserves this order through ordinary block parameters, including owned
temporaries created by instructions.
An affine value is owned even when it permits implicit dropping; binding it
establishes an inner ownership scope just as binding a linear value does.

## Pure data dependency

Use the separate build module `boundary_data_v2` for schemas, Program and State
records, canonical codecs and pure admission. A dependency requesting
`.@"data-only" = true` constructs only this module. It does not construct the
authoring, oracle, proof or legacy compatibility targets.

World's production dependency is this data module. The module does not lower
source or evaluate instructions, handlers or continuations.

## Checks and assets

```sh
zig build check-v2-data
zig build check-v2-semantics
zig build check-v2-economy
zig build check-v2 -Doptimize=ReleaseSafe
zig build emit-boundary-v2-release -Doptimize=ReleaseSafe --prefix zig-out/v2
```

The aggregate includes the independent source oracle, the pinned Lean 4.33.1
formal core, pure malformed-input tests, historical BPI1 lifting and structural
economy witnesses. It requires Node 26.8.1 and Lean for those requested checks;
ordinary compiler/data consumers require only Zig. It needs neither World nor a
WASM engine. Emission creates local assets and never tags, publishes or merges.
The five files appear under `zig-out/v2/release`: semantic JSON and indexed
binary fixtures, the source/examples archive, a source/asset receipt, and
`SHA256SUMS`. Receipts record the actual Git head and whether source is dirty;
a development emission is not evidence of a published clean commit.

See [the wire specification](docs/bpi2-wire.md),
[the formal inventory](semantics/v2/README.md),
[measured economy](docs/economy-v2.md), and
[BPI1 lifting](docs/bpi1-lifting.md). `boundary_bpi1` and `bpi1-lift` provide pure
historical-data compatibility. Lifted programs contain BPI2 instructions and
start from InitialArgs; PST1 is not migrated.

## Migration from 1.x

The generated evaluator, Machine/Process execution facades, driver, Agent
compatibility facade and WASM targets have been retired from this package.
Use Boundary for authoring/data and World for execution. Historical v1 records
remain unchanged under `conformance/` and `test/v2/legacy/`; old documentation
is separated under `docs/historical/v1/`. Published releases and their source
commits remain intact.
