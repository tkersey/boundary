# Refactor Dashboard

Run ID: `20260425T011515Z`

## Summary

| Metric | Before | After | Delta | Direction |
| --- | ---: | ---: | ---: | --- |
| Touched source code LOC (`cloc`) | 2708 | 2686 | -22 | down |
| Diff stat for touched code files | - | - | 15 insertions, 42 deletions | net -27 |
| Exact `preserveValue` helper clones in facade-backed benchmarks | 7 | 0 | -7 | down |
| Lint issues | 0 | 0 | 0 | unchanged |
| Focused benchmark gates | 4 passed | 4 passed | 0 | unchanged |

## Proof

| Command | Result |
| --- | --- |
| `zig build lint -- --max-warnings 0` | pass, 203 files, no issues |
| `zig build bench-state-effect --summary none` | pass, checksums preserved |
| `zig build bench-family-matrix --summary none` | pass, lane checksums preserved |
| `zig build bench-runtime-backends --summary none` | pass, lane checksums preserved |
| `zig build zprof-hotspots --summary none` | pass, allocation/free counts balanced and checksums preserved |
| `git diff --check -- <touched code paths>` | pass |

## Blocked Lane

`zig build test --summary none` failed in `test/source_ownership_probe_test.zig` on plain downstream `ability.with` compatibility. The failing path is outside this benchmark-helper refactor.
