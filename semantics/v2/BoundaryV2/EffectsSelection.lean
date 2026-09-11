import BoundaryV2.Effects

namespace BoundaryV2.Effects

theorem Stack.append_done (stack : Stack A r a s b) : stack.append .done = stack := by
  induction stack using Stack.spine_induction with
  | done => rfl
  | push frame rest ih => exact congrArg (Stack.push frame) ih

theorem Stack.append_associative (first : Stack A r a s b) (second : Stack A s b t c)
    (third : Stack A t c u d) :
    (first.append second).append third = first.append (second.append third) := by
  induction first using Stack.spine_induction with
  | done => rfl
  | push frame rest ih => exact congrArg (Stack.push frame) (ih second)

def Selected.whole (selected : Selected A r a s b) : Stack A r a s b :=
  selected.inside.append
    (.push (.delimiter selected.identity selected.handler selected.env) selected.outsideStack)

theorem selection_reconstructs_effectful_stack (stack : Stack A r a s b) (identity : Nat)
    (selected : Selected A r a s b) (found : select identity stack = some selected) :
    selected.whole = stack := by
  induction stack using Stack.spine_induction with
  | done => simp [select] at found
  | push frame rest ih =>
    cases frame with
    | delimiter actual handler env =>
      simp only [select] at found
      split at found
      next same => cases found; rfl
      next different =>
        simp only [Option.map_eq_some_iff] at found
        obtain ⟨inner, found, rfl⟩ := found
        exact congrArg (Stack.push (.delimiter actual handler env)) (ih inner found)
    | bind | region | post | «repeat» =>
      simp only [select, Option.map_eq_some_iff] at found
      obtain ⟨inner, found, rfl⟩ := found
      exact congrArg (Stack.push _) (ih inner found)

theorem selection_uses_requested_attachment (stack : Stack A r a s b) (identity : Nat)
    (selected : Selected A r a s b) (found : select identity stack = some selected) :
    selected.identity = identity := by
  induction stack using Stack.spine_induction with
  | done => simp [select] at found
  | push frame rest ih =>
    cases frame with
    | delimiter actual handler env =>
      simp only [select] at found
      split at found
      next same => cases found; exact same.symm
      next different =>
        simp only [Option.map_eq_some_iff] at found
        obtain ⟨inner, found, rfl⟩ := found
        exact ih inner found
    | bind | region | post | «repeat» =>
      simp only [select, Option.map_eq_some_iff] at found
      obtain ⟨inner, found, rfl⟩ := found
      exact ih inner found

theorem selection_is_first_matching_attachment (stack : Stack A r a s b) (identity : Nat)
    (selected : Selected A r a s b) (found : select identity stack = some selected) :
    identity ∉ selected.inside.attachments := by
  induction stack using Stack.spine_induction with
  | done => simp [select] at found
  | push frame rest ih =>
    cases frame with
    | delimiter actual handler env =>
      simp only [select] at found
      split at found
      next same => cases found; simp [Stack.attachments]
      next different =>
        simp only [Option.map_eq_some_iff] at found
        obtain ⟨inner, found, rfl⟩ := found
        simpa only [Selected.prepend, Stack.attachments, List.mem_cons, not_or] using
          And.intro different (ih inner found)
    | bind | region | post | «repeat» =>
      simp only [select, Option.map_eq_some_iff] at found
      obtain ⟨inner, found, rfl⟩ := found
      exact ih inner found

theorem selection_absent_iff_no_matching_active_delimiter (stack : Stack A r a s b)
    (identity : Nat) : select identity stack = none ↔ identity ∉ stack.attachments := by
  induction stack using Stack.spine_induction with
  | done => simp [select, Stack.attachments]
  | push frame rest ih =>
    cases frame with
    | delimiter actual handler env =>
      by_cases same : identity = actual <;> simp [select, Stack.attachments, same, ih]
    | bind | region | post | «repeat» => simp [select, Stack.attachments, ih]

end BoundaryV2.Effects
