# Generated source conformance sample

`generated_programs.zig` constructs sixteen ordinary public-builder programs,
using seeds 0–15. A 32-bit LCG (`x * 1664525 + 1013904223`, wrapping, initialized
with `seed xor 0x9e3779b9`) chooses expression constructors. Depth is
`3 + seed % 3`: at most 63 expression nodes per generated tree. These limits
bound test authoring; they are not runtime fuel or limits in the Lean semantics.

Every program requests an external integer, captures it in a lexical closure,
applies that closure to a separately bound integer, and exits through an
effectful cleanup. The generated expression combines addition, subtraction,
multiplication, pairs, and projections. Unsigned arithmetic faults carry the
authored failure `1000 + seed`. Seed bit 0 inserts a yield in the computation;
bit 1 inserts a cleanup yield; bit 3 makes cleanup fail with `2000 + seed` after
its request. Inputs are `seed + 3`; the environment replies with `seed + 17`
and then unit. Source execution must finish, contain exactly the prescribed
request/yield order, and include both successful and failing cases in the sample.
Seed 6 returns `430`; seed 12 replaces a normal return with cleanup failure
`2012`. The source-side checks retain these concrete value-position and exit
distinctions in addition to the generated trace checks.

## Mapping to the symbolic core

| Generated source | Core interpretation and local proof surface | Concrete bridge |
| --- | --- | --- |
| Integer leaves and arithmetic | `LeafAlgebra`: typed pure values and either a value or authored fault, with no internal references. | Production `u64` bounds and overflow/underflow are evaluated by the independent source oracle and tested against World. They are not equated with unbounded mathematical integer arithmetic. |
| Pairs and projections | Structural values and ordered operand evaluation in `GeneralizedOwnedOperands` and `GeneralizedOwnedOperandLowering`. | Both pair operands execute before the selected field is returned; primitive failure retains the enclosing protection. |
| Captured `received`, helper parameter, and separate `shadow` binding | `Source.Expression.lambda`, explicit captured environments, and `compiled_owned_operand_application`; ordinary context and observation laws in `GeneralizedProgramObservations`. | `Builder.lambda`, `bind`, and `apply` become ordinary first-order code and environment fields through the production compiler. No native helper callback executes in World. |
| `generated/input : u64 -> u64` | An arbitrary typed operation and its pending typed future; `every_request_response_remains_related`. | The oracle reads the staged source. World receives a normal encoded image and a response bound to its actual request. |
| Authored yields and cleanup requests | Distinct yield/request observations; polling is silent. | The conformance runner compares complete native/WASM outcomes and restores a fresh instance at each boundary, alternating the selected backend. |
| `protect` and `generated/cleanup : ExitInfo -> unit` | Cleanup entry, completion, and original/cleanup-failure ordering in `GeneralizedProtectionExecution` and `GeneralizedExitCompletion`. | The cleanup receives the real exit information, may yield/request, and may fail. The oracle computes expected exit information independently of the emitted image. |

This is a finite executable bridge to the core's contracts, not a proof of the
production compiler, a verified encoding, or a program certificate. It adds a
small generated sample to the existing distinguishing fixtures; it does not
replace their handler, ownership, lifetime, cancellation, or library cases.

## Running and reproducing

```sh
zig build emit-v2-source-fixtures -Doptimize=ReleaseSafe -j2 --summary all
zig build check-v2 -Doptimize=ReleaseSafe -j2 --summary all
zig build check-v2-conformance -Dworld-source="$WORLD_CHECKOUT" -Doptimize=ReleaseSafe -j2 --summary all
node test/v2/conformance.mjs --world "$WORLD_CHECKOUT" --fixtures zig-out --case generated-6
```

`WORLD_CHECKOUT` must be a clean checkout of the approved, unmodified World
commit `87698f92ca7be4d5442e97ba27a2468aa3ff6a7c`. The runner prints the Boundary
and World commits, tool versions, case name (and therefore seed), and comparison
counts. `source-generated-N.json` and `source-generated-N.bpi2` retain the ordinary
staged source and image. A horizon or runtime error is an unfinished/failed
check, never a successful match. The Linux workflow runs these same entry points
and reports clean proof-build and test costs.
