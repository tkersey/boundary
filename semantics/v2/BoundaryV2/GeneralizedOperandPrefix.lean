import BoundaryV2.GeneralizedTargetDeterminism

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Every compiled computation begins with exactly its source operand prefix.
The remaining instruction retains all authored code, scope, and control work.
This constructor-complete equation ties generic operand failure to compilation. -/
theorem computation_has_operand_prefix (body : Source.Computation signature algebra program context result) :
    ∃ next : Target.Code signature algebra program context (body.operandPrefix.types.reverse ++ []) result,
      computation body = arguments body.operandPrefix.arguments next := by
  cases body with
  | returnValue value | primitive operation inputs => exact ⟨.ret, rfl⟩
  | call reference inputs => exact ⟨.callNamed reference .ret, rfl⟩
  | @apply context use parameters result function inputs =>
    refine ⟨by simpa [Source.Computation.operandPrefix, List.reverse_cons, List.append_assoc] using
      (Target.Code.callClosure (signature := signature) (algebra := algebra) (definitions := program)
        (context := context) (use := use) (parameters := parameters) (stack := []) (answer := result) .ret), ?_⟩
    simp [computation, Source.Computation.operandPrefix, arguments]
  | matchSum value left right => exact ⟨.branch (computation left) (computation right), rfl⟩
  | perform operation capability payload bodies =>
    refine ⟨by simpa [Source.Computation.operandPrefix, List.reverse_cons, List.append_assoc] using
      (Target.Code.dispatch (signature := signature) (algebra := algebra) (definitions := program)
        (context := context) (stack := []) operation .ret), ?_⟩
    simp [computation, Source.Computation.operandPrefix, arguments]
  | resume continuation value => exact ⟨.resume .ret, rfl⟩
  | resumeWith effect continuation value returned clauses => exact ⟨.replaceHandler effect (computation returned) (Defunctionalization.clauses clauses) .ret, rfl⟩
  | inject continuation body => exact ⟨.inject .ret, rfl⟩
  | cellNew region value => exact ⟨.cellNew .ret, rfl⟩
  | cellRead cell => exact ⟨.cellRead .ret, rfl⟩
  | cellWrite cell value => exact ⟨.cellWrite .ret, rfl⟩
  | dispose continuation => exact ⟨.dispose .ret, rfl⟩
  | clone continuation => exact ⟨.clone .ret, rfl⟩
  | package value => exact ⟨.package .ret, rfl⟩
  | unpackage value => exact ⟨.unpackage .ret, rfl⟩
  | bind first rest => exact ⟨computation (.bind first rest), rfl⟩
  | handle effect mode returned clauses body => exact ⟨computation (.handle effect mode returned clauses body), rfl⟩
  | withRegion body => exact ⟨computation (.withRegion body), rfl⟩
  | protect cleanup body => exact ⟨computation (.protect cleanup body), rfl⟩
  | fail fault => exact ⟨computation (.fail fault), rfl⟩
  | yieldThen body => exact ⟨computation (.yieldThen body), rfl⟩

/-- A failed pure prefix determines the ordinary fault observation before the
receiving opcode can run. This covers every computation constructor through
the compiler decomposition above, including store-dependent instructions. -/
theorem compiled_operand_fault_observation (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (failed : body.operandPrefix.arguments.evaluate bindings = .error fault)
    (observation : Target.Observation signature algebra program result) :
    Target.Observes (definitions table) (.code (computation body) (environment bindings) .nil .done) observation ↔
      observation = .failed fault := by
  obtain ⟨next, compiled⟩ := computation_has_operand_prefix body
  obtain ⟨count, after, steps, faulted⟩ := arguments_fault_drains body.operandPrefix.arguments bindings next .nil fault failed
  rw [compiled, steps.observes_iff .done]
  cases faulted
  rw [Target.CallStep.observes_iff Target.CallStep.fault rfl]
  exact Target.HeadObservation.observes_iff .failed _

end BoundaryV2.Generalized.Defunctionalization
