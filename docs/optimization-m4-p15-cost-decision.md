# P15 measured-cost decision

Status: the user explicitly accepts the bounded P15 costs under specification §9.5.

Candidate sources and immutable image hashes are bound in [the raw report](performance/m4-p15.json). The frozen P14 compiler produces byte-identical controls. The qualified World kernel and Agent package binding are unchanged.

## Confirmed timing increases

Three alternating process windows, plus two confirmation windows for suspected increases; at least three warmups and nine samples per process. A regression requires median ratio >1.05 and four of five ratios >1.05.

| Family | Engine | Phase | Input length | Increase | Relative |
|---|---|---|---:|---:|---:|
| xor | native | admission | 1 | 0.96 µs | 21.3% |
| xor | native | fresh | 1 | 0.81 µs | 9.7% |
| xor | native | cycle | 1 | 25.13 µs | 25.6% |
| xor | wasm | admission | 1 | 3.40 µs | 15.9% |
| xor | wasm | cycle | 1 | 191.21 µs | 24.3% |
| boolean | native | admission | 1 | 1.23 µs | 23.3% |
| boolean | native | fresh | 1 | 1.05 µs | 11.1% |
| boolean | native | cycle | 1 | 59.00 µs | 46.2% |
| boolean | wasm | fresh | 1 | 3.05 µs | 6.7% |
| boolean | wasm | cycle | 1 | 468.00 µs | 47.0% |

No fresh-execution slowdown is confirmed at lengths 16, 256 or 4096. The Boolean large-input WASM sampler uses one execution per sample, retaining the required repetitions; the raw report explicitly corrects the earlier controller description.

## Memory increases above the threshold

Threshold: max(1 KiB, 1% of control). Admission measurements repeat the same image at each input length.

| Family | Engine | Phase | Length | Before | After | Increase |
|---|---|---|---:|---:|---:|---:|
| xor | wasm | admission.peak | 1 | 6324 | 7758 | 1434 bytes |
| xor | wasm | admission.peak | 16 | 6324 | 7758 | 1434 bytes |
| xor | wasm | cycle64.peak | 16 | 10726 | 14866 | 4140 bytes |
| xor | wasm | admission.peak | 256 | 6324 | 7758 | 1434 bytes |
| xor | wasm | admission.peak | 4096 | 6324 | 7758 | 1434 bytes |
| boolean | wasm | admission.peak | 1 | 7310 | 9356 | 2046 bytes |
| boolean | wasm | admission.retained | 1 | 6856 | 8066 | 1210 bytes |
| boolean | wasm | admission.peak | 16 | 7310 | 9356 | 2046 bytes |
| boolean | wasm | admission.retained | 16 | 6856 | 8066 | 1210 bytes |
| boolean | wasm | admission.peak | 256 | 7310 | 9356 | 2046 bytes |
| boolean | wasm | admission.retained | 256 | 6856 | 8066 | 1210 bytes |
| boolean | wasm | cycle64.peak | 256 | 10543 | 12044 | 1501 bytes |
| boolean | wasm | admission.peak | 4096 | 7310 | 9356 | 2046 bytes |
| boolean | wasm | admission.retained | 4096 | 6856 | 8066 | 1210 bytes |
| boolean | wasm | cycle64.peak | 4096 | 10543 | 12044 | 1501 bytes |
| boolean | wasm | cycle1.peak | 1 | 10505 | 11815 | 1310 bytes |
| boolean | wasm | cycle1.peak | 16 | 10505 | 11815 | 1310 bytes |
| boolean | wasm | cycle1.peak | 256 | 10505 | 11815 | 1310 bytes |
| boolean | native | admission.retained | 1 | 8026 | 9114 | 1088 bytes |
| boolean | native | cycle.peak | 1 | 15150 | 16503 | 1353 bytes |

## Preserved behavior and benefit

319 aggregate steps / 742 tests; six native tests; 24 platform arms and 294 native/Node/Wasmtime boundaries; 24 malformed inputs, same-image restores and wrong-image rejections. All pass. Independent admission-valid identity, orientation and transfer mutations are rejected. Both laws have allocation-failure coverage.

At 4096 actions, native fresh peak falls 3,752,821 → 106,155 bytes for XOR and 3,723,534 → 40,802 for Boolean tables. Deepest pending continuation frames fall from 4096 to zero. Checkpoints remain within the growth criterion; long-chain checkpoints shrink. All 18 Agent images remain unchanged; no Agent benefit is claimed.

The user explicitly accepted these bounded P15 costs after the complete report and consolidated question. This decision applies only to the reported candidate and costs; it does not resolve separate M3/P13 decisions or authorize future optimization costs.
