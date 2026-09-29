# P19 measured-cost decision

Status: explicit acceptance or correction pending under §9.5. Final sources, image identities and raw samples are in [the report](performance/m5-p19.json). The initial 92-regression candidate is separately retained and rejected as an economic-selection result.

## Final scope

The pure loop and branch-local cell loop remove a repeated dispatch block. The original live-prefix cell loop is retained as a fallback rather than optimized merely because a condition read became a jump. All three fixtures remain in the matrix. The final result has 188 timed comparisons and two exact-image comparisons.

## Confirmed timing increases

There are 74 confirmed comparisons against distinct local semantic and structural controls. Duplicate workload dimensions are explicit, not aggregated away.

| Baseline | Fixture | Engine | Phase | Input | Increase | Relative |
|---|---|---|---|---|---:|---:|
| semantic | selectable-false | native | admission | length-0 | 1.82 µs | 38.0% |
| semantic | selectable-false | native | fresh | length-0 | 1.77 µs | 26.7% |
| semantic | selectable-false | native | fresh | length-1 | 1.72 µs | 23.6% |
| semantic | selectable-false | native | cycle | length-0 | 12.42 µs | 21.4% |
| semantic | selectable-false | native | cycle | length-1 | 28.54 µs | 23.3% |
| semantic | selectable-false | wasm | fresh | length-0 | 2.66 µs | 7.0% |
| semantic | selectable-false | wasm | cycle | length-0 | 63.54 µs | 13.2% |
| semantic | selectable-false | wasm | cycle | length-1 | 172.08 µs | 18.7% |
| semantic | selectable-true | native | admission | length-0 | 1.84 µs | 38.6% |
| semantic | selectable-true | native | fresh | length-0 | 1.77 µs | 26.8% |
| semantic | selectable-true | native | fresh | length-1 | 1.87 µs | 25.0% |
| semantic | selectable-true | native | cycle | length-0 | 13.96 µs | 24.5% |
| semantic | selectable-true | native | cycle | length-1 | 25.67 µs | 21.9% |
| semantic | selectable-true | wasm | fresh | length-1 | 3.54 µs | 8.7% |
| semantic | selectable-true | wasm | cycle | length-0 | 76.79 µs | 16.5% |
| semantic | selectable-true | wasm | cycle | length-1 | 132.75 µs | 14.9% |
| semantic | branchcells-false | native | admission | length-0 | 2.00 µs | 23.3% |
| semantic | branchcells-false | native | fresh | length-0 | 1.85 µs | 15.8% |
| semantic | branchcells-false | native | fresh | length-1 | 1.21 µs | 9.5% |
| semantic | branchcells-false | native | cycle | length-0 | 16.92 µs | 11.9% |
| semantic | branchcells-false | native | cycle | length-1 | 36.92 µs | 11.7% |
| semantic | branchcells-false | wasm | admission | length-0 | 3.83 µs | 14.1% |
| semantic | branchcells-false | wasm | fresh | length-0 | 4.14 µs | 8.5% |
| semantic | branchcells-false | wasm | fresh | length-256 | 124.17 µs | 15.0% |
| semantic | branchcells-false | wasm | cycle | length-0 | 87.75 µs | 9.1% |
| semantic | branchcells-false | wasm | cycle | length-1 | 149.25 µs | 6.7% |
| semantic | branchcells-true | native | admission | length-0 | 1.91 µs | 22.3% |
| semantic | branchcells-true | native | fresh | length-0 | 1.91 µs | 16.3% |
| semantic | branchcells-true | native | fresh | length-1 | 1.54 µs | 11.8% |
| semantic | branchcells-true | native | cycle | length-0 | 21.29 µs | 15.4% |
| semantic | branchcells-true | native | cycle | length-1 | 40.42 µs | 13.3% |
| semantic | branchcells-true | wasm | admission | length-0 | 4.53 µs | 17.0% |
| semantic | branchcells-true | wasm | fresh | length-1 | 4.08 µs | 7.9% |
| semantic | branchcells-true | wasm | fresh | length-256 | 124.29 µs | 15.0% |
| semantic | branchcells-true | wasm | cycle | length-0 | 68.96 µs | 7.1% |
| structural | selectable-false | native | admission | length-0 | 1.88 µs | 38.5% |
| structural | selectable-false | native | fresh | length-0 | 1.79 µs | 27.0% |
| structural | selectable-false | native | fresh | length-1 | 1.79 µs | 25.0% |
| structural | selectable-false | native | fresh | length-16 | 1.16 µs | 7.6% |
| structural | selectable-false | native | cycle | length-0 | 12.88 µs | 22.4% |
| structural | selectable-false | native | cycle | length-1 | 26.29 µs | 22.4% |
| structural | selectable-false | native | cycle | length-16 | 61.21 µs | 5.9% |
| structural | selectable-false | wasm | cycle | length-0 | 68.96 µs | 15.1% |
| structural | selectable-false | wasm | cycle | length-1 | 123.13 µs | 13.2% |
| structural | selectable-true | native | admission | length-0 | 1.94 µs | 39.9% |
| structural | selectable-true | native | fresh | length-0 | 1.79 µs | 27.0% |
| structural | selectable-true | native | fresh | length-1 | 1.78 µs | 24.8% |
| structural | selectable-true | native | cycle | length-0 | 13.63 µs | 23.7% |
| structural | selectable-true | native | cycle | length-1 | 25.88 µs | 22.1% |
| structural | selectable-true | native | cycle | length-16 | 55.17 µs | 5.3% |
| structural | selectable-true | wasm | fresh | length-1 | 2.61 µs | 6.5% |
| structural | selectable-true | wasm | cycle | length-0 | 43.75 µs | 9.6% |
| structural | selectable-true | wasm | cycle | length-1 | 118.79 µs | 13.2% |
| structural | branchcells-false | native | admission | length-0 | 1.96 µs | 22.8% |
| structural | branchcells-false | native | fresh | length-0 | 1.80 µs | 16.1% |
| structural | branchcells-false | native | fresh | length-1 | 1.75 µs | 14.3% |
| structural | branchcells-false | native | cycle | length-0 | 20.08 µs | 14.5% |
| structural | branchcells-false | native | cycle | length-1 | 40.42 µs | 13.4% |
| structural | branchcells-false | wasm | admission | length-0 | 3.50 µs | 12.8% |
| structural | branchcells-false | wasm | fresh | length-0 | 3.72 µs | 7.7% |
| structural | branchcells-false | wasm | fresh | length-1 | 3.59 µs | 6.8% |
| structural | branchcells-false | wasm | fresh | length-256 | 83.71 µs | 9.6% |
| structural | branchcells-false | wasm | cycle | length-0 | 68.67 µs | 6.7% |
| structural | branchcells-false | wasm | cycle | length-1 | 152.71 µs | 7.1% |
| structural | branchcells-true | native | admission | length-0 | 1.96 µs | 22.8% |
| structural | branchcells-true | native | fresh | length-0 | 1.64 µs | 14.2% |
| structural | branchcells-true | native | fresh | length-1 | 1.92 µs | 15.8% |
| structural | branchcells-true | native | cycle | length-0 | 23.04 µs | 16.4% |
| structural | branchcells-true | native | cycle | length-1 | 42.13 µs | 14.0% |
| structural | branchcells-true | wasm | admission | length-0 | 3.46 µs | 12.9% |
| structural | branchcells-true | wasm | fresh | length-0 | 3.35 µs | 6.7% |
| structural | branchcells-true | wasm | fresh | length-256 | 76.71 µs | 8.9% |
| structural | branchcells-true | wasm | cycle | length-0 | 140.62 µs | 14.5% |
| structural | branchcells-true | wasm | cycle | length-1 | 225.33 µs | 10.4% |

Against the frozen semantic control, both 256-iteration branch-local cell paths show about 15% WASM fresh-invocation slowdowns (about 124 µs). These are not described as merely empty-input costs. The raw report retains all faster, unchanged and inconclusive cells as well.

## Memory increases above the threshold

| Baseline | Fixture | Engine/phase | Paths | Before | After | Increase |
|---|---|---|---|---:|---:|---:|
| control | selectable-false | wasm/admission.peak | length-0, length-1, length-16, length-256, length-4096 | 7108 | 8416 | 1308 bytes |
| structural | selectable-false | wasm/admission.peak | length-0, length-1, length-16, length-256, length-4096 | 7096 | 8416 | 1320 bytes |
| control | selectable-false | wasm/cycle64.peak | length-256, length-4096 | 9620 | 12976 | 3356 bytes |
| structural | selectable-false | wasm/cycle64.peak | length-256, length-4096 | 9607 | 12976 | 3369 bytes |
| control | selectable-true | wasm/admission.peak | length-0, length-1, length-16, length-256, length-4096 | 7108 | 8416 | 1308 bytes |
| structural | selectable-true | wasm/admission.peak | length-0, length-1, length-16, length-256, length-4096 | 7096 | 8416 | 1320 bytes |
| control | selectable-true | wasm/cycle64.peak | length-256, length-4096 | 9620 | 12976 | 3356 bytes |
| structural | selectable-true | wasm/cycle64.peak | length-256, length-4096 | 9607 | 12976 | 3369 bytes |
| control | branchcells-false | wasm/admission.peak | length-0, length-1, length-16, length-256, length-4096 | 10518 | 11718 | 1200 bytes |
| structural | branchcells-false | wasm/admission.peak | length-0, length-1, length-16, length-256, length-4096 | 10510 | 11718 | 1208 bytes |
| control | branchcells-true | wasm/admission.peak | length-0, length-1, length-16, length-256, length-4096 | 10518 | 11718 | 1200 bytes |
| structural | branchcells-true | wasm/admission.peak | length-0, length-1, length-16, length-256, length-4096 | 10510 | 11718 | 1208 bytes |
| control | selectable-false | wasm/cycle1.peak | length-0, length-1, length-16, length-256 | 9354 | 10388 | 1034 bytes |
| structural | selectable-false | wasm/cycle1.peak | length-0, length-1, length-16, length-256 | 9341 | 10388 | 1047 bytes |
| control | selectable-true | wasm/cycle1.peak | length-0, length-1, length-16, length-256 | 9354 | 10388 | 1034 bytes |
| structural | selectable-true | wasm/cycle1.peak | length-0, length-1, length-16, length-256 | 9341 | 10388 | 1047 bytes |
| control | branchcells-false | wasm/cycle1.peak | length-0, length-1, length-16, length-256 | 12366 | 15516 | 3150 bytes |
| structural | branchcells-false | wasm/cycle1.peak | length-0, length-1, length-16, length-256 | 12357 | 15516 | 3159 bytes |
| control | branchcells-true | wasm/cycle1.peak | length-0, length-1, length-16, length-256 | 12366 | 15516 | 3150 bytes |
| structural | branchcells-true | wasm/cycle1.peak | length-0, length-1, length-16, length-256 | 12357 | 15516 | 3159 bytes |
| control | selectable-false | native/admission.peakBytes | length-0 | 7254 | 11262 | 4008 bytes |
| control | selectable-false | native/admission.retainedBytes | length-0 | 6930 | 8160 | 1230 bytes |
| control | selectable-false | native/fresh.peakBytes | length-0, length-1, length-16, length-256, length-4096 | 9942 | 11468 | 1526 bytes |
| control | selectable-false | native/cycle.peakBytes | length-0 | 13794 | 17465 | 3671 bytes |
| control | selectable-false | native/cycle.peakBytes | length-1, length-16, length-256 | 13797 | 17465 | 3668 bytes |
| control | selectable-true | native/admission.peakBytes | length-0 | 7254 | 11262 | 4008 bytes |
| control | selectable-true | native/admission.retainedBytes | length-0 | 6930 | 8160 | 1230 bytes |
| control | selectable-true | native/fresh.peakBytes | length-0, length-1, length-16, length-256, length-4096 | 9942 | 11468 | 1526 bytes |
| control | selectable-true | native/cycle.peakBytes | length-0 | 13794 | 17465 | 3671 bytes |
| control | selectable-true | native/cycle.peakBytes | length-1, length-16, length-256 | 13797 | 17465 | 3668 bytes |
| control | branchcells-false | native/admission.peakBytes | length-0 | 13114 | 14586 | 1472 bytes |
| control | branchcells-false | native/admission.retainedBytes | length-0 | 10148 | 11222 | 1074 bytes |
| control | branchcells-false | native/fresh.peakBytes | length-0, length-1 | 14059 | 15167 | 1108 bytes |
| control | branchcells-false | native/fresh.peakBytes | length-16 | 16507 | 17615 | 1108 bytes |
| control | branchcells-false | native/fresh.peakBytes | length-256, length-4096 | 19328 | 20462 | 1134 bytes |
| control | branchcells-false | native/cycle.peakBytes | length-0 | 20122 | 21680 | 1558 bytes |
| control | branchcells-false | native/cycle.peakBytes | length-1, length-16 | 21660 | 23167 | 1507 bytes |
| control | branchcells-true | native/admission.peakBytes | length-0 | 13114 | 14586 | 1472 bytes |
| control | branchcells-true | native/admission.retainedBytes | length-0 | 10148 | 11222 | 1074 bytes |
| control | branchcells-true | native/fresh.peakBytes | length-0, length-1 | 14059 | 15167 | 1108 bytes |
| control | branchcells-true | native/fresh.peakBytes | length-16 | 16507 | 17615 | 1108 bytes |
| control | branchcells-true | native/fresh.peakBytes | length-256, length-4096 | 19328 | 20462 | 1134 bytes |
| control | branchcells-true | native/cycle.peakBytes | length-0 | 20122 | 21680 | 1558 bytes |
| control | branchcells-true | native/cycle.peakBytes | length-1, length-16 | 21660 | 23167 | 1507 bytes |
| structural | selectable-false | native/admission.peakBytes | length-0 | 7248 | 11262 | 4014 bytes |
| structural | selectable-false | native/admission.retainedBytes | length-0 | 6924 | 8160 | 1236 bytes |
| structural | selectable-false | native/fresh.peakBytes | length-0, length-1, length-16, length-256, length-4096 | 9935 | 11468 | 1533 bytes |
| structural | selectable-false | native/cycle.peakBytes | length-0 | 13787 | 17465 | 3678 bytes |
| structural | selectable-false | native/cycle.peakBytes | length-1, length-16, length-256 | 13790 | 17465 | 3675 bytes |
| structural | selectable-true | native/admission.peakBytes | length-0 | 7248 | 11262 | 4014 bytes |
| structural | selectable-true | native/admission.retainedBytes | length-0 | 6924 | 8160 | 1236 bytes |
| structural | selectable-true | native/fresh.peakBytes | length-0, length-1, length-16, length-256, length-4096 | 9935 | 11468 | 1533 bytes |
| structural | selectable-true | native/cycle.peakBytes | length-0 | 13787 | 17465 | 3678 bytes |
| structural | selectable-true | native/cycle.peakBytes | length-1, length-16, length-256 | 13790 | 17465 | 3675 bytes |
| structural | branchcells-false | native/admission.peakBytes | length-0 | 13102 | 14586 | 1484 bytes |
| structural | branchcells-false | native/admission.retainedBytes | length-0 | 10136 | 11222 | 1086 bytes |
| structural | branchcells-false | native/fresh.peakBytes | length-0, length-1 | 14046 | 15167 | 1121 bytes |
| structural | branchcells-false | native/fresh.peakBytes | length-16 | 16494 | 17615 | 1121 bytes |
| structural | branchcells-false | native/fresh.peakBytes | length-256, length-4096 | 19315 | 20462 | 1147 bytes |
| structural | branchcells-false | native/cycle.peakBytes | length-0 | 20109 | 21680 | 1571 bytes |
| structural | branchcells-false | native/cycle.peakBytes | length-1, length-16 | 21647 | 23167 | 1520 bytes |
| structural | branchcells-true | native/admission.peakBytes | length-0 | 13102 | 14586 | 1484 bytes |
| structural | branchcells-true | native/admission.retainedBytes | length-0 | 10136 | 11222 | 1086 bytes |
| structural | branchcells-true | native/fresh.peakBytes | length-0, length-1 | 14046 | 15167 | 1121 bytes |
| structural | branchcells-true | native/fresh.peakBytes | length-16 | 16494 | 17615 | 1121 bytes |
| structural | branchcells-true | native/fresh.peakBytes | length-256, length-4096 | 19315 | 20462 | 1147 bytes |
| structural | branchcells-true | native/cycle.peakBytes | length-0 | 20109 | 21680 | 1571 bytes |
| structural | branchcells-true | native/cycle.peakBytes | length-1, length-16 | 21647 | 23167 | 1520 bytes |

## Technical qualification

319 aggregate steps / 775 tests and five revised native tests pass. The final platform matrix passes 120 arms and 1280 native/Node/Wasmtime boundaries, plus 120 each of malformed-input, same-image-restore and wrong-image checks. Both Boolean paths, zero trips, source-free links, per-iteration allocation/mutation, failure ordering, structural-contract preservation and exact code-budget rollback are covered.

At 257 iterations the selected pure loop executes 1550 logical steps instead of 1806, with one runtime selector test instead of 257. Branch-local cell paths preserve N creations and writes. All 18 Agent images are unchanged; no real-Agent speedup is claimed.

Any acceptance applies only to the final costs documented here. It does not accept future costs or settle the separate M3/P13/P16/P18 decisions.
