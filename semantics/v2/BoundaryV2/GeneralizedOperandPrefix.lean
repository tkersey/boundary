import BoundaryV2.GeneralizedTargetDeterminism

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- The first control instruction after the typed operand prefix, together
with its authored bodies and clauses. This is computable first-order code. -/
def operandTail (body : Source.Computation signature algebra program context result) :
    Target.Code signature algebra program context (body.operandPrefix.types.reverse ++ []) result := by
  cases body with
  | returnValue value | primitive operation inputs => exact .ret
  | call reference inputs => exact .callNamed reference .ret
  | @apply context use parameters result function inputs =>
    simpa [Source.Computation.operandPrefix, List.reverse_cons, List.append_assoc] using
      (Target.Code.callClosure (signature := signature) (algebra := algebra) (definitions := program)
        (context := context) (use := use) (parameters := parameters) (stack := []) (answer := result) .ret)
  | matchSum value left right => exact .branch (computation left) (computation right)
  | perform operation capability payload bodies =>
    simpa [Source.Computation.operandPrefix, List.reverse_cons, List.append_assoc] using
      (Target.Code.dispatch (signature := signature) (algebra := algebra) (definitions := program)
        (context := context) (stack := []) operation .ret)
  | resume continuation value => exact .resume .ret
  | resumeWith effect continuation value returned clauses => exact .replaceHandler effect (computation returned) (Defunctionalization.clauses clauses) .ret
  | inject continuation body => exact .inject .ret
  | cellNew region value => exact .cellNew .ret
  | cellRead cell => exact .cellRead .ret
  | cellWrite cell value => exact .cellWrite .ret
  | dispose continuation => exact .dispose .ret
  | clone continuation => exact .clone .ret
  | package value => exact .package .ret
  | unpackage value => exact .unpackage .ret
  | bind first rest => exact computation (.bind first rest)
  | handle effect mode returned clauses body => exact computation (.handle effect mode returned clauses body)
  | withRegion body => exact computation (.withRegion body)
  | protect cleanup body => exact computation (.protect cleanup body)
  | fail fault => exact computation (.fail fault)
  | yieldThen body => exact computation (.yieldThen body)

/-- The source prefix and the effective target tail reconstruct the unchanged
compiler for every computation constructor. -/
theorem computation_operand_prefix (body : Source.Computation signature algebra program context result) :
    computation body = arguments body.operandPrefix.arguments (operandTail body) := by
  cases body <;> simp [computation, Source.Computation.operandPrefix, arguments, operandTail]
  all_goals rfl

theorem computation_has_operand_prefix (body : Source.Computation signature algebra program context result) :
    ∃ next : Target.Code signature algebra program context (body.operandPrefix.types.reverse ++ []) result,
      computation body = arguments body.operandPrefix.arguments next :=
  ⟨operandTail body, computation_operand_prefix body⟩

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
