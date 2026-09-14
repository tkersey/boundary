import BoundaryV2.GeneralizedSourceSupport
import BoundaryV2.GeneralizedValueRelocation

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

namespace Source

/- Rename authored references independently of target instructions. Types,
primitive operations, lexical positions, and finite definition indices stay fixed. -/
mutual
  def Expression.relocate (relocation : UseScope.Relocation) :
      Expression signature algebra program context type → Expression signature algebra program context type
    | .datum datum => .datum (datum.relocate relocation)
    | .reference reference => .reference reference
    | .pair first second => .pair (first.relocate relocation) (second.relocate relocation)
    | .first value => .first (value.relocate relocation)
    | .second value => .second (value.relocate relocation)
    | .left value => .left (value.relocate relocation)
    | .right value => .right (value.relocate relocation)
    | .primitive operation inputs => .primitive operation (inputs.relocate relocation)
    | .lambda captures body => .lambda captures (body.relocate relocation)

  def Arguments.relocate (relocation : UseScope.Relocation) :
      Arguments signature algebra program context types → Arguments signature algebra program context types
    | .nil => .nil
    | .cons first rest => .cons (first.relocate relocation) (rest.relocate relocation)

  def Computation.relocate (relocation : UseScope.Relocation) :
      Computation signature algebra program context result → Computation signature algebra program context result
    | .returnValue value => .returnValue (value.relocate relocation)
    | .bind first rest => .bind (first.relocate relocation) (rest.relocate relocation)
    | .apply function inputs => .apply (function.relocate relocation) (inputs.relocate relocation)
    | .call reference inputs => .call reference (inputs.relocate relocation)
    | .primitive operation inputs => .primitive operation (inputs.relocate relocation)
    | .matchSum test left right => .matchSum (test.relocate relocation) (left.relocate relocation) (right.relocate relocation)
    | .perform operation capability payload bodies =>
      .perform operation (capability.relocate relocation) (payload.relocate relocation) (bodies.relocate relocation)
    | .handle effect mode returned clauses body =>
      .handle effect mode (returned.relocate relocation) (clauses.relocate relocation) (body.relocate relocation)
    | .resume continuation value => .resume (continuation.relocate relocation) (value.relocate relocation)
    | .resumeWith effect continuation value returned clauses =>
      .resumeWith effect (continuation.relocate relocation) (value.relocate relocation)
        (returned.relocate relocation) (clauses.relocate relocation)
    | .inject continuation body => .inject (continuation.relocate relocation) (body.relocate relocation)
    | .withRegion body => .withRegion (body.relocate relocation)
    | .cellNew region value => .cellNew (region.relocate relocation) (value.relocate relocation)
    | .cellRead value => .cellRead (value.relocate relocation)
    | .cellWrite cell value => .cellWrite (cell.relocate relocation) (value.relocate relocation)
    | .protect cleanup body => .protect (cleanup.relocate relocation) (body.relocate relocation)
    | .dispose value => .dispose (value.relocate relocation)
    | .clone value => .clone (value.relocate relocation)
    | .package value => .package (value.relocate relocation)
    | .unpackage value => .unpackage (value.relocate relocation)
    | .fail fault => .fail fault
    | .yieldThen body => .yieldThen (body.relocate relocation)

  def Clauses.relocate (relocation : UseScope.Relocation) :
      Clauses signature algebra program effect mode context body answer → Clauses signature algebra program effect mode context body answer
    | .nil => .nil
    | .cons operation use body rest => .cons operation use (body.relocate relocation) (rest.relocate relocation)
end

end Source

namespace Defunctionalization

private theorem relocate_code_cast (relocation : UseScope.Relocation)
    {first second : List (TypeOf signature)} (same : first = second)
    (castEqual : Target.Code signature algebra program context first result = Target.Code signature algebra program context second result)
    (code : Target.Code signature algebra program context first result) :
    (castEqual.mp code).relocate relocation = castEqual.mp (code.relocate relocation) := by cases same; rfl

theorem relocate_selection (relocation : UseScope.Relocation) (captures : Selection context captured)
    (next : Target.Code signature algebra program context (captured.reverse ++ stack) result) :
    (selection captures next).relocate relocation = selection captures (next.relocate relocation) := by
  induction captures generalizing stack with
  | nil => rfl
  | cons reference rest induction =>
    simp only [selection, Target.Code.relocate, induction]
    exact congrArg (Target.Code.load reference) (congrArg (selection rest) (relocate_code_cast relocation
      (by simp only [List.reverse_cons, List.append_assoc, List.singleton_append]) _ next))

private theorem compilation_relocation_bounded (relocation : UseScope.Relocation) (bound : Nat) :
    (∀ {context type stack result} (source : Source.Expression signature algebra program context type), sizeOf source < bound →
      ∀ (next : Target.Code signature algebra program context (type :: stack) result),
      (expression source next).relocate relocation = expression (source.relocate relocation) (next.relocate relocation)) ∧
    (∀ {context types stack result} (source : Source.Arguments signature algebra program context types), sizeOf source < bound →
      ∀ (next : Target.Code signature algebra program context (types.reverse ++ stack) result),
      (arguments source next).relocate relocation = arguments (source.relocate relocation) (next.relocate relocation)) ∧
    (∀ {context result} (source : Source.Computation signature algebra program context result), sizeOf source < bound →
      (computation source).relocate relocation = computation (source.relocate relocation)) ∧
    (∀ {effect mode context body answer} (source : Source.Clauses signature algebra program effect mode context body answer), sizeOf source < bound →
      (clauses source).relocate relocation = clauses (source.relocate relocation)) := by
  cases bound with
  | zero => refine ⟨?_, ?_, ?_, ?_⟩ <;> intros <;> omega
  | succ bound =>
    obtain ⟨expressions, argumentLists, computations, clauseLists⟩ := compilation_relocation_bounded relocation bound
    refine ⟨?_, ?_, ?_, ?_⟩
    · intro context type stack result source sized next
      cases source with
      | datum datum | reference reference => rfl
      | pair first second =>
        simp only [expression, Source.Expression.relocate, expressions first (by simp_all; omega),
          expressions second (by simp_all; omega), Target.Code.relocate]
      | first operand | second operand | left operand | right operand =>
        exact expressions operand (by simp_all; omega) _
      | primitive operation inputs => exact argumentLists inputs (by simp_all; omega) _
      | lambda captures body =>
        simp only [expression, Source.Expression.relocate, relocate_selection, Target.Code.relocate,
          computations body (by simp_all; omega)]
    · intro context types stack result source sized next
      cases source with
      | nil => rfl
      | cons first rest =>
        simp only [arguments, Source.Arguments.relocate, expressions first (by simp_all; omega),
          argumentLists rest (by simp_all; omega)]
        exact congrArg (expression (first.relocate relocation))
          (congrArg (arguments (rest.relocate relocation)) (relocate_code_cast relocation
            (by simp only [List.reverse_cons, List.append_assoc, List.singleton_append]) _ next))
    · intro context result source sized
      cases source with
      | returnValue value => exact expressions value (by simp_all; omega) .ret
      | bind first rest =>
        simp only [computation, Source.Computation.relocate, Target.Code.relocate,
          computations first (by simp_all; omega), computations rest (by simp_all; omega)]
      | apply function inputs =>
        simp only [computation, Source.Computation.relocate, expressions function (by simp_all; omega),
          argumentLists inputs (by simp_all; omega), Target.Code.relocate]
      | call reference inputs => exact argumentLists inputs (by simp_all; omega) (.callNamed reference .ret)
      | primitive operation inputs => exact argumentLists inputs (by simp_all; omega) (.primitive operation .ret)
      | matchSum test left right =>
        simp only [computation, Source.Computation.relocate, expressions test (by simp_all; omega), Target.Code.relocate,
          computations left (by simp_all; omega), computations right (by simp_all; omega)]
      | perform operation capability payload bodies =>
        simp only [computation, Source.Computation.relocate, expressions capability (by simp_all; omega),
          expressions payload (by simp_all; omega), argumentLists bodies (by simp_all; omega), Target.Code.relocate]
      | handle effect mode returned handlers body =>
        simp only [computation, Source.Computation.relocate, Target.Code.relocate,
          computations returned (by simp_all; omega), clauseLists handlers (by simp_all; omega), computations body (by simp_all; omega)]
      | resume continuation value | inject continuation value =>
        simp only [computation, Source.Computation.relocate, expressions continuation (by simp_all; omega),
          expressions value (by simp_all; omega), Target.Code.relocate]
      | resumeWith effect continuation value returned handlers =>
        simp only [computation, Source.Computation.relocate, expressions continuation (by simp_all; omega),
          expressions value (by simp_all; omega), Target.Code.relocate, computations returned (by simp_all; omega),
          clauseLists handlers (by simp_all; omega)]
      | withRegion body | yieldThen body =>
        simp only [computation, Source.Computation.relocate, Target.Code.relocate, computations body (by simp_all; omega)]
      | cellNew first second | cellWrite first second =>
        simp only [computation, Source.Computation.relocate, expressions first (by simp_all; omega),
          expressions second (by simp_all; omega), Target.Code.relocate]
      | cellRead value => exact expressions value (by simp_all; omega) (.cellRead .ret)
      | dispose value => exact expressions value (by simp_all; omega) (.dispose .ret)
      | clone value => exact expressions value (by simp_all; omega) (.clone .ret)
      | package value => exact expressions value (by simp_all; omega) (.package .ret)
      | unpackage value => exact expressions value (by simp_all; omega) (.unpackage .ret)
      | protect cleanup body =>
        simp only [computation, Source.Computation.relocate, Target.Code.relocate,
          computations cleanup (by simp_all; omega), computations body (by simp_all; omega)]
      | fail fault => rfl
    · intro effect mode context body answer source sized
      cases source with
      | nil => rfl
      | cons operation use body rest =>
        simp only [clauses, Source.Clauses.relocate, Target.Clauses.relocate,
          computations body (by simp_all; omega), clauseLists rest (by simp_all; omega)]
  termination_by bound

theorem expression_relocation_commutes (relocation : UseScope.Relocation)
    (source : Source.Expression signature algebra program context type)
    (next : Target.Code signature algebra program context (type :: stack) result) :
    (expression source next).relocate relocation = expression (source.relocate relocation) (next.relocate relocation) :=
  (compilation_relocation_bounded relocation (sizeOf source + 1)).1 source (Nat.lt_succ_self _) next

theorem computation_relocation_commutes (relocation : UseScope.Relocation)
    (source : Source.Computation signature algebra program context result) :
    (computation source).relocate relocation = computation (source.relocate relocation) :=
  (compilation_relocation_bounded relocation (sizeOf source + 1)).2.2.1 source (Nat.lt_succ_self _)

theorem clauses_relocation_commutes (relocation : UseScope.Relocation)
    (source : Source.Clauses signature algebra program effect mode context body answer) :
    (clauses source).relocate relocation = clauses (source.relocate relocation) :=
  (compilation_relocation_bounded relocation (sizeOf source + 1)).2.2.2 source (Nat.lt_succ_self _)

end Defunctionalization
end BoundaryV2.Generalized
