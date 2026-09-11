import BoundaryV2.BorrowReachability

namespace BoundaryV2.FiniteReachability

structure EvaluationState (α : Type) where
  remaining : List α
  pending : List α
  found : List α
  deriving DecidableEq, Repr

def evaluationMeaning [DecidableEq α] (next : α → List α) (state : EvaluationState α) : List α :=
  state.found ++ gather next state.remaining state.pending

def advance [DecidableEq α] (next : α → List α) (state : EvaluationState α) : EvaluationState α :=
  match state.pending.find? state.remaining.contains with
  | none => state
  | some selected => ⟨state.remaining.erase selected, next selected ++ state.pending, state.found ++ [selected]⟩

theorem advance_preserves_meaning [DecidableEq α] (next : α → List α) (state : EvaluationState α) :
    evaluationMeaning next (advance next state) = evaluationMeaning next state := by
  unfold advance
  cases found : state.pending.find? state.remaining.contains with
  | none => rfl
  | some selected =>
    simp only [evaluationMeaning]
    conv => rhs; rw [gather, found]
    simp [List.append_assoc]

def advanceN [DecidableEq α] (next : α → List α) : Nat → EvaluationState α → EvaluationState α
  | 0, state => state
  | count + 1, state => advanceN next count (advance next state)

theorem advanceN_preserves_meaning [DecidableEq α] (next : α → List α) (count : Nat) (state : EvaluationState α) :
    evaluationMeaning next (advanceN next count state) = evaluationMeaning next state := by
  induction count generalizing state with
  | zero => rfl
  | succ count ih => exact (ih _).trans (advance_preserves_meaning next state)

theorem evaluation_of_chunk [DecidableEq α] (next : α → List α) (count : Nat)
    (before after : EvaluationState α) (result : List α)
    (chunk : advanceN next count before = after) (tail : evaluationMeaning next after = result) :
    evaluationMeaning next before = result := by
  rw [← advanceN_preserves_meaning next count before, chunk]
  exact tail

theorem evaluation_finished [DecidableEq α] (next : α → List α) (state : EvaluationState α)
    (finished : state.pending.find? state.remaining.contains = none) :
    evaluationMeaning next state = state.found := by
  unfold evaluationMeaning
  rw [gather, finished]
  exact List.append_nil _

end BoundaryV2.FiniteReachability

namespace BoundaryV2.Profile.Target.Borrow

theorem reachable_of_evaluation (program : Program) (start : BlockId)
    (state : FiniteReachability.EvaluationState BlockId) (found ordered : List BlockId)
    (initial : state = ⟨blockIds program, [start], []⟩)
    (checked : FiniteReachability.evaluationMeaning (successors program) state = found)
    (sorted : (blockIds program).filter found.contains = ordered) : reachable program start = ordered := by
  rw [reachable_forward]
  unfold reachableFast
  have gathered : FiniteReachability.gather (successors program) (blockIds program) [start] = found := by
    simpa only [initial, FiniteReachability.evaluationMeaning, List.nil_append] using checked
  rw [gathered]
  exact sorted

end BoundaryV2.Profile.Target.Borrow
