import Std

namespace BoundaryV2.EarlierRows

theorem getD_true (value : Option Bool) : value.getD false = true ↔ value = some true := by
  cases value <;> simp

/-- A finite declaration scan. A true row requires both its local obligation
and every syntactic child; a forward or missing child is rejected. This count
is the input declaration count, never a bound on program execution. -/
def compute (localCheck : Nat → Bool) (children : Nat → List Nat) : Nat → List Bool
  | 0 => []
  | count + 1 =>
    let earlier := compute localCheck children count
    earlier ++ [localCheck count && (children count).all (fun child => earlier[child]?.getD false)]

theorem length (localCheck : Nat → Bool) (children : Nat → List Nat) (count : Nat) :
    (compute localCheck children count).length = count := by
  induction count with
  | zero => rfl
  | succ count ih => simp [compute, ih]

theorem row (localCheck : Nat → Bool) (children : Nat → List Nat) (count index : Nat)
    (inside : index < count) :
    (compute localCheck children count)[index]? = some (localCheck index &&
      (children index).all (fun child => (compute localCheck children index)[child]?.getD false)) := by
  induction count with
  | zero => omega
  | succ count ih =>
    by_cases earlier : index < count
    · simpa [compute, List.getElem?_append, length, earlier] using ih earlier
    · have last : index = count := by omega
      subst index
      simp [compute, length]

theorem lookup_stable (localCheck : Nat → Bool) (children : Nat → List Nat)
    (left right index : Nat) (inLeft : index < left) (inRight : index < right) :
    (compute localCheck children left)[index]? = (compute localCheck children right)[index]? := by
  rw [row _ _ _ _ inLeft, row _ _ _ _ inRight]

theorem accepted_row (localCheck : Nat → Bool) (children : Nat → List Nat)
    (count index : Nat) (accepted : (compute localCheck children count)[index]? = some true) :
    localCheck index = true ∧ ∀ child ∈ children index,
      child < index ∧ (compute localCheck children count)[child]? = some true := by
  have inside : index < count := by
    simpa [length] using (List.getElem?_eq_some_iff.mp accepted).1
  rw [row _ _ _ _ inside] at accepted
  simp only [Option.some.injEq, Bool.and_eq_true, List.all_eq_true] at accepted
  refine ⟨accepted.1, ?_⟩
  intro child member
  have prior := accepted.2 child member
  cases found : (compute localCheck children index)[child]? with
  | none => simp [found] at prior
  | some result =>
    have equal : result = true := by simpa [found] using prior
    subst result
    have before : child < index := by
      simpa [length] using (List.getElem?_eq_some_iff.mp found).1
    refine ⟨before, ?_⟩
    rw [← lookup_stable localCheck children index count child before (by omega)]
    exact found

inductive Reach (children : Nat → List Nat) (root : Nat) : Nat → Prop where
  | root : Reach children root root
  | child : Reach children root parent → node ∈ children parent → Reach children root node

theorem descendants_checked (localCheck : Nat → Bool) (children : Nat → List Nat)
    (count root : Nat) (accepted : (compute localCheck children count)[root]? = some true)
    (reachable : Reach children root node) : localCheck node = true := by
  have reached : (compute localCheck children count)[node]? = some true := by
    induction reachable with
    | root => exact accepted
    | child _ member ih => exact (accepted_row localCheck children count _ ih).2 _ member |>.2
  exact (accepted_row localCheck children count node reached).1

end BoundaryV2.EarlierRows
