import BoundaryV2.GeneralizedSupport
import BoundaryV2.GeneralizedCompile

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

namespace Source

/- Authored reference occurrences are collected independently of target code.
Lexical selections contain variable positions, not new nominal identities. -/
mutual
  def Expression.references : Expression signature algebra program context type → List Reference
    | .datum value => value.references
    | .reference _ => []
    | .pair first second => first.references ++ second.references
    | .first value | .second value | .left value | .right value => value.references
    | .primitive _ inputs => inputs.references
    | .lambda _ body => body.references

  def Arguments.references : Arguments signature algebra program context types → List Reference
    | .nil => []
    | .cons first rest => first.references ++ rest.references

  def Computation.references : Computation signature algebra program context result → List Reference
    | .returnValue value => value.references
    | .bind first rest => first.references ++ rest.references
    | .apply function inputs => function.references ++ inputs.references
    | .call _ inputs | .primitive _ inputs => inputs.references
    | .matchSum test left right => test.references ++ left.references ++ right.references
    | .perform _ capability payload bodies => capability.references ++ payload.references ++ bodies.references
    | .handle _ _ returned clauses body => returned.references ++ clauses.references ++ body.references
    | .resume continuation value | .inject continuation value => continuation.references ++ value.references
    | .resumeWith _ continuation value returned clauses =>
      continuation.references ++ value.references ++ returned.references ++ clauses.references
    | .withRegion body | .yieldThen body => body.references
    | .cellNew first second | .cellWrite first second => first.references ++ second.references
    | .cellRead value | .dispose value | .clone value | .package value | .unpackage value => value.references
    | .protect cleanup body => cleanup.references ++ body.references
    | .fail _ => []

  def Clauses.references : Clauses signature algebra program effect mode context body answer → List Reference
    | .nil => []
    | .cons _ _ body rest => body.references ++ rest.references
end

end Source

namespace Defunctionalization

private theorem code_cast_references
    {first second : List (TypeOf signature)} (same : first = second)
    (castEqual : Target.Code signature algebra program context first result = Target.Code signature algebra program context second result)
    (code : Target.Code signature algebra program context first result) :
    (castEqual.mp code).references = code.references := by cases same; rfl

theorem selection_preserves_reference_support
    (captures : Selection context captured)
    (next : Target.Code signature algebra program context (captured.reverse ++ stack) result) :
    (selection captures next).references = next.references := by
  induction captures generalizing stack with
  | nil => rfl
  | cons reference rest induction =>
    exact (induction _).trans (code_cast_references
      (by simp only [List.reverse_cons, List.append_assoc, List.singleton_append]) _ next)

private theorem compilation_references_bounded (bound : Nat) :
    (∀ {context type stack result} (source : Source.Expression signature algebra program context type), sizeOf source < bound →
      ∀ (next : Target.Code signature algebra program context (type :: stack) result),
      (expression source next).references = source.references ++ next.references) ∧
    (∀ {context types stack result} (source : Source.Arguments signature algebra program context types), sizeOf source < bound →
      ∀ (next : Target.Code signature algebra program context (types.reverse ++ stack) result),
      (arguments source next).references = source.references ++ next.references) ∧
    (∀ {context result} (source : Source.Computation signature algebra program context result), sizeOf source < bound →
      (computation source).references = source.references) ∧
    (∀ {effect mode context body answer} (source : Source.Clauses signature algebra program effect mode context body answer), sizeOf source < bound →
      (clauses source).references = source.references) := by
  cases bound with
  | zero => refine ⟨?_, ?_, ?_, ?_⟩ <;> intros <;> omega
  | succ bound =>
    obtain ⟨expressions, argumentLists, computations, clauseLists⟩ := compilation_references_bounded bound
    refine ⟨?_, ?_, ?_, ?_⟩
    · intro context type stack result source sized next
      cases source with
      | datum value | reference reference => rfl
      | pair first second =>
        simp only [expression, Source.Expression.references, expressions first (by simp_all; omega),
          expressions second (by simp_all; omega), Target.Code.references, List.append_assoc]
      | first operand | second operand | left operand | right operand =>
        exact expressions operand (by simp_all; omega) _
      | primitive operation inputs => exact argumentLists inputs (by simp_all; omega) _
      | lambda captures body =>
        simp only [expression, Source.Expression.references, selection_preserves_reference_support,
          Target.Code.references, computations body (by simp_all; omega)]
    · intro context types stack result source sized next
      cases source with
      | nil => rfl
      | cons first rest =>
        simp only [arguments, Source.Arguments.references, expressions first (by simp_all; omega),
          argumentLists rest (by simp_all; omega), List.append_assoc]
        exact congrArg (first.references ++ ·)
          (congrArg (rest.references ++ ·) (code_cast_references
            (by simp only [List.reverse_cons, List.append_assoc, List.singleton_append]) _ next))
    · intro context result source sized
      cases source with
      | returnValue value =>
        simpa only [computation, Source.Computation.references, Target.Code.references, List.append_nil] using
          expressions value (by simp_all; omega) (Target.Code.ret)
      | bind first rest => simp only [computation, Source.Computation.references, Target.Code.references,
          computations first (by simp_all; omega), computations rest (by simp_all; omega)]
      | apply function inputs => simp only [computation, Source.Computation.references,
          expressions function (by simp_all; omega), argumentLists inputs (by simp_all; omega), Target.Code.references, List.append_nil]
      | call reference inputs =>
        simpa only [computation, Source.Computation.references, Target.Code.references, List.append_nil] using
          argumentLists inputs (by simp_all; omega) (.callNamed reference .ret)
      | primitive operation inputs =>
        simpa only [computation, Source.Computation.references, Target.Code.references, List.append_nil] using
          argumentLists inputs (by simp_all; omega) (.primitive operation .ret)
      | matchSum test left right => simp only [computation, Source.Computation.references,
          expressions test (by simp_all; omega), Target.Code.references,
          computations left (by simp_all; omega), computations right (by simp_all; omega), List.append_assoc]
      | perform operation capability payload bodies => simp only [computation, Source.Computation.references,
          expressions capability (by simp_all; omega), expressions payload (by simp_all; omega),
          argumentLists bodies (by simp_all; omega), Target.Code.references, List.append_nil, List.append_assoc]
      | handle effect mode returned handlers body => simp only [computation, Source.Computation.references, Target.Code.references,
          computations returned (by simp_all; omega), clauseLists handlers (by simp_all; omega),
          computations body (by simp_all; omega), List.append_nil]
      | resume continuation value | inject continuation value => simp only [computation, Source.Computation.references,
          expressions continuation (by simp_all; omega), expressions value (by simp_all; omega), Target.Code.references, List.append_nil]
      | resumeWith effect continuation value returned handlers => simp only [computation, Source.Computation.references,
          expressions continuation (by simp_all; omega), expressions value (by simp_all; omega), Target.Code.references,
          computations returned (by simp_all; omega), clauseLists handlers (by simp_all; omega), List.append_nil, List.append_assoc]
      | withRegion body | yieldThen body => simp only [computation, Source.Computation.references, Target.Code.references,
          computations body (by simp_all; omega), List.append_nil]
      | cellNew first second | cellWrite first second => simp only [computation, Source.Computation.references,
          expressions first (by simp_all; omega), expressions second (by simp_all; omega), Target.Code.references, List.append_nil]
      | cellRead value =>
        simpa only [computation, Source.Computation.references, Target.Code.references, List.append_nil] using
          expressions value (by simp_all; omega) (.cellRead .ret)
      | dispose value =>
        simpa only [computation, Source.Computation.references, Target.Code.references, List.append_nil] using
          expressions value (by simp_all; omega) (.dispose .ret)
      | clone value =>
        simpa only [computation, Source.Computation.references, Target.Code.references, List.append_nil] using
          expressions value (by simp_all; omega) (.clone .ret)
      | package value =>
        simpa only [computation, Source.Computation.references, Target.Code.references, List.append_nil] using
          expressions value (by simp_all; omega) (.package .ret)
      | unpackage value =>
        simpa only [computation, Source.Computation.references, Target.Code.references, List.append_nil] using
          expressions value (by simp_all; omega) (.unpackage .ret)
      | protect cleanup body => simp only [computation, Source.Computation.references, Target.Code.references,
          computations cleanup (by simp_all; omega), computations body (by simp_all; omega), List.append_nil]
      | fail fault => rfl
    · intro effect mode context body answer source sized
      cases source with
      | nil => rfl
      | cons operation use body rest => simp only [clauses, Source.Clauses.references, Target.Clauses.references,
          computations body (by simp_all; omega), clauseLists rest (by simp_all; omega)]
  termination_by bound

theorem expression_reference_support (source : Source.Expression signature algebra program context type)
    (next : Target.Code signature algebra program context (type :: stack) result) :
    (expression source next).references = source.references ++ next.references :=
  (compilation_references_bounded (sizeOf source + 1)).1 source (Nat.lt_succ_self _) next

theorem computation_reference_support (source : Source.Computation signature algebra program context result) :
    (computation source).references = source.references :=
  (compilation_references_bounded (sizeOf source + 1)).2.2.1 source (Nat.lt_succ_self _)

theorem clauses_reference_support (source : Source.Clauses signature algebra program effect mode context body answer) :
    (clauses source).references = source.references :=
  (compilation_references_bounded (sizeOf source + 1)).2.2.2 source (Nat.lt_succ_self _)

end Defunctionalization
end BoundaryV2.Generalized
