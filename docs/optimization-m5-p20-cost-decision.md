# P20 measured costs — decision pending

The candidate contains checked affine recurrence/guard reductions and World's
same-image sequence-access bounds reuse. Boundary is based on `7c7b586`; World
is based on `0ba2120`; both P20 changes remain uncommitted. Exact relevant source
hashes and raw measurements are in [m5-p20.json](performance/m5-p20.json).

## Protected behavior and measured benefit

- Boundary: 319 steps and 790 tests pass; five native P20 tests pass, including
  zero/max loops, original fault payloads, overflowing-final-update rejection,
  source-free linking and same-image checkpoint restoration.
- World: full local aggregate, real Chromium/Firefox transfer, native/Node and
  Wasmtime transfer pass. 1,120 native same-image requests have byte-identical
  outcomes. All 48 P20 compiler/platform cases pass.
- Guard comparisons fall from `2N+1` to `N+1`. Affine length 50 removes 50
  multiplications. World performs one physical range check per sequence access.
- At length 50, guard fresh-execution median ratios versus P19 are 0.915 native
  and 0.918 WASM; access ratios are 0.941 and 0.964. These are measured medians,
  not claims for all workloads. All 18 Agent images remain unchanged.

## Costs requiring §9.5 disposition

Of 108 compiler timing comparisons (P19 semantic and structural baselines), 18
confirm increases, all in the affine family. Native admission increases by
0.310–0.364 µs (6.6–7.7%); WASM admission increases by 5.05–5.93 µs (27.2–30.2%).
Three short fresh-invocation cells increase by 0.544–3.81 µs (8.3–9.6%).
Checkpoint-cycle increases range from 24.0 to 197.6 µs (6.4–31.1%), including a
native length-50 structural comparison. No guard/access timing slowdown is
confirmed. Confirmation requires five windows with median ratio above 1.05 and
at least four ratios above 1.05; raw samples and ordering are retained.

Affine native fresh peak increases by 1,050–1,051 bytes at all four measured
lengths, and zero-trip checkpoint-cycle peak by the same amount. WASM
checkpoint-cycle peak at all four lengths grows by 1,048–1,049 bytes, to 9,889 bytes.
These exceed the max(1 KiB, 1%) threshold. No other measured compiler memory
cell exceeds that threshold; checkpoint maximum sizes do not grow.

The separate same-image World runtime comparison completes all 54 timing cells
with no confirmed slowdown and no memory threshold increase. This uses the
locally qualified candidate kernel; it does not claim authenticated delivery.

## Decision and remaining delivery

Await explicit acceptance or correction of the bounded affine costs above.
Earlier P15 or other optimization acceptances do not apply to P20. Runtime
artifact publication/acquisition and Agent binding remain outstanding. Final
serial reviews remain deferred until the full requested implementation is ready.
