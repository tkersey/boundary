import BoundaryV2.ProgramCanonical

namespace BoundaryV2.Profile.Target.Canonical

inductive EvaluationState where
  | pending (remaining waiting order : List Reference)
  | finished (result : Option (List Reference))
  deriving DecidableEq, Repr

def evaluationMeaning (program : Program) : EvaluationState → Option (List Reference)
  | .pending remaining waiting order => walk program remaining waiting order
  | .finished result => result

def advance (program : Program) : EvaluationState → EvaluationState
  | .finished result => .finished result
  | .pending _ [] order => .finished (some order)
  | .pending remaining (reference :: tail) order =>
    match nodeReferences program reference with
    | none => .finished none
    | some children =>
      if reference.kind == .region then
        .pending remaining tail (if order.contains reference then order else order ++ [reference])
      else if reference ∈ remaining then
        if interned program order reference then
          .pending (remaining.erase reference) tail order
        else .pending (remaining.erase reference) (children ++ tail) (order ++ [reference])
      else .pending remaining tail order

theorem advance_preserves_meaning (program : Program) (state : EvaluationState) :
    evaluationMeaning program (advance program state) = evaluationMeaning program state := by
  cases state with
  | finished result => rfl
  | pending remaining waiting order =>
    cases waiting with
    | nil => simp [advance, evaluationMeaning, walk]
    | cons reference tail =>
      simp only [advance, evaluationMeaning]
      rw [walk]
      cases found : nodeReferences program reference with
      | none => rfl
      | some children =>
        by_cases region : reference.kind == .region <;>
          by_cases fresh : reference ∈ remaining <;>
          by_cases duplicate : interned program order reference <;>
          simp [region, fresh, duplicate]

def advanceN (program : Program) : Nat → EvaluationState → EvaluationState
  | 0, state => state
  | count + 1, state => advanceN program count (advance program state)

theorem advanceN_preserves_meaning (program : Program) (count : Nat) (state : EvaluationState) :
    evaluationMeaning program (advanceN program count state) = evaluationMeaning program state := by
  induction count generalizing state with
  | zero => rfl
  | succ count ih => exact (ih _).trans (advance_preserves_meaning program state)

theorem evaluation_of_chunk (program : Program) (count : Nat) (before after : EvaluationState)
    (result : Option (List Reference)) (chunk : advanceN program count before = after)
    (tail : evaluationMeaning program after = result) : evaluationMeaning program before = result := by
  rw [← advanceN_preserves_meaning program count before, chunk]
  exact tail

theorem discover_of_evaluation (program : Program) (state : EvaluationState) (order : List Reference)
    (initial : state = .pending (catalogReferences program) (rootReferences program.roots) [])
    (checked : evaluationMeaning program state = some order) : discover program = some order := by
  simpa only [initial, evaluationMeaning, discover] using checked

end BoundaryV2.Profile.Target.Canonical
