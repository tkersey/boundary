# Optimization acceptance

**State:** repository cleanup is retained. The compiler, standalone-caller and Reader-ordering
review repairs are qualified with authenticated package bindings; fresh final serial
reviews remain open. This is the consolidated acceptance report for
Boundary #161, World #59 and Agent #39. No merge or release is authorized.

The [current specification](canonical-cutover-and-optimization-spec.md) owns all
P01–P31, T01–T42, G01–G45 and L01–L20 requirements. The implementation and witnesses
below have bounded domains; passing tests are not a universal correctness proof.
The [measurement record](performance/optimization-acceptance.json) retains exact
identities, current comparison samples, commands, cost acceptance, failure limits,
and an immutable archive index. Superseded milestone narratives and raw historical
reports remain at the indexed Git commits, with their original subjects and hashes.

## Qualified tuple and validation

| Role | Exact qualified input |
| --- | --- |
| Boundary compiler | `42c089c9c07cf01054ecd057d39a95660db919de` |
| Agent consumer | `db48ebcdf1565be94d31b41f6b124b057e039f7a` |
| World runtime source | `cb52f4ff43bbf23daf9cacb31ea26d9e3648235f` |
| World kernel SHA-256 | `9356b1264a215486b579a143dcc2ff73711f2a7e44898b3560922d68cdf1338d` |
| Boundary package | `boundary-3.0.0-dev.0-flclaPJ9fQDsfjdn3cJd09Kpyo7JNlF-d8B_fDzkbrp1` |
| Runtime producer | GitHub run `36629384504`, artifact `11062197659` |
| Cumulative compiler baseline | Boundary `63137689bf788bc408ba638f47256f2a8f219b44`, Agent `dd336f0c3833b233978c103caf73b3bcad1daf47` |
| Cumulative runtime baseline | Kernel `7d31effb1d4e32523d0fcbd5b4d5f5a8a2289fbd4c731173a33b1c174524282f` |

The downloaded Boundary source tree was recomputed and matched GitHub's commit
API. Both Zig-managed and archive-extracted package inventories were measured and
verified independently; their mode differences are not normalized away. World
retains its own Boundary `511fe38` build input. Agent's compiler dependency is a
separate authenticated input. Source, package and runtime identities are distinct.

| Executed check | Terminal result |
| --- | --- |
| Boundary `zig build check -Doptimize=ReleaseSafe --summary all` | 319/319 steps; 842/842 tests; exit 0 |
| Boundary data and authoring subset | 540 data + 227 authoring tests; exit 0 |
| Native variant payload execution, original/checked/shared/source-free link | pass; independent expected scalar outputs |
| Node/Wasmtime variant matrix, authenticated kernel | 12 cases; 288 comparisons; 12 same-image restores; 12 wrong-image rejections |
| Agent `check-agent4 check-agent4-integration check-compiled-tool-browser`, ReleaseSafe | 411/411 steps; 202/202 Zig tests; final Node suite 95/95; no skips; exit 0 |
| Current Agent corpus from repaired compiler | All 18 images byte-identical to the previously qualified corpus |
| Annex A/B/C exact reference-model blocks | All pass; exact block hashes and counts in the measurement record |

The Agent command's exact source/archive/runtime/browser/cache/prefix inputs and
terminal log hash are retained in the measurement record. These observations
belong to the tuple above. Cleanup successors require their own artifact bindings;
documentation removal is not a new measurement of execution.

## Contracts and canonical adoption

Every production closed compile and final closed link invokes checked P01.
Typed/direct compilation, standalone linking and Agent's compiled-tool path use
the shared compiler. Open components defer whole-program coalescing to closed
linking. Codecs and World execution do not silently optimize existing images or
reinterpret State. Removed `off`/`safe` controls remain rejected; historical
comparisons use separate predecessor artifacts or independent fixed fixtures.

Original admission and capture observations precede transformation. Independent
transformation checks, fresh candidate admission, nominal/ownership distinctions,
P01 exact no-growth selection, legal no-op, and deterministic work-limit rollback
remain required. Structural compilation preserves its logical-step contract;
semantic compilation preserves its specified external observations. World
acceleration preserves the exact same-image stepping/interruption relation.

The finite Stage A retirement is closed: Agent `value_equality.define`, `adapted`
and `compare`, their source-ID specialization and owned migration callers were
retired in `6e43faf`. The callback error translation and independently frozen
producer fixtures were repaired. Source inspection, domain admission, component
construction and invalid-IR fixtures remain legitimate IR users. Uniform frontend
syntax is excluded. SQLite/durable-session/recovery work remains cancelled; no
replacement persistence system was introduced.

## Delivered capability and retained proof surfaces

Unqualified module names below are under Boundary `src/data`; explicit paths
are relative to Boundary unless marked World. Each entry names the
implemented fragment and its retained unit/native/platform witnesses. The archive
index supplies the original local comparison, source hashes, commands and limits
for every measured milestone; these historical results are not current-head claims.

| Package | Implemented capability | Principal proof surface |
| --- | --- | --- |
| P01 | Mandatory checked whole-program coalescing; exact no-growth and rollback | `src/data/coalescing*`, [T01–T42 map](coalescing-acceptance.md), frozen predecessor fixtures |
| P02 | Versioned value/constructor, constant, known-bit and length facts; caller propagation | `src/data/value_facts*`, `call_contexts*`, `application_specialization_tests.zig` |
| P03 | Checked direct application with ordered captures/arguments and opaque fallbacks | `application_specialization*`; native and source-free link cases |
| P04 | Pure expression reuse under versioned facts | `expression_reuse*`; changed-cell and first-failure negatives |
| P05 | Dead computation and private input removal; retained operational reads preserved | `dead_computation*`, `dead_arguments.zig`, `input_demand_tests.zig` |
| P06 | Checked partial redundancy elimination | `partial_redundancy*`; ownership, branch and platform witnesses |
| P07 | Dead capture, field projection, summaries and observation-closed affine state | `capture_*`, `affine_*`; L01–L20 below |
| P08 | Product/cell/closure scalar replacement in proved private regions | `aggregate_reduction*`, `cell_reduction*`; escape/ownership negatives |
| P09 | Known-callable/tag/literal workers, runtime capture arguments and selective leaf inlining | `call_patterns*`, `call_pattern_*`, `leaf_inlining*`; payload-transfer mutation and source-free execution |
| P10 | Nonrecursive and mutually recursive private continuation groups | `contification*`; first-class escape and suspension witnesses |
| P11 | Shared tail clauses and capability/evidence forwarding | `tail_clauses*`, `evidence_forwarding*`; dynamic-installation and custody cases |
| P12 | Checked empty-handler and disjoint Reader fusion | `handler_elimination*`, `reader_fusion*`; return/state/effect near-misses |
| P13 | Eager map/fold and demand-preserving unfold fusion | `sequence_fusion*`, `unfold_fusion*`; failing unused suffix controls |
| P14 | Forwarding-thunk and hyperfunction reductions | `thunk_forwarding*`; native hyper/memo, ignored peer/fault and multishot cases |
| P15 | Finite action-summary contexts | `action_laws.zig`, `context_compression*`; noncommuting orientation and checked-add counterexamples |
| P16 | Persistent sequence constructor contexts | `constructor_contexts*`; escaped/multishot fallback and output-order checks |
| P17 | Source construction with linearized rows/fields and bounded materialization | `src/source*`, `src/authoring*`, `test/v2/construction*`; N/2N/4N operation counts |
| P18 | Total and guarded loop motion | `loop_regions*`, `loop_motion*`; zero-trip, fault, cell/borrow negatives |
| P19 | Bounded loop unswitching with economic selection | `loop_unswitch*`; dynamic cell versions, generic fallback and held-out cases |
| P20 | Checked induction/range and affine transforms; same-image range work | `induction*`, `affine_induction*`; World alias, bounds and stepping checks |
| P21 | Common tails, bounded duplication and pure outlining | `common_tails*`, `tail_duplication*`, `outlining*`; custody/failure and recursive controls |
| P22 | Logical interference packing plus persistent physical-page packing | `slot_packing*`; World `activation_slots*`, retained views, reuse, allocation failures |
| P23 | Immutable profile-guided policy with exact identity and fixed budgets | `optimization_profile.zig`, profile tests in `call_patterns_tests`; typed/source forwarding and malformed/stale rejection |
| P24 | Restricted rectangular interchange and checked tiling with selection | `rectangular*`; point-visitation, zero-trip, dependent/order-sensitive negatives |
| P25 | Bounded scalar superinstructions | World `scalar_batch*`; every quantum cut, checked failure and cancellation |
| P26 | Compatible-frame reuse and dead-blob retention control | World `frame_reuse*`, `blob_retention*`, alias/collection/failure tests |
| P27 | Typed equality saturation with checked extraction | `equality_saturation*`; missing side conditions, width/type/cycle and budget negatives |
| P28 | Offline SMT discovery through the production acceptance checker | `tools/bitvector_search.py`, bitvector tool/tests; proved XOR law and refuted/unknown guards |
| P29 | Controlled recursive specialization/generalization | `recursive_specialization_tests.zig`, call-pattern worker construction; growing/near-equal configurations |
| P30 | Exact schema partition/interning | `schema_partition.zig`; independent pairwise oracle, forced collision and eight private hash seeds |
| P31 | Compiler-free final closed linking with full policy forwarding | `tools/component_link.zig`, component/link tests; destroyed source/object storage and false borrow/import rejection |

These are executable transformations, not authoring-helper counts. Examples of
measured capability include affine three-word captures becoming two, 128-word
private-worker storage reduction, P15 long-chain peaks falling from about 3.7 MB
to 41–106 KB, P25/P26 512-call allocations falling from 1,030 to 6, roughly 1 MiB
released from paused residents, and P22 64-branch page savings of 12–23 KiB.
These claims retain their exact original workloads and measurement identities in
the archive; they do not assert every Agent workload benefits or that size proves speed.

## Cost acceptance and cumulative comparisons

The user explicitly stated **“All costs are accepted.”** This resolves all
currently recorded tradeoffs, including M3/P13/P16/P18/P19/P20/P24 and the final
cumulative cells. Previous separate acceptances for the cutover, M2/M2.5,
P12/P14/P15/P22/P25/P26 and admission costs remain valid. The decision is not a
waiver for future unmeasured costs or correctness/authority requirements.

The measurement record retains all five alternating windows of nine samples for
six final consumer runs, with three warmups per window. Local and pre-cutover
comparisons remain separate. All 48 local admission/replay comparisons showed no
confirmed slowdown or memory increase. Across 30 cumulative replay scenarios,
no fresh-invocation slowdown was confirmed. This excludes external host/model time.

Six cumulative admission-memory increases match the previously accepted measured
values exactly (peak +5,880–14,614 bytes; retained +4,054–12,104 bytes). Review-model
admission measured +63.374 µs (13.83%), versus the earlier accepted approximately
+62.7 µs (13.6%); the local comparison confirmed no additional runtime slowdown.
Fifteen document/consequence cumulative execution-memory increases, up to 9,332
bytes in WASM, are now explicitly accepted. Native M3 cumulative peaks reached
+21,972 bytes. Exact row identities, values and samples remain in the record.

| Accepted historical package costs | Recorded scope, not a new measurement |
| --- | --- |
| M3 | Callable +2.44 µs; 13 phase increases up to 74.208 µs; cumulative document/consequence memory as above |
| P13 | Three WASM increases up to 8.42 µs |
| P16 | Eight timing increases up to 100 µs |
| P18 | 19 timing increases up to 150.58 µs; memory up to 2,674 bytes |
| P19 | 74 local/structural comparisons up to 225.33 µs; memory up to 4,014 bytes; includes a real 256-branch execution increase |
| P20 | 18 compiler-output timing increases up to 197.6 µs; memory about 1,051 bytes |
| P24 | Selected 1×1 WASM fresh +2.48 µs (5.7%), and 20×0 admission +3.88 µs (16.5%); rejected tiling is excluded |
| P22 | Four native storage cells +10–83 ns; two native pause cells about +41 ns near clock resolution |
| P25/P26 | Four-operation WASM fresh +1.06 µs; bounded reclamation pauses +0.166–10.208 µs native and +1.04–1.35 µs WASM |

All other accepted cells remain identifiable in the archive and retained cost
extracts. Explained Boundary construction regressions are accepted under the
specification's compiler policy; they are not claimed as World performance gains.

## Cross-package obligations

| Requirements | Retained deciding witnesses |
| --- | --- |
| G01–G08 | Original-invalid declaration/component rejection; typed capture callbacks; simultaneous assignments and epochs; admitted wrong-result mutations; opaque/unknown constructor and feasible profile alternatives |
| G09–G14 | First-failure arithmetic, changed-cell expression/PRE/motion controls, owned cleanup, independent/shared memo cells, ignored hyperfunction peer, suspension/escape contification negatives |
| G15–G19 | Deep/shallow/dynamic handler and capability cases; Reader near-misses; eager/demand-sensitive sequence cases; action orientation; multishot/escaping constructor contexts |
| G20–G25 | World retained snapshot/alias reuse; logical/physical slot tests; scalar batch every-cut checks; structural/semantic controls; cancellation/cleanup; same-image restores and cross-image rejection |
| G26–G33 | Nominal authority pins; scope/failure outlining; zero-trip/overflow/dependent loops; upper-bound-not-length; stale profiles; equality extraction guards; SMT negative/unknown guards; recursive growing configurations |
| G34–G40 | Collision/seed/concurrency tests; deterministic work and allocation failures; source-free closed linking; Agent direct/compiled-tool policy and approvals; unchanged retry; actual encoded-size thresholds |
| G41 | Native six-variant ablation and nine WASM cases, 72 fresh-instance boundaries; 197/113/106-byte original/staged/shared images |
| G42 | Construction counter/order and N/2N/4N scaling witnesses; measured compiler costs separated from execution |
| G43 | Explicit ambiguous origins after rewriting; stale source IDs cleared; later successful compilation resets diagnostics |
| G44 | Independent BPI3/PST3/component/wire goldens and duplicate-containing image round trips; codecs do not optimize |
| G45 | Exact Annex A/B model execution; Annex C separately supports L20; finite-model scope only |

For the individual P01 obligations see the [T01–T42 witness map](coalescing-acceptance.md).

## Affine capture-state obligations

| ID | Retained deciding witness |
| --- | --- |
| L01 | `affine_capture_tests`: 24 generated, admitted non-permutation matrices with dynamic inputs/offsets; emission and independent acceptance. |
| L02 | `test/v2/affine_capture`: three-word recurrent capture becomes two; independent expected values at 0, 1, 2, 3, 8 and 31 updates. `original capture admission precedes every affine target decision` preserves rejection even for invalid targets/zero budgets. |
| L03 | `a future reset prevents a one-coordinate parity rewrite`; Annex C independently supplies the shortest future distinguishing suffix. |
| L04 | Native recurrent input/offset witness, missing caller-bias mutation, wrong recursive argument mutation, and `independent acceptance rejects an admissible wrong affine offset`. |
| L05 | Two dynamically selected recursive modes and a separately added third reset mode; the expanded action set forces full state and rejects the stale two-mode candidate. |
| L06 | `affine_parallel_tests`, stable-slot extraction test, native cyclic-edge execution, and one-expression accumulator reuse with independent checking. |
| L07 | `full product inspection of the rotating state preserves all three words`: admitted full tuple observation, rank three, exact P01 no-op. |
| L08 | Full two-word inspection followed by a one-coordinate private loop; native request/resume; independently encoded inspection/loop objects linked without source storage. |
| L09 | Calling a full observer from the parity worker forces the full state; the indexed closure-kernel test separately checks backward propagation over a return edge. |
| L10 | `additional opaque observation expands the actual record state space`: unchanged transitions and containment of every previous basis row in the expanded closure. |
| L11 | Distinct observation/canonical bases independently validate and execute. `affine_state.cost` measures actual construction instructions, all worker update/output/control instructions, and encoded bytes; selection is an explicit deterministic heuristic, not a speed/minimality theorem. |
| L12 | The same-rank wrong basis `{1,2}` is rejected against the actual emitted records; rank alone grants no equivalence. |
| L13 | Rank-zero emission and full-rank no-op tests, plus default-pipeline retention of small unprofitable direct cases. |
| L14 | Exact scalar/reusable/no-owned-or-borrowed-region eligibility; nonlinear OR is a retained boundary; valid opaque computation consumer declines; constructor-backed/public/handler/resource interfaces cannot enter the direct-parameter route. |
| L15 | Independently encoded caller/worker BMO1 objects expose the recurrence only at closed link; ordinary linker/interface admission still precedes the shared semantic stage. Object buffers are destroyed before execution. |
| L16 | Checked 2/3/8/32/64/128-word scaling; direct-parameter 128-word boundary; native/WASM/Wasmtime outputs. The extended cost probe measures initialization, Prepared storage, invocation peak and checkpoints separately. Native/WASM storage and paired latency are measured below; the one native admission increase has explicit user acceptance. |
| L17 | Independently admitted wrong capture order, recursive arguments, parallel transfer, offset, and successor worker are rejected by the record checker. |
| L18 | Annex C prefix reconstruction; 21 actual-image same-image restores and wrong-image rejections through the unchanged kernel. No semantic compiler certificate is used to change World stepping. |
| L19 | Allocation-failure injection for extraction, emission, checked capture/direct transformations and product unpacking; exact deterministic P01 rollback; changed-mode stale candidate rejection and decoded-input lifetime checks. |
| L20 | the consolidated measurement record retains the executed finite-model counts and independent-oracle results separately from production tests. |

## Failures, limits and remaining work

The first six-lens review of Boundary `086c203` found three genuine correctness
defects. Boundary `42c089c` repairs operational input demand, selected-variant
payload transport, and typed/source profile forwarding. Independent mutation
checks remain; ordinary capture liveness is unchanged. The intermediate fixture
union error and incomplete payload checker were corrected before the passing
aggregate. Earlier failed aggregates, rejected P19/P22/P24/P26 experiments, and
transport failures remain in the immutable archive; none is relabeled passed.

No clean review credit survives the invalidated subject. The fresh final serial
review contract applies only after cleanup and affected artifact checks. Canonical
Review Fold history could not be projected (InvalidStoreBinding); no complete
historical horizon, first-occurrence or universal exclusion claim is made.

Synthetic opportunities are labeled as such. All 18 current Agent images are
unchanged by the review repair, so it is not a new Agent speedup. The model
appendices establish finite-model results only. Required ownership, first-failure,
nominal authority, cleanup, cancellation and same-image interruption contracts
remain independently enforced. No persistence subsystem was added or substituted.

## Repository cleanup account

- Boundary: consolidate 110 superseded milestone/cost/report artifacts into this
  report and its measurement record. Keep the compact P01 witness map, current
  coalescing API documentation, full accepted specification, useful harnesses,
  independent fixtures and all production sources. Remove obsolete report entries
  from the Zig package allowlist.
- Agent: consolidate 29 historical milestone/census/measurement artifacts into
  its existing qualification page and this shared record. Preserve dependency
  authentication, contract documentation, frozen parser producer and all useful
  test/benchmark harnesses. Exclude generated historical receipts from packaging.
- World: no redundant delivery report or obsolete experimental harness was found
  in this assignment's change set. Retain the distinct P22/P25/P26 measurement and
  correctness harnesses; point verification documentation to the shared acceptance
  record. No runtime code or kernel rebuild is needed for this documentation step.

The archive index lists each removed artifact, repository, immutable commit, byte
length and SHA-256. Before removal, every file was byte-compared with its committed
version. Sole new integration evidence is retained here (command, exact tuple,
terminal counts and log hash). Actual authenticated bundles used as measured
controls/candidates and canonical owner stores remain intact. Unrelated/concurrent
work is preserved. Historical source/package identities remain historical.

Affected documentation references and package inputs passed cleanup checks.
Results and the new package binding are recorded separately from the earlier
execution qualification; the full integration run was not repeated solely because
report files were removed.

Cleanup checks passed: 845 retained source/test files are byte-identical to their
qualified heads; 139 retired artifacts match their committed archives; 96 current
comparisons and 8,640 raw timing samples are preserved; all checked relative links
and package allowlist paths exist. The generated bitvector Python bytecode cache
was removed; its source and tests remain. A local-directory package inspection
was stopped after recursively copying its own temporary output; that temporary
copy was removed. The stopped directory fetch receives no qualification credit.
Archive-based inspection and independent authentication of the published package
subsequently passed. No full runtime suite was repeated for the report-only cleanup.

### Cleanup successor qualification

Boundary `dc42ff9bac6f712a2e432e23254b31b6f17bd595` supplies the authenticated
cleaned package `boundary-3.0.0-dev.0-flclaO9RRADpcWhrNMAkiBHBcosyJecfZEVYpt94QRVv`.
Its source tree matches GitHub, both package mode profiles verify, and its complete
production source inventory is identical to the qualified repair. Agent
`1c35910ae252c0469aca98d077f2c6a642aaf809` binds it. World
`9e2956a4ed93928222fd2ec0415433f5129ba51b` changes verification documentation only;
the actual runtime still comes from authenticated `cb52f4f`, kernel `9356b126`.

Cleaned-package emission passed **202/202 steps**. Its complete declared
distribution inventory and all **67 input files** are byte-identical to the
qualified pre-cleanup distribution. Six additional outputs in the old full-test
directory belong to separate check targets, as verified from the unchanged build
declarations; they are not missing distribution files. A02 outside-tree public
authoring passed, and the newly built source-independent archive passed its
**3/3 documented-command tests**, including parser and inquiry execution.
The source archive hash, package inventories, use-archive receipt and scoped
verification results are retained in the measurement record.

This final evidence update is outside the dependency package allowlist. It does
not change the authenticated compiler package or require another runtime build.
Final reviews must cover the current corrected heads, including this cleanup.

### Final-review follow-up: predecessor transfer demand

Fresh-eyes review of `44505a4` found that dead-computation removal pinned explicit
transfer sources only in their own block. An admitted predecessor definition could
therefore be erased and cause `UnavailableSlot` during semantic compilation.
This invalidates that candidate and resets all review credit; all six initial
outcomes were collected before reopening implementation.

The successor reuses the existing CFG-wide executable-demand fixed point in the
DCE finder and independent validator, retiring `pinEdge` and
`pinExplicitTransfers`. Ordinary capture/retention liveness and original/candidate
ownership admission remain separate. Cross-block jump/yield, overwrite, genuine
dead-definition and loop-backedge regressions pass. Native/source-free execution
and fresh-instance WASM quantum-one checkpoints preserve expected values and
authored yields. Full Boundary qualification passes 319/319 steps and 844/844 tests;
all 18 current Agent corpus images remain byte-identical. The successor is published and bound; fresh final reviews remain open.
The machine-readable follow-up preserves the red result and scoped green evidence.
No additional report family, authoring migration or runtime rebuild is introduced.

The published repair is Boundary `4d24fca7faa43e29dae70b19522a31e1cd2a007b`,
bound by Agent `5dbd639eb66add423eefc4ae49db8c43f3a5bdaf`. Its source tree and
both package profiles are independently authenticated. Re-emission passed
231 steps plus one test, with 30 additional parser-artifact steps; all 75
image/object/argument files, 41 binary fixtures and the 67 declared distribution
files match the original integrated inputs exactly. Outside-tree A02 authoring
and the new use-archive command suite (3/3) passed. Agent host code and kernel `9356b126`
are unchanged. The earlier 411-step runtime result retains its original tuple;
reuse is limited to those identical inputs, while the newly admitted transfer
cases have their own native/WASM proof. No historical measurement is relabeled.

### Final-review follow-up: retained standalone callers

Invariant review of `42b1a26` found three retained package/probe callers still
using the retired `computation` export. Boundary `d43448a` changes seven references
to the existing `source` export. No compiler/runtime implementation or assertion
changes. The aggregate omitted these standalone entrypoints; all review credit
was reset and all six initial outcomes were folded before repair.

The four rejection tests pass, the category fixture now emits its intended
Schema/Operation diagnostic, and the timing probe builds and emits 20 samples.
The committed public-package check passes every rejection diagnostic and six
native/Node/Wasmtime scenarios. A scan of 363 tracked Zig files and 53 named
Boundary import bindings found no remaining retired-export dereferences.

Agent `5f4999fd6ffcef6243ff59a452782228ceb4a312` binds the independently authenticated published package.
Both package profiles verify; only the three repaired test/probe files differ
from the preceding package. Emission passes 231 steps and one test, with 30
additional parser steps. All 75 image/object/argument files, 41 binary fixtures
and 67 distribution files match the prior qualified artifacts exactly. Outside-tree
authoring and all three use-archive command tests pass. Historical aggregate/runtime
results keep their original subjects and are reused only for unchanged inputs;
the new standalone checks are recorded separately. Fresh final reviews remain open.

### Final-review follow-up: Reader effect ordering

Invariant review of `6e68888` found that Reader fusion reused nesting-ordered
handled evidence as a canonical effect row. Admitted descending effect-ID pairs
therefore failed with `NonCanonical`. All six initial reviews were folded before
repair; all credit was reset.

Boundary `4d0649e9c93a3d9659f5899ad8d479c8eda205e2` preserves positional handled
and capability evidence while separately constructing the sorted effect row.
Independent validation uses original effect membership and candidate admission,
with handler/state ordering unchanged. The regression fails before repair and
passes afterward; deliberately corrupted handled evidence and rows are rejected.
The full ReleaseSafe aggregate passes **319/319 steps and 845/845 tests**.

Both ID orders pass the existing Boolean state/operation cases and noncommuting
return cases through standalone fusion, semantic compilation and source-free
linking. Native/Node/Wasmtime qualification passes **300 comparisons**, **24**
malformed-input rejections, **24** checkpoint restores and **24** wrong-image
rejections, including quantum-one execution. The committed public-package check
also passes all rejection diagnostics and six execution scenarios.

Agent `da16920dbf2ad879b243265c17decbb34fcd9ce4` binds the independently authenticated
package; both package profiles verify. Emission passes **259/259 steps and one
test**. All **75** image/object/argument files, **41** binary fixtures and **67**
distribution files match the preceding qualified inputs. A02 outside-tree
authoring and all **3/3** archive-command tests pass. The archive was built with
the two dependency edits before their commit; its original receipt preserves
that source observation. No later source change is hidden or relabeled.

World runtime remains `cb52f4f`, kernel `9356b126`. Earlier full integration and
performance results keep their original subjects; reuse covers only identical
runtime inputs and unchanged hosts/kernel. The new Reader cases have separate
current proof. Cleanup and accepted cost accounting remain intact. Fresh final
serial reviews are still required.
