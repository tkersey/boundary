# Coalescing v2 acceptance inventory

This is a current evidence inventory, not a completion certificate. It follows
the accepted September 25 version 2 specification without weakening its gates.
The compiler default remains **off**. Agent's 18-configuration census found no
function/constructor reductions; description-only savings do not satisfy §16.2.

The implementation/evidence basis is Boundary `1a212c3` plus the browser harness
in this change, Agent `3e794e0` (pinned to Boundary `cc1cdb0`), and authenticated
World `c20695e`. Agent must be repinned and requalified against the final Boundary
candidate. No final CAS review epoch has begun.

“Supported” below means the listed bounded witness exists and passed its stated
checks. It does not establish universal correctness, complete platform coverage,
or unrelated requirements. “Partial” names an unresolved requirement within the
row. The reports linked from [coalescing.md](coalescing.md) record commands,
runtime identities, measurements, limits, and remaining work.

| ID | Current evidence | Disposition / remaining observation |
| --- | --- | --- |
| T01 | Public independently emitted closures at N=1,2,16,64,256; native/Node/Wasmtime values and overflow | Supported; constant helper/constructor/capture cardinality and shrinking images recorded. |
| T02 | `coalescing_view_tests`, `coalescing_origins_tests`, runtime edge cases | Supported for renamed blocks/slots/custody including unused locals and ancestor structure; representative layout checked independently. |
| T03 | Three-slot renamings, returned operand-order mutations, view input tests, reversed same-typed captures | Supported bounded witnesses; shared subtraction code preserves opposite captured operand order and overflow across runtimes. |
| T04 | Swap and three-way simultaneous cycles, repeated slots, native/Node/Wasmtime step agreement | Supported bounded assignment domain. |
| T05 | Different literals/base cases, arithmetic opcode/operand mutations, field immediate, fault payloads, swapped branch/sum roles | Supported focused mutation witnesses; originals and mutants admit independently before correspondence rejection. |
| T06 | Width/sign, bytes/text/array bounds and enum-tag no-merge cases; typed-constructor distinction | Partial: extend use/effect/internal contract differences systematically. |
| T07 | Duplicate `sum(A,A)` retains both injections and rejects ordinal 2; swapped-case mutant rejected | Supported existing ordinal/product witnesses. |
| T08 | Closure scaling and stateful closure capture descriptions share while values differ | Supported; independent expected captures and allocation-site counts. |
| T09 | Independent/shared mutable-cell fixtures; native/Node/Wasmtime/browser transfer | Supported: `1,1,2` versus `1,2,3`, with cell allocation sites retained. |
| T10 | Depth-eight alternating direct/constructed helper chains and changed leaf | Supported; structural reductions, normal/overflow results and matched boundaries. |
| T11 | Actual recursive candidate groups; terminating role/base cases and 128-step/42-request prefix | Partial: function-local cyclic CFG has structural/view tests, but its renamed-loop execution witness remains missing. |
| T12 | Fresh ordinary `ana`/query/invoke/defer helpers; differing Step configuration; unforced divergent peer | Supported bounded reciprocal/lazy cases with source oracle and three runtimes; browser subset included. |
| T13 | Independent/shared memo cells plus evaluation counter | Supported: independent cells evaluate twice, deliberate sharing once; runtime transfer retains this distinction. |
| T14 | Existing deep/shallow/answer-transforming fixtures in both modes and source oracle | Partial: assert actual handler-description merging and explicit incompatible mode/strategy no-merge fixtures. |
| T15 | Same-named private effect instances remain distinct under off/safe linking; sparse-region tests | Partial: extend explicit same-shaped private region/resource cross-object cases and runtime traces. |
| T16 | Public pass with live privileged/unprivileged identical helpers; unauthorized pack/unpack rejection | Supported admission/structural witnesses; no authority widening. |
| T17 | Two live privileged identical helpers remain singleton with separate authority sets | Supported structural witness. |
| T18 | Existing ownership/capture/borrow negatives retained; named capture checks run safe; linked false contracts reject both modes | Partial: systematic off/safe invocation of all relevant invalid fixtures and semantic-reason parity remains incomplete. |
| T19 | Cleanup/failure/disposal fixtures; Agent cancellation with compiled cleanup; browser cleanup requests | Partial: dedicated shared-code cleanup that itself suspends across return/failure/cancel remains incomplete. |
| T20 | Existing State/Choice multi-shot examples preserve local `[1,1]` vs shared `[1,2]` under transfer | Partial: combine recursive reentry, retained branches and resume/dispose in one coalescing witness. |
| T21 | Quantum-one native/Node/Wasmtime/browser progression, yields, resumed outcomes | Supported for recorded finite fixtures; recursive prefix is explicitly bounded. |
| T22 | Independent emitter processes, transported linker/object-only directory; actual cross-object code/constructor reductions | Partial: explicit binding that exposes cross-object sharing and recursive constructor/handler interfaces need further coverage. |
| T23 | Original imported borrow promises and constructor/handler substitution checked before projection in both modes | Partial: equivalent functions from distinct live caller/provenance contexts need a dedicated valid/invalid pair. |
| T24 | Existing forged constructor/handler borrow-substitution cases reject both modes | Supported those witnesses; full changed-contract matrix remains under T36. |
| T25 | Exact sorted keys, no fingerprints; independent finite relation oracle | Hash-collision route is inapplicable because no hash decides equivalence; deterministic output tests remain required. |
| T26 | Idempotence, repeat calls, concurrent varied compilations, reordered component instances/bindings | Supported bounded cases. |
| T27 | No-op exact-byte retention and cheapest-candidate selection | Partial: explicit real-codec size-rejection witness still required. |
| T28 | Existing exact codec counter, candidate encode equality, generated vector fixtures | Partial: coalescing-specific threshold cases at ID/LEB/vector codec transitions need explicit assertions. |
| T29 | `checkAllAllocationFailures` on discovery, candidate selection, diagnostics and ownership; work limits | Partial: complete new allocation-site inventory and overflow-path witnesses still need final audit. |
| T30 | Raw-record locations, full temporary map composition, typed-constructor origin discrimination, bounded ambiguity presentation | Supported tested diagnostics; source/end-to-end mutation coverage should be extended before final closure. |
| T31 | Old independent wire goldens retained; duplicate-schema BPI3 roundtrip preserves exact bytes without optimization | Supported codec/admission compatibility witnesses. |
| T32 | Each image restores its own states on fresh hosts; wrong-program state rejects | Supported in recorded native/Node/Wasmtime/browser scenarios. |
| T33 | Agent forwards through direct and final compiled-tool paths; protected applications in census | Partial: final dependency tuple and complete protected-runtime off/safe matrix required. |
| T34 | Output survives source/scratch release; four independent compiler threads and separate leak-checking allocators | Supported bounded lifetime/concurrency tests. |
| T35 | Separately admitted return-41/42, constructor-contract, and shared-body mutants rejected | Supported independent raw-record validation witnesses. |
| T36 | Missing/cyclic/foreign maps, nonbijections, pins, continuation/branch/sum edges, fault payloads, nominal effect maps | Partial: remaining region/resource and handler/constructor scalar/ordered contracts need systematic mutation coverage. |
| T37 | Singleton child restriction splits parents in graph oracle; both production profiles validate | Supported bounded restriction witnesses; production nested-parent coverage can be strengthened. |
| T38 | Exact ordering seam tests bytes/entry/full tie-break; fixed-point idempotence | Partial: demonstrate nontrivial repeated selection and description-winning cost path through the full selector. |
| T39 | Dead lower-ID duplicate origin test; live versus discarded authority; invalid unused pack/unpack rejection | Supported public-path witnesses and replay/idempotence checks. |
| T40 | Typed companion options preserve mandatory named capture observer/publication; observation byte equality | Partial: explicit cache-reuse original-occurrence callback cardinality still needs final coverage. |
| T41 | Exhaustion after an accepted intermediate round returns original baseline bytes | Supported deterministic rollback and ownership tests. |
| T42 | Exact Python appendix results reproduced; Zig exhaustive 4,330 graphs and independent 500-case oracle | Supported finite-model scope only; does not discharge the full runtime laws. |

## Promotion and measurement gates

| Gate | Current state |
| --- | --- |
| §16.1 structural/semantic | Incomplete while the partial rows above remain. |
| §16.2 real consumer code-sharing benefit | Unmet in recorded Agent corpus; no workload inflation or gate substitution authorized. |
| §16.3 runtime/admission/memory/checkpoint | Incomplete. Synthetic cold Boundary admission measurements are not World/Agent runtime qualification. |
| §16.4 compiler/linker economics | Initial ten-fixture compiler measurements exist. B0 control, scaling, unique graphs, source-free link and full phase accounting remain open. |
| §16.5 default/promotion | Keep off by default and retain drafts. |
| Serial review convergence | Not started; only a fully realized, locally proved candidate can earn closure credit. |

The next implementation work follows the partial rows; another passing aggregate
alone cannot change their disposition. Final delivery must refresh this inventory
against the exact commits and provider state.
