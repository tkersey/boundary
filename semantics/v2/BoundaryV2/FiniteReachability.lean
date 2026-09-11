import Std

namespace BoundaryV2.FiniteReachability

/-- A finite path stays in the supplied domain and begins at one of the seeds.
Cycles without a seed cannot introduce a reachable node. -/
inductive ReachIn (next : α → List α) (domain seeds : List α) : α → Prop where
  | root : value ∈ domain → value ∈ seeds → ReachIn next domain seeds value
  | edge : ReachIn next domain seeds parent → value ∈ domain → value ∈ next parent →
      ReachIn next domain seeds value

theorem ReachIn.inside (reached : ReachIn next domain seeds value) : value ∈ domain := by
  cases reached with
  | root member _ => exact member
  | edge _ member _ => exact member

/-- Each recursive call removes a discovered node from the finite domain.
Repeated edges and cycles do not consume an execution-fuel allowance. -/
def gather [DecidableEq α] (next : α → List α) (remaining pending : List α) : List α :=
  match _found : pending.find? remaining.contains with
  | none => []
  | some selected => selected :: gather next (remaining.erase selected) (next selected ++ pending)
termination_by remaining.length
decreasing_by
  have member : selected ∈ remaining := List.contains_iff_mem.mp (List.find?_some _found)
  have smaller := List.length_erase_of_mem member
  have positive := List.length_pos_of_mem member
  omega

private theorem expand_reach [DecidableEq α] (next : α → List α) (domain seeds : List α)
    (selected : α) (inside : selected ∈ domain) (seed : selected ∈ seeds)
    (reached : ReachIn next (domain.erase selected) (next selected ++ seeds) value) :
    ReachIn next domain seeds value := by
  induction reached with
  | root member source =>
    have member := List.mem_of_mem_erase member
    rcases List.mem_append.mp source with child | original
    · exact .edge (.root inside seed) member child
    · exact .root member original
  | edge _ member child ih => exact .edge ih (List.mem_of_mem_erase member) child

private theorem remove_reach [DecidableEq α] (next : α → List α) (domain seeds : List α)
    (selected : α) (reached : ReachIn next domain seeds value) (different : value ≠ selected) :
    ReachIn next (domain.erase selected) (next selected ++ seeds) value := by
  induction reached with
  | root member seed =>
    exact .root ((List.mem_erase_of_ne different).mpr member) (List.mem_append_right _ seed)
  | @edge parent value _ member child ih =>
    have member : value ∈ domain.erase selected := (List.mem_erase_of_ne different).mpr member
    by_cases same : parent = selected
    · subst parent
      exact .root member (List.mem_append_left _ child)
    · exact .edge (ih same) member child

theorem gather_exact [DecidableEq α] (next : α → List α) (remaining pending : List α) (value : α) :
    value ∈ gather next remaining pending ↔ ReachIn next remaining pending value := by
  fun_induction gather next remaining pending with
  | case1 remaining pending found =>
    constructor
    · simp
    · intro reached
      have noRoot : ∀ candidate ∈ pending, candidate ∉ remaining := by
        intro candidate member
        simpa using List.find?_eq_none.mp found candidate member
      induction reached with
      | root inside seed => exact False.elim (noRoot _ seed inside)
      | edge _ _ _ ih => cases ih
  | case2 remaining pending selected found ih =>
    have inside : selected ∈ remaining := List.contains_iff_mem.mp (List.find?_some found)
    have seed : selected ∈ pending := List.mem_of_find?_eq_some found
    constructor
    · intro member
      rcases List.mem_cons.mp member with equal | rest
      · subst value; exact .root inside seed
      · exact expand_reach next remaining pending selected inside seed (ih.mp rest)
    · intro reached
      by_cases same : value = selected
      · exact List.mem_cons.mpr (.inl same)
      · exact List.mem_cons.mpr (.inr (ih.mpr (remove_reach next remaining pending selected reached same)))

theorem gather_in_domain [DecidableEq α] (next : α → List α) (remaining pending : List α)
    (member : value ∈ gather next remaining pending) : value ∈ remaining :=
  ((gather_exact next remaining pending value).mp member).inside

end BoundaryV2.FiniteReachability
