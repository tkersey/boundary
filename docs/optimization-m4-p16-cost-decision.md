# P16 measured-cost decision

Status: explicit acceptance or correction pending under specification §9.5.

Sources, exact image hashes and raw samples are in [the report](performance/m4-p16.json). The frozen P15 compiler produces byte-identical controls. World and Agent package bindings remain unchanged.

## Confirmed timing increases

Three independently launched alternating windows with three warmups and nine samples per process, plus two confirmation windows for suspected regressions. Median paired ratio must exceed 1.05 and at least four of five individual ratios must exceed 1.05.

| Family | Engine | Phase | Length | Increase | Relative |
|---|---|---|---:|---:|---:|
| mapped | native | admission | 0 | 0.44 µs | 9.6% |
| mapped | native | fresh | 0 | 0.67 µs | 10.0% |
| mapped | native | cycle | 0 | 11.79 µs | 31.1% |
| mapped | wasm | cycle | 0 | 100.00 µs | 30.0% |
| paired | native | admission | 0 | 0.55 µs | 11.9% |
| paired | native | fresh | 0 | 0.59 µs | 8.7% |
| paired | native | cycle | 0 | 11.92 µs | 31.2% |
| paired | wasm | cycle | 0 | 89.50 µs | 26.6% |

No nonempty fresh-execution slowdown is confirmed. Admission uses the image alone; its displayed input length is only the first harness row. Empty-input extra control work has no frame savings to offset it. The constructor loop still avoids retaining a frame per nonempty input.

## Memory and checkpoint costs

No measured native/WASM peak, retained-program or checkpoint comparison exceeds the supplied growth threshold. Quantum-one and quantum-64 cycles are reported separately.

## Qualified result

319 aggregate steps and 748 tests pass. Six native tests include ordered singleton/paired constructors through 4096 inputs, source-free linking, retained input alias, admission-valid orientation mutation, intermediate checkpoints and nonlinear reentry/cloned continuations. The platform matrix passes 24 arms and 316 native/Node/Wasmtime boundaries, plus 24 each of malformed-input, same-image restoration and wrong-image rejection checks.

Pending frames fall 4096 → 0. Output remains 4098/8194 bytes, and deepest-return checkpoints remain 4176/8272 bytes. At that size, total native allocation traffic falls 17,322,260 → 10,463,180 bytes for singleton chunks and 25,864,532 → 19,006,859 for paired chunks. The persistent output copying still scales quadratically; no constant-total-space claim is made. All 18 Agent images are unchanged.

P15 acceptance does not authorize these new P16 timing costs. A P16 decision applies only to these measured costs and does not resolve separate M3/P13 decisions or authorize future costs.
