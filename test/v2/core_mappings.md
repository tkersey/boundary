# Production conformance and the generalized core

This is the interpretation map for the programs emitted by
[emit_source.zig](emit_source.zig) and selected by
[semantic_cases.mjs](semantic_cases.mjs). The public builder produces the
staged source; the normal compiler produces its BPI2 image. The independent
[source oracle](source_oracle.mjs) interprets that staged source without reading
the image. [conformance.mjs](conformance.mjs) compares its observations with
fresh native and WASM World instances.

The map identifies the core constructions exercised by each fixture and the
observations that distinguish them. The linked Lean developments prove local
laws, with their stated capture/support premises. They do not prove that the
production compiler establishes every premise, or certify these image bytes.
Remaining whole-core, dormant-template, and lifetime composition is tracked in
the [proof inventory](../../semantics/v2/README.md).

## Constructor interpretation

| Public authoring construction | Symbolic interpretation |
| --- | --- |
| `declare`/`define`, lexical references, `lambda`, `bind`, `apply`, named calls | A finite source code table, ordered environments, authored computation closures, and higher-order caller contexts. Compilation replaces the executable continuation with target code and frame data. Source bind provenance retains the actual body and captured environment. |
| Effect declaration, capability, `perform`, `handle` | A typed operation family and a nominal attachment. The payload, operation result, handler body result, and handler answer remain separate types. Equal effect descriptions do not identify different installations. |
| `resume_value`, `resume_computation`, `resume_with` | Value reentry, use-site computation injection, and successor-handler reentry. Deep capture retains its return delimiter; shallow capture stops before it. Clause postprocessing remains outside the resumed future. |
| Multi resumption, `clone`, packages, owned computation closures | Admitted immutable templates, fresh activation maps, and actual owning-field handoff. Reusable permission does not authorize copying exclusive captures or existing cleanup obligations. |
| `with_region`, `cell_new`, `cell_get`, `cell_set` | Named live regions and current typed cell contents. Branch-local copies have fresh identities; shared outer cells are read from the current arena. Region names do not prescribe cleanup order. |
| `protect`, `dispose`, failure, `yield_then` | Explicit exit information and a retained cleanup continuation. Operand handoff, original failure, ordered cleanup failures, first cancellation reason, and pending/running/finished cleanup remain distinct. |
| Scalars, products, sums, sequences, resource pack/unpack | Ordered structural values and the leaf/resource interfaces. Concrete `u64` bounds, encodings, collection algorithms, and resource representation checks remain executable production obligations. |

## Fixture map

Case suffixes select inputs or cancellation scripts; the `program` column in
`semantic_cases.mjs` identifies the shared source artifact. Numeric values below
are decoded values, except where a tagged product or sequence is stated.

| Program stems | Public builder source and distinguishing observation | Core law surface |
| --- | --- | --- |
| `lexical` | [examples.zig](../../src/v2/source/examples.zig), `lexical`: a closure captures input `40` and receives a separate argument `2`, returning `42`. Capture order and argument position both matter. | [GeneralizedClosureEvaluation](../../semantics/v2/BoundaryV2/GeneralizedClosureEvaluation.lean), [GeneralizedOrdinaryOwnedExecution](../../semantics/v2/BoundaryV2/GeneralizedOrdinaryOwnedExecution.lean), D. |
| `recursive` | `examples.zig`, `recursive`: `recursive-10000` follows a finite recursive code-table call chain and returns true. The test input bounds the example; the core has no semantic fuel. | [GeneralizedCalls](../../semantics/v2/BoundaryV2/GeneralizedCalls.lean), [GeneralizedProgramObservations](../../semantics/v2/BoundaryV2/GeneralizedProgramObservations.lean), D. |
| `deep` | `examples.zig`, `deep`: the body asks, adds `1`, and returns through a clause that multiplies by `10`; the operation clause resumes with `5`, then adds `7`. The result is `67`, distinguishing the return delimiter from the later clause caller. | [GeneralizedHandlerExecutionExamples](../../semantics/v2/BoundaryV2/GeneralizedHandlerExecutionExamples.lean), [GeneralizedReification](../../semantics/v2/BoundaryV2/GeneralizedReification.lean), D/H. |
| `nested` | [control_examples.zig](../../src/v2/source/control_examples.zig), `nested`: two installations of the same effect retain different capability values; nested return and clause postprocessing produce `677`. | Nominal selection/forwarding and context reconstruction in [GeneralizedForwarding](../../semantics/v2/BoundaryV2/GeneralizedForwarding.lean), H. |
| `shallow` | `control_examples.zig`, `shallow`: a two-phase boolean protocol installs successor state. Input `0` completes; input `1` fails. A shallow continuation must not retain the old return interpretation. | [GeneralizedSuccessor](../../semantics/v2/BoundaryV2/GeneralizedSuccessor.lean), [GeneralizedControlExecution](../../semantics/v2/BoundaryV2/GeneralizedControlExecution.lean), H. |
| `injection`, `shallow-injection` | [injection_example.zig](../../src/v2/source/injection_example.zig): the same raised value is handled at the clause site or restored use site. The alternatives return `109` and `209`; both deep and shallow variants are exercised. | [GeneralizedInjectionExecution](../../semantics/v2/BoundaryV2/GeneralizedInjectionExecution.lean), [GeneralizedMultiControlEntry](../../semantics/v2/BoundaryV2/GeneralizedMultiControlEntry.lean), D/H/U. |
| `shallow-resumptions` | [shallow_resume_example.zig](../../src/v2/source/shallow_resume_example.zig): deep/shallow × linear/multi × value/computation reentry. The eight results are four `99`s followed by four `42`s. Multi variants use the template twice. | Deep/shallow capture, registered multi entry, and answer separation in [GeneralizedMultiEntry](../../semantics/v2/BoundaryV2/GeneralizedMultiEntry.lean) and `GeneralizedMultiControlEntry`, H/U. |
| `answers` | [answer_example.zig](../../src/v2/source/answer_example.zig): the same State body is interpreted into optional and value-with-state answers. The oracle checks the full tagged product, including the returned value and final state. | [GeneralizedSuccessorExamples](../../semantics/v2/BoundaryV2/GeneralizedSuccessorExamples.lean), handler answer transformation, H. |
| `successor-state` | [successor_state_example.zig](../../src/v2/source/successor_state_example.zig): a shallow successor carries an outer capability and a live cell through a yield. The result is `(42, 37)`. | Successor environment preservation, fresh installation, and live cell access in `GeneralizedSuccessor`, [GeneralizedRegionExecution](../../semantics/v2/BoundaryV2/GeneralizedRegionExecution.lean), and `GeneralizedMultiControlEntry`, H/U. |
| `clause-payload` | [clause_payload_example.zig](../../src/v2/source/clause_payload_example.zig): an inner clause carries an older attachment, yields, and disposes its token. The ordinary case returns unit; static younger/self-borrow variants remain in authoring tests. | Explicit capability identity, source support, and capture/lifetime permissions; [GeneralizedLifetimeExamples](../../semantics/v2/BoundaryV2/GeneralizedLifetimeExamples.lean), H/U. |
| `choices-all`, `choices-first` | `examples.zig` and the public [Choice library](../../src/v2/library/choice.zig): the same two-choice body is collected exhaustively or short-circuited to the first result. The oracle checks the encoded sequence/optional result. | Multi activation and clause-answer bypass; [GeneralizedTemplates](../../semantics/v2/BoundaryV2/GeneralizedTemplates.lean), [GeneralizedBranching](../../semantics/v2/BoundaryV2/GeneralizedBranching.lean), H/U. |
| `state-local`, `state-shared` | [state_choice_example.zig](../../src/v2/source/state_choice_example.zig): changing State/Choice nesting changes the second branch's state result. The first result is `1`; the second is `1` for local state and `2` for shared state. No commutativity law is assumed. | [GeneralizedTemplateExamples](../../semantics/v2/BoundaryV2/GeneralizedTemplateExamples.lean), [GeneralizedSourceActivation](../../semantics/v2/BoundaryV2/GeneralizedSourceActivation.lean), U. |
| `reentrant`, `cloned` | [reentrant_example.zig](../../src/v2/source/reentrant_example.zig): a template is stored in a cell it captures and reentered while its earlier activation is live. `cloned` obtains it by explicit conversion. Both yield and return `113`. | Fresh local maps, alias preservation, current shared state, and owned freeze in [GeneralizedSourceFreeze](../../semantics/v2/BoundaryV2/GeneralizedSourceFreeze.lean) and `GeneralizedSourceActivation`, U/O. Full dormant-template registry lifecycle composition remains open. |
| `ownership` | [ownership_example.zig](../../src/v2/source/ownership_example.zig): two one-shot controls of the same type belong to different installations. The inner clause yields while the outer token remains owned; the program returns `1`. | [GeneralizedControlStore](../../semantics/v2/BoundaryV2/GeneralizedControlStore.lean), [GeneralizedHandlerExecutionExamples](../../semantics/v2/BoundaryV2/GeneralizedHandlerExecutionExamples.lean), U. |
| `resource-scalar`, `resource-pair` | [resource_example.zig](../../src/v2/source/resource_example.zig): one resource client works with two private representations. Normal runs return `42`; body/cleanup cancellation variants retain the first reason `stop` and the required request history. | Nominal resource authority and cleanup composition in [GeneralizedResources](../../semantics/v2/BoundaryV2/GeneralizedResources.lean), [GeneralizedStatefulCleanup](../../semantics/v2/BoundaryV2/GeneralizedStatefulCleanup.lean), U/X. Representation equality grants no authority. |
| `generator` | [generator_example.zig](../../src/v2/source/generator_example.zig): values `42` and `43` cross a yield, followed by the external release request carrying `43`. The owned future and its cleanup survive suspension. | Owned packaging/unpacking, disposal, and open observation in [GeneralizedPackageExecution](../../semantics/v2/BoundaryV2/GeneralizedPackageExecution.lean), [GeneralizedDisposalExecution](../../semantics/v2/BoundaryV2/GeneralizedDisposalExecution.lean), U/X/O. |
| `scheduler` | [scheduler_example.zig](../../src/v2/source/scheduler_example.zig): two source-authored tasks, a pending join, and FIFO execution yield result `30` and task log `[1,2,3,4]`. The host only supplies the ordinary execution protocol. | Library composition of typed requests, owned resumptions, and cells; D/H/U/O. The fixture is not a fairness theorem. |
| `queens-dfs`, `queens-bfs` | [queens_example.zig](../../src/v2/source/queens_example.zig): both public search interpreters find `[2,4,1,3]` and `[3,1,4,2]` in `60` attempts, with different selection positions. Each solution passes through acquire/visit/release requests. | Finite library composition of branching, state, owned control, and cleanup; H/U/X/O. Search order is preserved, not normalized away. |
| `scoped-reader` | [scoped_reader_example.zig](../../src/v2/source/scoped_reader_example.zig): scoped forwarding transforms the inside computation as well as resuming the outside. It returns `(20,10)` and logs payloads `2,1,1` on an unrelated residual effect. | Computation-argument scope and forwarding in [GeneralizedForwardingExamples](../../semantics/v2/BoundaryV2/GeneralizedForwardingExamples.lean), H/D/O. The two equal log payloads remain two trace events. |
| `writer-raise` | [writer_raise_example.zig](../../src/v2/source/writer_raise_example.zig): Writer, Raise, and cleanup compose in source. The oracle checks the caught value `9` and ordered log `[1,3]` as one tagged result. | Effectful clauses, answer transformation, and cleanup ordering; H/X. |
| `cell-order` | [cell_order_example.zig](../../src/v2/source/cell_order_example.zig): a product evaluates read, write, read, returning `(1, unit, 7)`. Reusing the same expression node does not cache the first read. | Ordered operands and current cell contents in [GeneralizedStatefulOperandExecution](../../semantics/v2/BoundaryV2/GeneralizedStatefulOperandExecution.lean), U/X. |
| `handle-operand-order`, `protect-operand-order` | [operand_order_example.zig](../../src/v2/source/operand_order_example.zig): control operands write distinct values before the last read; both results are `7`. | Complete operand evaluation before handler/protection entry; `GeneralizedOwnedOperandLowering` and `GeneralizedProtectionExecution`, D/X. |
| `abort-custody` | [abort_example.zig](../../src/v2/source/abort_example.zig): the owned branch requests before failing with `9`; the empty branch returns `41` without a request. | Custody through calls and failure, with distinct observable branches; U/X/O. |
| `clause-abort` | [clause_abort_example.zig](../../src/v2/source/clause_abort_example.zig): a clause fails while it owns a protected continuation. The release request receives the original failure `9`; repeated cancellation during cleanup keeps the pending request. | Owned disposal and exit history in `GeneralizedDisposalExecution`, [GeneralizedExitCompletion](../../semantics/v2/BoundaryV2/GeneralizedExitCompletion.lean), X/O. |
| `unwind`, `yielding-cleanup` | [unwind_example.zig](../../src/v2/source/unwind_example.zig): original failure/normal alternatives, two failing cleanups, requests, and optional cleanup yields. The first primary is retained when present; cleanup failures remain `[7,8]`; repeated cancellation keeps `stop`. | [GeneralizedUnwinding](../../semantics/v2/BoundaryV2/GeneralizedUnwinding.lean), `GeneralizedStatefulCleanup`, and `GeneralizedExitCompletion`, X/O. |
| `borrow-operands` | [borrow_operand_example.zig](../../src/v2/source/borrow_operand_example.zig), with [custody_order_example.zig](../../src/v2/source/custody_order_example.zig) and [operand_failure_example.zig](../../src/v2/source/operand_failure_example.zig): indices `0–31` exercise borrow/ownership failures; `32–41` expose custody order; `42–52` fail a later operand across call, apply, capture, protection, region, and scope cases. The source oracle checks the authored failure and ordered release payloads. | Ordered owning-field handoff and inner-first/creation-order exit laws in `GeneralizedOwnedOperands`, `GeneralizedStatefulOperandExecution`, and [GeneralizedRegionRetirement](../../semantics/v2/BoundaryV2/GeneralizedRegionRetirement.lean), U/X. Concrete static borrow analysis is tested, not universally proved. |
| `cleanup-disposal`, `cleanup-disposal-running`, `cleanup-disposal-failure`, `cleanup-disposal-owned` | [cleanup_disposal.zig](cleanup_disposal.zig): variants abandon a captured cleanup, distinguish already-running cleanup, preserve failure/cancellation, and dispose an owned generator result. Checked logs include `[1,3,99,99]`, `[1,3,99]`, and `[3,7,99]`; the failure variant yields and retains the first cancellation reason. | Captured cleanup cursor, disposal, first reason, and ordered exit obligations; X/U. [GeneralizedNestedCleanup](../../semantics/v2/BoundaryV2/GeneralizedNestedCleanup.lean) supplies the local nested driver, with shared resources and ordered failure composition. These retained regressions require the approved unmodified World fix. Complete integration with owned disposal and all lifetimes remains open. |
| `indexed` | [indexed_example.zig](../../src/v2/source/indexed_example.zig): the same Choice library handles an external `unit -> u64` request and a separate `unit -> bool` request. Results are `Some(37)` and `Some(true)`. The runner replays the earlier accepted response against the later request and verifies rejection plus unchanged polling. | Typed signatures and future reentry in [GeneralizedInteractionExamples](../../semantics/v2/BoundaryV2/GeneralizedInteractionExamples.lean), O/H. The concrete stale-packet check has different requests/types; it is not global anti-replay proof. |
| `bounded-values`, `scalar-contracts` | `examples.zig` and [scalar_contract_example.zig](../../src/v2/source/scalar_contract_example.zig): bounded collections, UTF-8, indexes/variants, scalar arithmetic faults, and concrete encodings. `scalar-contracts` has 19 scripted alternatives. | The leaf algebra's pure value-or-fault contract and structural value support. Concrete opcode and codec correctness are production tests, outside the Lean core theorem. |
| `generated-0` through `generated-15` | [generated_programs.zig](generated_programs.zig): deterministic combinations of captures, structured arithmetic, requests, yields, and cleanup. | The complete constructor and seed mapping is in [generated_programs.md](generated_programs.md). |

## Static refusal counterparts

These cases run in the ordinary authoring/data checks, rather than asking the
source oracle to predict compiler admission. They retain the rejected program
and a required-valid counterpart where the source test provides one.

| Obligation | Existing production test |
| --- | --- |
| Conversion consumes the original one-shot authority | [source tests](../../src/v2/source/tests.zig), `converting an owned capture consumes the original before any template activation`: substitute the original control after `clone`; admission rejects `InvalidOwnership`. |
| An exclusive caller capture cannot become multi-use | `latent multi use rejects an exclusive caller capture but permits capture before acquisition`: acquisition-before-multi rejects, while capture-before-acquisition compiles. |
| A resource borrow cannot escape its protected body | `a resource borrow cannot escape its protected body even when immediately read by the caller`: returning the loan then reading it outside protection rejects. |
| Resource identity is nominal authority | `source clients cannot introduce or eliminate a private resource representation`: unauthorized pack and unpack both reject despite using the same representation schema. |
| Older capability payloads differ from the suspended attachment | `operation clauses accept older capability payloads and reject their own attachment`; successor-state and actual-handler-state lifetime tests exercise independent capability/cell support. |
| Multi capture includes dormant handler state and continuation edges | [capture tests](../../src/v2/source/capture_tests.zig): protected-borrow variants reject; the safe unit-state counterpart compiles. |
| Sharing syntax cannot erase ownership-sensitive uses | [projection tests](../../src/v2/source/projection_tests.zig): repeated consuming projections and a borrow after consumption reject; explicit scalar binding and live borrowing observers remain valid. |
| Returned cells and owned regions preserve lifetime distinctions | `choice returns borrowed cells to a caller inside their live region` and `escaping choice captures own even a region with no live cells`. |

## Observation boundary and reproduction

All 143 current scripts prescribe a terminal outcome: 52 complete, 87 fail,
and 4 cancel. The runner rejects an unfinished source result or an unscripted
runtime request. This does not remove open observations: each requested boundary
is compared and polled before its scripted response is supplied.

Every normal comparison runs a fresh native process and creates a fresh WASM
host. Complete outcome bytes must agree, and alternating native/WASM results
supply the next saved state. The resulting semantic trace is compared with the
source oracle, preserving request identity, payload, order, yield, failure, and
cleanup information. A mutated response and the `indexed` stale response must
reject in both engines without consuming the pending future. No proof claim is
based on digest injectivity or a new process alone.

```sh
zig build check-v2 -Doptimize=ReleaseSafe -j2 --summary all
zig build check-v2-conformance -Dworld-source="$WORLD_CHECKOUT" -Doptimize=ReleaseSafe -j2 --summary all
node test/v2/conformance.mjs --world "$WORLD_CHECKOUT" --fixtures zig-out --case indexed
```

The clean World checkout remains pinned to
`87698f92ca7be4d5442e97ba27a2468aa3ff6a7c`. Boundary and World identities, tool
versions, case names, and comparison counts appear in ordinary command output.
Static refusal regressions stay in the authoring/data tests; the source oracle
is not used to decide static ownership or borrow admission.
