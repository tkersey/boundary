# Boundary 2 economy checks

`zig build check-v2-economy` checks actual source-level handler installations at
1, 8 and 64 sites. All installations share one handler definition and the same
executable function count; ordinary installation state does not specialize code.
The selected clauses have no captured continuation after checked tail lowering.
World independently executes the emitted programs.

An additional 64 KiB pointer-free constant occupies one canonical constant
record even when used twice. Emitted image growth is the payload plus the
bounded changes to its ULEB lengths and following directory offsets.

The twenty frozen BPI1 inputs also have a conservative serialized-overhead
guard. Subtract unique authored constant bytes from the v1 image, multiply the
remaining overhead by 1.5 and add 4 KiB. Each complete lifted v2 image fits that
bound, even before subtracting its own constant payload. Per-image sizes are
emitted as `economy-image-sizes.json` with the executable economy fixtures.

The source tests and size checks require no World interpreter or WASM engine.
`test/v2/economy_v1.zig` and `economy_v2.zig` provide equivalent one-effect and
arithmetic compiler workloads. World owns the serial compiler timing harness,
live execution/allocation measurements, and comparison with the frozen public
v1 interpreter. Legacy runtime execution does not enter Boundary's economy
target.

For separate compiler and pure codec phase timings, run
`node test/v2/compiler_phases.mjs .cache/v2/compiler-phases` in an available
serial measurement window. It builds all eight native profilers before timing,
then records five warmups and 21 samples per workload in ReleaseSafe. The
report includes source input digests, executable digests, image sizes, source
copy/check/lowering, target checking, direct optimization, canonicalization,
and image/snapshot/protocol codecs. Snapshot timings use an admitted initial
logical State and make no historical execution claim.
