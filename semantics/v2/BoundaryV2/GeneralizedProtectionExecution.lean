import BoundaryV2.GeneralizedStateExecution
import BoundaryV2.GeneralizedExit
import BoundaryV2.GeneralizedProgramSimulation

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- Protection stores the authored cleanup without running it. The fresh
obligation remains attached to the body through the represented context. -/
theorem compiled_protection_entry
    (table : Source.Definitions signature algebra program)
    (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
    (body : Source.Computation signature algebra program context answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region)) (extra : List Reference) :
    let identity := Target.freshObligation (definitions table) (computation (.protect cleanup body))
      (environment bindings) .nil targetOutside targetStore (cells sourceCells) extra
    Source.ExecutionStep table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.protect cleanup body) bindings)⟩, sourceCells, regions⟩
      ⟨⟨sourceStore, sourceOutside.plug (.protection identity cleanup bindings (.evaluate body bindings))⟩, sourceCells, regions⟩ ∧
    Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.protect cleanup body)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ 1
      ⟨⟨targetStore, .code (computation body) (environment bindings) .nil
        (.push (.protection identity (computation cleanup) (environment bindings))
          (.push (.returnTo .ret (environment bindings) .nil) targetOutside))⟩, cells sourceCells, regions⟩ ∧
    CellStateRelated
      ⟨⟨sourceStore, sourceOutside.plug (.protection identity cleanup bindings (.evaluate body bindings))⟩, sourceCells, regions⟩
      ⟨⟨targetStore, .code (computation body) (environment bindings) .nil
        (.push (.protection identity (computation cleanup) (environment bindings))
          (.push (.returnTo .ret (environment bindings) .nil) targetOutside))⟩, cells sourceCells, regions⟩ := by
  dsimp only
  have same := fresh_obligation_corresponds table (.protect cleanup body) bindings targetOutside targetStore sourceCells extra
  refine ⟨.enterProtection extra (context_installation_support outside) (store_installation_support stores) same.symm,
    .single (.enterProtection extra rfl), ?_⟩
  let identity := Target.freshObligation (definitions table) (computation (.protect cleanup body))
    (environment bindings) .nil targetOutside targetStore (cells sourceCells) extra
  refine ⟨⟨stores, ?_⟩, rfl, rfl⟩
  simpa only [identity, Source.Context.plug, Source.Frame.plug] using EntryRelated.evaluate body bindings
    (.push (.protection identity cleanup bindings) (.passthrough bindings outside))

omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)] in
theorem compiled_cleanup_begin
    (table : Source.Definitions signature algebra program)
    (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (identity : Id .obligation) (fields : List UseScope.Field) (exit : ExitInfo algebra.Fault algebra.Reason) :
    ExitComposition.Step (definitions table)
      ⟨identity, .pending ⟨context, computation cleanup, environment bindings⟩, fields, exit⟩ 1
      ⟨identity, .running (.code (computation cleanup) (.cons (.exit exit) (environment bindings)) .nil .done) .active, fields, exit⟩ ∧
    EntryRelated (.evaluate cleanup (.cons (.exit exit) bindings))
      (.code (computation cleanup) (.cons (.exit exit) (environment bindings)) .nil .done) :=
  ⟨.begin, .evaluate cleanup (.cons (.exit exit) bindings) .done⟩

/- Any finite ordinary source cleanup run has a corresponding running target
cursor. The lifecycle consumes no second initiation right during that run. -/
omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)] in
theorem finite_cleanup_execution_corresponds
    (table : Source.Definitions signature algebra program)
    (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (identity : Id .obligation) (fields : List UseScope.Field) (exit : ExitInfo algebra.Fault algebra.Reason)
    (steps : Source.Steps table (.evaluate cleanup (.cons (.exit exit) bindings)) count sourceAfter) :
    ∃ targetAfter, ExitComposition.Steps (definitions table)
      ⟨identity, .pending ⟨context, computation cleanup, environment bindings⟩, fields, exit⟩ 1
      ⟨identity, .running targetAfter .active, fields, exit⟩ ∧ ProgramRelated sourceAfter .done targetAfter := by
  obtain ⟨targetCount, targetAfter, executed, related⟩ := finite_program_steps_simulate table steps
    (ProgramRelated.evaluate cleanup (.cons (.exit exit) bindings) .done)
  exact ⟨targetAfter, .cons .begin (ExitComposition.execute_steps executed), related⟩

end BoundaryV2.Generalized.Defunctionalization
