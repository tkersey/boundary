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

## Capture/worker census

`affine_capture.analyze` now admits the original Program and enumerates the
private worker's scalar observations and recursive call transitions. Its first
domain keeps a fixed capture layout and declines unsupported cross-block dataflow,
owned/borrowed captures and unresolved control. Actual recursive argument order
supplies the transition rows, input terms and offsets consumed by closure.
An admitted three-word recursive capture fixture derives rank two; exposing one
original coordinate under the same rotation requires rank three. All new partial
owners release under allocation failure, and exhausted work returns no plan.
The focused ReleaseSafe harness passes 15/15 tests including imported primitives.
This establishes the census/analysis slice only. No capture or worker ABI has yet
been rewritten, and no runtime memory saving is claimed.

## First checked emitted candidate

The current local implementation emits a two-word capture descriptor, a reduced
worker input prefix and matching recursive call arguments. Initialization computes
the selected basis from original operands after their existing evaluation.
`affine_validate.zig` independently symbolically interprets original and emitted
records; it does not invoke extraction, closure or emission. It checks unchanged
metadata/control, ordered boundary observations, initialization and recursive
state/input/constant equations. Unsupported cross-block transfers are rejected.
Fresh original/candidate admission remains separate from this correspondence.

`affine_state.run` accepts only that checked candidate and then runs final P01.
Work exhaustion returns the exact P01 baseline. The 29-test focused ReleaseSafe
harness passes, including allocation-failure sweeps and well-typed capture-order,
recursive-input and basis mutations. The native World test executes original and
checked images against independent expected outputs for both branch choices and
three input vectors (12 executions). It passes. This fixture currently exercises
one recursive transition, not the complete repeated-input/multimode obligation.

These changes are not yet integrated into the shared compiler/final-link schedule.
Location-sensitive layouts, broader recurrence, full input/offset coverage,
source-free integration, platform/economic qualification and remaining L01–L20
cases remain required. Two captured words do not establish lower total memory.

The data aggregate completes with **3/3 steps and 265/265 tests**. The native World
suite now passes two tests: the original twelve branch executions plus thirty-six
original/reduced recurrent executions at 0, 1, 2, 3, 8 and 31 updates. The latter
uses dynamic XOR input, nonzero update offset and direct-input/output-offset terms.
The first run exposed an in-place array-update error in the Zig host oracle on the
original image (input 1,2,4,8; two updates). The oracle now snapshots predecessor
scalars before assignment, implementing the specified simultaneous update. Both
original and reduced programs match it; no optimizer or runtime change was needed.
These are correctness witnesses, not runtime cost measurements.
