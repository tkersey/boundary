# P18 measured-cost decision

Status: explicit acceptance or correction pending under §9.5. Sources, images, all 116 final paired timing cells and raw memory observations are in [the report](performance/m5-p18.json).

## Confirmed timing increases

The exact frozen P17 semantic control and structural baseline remain separate. Three alternating process windows plus two confirmations, with three warmups and nine samples in each process. A regression requires median paired ratio >1.05 and at least four of five individual ratios >1.05.

| Comparison | Family | Engine | Phase | Input | Increase | Relative |
|---|---|---|---|---|---:|---:|
| semantic | counted | native | cycle | length-0 | 6.58 µs | 13.5% |
| semantic | counted | wasm | cycle | length-0 | 47.21 µs | 10.6% |
| semantic | guarded | native | admission | length-0 | 1.50 µs | 37.7% |
| semantic | guarded | native | fresh | length-0 | 1.43 µs | 25.2% |
| semantic | guarded | native | fresh | length-1 | 1.56 µs | 24.2% |
| semantic | guarded | native | cycle | length-0 | 11.13 µs | 22.2% |
| semantic | guarded | native | cycle | length-1 | 26.67 µs | 27.2% |
| semantic | guarded | wasm | fresh | length-1 | 3.69 µs | 9.3% |
| semantic | guarded | wasm | cycle | length-0 | 38.96 µs | 8.8% |
| semantic | guarded | wasm | cycle | length-1 | 150.58 µs | 18.6% |
| structural | counted | native | cycle | length-0 | 6.38 µs | 13.0% |
| structural | counted | wasm | cycle | length-0 | 39.67 µs | 8.8% |
| structural | guarded | native | admission | length-0 | 1.49 µs | 36.8% |
| structural | guarded | native | fresh | length-0 | 1.35 µs | 23.6% |
| structural | guarded | native | fresh | length-1 | 1.49 µs | 24.1% |
| structural | guarded | native | cycle | length-0 | 10.33 µs | 20.5% |
| structural | guarded | native | cycle | length-1 | 24.92 µs | 25.5% |
| structural | guarded | wasm | cycle | length-0 | 40.75 µs | 9.1% |
| structural | guarded | wasm | cycle | length-1 | 125.63 µs | 15.5% |

No longer fresh-run slowdown is confirmed. The nested-loop case has no confirmed timing increase. The common preheader variant retains an empty-cycle cost; the guarded fallback retains short-run/admission costs.

## Memory increases above max(1 KiB, 1%)

| Baseline | Family | Engine/phase | Paths | Before | After | Increase |
|---|---|---|---|---:|---:|---:|
| structural | guarded | wasm/admission.peak | length-1, length-16, length-256, length-4096, length-0 | 4946 | 7620 | 2674 bytes |
| structural | guarded | wasm/admission.retained | length-1, length-16, length-256, length-4096, length-0 | 4788 | 6022 | 1234 bytes |
| structural | guarded | wasm/fresh.peak | length-1, length-16, length-256, length-4096 | 7330 | 8583 | 1253 bytes |
| structural | guarded | wasm/cycle64.peak | length-1 | 7331 | 8584 | 1253 bytes |
| control | guarded | wasm/admission.peak | length-1, length-16, length-256, length-4096, length-0 | 4958 | 7620 | 2662 bytes |
| control | guarded | wasm/admission.retained | length-1, length-16, length-256, length-4096, length-0 | 4800 | 6022 | 1222 bytes |
| control | guarded | wasm/fresh.peak | length-1, length-16, length-256, length-4096 | 7343 | 8583 | 1240 bytes |
| control | guarded | wasm/cycle64.peak | length-1 | 7344 | 8584 | 1240 bytes |
| structural | guarded | wasm/cycle64.peak | length-16 | 8063 | 9885 | 1822 bytes |
| control | guarded | wasm/cycle64.peak | length-16 | 8076 | 9885 | 1809 bytes |
| structural | guarded | wasm/cycle64.peak | length-256, length-4096 | 8012 | 9885 | 1873 bytes |
| control | guarded | wasm/cycle64.peak | length-256, length-4096 | 8025 | 9885 | 1860 bytes |
| structural | guarded | wasm/cycle1.peak | length-0, length-1, length-16, length-256 | 7746 | 9677 | 1931 bytes |
| control | guarded | wasm/cycle1.peak | length-0, length-1, length-16, length-256 | 7759 | 9677 | 1918 bytes |
| control | guarded | native/admission.retainedBytes | length-0 | 5322 | 6364 | 1042 bytes |
| control | guarded | native/fresh.peakBytes | length-0, length-1, length-16, length-256, length-4096 | 8437 | 9497 | 1060 bytes |
| control | guarded | native/cycle.peakBytes | length-0, length-1, length-16, length-256 | 12268 | 13328 | 1060 bytes |
| structural | guarded | native/admission.retainedBytes | length-0 | 5316 | 6364 | 1048 bytes |
| structural | guarded | native/fresh.peakBytes | length-0, length-1, length-16, length-256, length-4096 | 8430 | 9497 | 1067 bytes |
| structural | guarded | native/cycle.peakBytes | length-0, length-1, length-16, length-256 | 12261 | 13328 | 1067 bytes |

Checkpoint sizes remain within their growth criterion. Common preheader cases match the local control in image size and admission peak/retained storage. The remaining memory increases belong to the guarded route, whose original value must survive zero trips.

## Qualified result and limits

319 aggregate steps / 766 tests; 30 final focused tests with allocation failure on all placement paths; seven native tests; 48 arms / 800 native, Node WASM and Wasmtime boundaries. All 48 malformed-input, same-image restore and wrong-image rejection checks pass.

The ordinary loop changes two XORs per iteration to one per iteration plus one invariant evaluation per invocation. Nested loops compute at the correct outer-dependent scope. Zero-trip failing/observable work stays absent; the live-zero-value fixture keeps its old value. Aliased reads, loop-carried versions, custody, borrowed owners and public infinite-loop observations remain protected. All 18 Agent images are unchanged.

The initial all-guarded strategy incurred unnecessary overhead and is separately retained as superseded evidence for dead-entry cases. Its costs are not the final costs. Any P18 acceptance applies only to the final bounded costs above and does not authorize future costs or settle separate M3/P13/P16 decisions.
