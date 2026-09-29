# P12 measured cost decision

This decision covers the P12 input-preserving handler elimination/fusion candidate
on top of Boundary `bd6edeb87186628d2b13f1fda716a200d3d83465`, with exact source and
image hashes in `performance/m4-p12.json`. It does not accept unrelated M3 costs.
The World kernel remains `7d31effb1d4e32523d0fcbd5b4d5f5a8a2289fbd4c731173a33b1c174524282f`.

## Required timing protocol

All 56 native/WASM paired timing cells completed. Four exceed §9.5's threshold
under the required five-window confirmation rule:

| Fixture / WASM phase | Paired median increase | Ratio |
| --- | ---: | ---: |
| Composed empty handlers / admission | 4.63 µs | 1.2004 |
| Composed Readers / complete quantum-one checkpoint cycle, `0000` | 393.54 µs | 1.1333 |
| Composed Readers / complete quantum-one checkpoint cycle, `1111` | 493.33 µs | 1.1750 |
| Composed Readers / complete quantum-one checkpoint cycle, `1010` | 435.54 µs | 1.1522 |

No native timing or WASM fresh-invocation slowdown is confirmed. These cycle costs
include the complete execution and repeated save/restore; they are not isolated
checkpoint encoding times.

The admission samples visibly cross WASM tiering transitions. A separate five-
window diagnostic records 76 batches of 64 admissions per process: the candidate's
first-batch median ratio is 0.8354 and its stabilized ratio is 0.7137. This explains
why a smaller/faster steady image can lose on the prescribed short warm-up window;
it does **not** remove the original timing result or waive its acceptance gate.

## Correctness and memory

All 172 finite/sampled cross-engine cases, 16 malformed inputs, 16 same-image
restores and 16 wrong-image rejections pass. Reader unit checks pass 22/22 and
Boolean leaf checks 43/43. Final slot-reuse integrated qualification completed
with terminal exit 0: 319/319 steps and 706/706 tests.

The measured memory violation was corrected before this decision. The fused body
reuses the eliminated closure slot for its new capability. Identity Reader bytes
are 400→392, composed Reader bytes 468→451. Canonical memory increases now stay
within the supplied threshold; checkpoints shrink from up to 199→169 bytes.
The final exact-source Agent comparison is byte-identical across all 18 images,
with no work-limit outcomes.

## Disposition

The user explicitly accepted these four bounded timing increases for the measured
P12 candidate, published at `5b272cc78ca43c79fd24204707c912bf26b75791`.
This acceptance is specific to the table above; it does not extend earlier
cutover, M2, M2.5 or packing decisions to other costs. The separate M3 decision
and the full remaining optimization programme stay open.
