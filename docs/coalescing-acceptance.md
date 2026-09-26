# Coalescing v2 acceptance inventory

This is a current evidence inventory, not a completion certificate. It follows
the September 25 version 2 specification as amended by the user in
[v2.1](coalescing-spec.md). The compiler/linker default is **safe**. Current
compile-time overhead and limited Agent reductions are accepted trade-offs;
a speedup and the former §16.2 real-consumer benefit are not acceptance gates.

The Boundary evidence includes default enablement and its follow-up correctness
fixtures. World remains authenticated `c20695e`. Agent owns the exact consumer
pin and its qualification report in [PR 38](https://github.com/tkersey/agent/pull/38).
Final CAS review convergence remains a separate delivery obligation.

“Supported” below means the listed bounded witness exists and passed its stated
checks. It does not establish universal correctness, complete platform coverage,
or unrelated requirements. The reports linked from [coalescing.md](coalescing.md) record commands,
runtime identities, measurements, limits, and remaining work.

| ID | Current evidence | Disposition / remaining observation |
| --- | --- | --- |
| T01 | Public independently emitted closures at N=1,2,16,64,256; unit thresholds around 16,64,128,256 | Supported: constant helper/constructor/capture cardinality, exact count/encode equality and shrinking images. |
| T02 | `coalescing_view_tests`, `coalescing_origins_tests`, runtime edge cases | Supported for renamed blocks/slots/custody including unused locals and ancestor structure; representative layout checked independently. |
| T03 | Three-slot renamings, returned operand-order mutations, view input tests, reversed same-typed captures | Supported bounded witnesses; shared subtraction code preserves opposite captured operand order and overflow across runtimes. |
| T04 | Swap and three-way simultaneous cycles, repeated slots, native/Node/Wasmtime step agreement | Supported bounded assignment domain. |
| T05 | Different literals/base cases, arithmetic opcode/operand mutations, field immediate, fault payloads, swapped branch/sum roles | Supported focused mutation witnesses; originals and mutants admit independently before correspondence rejection. |
| T06 | Width/sign, bytes/text/array bounds, enum tags and callable use/effect/capture-bound distinctions | Supported: independently admitted contract mutants reject and distinct callable schemas remain distinct. |
| T07 | Duplicate `sum(A,A)` retains both injections and rejects ordinal 2; swapped-case mutant rejected | Supported existing ordinal/product witnesses. |
| T08 | Closure scaling and stateful closure capture descriptions share while values differ | Supported; independent expected captures and allocation-site counts. |
| T09 | Independent/shared mutable-cell fixtures; native/Node/Wasmtime/browser transfer | Supported: `1,1,2` versus `1,2,3`, with cell allocation sites retained. |
| T10 | Depth-eight alternating direct/constructed helper chains and changed leaf | Supported; structural reductions, normal/overflow results and matched boundaries. |
| T11 | Recursive role/base-case groups, 128-step/42-request prefix, and renamed function-local loops | Supported: zero/odd/even loop execution and changed exit order agree across native/Node/Wasmtime; the infinite observation is explicitly bounded. |
| T12 | Fresh ordinary `ana`/query/invoke/defer helpers; differing Step configuration; unforced divergent peer | Supported bounded reciprocal/lazy cases with source oracle and three runtimes; browser subset included. |
| T13 | Independent/shared memo cells plus evaluation counter | Supported: independent cells evaluate twice, deliberate sharing once; runtime transfer retains this distinction. |
| T14 | Deep/shallow/answer transformation; duplicate stateful and effectful descriptions; separate valid tail/general contracts | Supported bounded witnesses: actual descriptions merge, installations retain state, mixed modes/strategies remain distinct. |
| T15 | Independent source-free private effect, region and resource objects | Supported: two anchors remain two; distinct anchored code does not merge; native/Node/Wasmtime request IDs, values and transfer traces agree. |
| T16 | Public pass with live privileged/unprivileged identical helpers; unauthorized pack/unpack rejection | Supported admission/structural witnesses; no authority widening. |
| T17 | Two live privileged identical helpers remain singleton with separate authority sets | Supported structural witness. |
| T18 | Owned-use, borrow-use-after-consumption, protected escape, capture-bound and linked-contract negatives in both modes | Supported exact semantic-error parity. Original source/target and interface/borrow checks precede the mode branch; optimization cannot sanitize their failures. |
| T19 | Two equivalent nested finalizers share code; each cleanup performs an external request | Supported: both installations remain; return, arithmetic failure and cancellation preserve release order 2 then 1 across the source oracle and three runtimes. |
| T20 | Mutually recursive helpers inside multi-shot State/Choice; local and deliberately shared mutable state | Supported: local [2,2,2,2] versus shared [2,3,5,6], with real code sharing and fresh-host transfer. Existing explicit-disposal and retained-state cases remain. |
| T21 | Quantum-one native/Node/Wasmtime/browser progression, yields, resumed outcomes | Supported for recorded finite fixtures; recursive prefix is explicitly bounded. |
| T22 | Independent emitter processes and object-only final linking; private anchors and explicit effect binding | Supported: binding enables a 3-to-2 function reduction; private effects remain separate. Existing mutually recursive component and honest/forged constructor/handler import tests cover those interfaces. |
| T23 | Original borrow promises checked before projection; equivalent helpers used through two distinct live resource loans | Supported: the valid pair shares two bodies while preserving independent acquisition/release; escaping the second loan rejects with InvalidOwnership in both modes. |
| T24 | Existing forged constructor/handler borrow-substitution cases reject both modes | Supported those witnesses; full changed-contract matrix remains under T36. |
| T25 | Exact sorted keys, no fingerprints; independent finite relation oracle | Hash-collision route is inapplicable because no hash decides equivalence; determinism is covered by T26. |
| T26 | Idempotence, repeat calls, concurrent varied compilations, reordered component instances/bindings | Supported bounded cases. |
| T27 | No-op exact-byte retention, exact cost selection, and independent growth/nonreducing guards | Supported: an independently validated candidate exercises synthetic cost rejection at the selection seam; no claim that this cost increase occurred in BPI3. |
| T28 | Exact counting encoder versus actual encoding for closure families around ID/LEB/vector thresholds | Supported at 1,2,15,16,17,63,64,65,127,128,129,255,256,257; all selected lengths are no larger than off. Independent codec goldens remain. |
| T29 | Allocation injection through graph, correspondence, both candidates, diagnostics, cleanup, recursive state and resource-loan fixtures | Supported: every exercised allocation failure releases owners, retains original input identity and reports the error. Explicit work-counter overflow and intermediate-round budget rollback pass; see the allocation/limit audit in coalescing.md. |
| T30 | Raw-record locations, composed temporary maps, typed-constructor origins and bounded ambiguity | Supported bounded diagnostics and allocation-failure clearing; original named-capture publication checks remain authoritative. |
| T31 | Old independent wire goldens retained; duplicate-schema BPI3 roundtrip preserves exact bytes without optimization | Supported codec/admission compatibility witnesses. |
| T32 | Each image restores its own states on fresh hosts; wrong-program state rejects | Supported in recorded native/Node/Wasmtime/browser scenarios. |
| T33 | Agent direct/final-link option propagation, default-equals-safe census and protected applications | Consumer qualification is owned by [Agent PR 38](https://github.com/tkersey/agent/pull/38), its authenticated lock and consumer report. Final pin/aggregate status is recorded there; no Boundary-only check substitutes for it. |
| T34 | Output survives source/scratch release; four independent compiler threads and separate leak-checking allocators | Supported bounded lifetime/concurrency tests. |
| T35 | Separately admitted return-41/42, constructor-contract, and shared-body mutants rejected | Supported independent raw-record validation witnesses. |
| T36 | Forged maps, local bijections, pins, ordered edges/operands/captures, fault payloads, nominal effects/regions/resources and handler strategies | Supported direct mutation witnesses plus the exhaustive raw-field inventory and correctness argument; no discovery comparator serves as validator. |
| T37 | Singleton child restrictions split predecessor classes in the independent graph oracle; both production profiles validate | Supported bounded restriction witnesses; raw reference commutation separately prevents publishing a stale parent correspondence. |
| T38 | Exact ordering seam tests bytes/entry/full tie-break, including a description win; fixed-point idempotence and intermediate-round rollback | Supported bounded evidence: every accepted production round checks strictly fewer live records; rare cost orderings are tested at the explicit seam allowed by T38, not claimed as observed codec results. |
| T39 | Dead lower-ID duplicate origin test; live versus discarded authority; invalid unused pack/unpack rejection | Supported public-path witnesses and replay/idempotence checks. |
| T40 | Typed options retain mandatory named-capture publication; three original closure callbacks survive constructor-cache reuse and later coalescing | Supported: original value/variable IDs and callback counts match in both modes, metadata contracts share only afterward, and observing does not change bytes. |
| T41 | Exhaustion after an accepted intermediate round returns original baseline bytes | Supported deterministic rollback and ownership tests. |
| T42 | Exact Python appendix results reproduced; Zig exhaustive 4,330 graphs and independent 500-case oracle | Supported finite-model scope only; does not discharge the full runtime laws. |

## Correctness, integration and bounded measurement

| Gate | Current state |
| --- | --- |
| §16.1 structural/semantic | Boundary witnesses and arguments are listed above; consumer release qualification remains with Agent under T33. |
| §16.2 real consumer code-sharing benefit | Retired by v2.1. The recorded 18 Agent configurations have unchanged function/constructor counts; report description savings honestly. |
| §16.3 runtime/admission/memory/checkpoint | Correctness and capacity safety remain required. Synthetic cold admission measurements do not establish World/Agent runtime improvements. |
| §16.4 compiler/linker economics | Bounded measured optimization retained; 21–48% enabled compile-time improvement on ten synthetic fixtures, with remaining 1.6–4.4× safe/off overhead accepted. A further bounded experiment reuses identical portfolios: cleanup compilation improves 19%, with identical images. Further gains are optional. |
| §16.5 default/promotion | Default safe; explicit off retained. Draft retention tracks incomplete correctness/integration/review, not performance benefit. |
| Serial review convergence | Not started; only a fully realized, locally proved candidate can earn closure credit. |

Final delivery binds these observations to exact Boundary/Agent commits and the
provider state. Clean test runs and a finite relation model do not constitute a
formal proof of the compiler or unmeasured performance claims.
