# M5: construction and loop optimization

The full corrected specification remains authoritative. P17 is recorded here;
P18 onward, final bindings and installed serial reviews remain open. Separate
M3/P13/P16 economic decisions are not superseded by this construction work.

## P17 construction boundary

The source binding spine already stores IDs and appends records rather than
recopying its preceding computation. Typed `Body.bind` accumulates bindings and
`Body.finish` materializes them once in reverse order. Keep those representations.
The N/2N/4N witnesses count source nodes, array relocation and emitter occurrences;
wall-clock points alone do not establish their growth law.

Two measured metadata operations did repeatedly search existing prefixes:

- `source.Row.unionWith`: an existing-row scan for each right-hand effect ID.
  Generator composition and need-state construction retain this public interface.
  Sorted rows now use a linear merge; unsorted inputs are privately sorted first.
  Left multiplicities, right deduplication, final order and input immutability are
  preserved. In particular, invalid duplicate-left evidence is not silently fixed.
- `Context.fields` and `Body.arguments`: repeated field-name searches. Per-call
  indexes now detect duplicate declarations and resolve supplied arguments.
  Checks still run in declaration order: an earlier missing name/foreign value
  wins over a later duplicate. Temporary indexes use the child allocator and are
  freed on return; owned metadata stays in the builder arena. Scope, source
  occurrence, capture, failure-layout and nominal checks remain in place.

No public API, native emitter invocation, source declaration order or persistent
cache is added. The first indexed version retained scratch in the builder arena;
measurement identified that cost and the retained version uses bounded-lived
scratch with one reservation. Small-arity fixed setup costs remain explicit.

### Deliberate limit

Distinct literal lookup still scans the mutable low-level constant table. At
512/1024/2048 distinct literals, the current implementation visits
130,816/523,776/2,096,128 records. It is not claimed linear. A persistent index
without a mutation boundary would change valid raw-table editing and subsequent
lookup/alias behavior; a new regression test demonstrates that counterexample.
The P17 binding/list representation is retained, not replaced by a redundant
higher-rank encoding or an unsafe cache. No raw construction migration is required.

### Deciding observations

- Long binding spine: 512/1024/2048 occurrences; exact source-node counts,
  array-pointer relocation counts and copied record bytes. Reused and distinct
  configurations are reported separately.
- Typed forward chain: 128/256/512 emitters produce 511/1023/2047 terms and
  513/1025/2049 values. Native emission counts remain N. Authoring is timed
  separately from observed source-copy/check/lowering/target-admission/P01 phases.
- Capture helpers: 32/64/128 authored captures remain exactly 32/64/128 checked
  target capture fields. Publication/capture validation is outside authoring time.
- Effect-row union and named declaration/assembly have separate repeated paired
  measurements against frozen P16 code. Ordered and unsorted row behavior,
  duplicate policy, caller storage and allocation failures have direct tests.
- Native execution compares an explicit binding spine with the forward builder,
  including every external request's nominal identity and payload, authenticated
  replies and the final value. Same-type, differently configured native emitters
  must retain distinct traces and images. Reversed named arguments must still
  materialize in declaration order.

No World execution speedup is claimed for a construction-only change. Consumer
and fixture image equality, integrated checks and final cost reporting remain to
be recorded before delivery.

## P17 retained measurements and qualification

The final five alternating paired windows (three warmups/nine samples per process)
are in `performance/m5-p17.json`. At 2048+2048 sorted row entries, paired median
ratio is 0.01147: control/candidate median times 1,405,667/16,125 ns. At 512 named
fields, declaration ratio is 0.03109 (297,542/9,250 ns), and assembly ratio is
0.02307 (590,250/13,667 ns). These are isolated construction operations, not an
application or execution-speed claim.

One-to-four-field cases pay approximately 42–84 ns of fixed index setup in the
paired observations. Scratch allocation increases are reported. These Boundary
construction tradeoffs fall under the corrected policy; no World cost exception
is inferred. The first arena-retained-index experiment is labelled superseded,
not relabelled as final evidence. Output metadata ownership remains unchanged.

Final ReleaseSafe aggregate: 319 steps / 753 tests, terminal exit zero. Three
native tests pass exact external-request identity/payload order, authenticated
replies, final values, emitter invocation traces and distinct configurations;
a 17-field reversed argument list materializes in declared order. Existing
source capture, nominal, lifecycle and allocation-failure tests remain included.
The new malformed-name tests preserve missing/duplicate/foreign-value priority.

The frozen P16 compiler produces byte-identical images and native emission traces
for both construction representations and both configurations. Raw and typed
representations also agree with each other. All 18 Agent images remain unchanged.
Existing same-image runtime evidence therefore remains applicable to those exact
artifacts; no kernel rebuild, runtime reinterpretation or new public selector is
involved. P17's construction capability and scoped improvements are delivered;
whole-authoring linearity is explicitly not claimed for mutable literal lookup.
P18 onward, pending M3/P13/P16 decisions, final bindings and serial reviews remain.
