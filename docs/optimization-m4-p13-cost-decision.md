# P13 measured cost decision

> **Current disposition — September 29, 2026:** The user explicitly accepted
> all recorded costs ("All costs are accepted."). This includes the measured
> costs below and their recorded cumulative comparisons. Earlier pending
> language is historical and superseded; future unmeasured costs are not
> preaccepted. Correctness and final review obligations remain unchanged.


Candidate: the map/fold and delayed-successor transformations on top of Boundary
`57672e765db5d13123e2141ace02e948ba533ee7`. Exact source, image, tool and runtime
hashes and raw samples are in `performance/m4-p13.json`. World remains at its
qualified f8a1597 source and unchanged kernel; only a native measurement executable
was rebuilt after temporary measurement tools disappeared.

All 42 native/WASM paired cells completed. Three exceed §9.5's threshold under
five alternating confirmation windows:

| WASM fixture / phase | Paired median increase | Ratio |
| --- | ---: | ---: |
| Empty map/fold, seed true / fresh invocation | 6.41 µs | 1.1925 |
| Lazy unfold / admission | 5.01 µs | 1.2344 |
| Lazy unfold, initial false and seed true / fresh invocation | 8.42 µs | 1.2584 |

No native timing or full checkpoint-cycle slowdown was confirmed. The 32/64/128-
element map/fold timing matrix has no confirmed slowdown. These are the prescribed
finite warm-up protocol results; smaller images and lower memory do not waive them.

Correctness passes: 319/319 integrated steps, 721/721 tests; focused 26/26 map and
39/39 unfold; five native map/resource/failure-order tests and three native unfold/
divergence/interruption tests. The cross-engine matrix passes 280 cases, 20 malformed
inputs, 16 restores and 15 applicable wrong-image rejections.

Native and WASM admission/retained/execution memory and checkpoint sizes stay within
the supplied thresholds for the measured controls. The transforming examples improve
memory and checkpoints. All 18 unchanged Agent images are byte-identical to P12,
with no work-limit outcomes; no Agent runtime speedup is claimed.

Disposition: pending explicit acceptance of these three bounded timing increases
or correction. P12's accepted timing costs and earlier decisions do not authorize
these P13 increases. The full programme remains active.
