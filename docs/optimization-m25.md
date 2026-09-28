# M2.5 — affine capture-state synthesis (in progress)

Development base: Boundary `7d48c08364dd6d021c46ea64fad584937e9e930f`
(PR #162), qualified with Agent `b40b6d0` (#40) and unchanged World runtime.
I.9 now defers full code reviews until the complete optimization programme and
technical qualification are finished. Earlier review receipts remain historical;
they do not gate this successor and do not certify changed code.

## Current implementation

`src/data/affine_space.zig` provides bounded exact GF(2) row insertion,
predecessor pullback, future-observation closure and independent equation
checking, for up to 128 whole-word coordinates. Deterministic work exhaustion
returns an error without publishing a partial closure. The equation checker
reconstructs supplied coefficients; it does not invoke the discovery algorithm.

`src/data/affine_extract.zig` consumes that kernel from actual record dataflow.
It models unsigned moves, constants and XOR, tracks writes to stable slots, and
reads every parallel transfer from the predecessor view. It keeps state rows,
ordered dynamic-input rows and constant offsets distinct. Unsupported operations
produce unknown, never a fabricated zero. The consumer must seed their required
original coordinates or decline the slice. The current test independently admits
its original records before extraction and derives the rotating transition from
the records rather than a fixture name.

Executed ReleaseSafe checks: standalone algebra 3/3; extractor harness 12/12
(including imported primitive tests). These are not twelve independent optimizer
witnesses. Solver cases include three-to-two rotating observations, reset exposing
an additional coordinate, exact-equation mutation rejection, budget rollback and
permutation parity at 2, 3, 8, 32, 64 and 128 coordinates.

## Remaining delivery

This is an early draft, not the M2.5 transformation delivery. The actual use census,
private capture/worker rewrite, location-indexed predecessor worklist, complete
IR/model/emitted-IR correspondence validation, shared pipeline/final-link adoption,
L01–L20 production witnesses and runtime economics remain required. The mathematical
kernel and extraction test do not prove emitted-program equivalence or memory gain.
The next slice must rewrite the three-live-word capture/worker cycle into two words
and validate the actual ordered interfaces and affine input/offset terms.
