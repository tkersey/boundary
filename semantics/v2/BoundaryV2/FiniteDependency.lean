import Std

namespace BoundaryV2.FiniteDependency

/-- A dependency has a finite path to a directly exposed property. A cycle
without an exposure is not evidence of an effect or lexical-region dependency. -/
inductive Depends (direct : α → Bool) (children : α → List α) : α → Prop where
  | here : direct value = true → Depends direct children value
  | through : child ∈ children value → Depends direct children child → Depends direct children value

def supported [BEq α] (direct : α → Bool) (children : α → List α) (safe : List α) (value : α) : Bool :=
  !direct value && (children value).all safe.contains

def prune [BEq α] (direct : α → Bool) (children : α → List α) (safe : List α) : List α :=
  safe.filter (supported direct children safe)

private theorem prune_decreases [BEq α] (direct : α → Bool) (children : α → List α) (safe : List α)
    (changed : prune direct children safe ≠ safe) : (prune direct children safe).length < safe.length := by
  have le := List.length_filter_le (supported direct children safe) safe
  have ne : (prune direct children safe).length ≠ safe.length := by
    intro equal
    exact changed (List.filter_eq_self.mpr (List.length_filter_eq_length_iff.mp equal))
  change (prune direct children safe).length ≤ safe.length at le
  omega

/-- Delete exposed nodes and their dependents until stable. The finite candidate
set shrinks strictly; neither execution nor recursive schemas are fuel-limited. -/
def refine [DecidableEq α] (direct : α → Bool) (children : α → List α) (safe : List α) : List α :=
  if _unchanged : prune direct children safe = safe then safe
  else refine direct children (prune direct children safe)
termination_by safe.length
decreasing_by exact prune_decreases direct children safe _unchanged

theorem refine_stable [DecidableEq α] (direct : α → Bool) (children : α → List α) (safe : List α) :
    prune direct children (refine direct children safe) = refine direct children safe := by
  fun_induction refine direct children safe with
  | case1 safe unchanged => exact unchanged
  | case2 safe changed ih => exact ih

theorem refine_subset [DecidableEq α] (direct : α → Bool) (children : α → List α) (safe : List α) :
    refine direct children safe ⊆ safe := by
  fun_induction refine direct children safe with
  | case1 safe unchanged => exact List.Subset.refl _
  | case2 safe changed ih =>
    intro value member
    exact (List.mem_filter.mp (ih member)).1

theorem refine_closed [DecidableEq α] (direct : α → Bool) (children : α → List α) (safe : List α) :
    ∀ value ∈ refine direct children safe,
      direct value = false ∧ ∀ child ∈ children value, child ∈ refine direct children safe := by
  have closed := List.filter_eq_self.mp (refine_stable direct children safe)
  simpa [supported, Bool.and_eq_true, List.all_eq_true] using closed

private theorem supported_monotone [DecidableEq α] (direct : α → Bool) (children : α → List α)
    (small large : List α) (included : small ⊆ large) (value : α)
    (accepted : supported direct children small value = true) :
    supported direct children large value = true := by
  simp only [supported, Bool.and_eq_true] at accepted ⊢
  refine ⟨accepted.1, List.all_eq_true.mpr ?_⟩
  intro child member
  exact List.contains_iff_mem.mpr (included (List.contains_iff_mem.mp (List.all_eq_true.mp accepted.2 child member)))

theorem refine_greatest [DecidableEq α] (direct : α → Bool) (children : α → List α)
    (safe closed : List α) (included : closed ⊆ safe)
    (supported : ∀ value ∈ closed, supported direct children closed value = true) :
    closed ⊆ refine direct children safe := by
  fun_induction refine direct children safe with
  | case1 safe unchanged => exact included
  | case2 safe changed ih =>
    apply ih
    intro value member
    exact List.mem_filter.mpr ⟨included member,
      supported_monotone direct children closed safe included value (supported value member)⟩

theorem refine_excludes_dependencies [DecidableEq α] (direct : α → Bool) (children : α → List α)
    (safe : List α) (value : α) (dependent : Depends direct children value) :
    value ∉ refine direct children safe := by
  induction dependent with
  | here exposed =>
    intro member
    have absent := (refine_closed direct children safe _ member).1
    simp [exposed] at absent
  | through member _ ih =>
    intro root
    exact ih ((refine_closed direct children safe _ root).2 _ member)

/-- Exactness needs a catalog containing every child of its members. The
catalog is supplied by the finite catalog, not by a certificate's claimed facts. -/
theorem refine_exact [DecidableEq α] (direct : α → Bool) (children : α → List α)
    (catalog : List α) (bounded : ∀ value ∈ catalog, ∀ child ∈ children value, child ∈ catalog)
    (value : α) (inside : value ∈ catalog) :
    value ∈ refine direct children catalog ↔ ¬ Depends direct children value := by
  constructor
  · intro member dependency
    exact refine_excludes_dependencies direct children catalog value dependency member
  · intro absent
    classical
    let closed := catalog.filter (fun value => decide (¬ Depends direct children value))
    have included : closed ⊆ catalog := fun _ member => (List.mem_filter.mp member).1
    have supports : ∀ value ∈ closed, supported direct children closed value = true := by
      intro root member
      have notDependent : ¬ Depends direct children root := by simpa [closed] using (List.mem_filter.mp member).2
      simp only [supported, Bool.and_eq_true, Bool.not_eq_true']
      refine ⟨?_, List.all_eq_true.mpr ?_⟩
      · cases exposed : direct root
        · rfl
        · exact False.elim (notDependent (.here exposed))
      · intro child edge
        apply List.contains_iff_mem.mpr
        apply List.mem_filter.mpr
        refine ⟨bounded root (included member) child edge, ?_⟩
        simpa using (show ¬ Depends direct children child from fun dependency => notDependent (.through edge dependency))
    exact refine_greatest direct children catalog closed included supports
      (List.mem_filter.mpr ⟨inside, by simpa using absent⟩)

end BoundaryV2.FiniteDependency
