import BoundaryV2.SourceMachine
import Lean.Elab.Tactic.Cbv

namespace BoundaryV2.Profile.Source.UsageExamples
open Machine

/-- A captured addition closure is called once or twice. The unused syntax
retains the double-use fragment even when the function selects the single call. -/
private def context (use : Use) (twice : Bool) : Context := {
  source := {
    entry := 0, failure := 1
    schemas := [.u64, .unit, .internal (.computation {
      parameters := [0], result := 0, captureBound := [0], use := use })]
    constants := [⟨1, []⟩, ⟨0, [2, 0, 0, 0, 0, 0, 0, 0]⟩]
    effects := [], handlers := [], regionCount := 0
    variables := [0, 0, 2, 0]
    values := [
      ⟨1, .literal 0⟩, ⟨0, .variable 0⟩, ⟨0, .variable 1⟩,
      ⟨0, .primitive .integerAdd [1, 2] 0 [⟨.arithmeticOverflow, 0⟩]⟩,
      ⟨2, .lambda 1⟩, ⟨2, .variable 2⟩, ⟨0, .literal 1⟩]
    terms := [.value 3, .apply 5 [6], .value 4, .bind 3 1 1, .bind 2 2 3, .bind 2 2 1]
    functions := [
      { parameters := [0], result := 0, body := some (if twice then 4 else 5) },
      { parameters := [1], result := 0, body := some 0 }] }
  captures := {
    values := [[], [(0, 0)], [(1, 0)], [(0, 1), (1, 1)], [(0, 4)], [(2, 0)], []]
    terms := [[(0, 2), (1, 2)], [(2, 1)], [(0, 5)], [(2, 2)], [(0, 6)], [(0, 6)]]
    functions := [[], [(0, 3)]] }
  constants := [.scalar 1 0, .scalar 0 2] }

theorem affine_double_use_has_valid_types : (context .affine true).typingValid = true := by
  decide_cbv

theorem affine_double_use_rejected_before_execution :
    initial (context .affine true) [.scalar 0 40] = .error .custody := by
  cbv

theorem reusable_double_use_admitted :
    (initial (context .reusable true) [.scalar 0 40]).isOk = true := by
  cbv

theorem unused_double_use_fragment_does_not_execute :
    (initial (context .affine false) [.scalar 0 40]).isOk = true := by
  cbv

/-- Retain the closure while returning a scalar without calling it. -/
private def unused (use : Use) : Context :=
  let base := context use false
  { base with
    source := { base.source with
      terms := base.source.terms ++ [.value 6, .bind 2 2 6]
      functions := [
        { parameters := [0], result := 0, body := some 7 },
        { parameters := [1], result := 0, body := some 0 }] }
    captures := { base.captures with terms := base.captures.terms ++ [[], [(0, 6)]] } }

/-- The false branch either returns without consuming the closure or fails.
The condition is an admitted argument, so both branches remain possible. -/
private def conditional (abrupt : Bool) : Context :=
  let base := unused .linear
  { base with
    source := { base.source with
      schemas := base.source.schemas ++ [.boolean]
      variables := base.source.variables ++ [3]
      values := base.source.values ++ [⟨3, .variable 4⟩]
      terms := base.source.terms.take 6 ++ [
        (if abrupt then .fail 0 else .value 6), .conditional 7 1 6, .bind 2 2 7]
      functions := [
        { parameters := [0, 4], result := 0, body := some 8 },
        { parameters := [1], result := 0, body := some 0 }] }
    captures := { base.captures with
      values := base.captures.values ++ [[(4, 0)]]
      terms := base.captures.terms.take 6 ++ [[], [(2, 2), (4, 1)], [(0, 6), (4, 2)]] } }

theorem unused_linear_closure_rejected :
    initial (unused .linear) [.scalar 0 40] = .error .custody := by cbv

theorem unused_affine_closure_admitted :
    (initial (unused .affine) [.scalar 0 40]).isOk = true := by cbv

theorem linear_closure_consumed_once_admitted :
    (initial (context .linear false) [.scalar 0 40]).isOk = true := by cbv

theorem consumption_in_only_one_normal_branch_rejected :
    initial (conditional false) [.scalar 0 40, .scalar 3 0] = .error .custody := by cbv

theorem failure_branch_preserves_unwind_admission :
    (initial (conditional true) [.scalar 0 40, .scalar 3 0]).isOk = true := by cbv

end BoundaryV2.Profile.Source.UsageExamples
