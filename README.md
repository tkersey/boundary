# Boundary 3

Boundary checks staged Zig computations and handlers and compiles them into
portable BPI3 program data. World 6 executes that data with one generic native/WASM
interpreter. Boundary contains no production evaluator.

This `3.0.0-dev.0` branch uses Zig `0.16.0`. See the
[current results and limits](docs/compositional-execution.md) and linked draft PRs
for qualification and live review/readiness status.

## Author and compile

Import the Zig build module `boundary`. Its public namespaces include `effect`,
`computation`, `handler`, `region`, `program`, `data`, and `library`.

Start with the [typed structured authoring guide](docs/typed-authoring.md) and
`boundary.authoring` for named values, forward sequencing and derived handlers.

An application implements `emit(builder)` using the checked staged builder.
`boundary.program.lower(allocator, Application)` compiles that application;
`boundary.program.compile(allocator, module)` compiles an already constructed
source module. Both use the same stable-slot compiler. The returned owner must
be deinitialized; it owns the emitted records and derived flow facts independently
of the source builder. `compiled.encode(allocator, destination)` emits BPI3 into
caller-owned storage. Arbitrary native Zig function bodies are not translated.

`program.compileObserved` additionally accepts caller-owned diagnostics and a
phase observer. Diagnostics identify source variables or target calls and scopes
where applicable. Observation does not change emitted bytes. The compiler checks
the original target before specialization and the final target after normalization.

The [public example](examples/one_effect.zig) compiles without a runtime:

```sh
zig build emit-one-effect -Doptimize=ReleaseSafe > example.bpi3
```

Its initial argument and result are canonical little-endian `u32` values. World
returns a typed `example.lookup.v2` request, and the environment supplies its
result. Application handlers, search, scheduling and cleanup remain Program code.

`library` provides State, Reader/local, Writer, Raise/catch, answer-transforming
choice, first/all results, DFS/BFS search, owned generators, protect/bracket and
FIFO cooperative scheduling. Ownership, borrowing, nominal identities, failure
order and cleanup remain checked. Stable slots retain earlier bindings without
copying them into every intermediate continuation interface.

## Pure data and components

Use the separate build module `boundary_data` for schemas, stable Program/State
records, codecs and admission. A dependency selecting `.@"data-only" = true`
constructs only that module; it does not build authoring, oracle or formal targets.
Current formats are [BPI3](docs/bpi3-wire.md), PST3 and the ABI 3 interaction
contracts. Versioned facade aliases have been removed.

[Separately compiled BMO1 components](docs/bmo1-components.md) carry explicit
interfaces and checked borrow contracts. The data-only `boundary-link` tool
resolves instance bindings and emits an independently admitted closed BPI3 image,
without component source or emitters.

## Validation

```sh
zig build check -Doptimize=ReleaseSafe
zig build check-authoring check-data check-components
zig build check-semantics
zig build emit-examples
zig build build-compiler
```

The current aggregate retains the independent higher-order source oracle,
current authoring/data checks, and native/wasm32 codec agreement. It needs Node for
those checks; ordinary authoring/data consumers need only Zig. The historical
compact model and unfinished generalized-effects study live in the
[Boundary Semantics research repository](https://github.com/tkersey/boundary-semantics).
Their Lean checks validate the retained models; they do not establish a checked
refinement of this compiler or runtime. Production confidence comes from the
implementation checks above. No build command publishes a release or merges a PR.

Recompile applications for the successor. Old saved executions require their old
pinned image/runtime pair or explicit completion/abandonment under that pair.
There is no automatic migration of old live State. Legacy data/runtime paths have
been retired with current regression coverage. Selected-tuple confirmation and
accepted milestone tradeoffs are documented in the current results. The linked
draft PRs carry live serial-review and readiness status.

The old image, compact-image, snapshot and protocol codecs are removed.
Use `data.program_image`, `data.state_image` and `data.invocation` for current
wire artifacts, and `data.graph_order` for pure graph traversal/normalization.
