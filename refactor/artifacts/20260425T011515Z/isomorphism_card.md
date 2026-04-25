# Isomorphism Card

## Change: centralize benchmark `preserveValue`

### Equivalence Contract

- **Inputs covered:** Benchmark helper calls in facade-backed `bench/*.zig` files that wrap checksum/result values before accumulation or reporting.
- **Ordering preserved:** Yes. Each call still evaluates the original value expression before passing it to `std.mem.doNotOptimizeAway`.
- **Tie-breaking:** N/A.
- **Error semantics:** Unchanged. The helper does not throw; surrounding `try` expressions remain at the call sites.
- **Laziness:** Unchanged. Zig argument evaluation remains eager at each call site.
- **Short-circuit eval:** N/A.
- **Floating-point:** N/A.
- **RNG / hash order:** Unchanged. No RNG/hash iteration is introduced.
- **Observable side-effects:** Unchanged. The only side effect is the same `std.mem.doNotOptimizeAway` call on the same value.
- **Type narrowing:** Unchanged. Generic `anytype` and `@TypeOf(value)` return type are preserved exactly.
- **Rerender behavior:** N/A.

### Verification

- [x] `zig build lint -- --max-warnings 0`
- [x] `zig build bench-state-effect --summary none`
- [x] `zig build bench-family-matrix --summary none`
- [x] `zig build bench-runtime-backends --summary none`
- [x] `zig build zprof-hotspots --summary none`
- [x] `cloc` before/after on touched source files shows source code `2708 -> 2686` (`-22`)
- [ ] `zig build test --summary none` blocked by unrelated plain `ability.with` downstream compatibility failures in `source_ownership_probe_test`
