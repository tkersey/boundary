# P24 measured costs — decision pending

Exact source, image, emitter, runtime and control identities and raw observations
are retained in [m5-p24.json](performance/m5-p24.json). The P23 control's production
module hashes match the recorded P23 qualification; it was reconstructed in a
temporary directory without replacing any active branch or checkout.

## Qualification and selected outputs

- ReleaseSafe aggregate: 319 steps and 807 tests passed. All 18 Agent images
  remain byte-identical to P23.
- Native tests cover 49 interchange domains and 100 tiled domains, with exact
  point visitation, same-image restores, structural step preservation and
  source-free linking. The platform matrix passes 30 cases and 181 sampled
  native/Wasmtime comparisons against Node.
- The 8×2 selected schedule reduces 169 logical steps to 121. Its fresh-execution
  median ratios versus P23 are 0.815 native and 0.865 WASM; checkpoint-cycle ratios
  are 0.724 and 0.736. The 17×9 fresh ratios are 0.943 and 0.955.
- The 20×0 shared schedule takes nine steps rather than 169. Selected admission,
  retained and execution memory have no threshold increase. Checkpoints do not grow.

## §9.5 disposition needed

The timing matrix contains 63 entries, including exact image-equality entries
and a deliberately separate rejected-tiling experiment. Two **selected-output**
comparisons confirm increases under the existing five-window/four-positive rule:

| Comparison | Phase | Increase |
| --- | --- | --- |
| 1×1 semantic versus structural | WASM fresh invocation | 2.48 µs / 5.7% |
| 20×0 semantic versus P23 | WASM admission | 3.88 µs / 16.5% |

The 1×1 semantic image is identical to P23's image: this is an inherited cumulative
comparison, not a new P24 execution regression. The 8×2 and 17×9 WASM admission
comparisons have higher median ratios but do not satisfy the required confirmation
rule; their raw windows remain visible. No selected fresh-execution slowdown versus
P23 is confirmed.

Boundary construction medians increase 37–41% on these small fixtures; measured
compiler working peaks are unchanged. This is explained by recognizing, constructing
and independently checking the new schedules, including evaluating rejected tiled
candidates. The corrected policy accepts explained Boundary construction regressions;
these are not traded for weaker admission or validation.

## Rejected tiling is not a selected gain

The raw 5×7 tiled candidate takes 373 logical steps versus 259, grows from 151 to
261 image bytes, and increases WASM admission peak by 5,504 bytes and cycle peak
by 6,276 bytes. All six measured timing phases regress. The active tiling cost guard
rejects this candidate; the shared compiler retains the original schedule. These
results support rejection and are not included in the selected-output acceptance
request. The independently validated tiled construction and its negative witnesses
remain available within the same compiler implementation.

Explicit acceptance or correction of the two selected-output costs above is
pending. Authenticated delivery/rebinding, publication and final serial reviews
remain open; nothing has been merged or released.
