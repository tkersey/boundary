# BPI1 lifting

`boundary_bpi1` is a separately importable pure Zig module. `decode` admits and
owns historical BPI1 bytes; `lift` returns an owned, canonical `data_v2.Program`.
Both reject unsupported evaluator versions. They have no PST1 input path and
execute no application instructions.

The supported inputs are admitted evaluator-semantics 1, 2, and 3. Every frozen
wire operation translates to ordinary v2 instructions. Constructor-retained
values become block parameters after finite liveness propagation, including
callee captures and values retained by a caller across recursive calls. Calls,
branches, residual operations, explicit yields, results, and authored failures
become their v2 control counterparts. No v1 instruction stream or evaluator is
embedded in BPI2.

Build and use the command:

```sh
zig build build-bpi1-lift
zig-out/bin/bpi1-lift < application.bpi1 > application.bpi2
zig-out/bin/bpi1-lift --value application.bpi1 to-v2 initial < initial.v1 > initial.v2
```

Value selectors are `initial`, `result`, `failure`, `payload:N`, and `resume:N`,
where N is the old effect ordinal. Directions are `to-v1` and `to-v2`. The pure
`types.schemas`, `types.toV1`, and `types.toV2` functions expose the same data
translation for build tools. Collection bounds, enum tag membership, field and
case order, and UTF-8 bytes are preserved. Value encodings change to v2 canonical
counts and variant ordinals, so passing unchanged v1 collection bytes to a v2
process is generally invalid.

Start the lifted image from converted InitialArgs. Request identities, program
identities, and process snapshots belong to the new execution. A saved PST1
cannot be resumed or reinterpreted as PST2. External results must be encoded
against the v2 request produced on the new logical path.

The immutable input inventory is `test/v2/legacy/inputs.json`. It distinguishes
World's historical Boundary 1.7.0 corpus from the public 1.8.2 assets and fixtures
emitted from frozen 1.8.2 source declarations. Boundary checks pure admission,
lifting, value round trips, and allocation failure. World owns comparisons with
the independently downloaded public 1.8.2 interpreter and native/JS/Wasmtime v2
execution.
