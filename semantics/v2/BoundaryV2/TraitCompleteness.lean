import BoundaryV2.Traits

namespace BoundaryV2.Profile.Traits

private def rounds (schemas : List (Schema space)) (root : Atom space) (count : Nat) : List (Atom space) :=
  Nat.rec [root] (fun _ previous => expand schemas previous) count

private theorem dedup_nodup [BEq α] [LawfulBEq α] (values : List α) : values.eraseDups.Nodup := by
  cases values with
  | nil => simp
  | cons head tail =>
    rw [List.eraseDups_cons, List.nodup_cons]
    refine ⟨?_, dedup_nodup (tail.filter (fun value => !value == head))⟩
    simp [List.mem_eraseDups]
termination_by values.length
decreasing_by simpa using Nat.lt_succ_of_le (List.length_filter_le (fun value => !value == head) tail)

private theorem expand_contains (schemas : List (Schema space)) (items : List (Atom space)) :
    items ⊆ expand schemas items := by
  intro atom member
  simpa [expand] using Or.inl member

private theorem expand_reachable (schemas : List (Schema space)) (root : Atom space) (items : List (Atom space))
    (reached : ∀ atom ∈ items, Reach schemas root atom) :
    ∀ atom ∈ expand schemas items, Reach schemas root atom := by
  intro atom member
  simp only [expand, List.mem_eraseDups, List.mem_append, List.mem_flatMap] at member
  rcases member with original | ⟨parent, parentMember, childMember⟩
  · exact reached atom original
  · cases found : rule schemas parent with
    | none => simp [found] at childMember
    | some children =>
      exact .step (reached parent parentMember) found (by simpa [found] using childMember)

private theorem rounds_reachable (schemas : List (Schema space)) (root : Atom space) (count : Nat) :
    ∀ atom ∈ rounds schemas root count, Reach schemas root atom := by
  induction count with
  | zero =>
    intro atom member
    change atom ∈ [root] at member
    simp only [List.mem_singleton] at member
    subst atom
    exact .refl
  | succ count induction => exact expand_reachable schemas root _ induction

private theorem rounds_nodup (schemas : List (Schema space)) (root : Atom space) (count : Nat) :
    (rounds schemas root count).Nodup := by
  cases count with
  | zero => change [root].Nodup; simp
  | succ count => exact dedup_nodup _

private theorem closed_expand (schemas : List (Schema space)) (items : List (Atom space))
    (checked : closed schemas items = true) : closed schemas (expand schemas items) = true := by
  have back : expand schemas items ⊆ items := by
    intro atom member
    simp only [expand, List.mem_eraseDups, List.mem_append, List.mem_flatMap] at member
    rcases member with original | ⟨parent, parentMember, childMember⟩
    · exact original
    · obtain ⟨children, found, childrenIn⟩ := closed_member schemas items checked parentMember
      exact childrenIn atom (by simpa [found] using childMember)
  apply List.all_eq_true.mpr
  intro atom member
  obtain ⟨children, found, childrenIn⟩ := closed_member schemas items checked (back member)
  simp only [found, List.all_eq_true, List.contains_iff_mem]
  exact fun child childMember => expand_contains schemas items (childrenIn child childMember)

private theorem expand_grows (schemas : List (Schema space)) (items : List (Atom space))
    (distinct : items.Nodup) (rules : ∀ atom ∈ items, ∃ children, rule schemas atom = some children)
    (notClosed : closed schemas items ≠ true) : items.length + 1 ≤ (expand schemas items).length := by
  have missing : ∃ atom, atom ∈ expand schemas items ∧ atom ∉ items := by
    apply Classical.byContradiction
    intro absent
    apply notClosed
    apply List.all_eq_true.mpr
    intro atom member
    obtain ⟨children, found⟩ := rules atom member
    simp only [found, List.all_eq_true, List.contains_iff_mem]
    intro child childMember
    have expanded : child ∈ expand schemas items := by
      simp only [expand, List.mem_eraseDups, List.mem_append, List.mem_flatMap]
      exact Or.inr ⟨atom, member, by simpa [found] using childMember⟩
    grind only []
  obtain ⟨atom, member, outside⟩ := missing
  have bigger : (atom :: items).Nodup := List.nodup_cons.mpr ⟨outside, distinct⟩
  apply bigger.length_le_of_subset
  intro child childMember
  rcases List.mem_cons.mp childMember with rfl | childMember
  · exact member
  · exact expand_contains schemas items childMember

private def atoms (schemas : List (Schema space)) : List (Atom space) :=
  (List.range schemas.length).flatMap fun index =>
    [(⟨index⟩, .copy), (⟨index⟩, .drop), (⟨index⟩, .clone), (⟨index⟩, .external)]

private theorem atoms_length (schemas : List (Schema space)) : (atoms schemas).length = 4 * schemas.length := by
  simp [atoms, List.length_flatMap, List.map_const', List.sum_replicate_nat, Nat.mul_comm]

private theorem safe_in_atoms (schemas : List (Schema space)) (root atom : Atom space)
    (safe : Safe schemas root) (reached : Reach schemas root atom) : atom ∈ atoms schemas := by
  obtain ⟨children, available⟩ := safe atom reached
  have bound : atom.1.value < schemas.length := by
    unfold rule at available
    cases found : schemas[atom.1.value]? with
    | none => simp [found] at available
    | some shape => exact (List.getElem?_eq_some_iff.mp found).choose
  apply List.mem_flatMap.mpr
  refine ⟨atom.1.value, List.mem_range.mpr bound, ?_⟩
  rcases atom with ⟨⟨index⟩, kind⟩
  cases kind <;> simp

/-- Every safe trait closes within the existing four-atoms-per-schema search
bound. Recursive schemas share atoms; this bound never limits execution. -/
theorem check_complete (schemas : List (Schema space)) (kind : Kind) (type : SchemaId space)
    (safe : Safe schemas (type, kind)) : check schemas kind type = true := by
  have growth (count : Nat) : closed schemas (rounds schemas (type, kind) count) = true ∨
      count + 1 ≤ (rounds schemas (type, kind) count).length := by
    induction count with
    | zero => exact Or.inr (by change 0 + 1 ≤ [(type, kind)].length; simp)
    | succ count induction =>
      rcases induction with checked | growing
      · exact Or.inl (closed_expand schemas _ checked)
      · by_cases checked : closed schemas (rounds schemas (type, kind) count) = true
        · exact Or.inl (closed_expand schemas _ checked)
        · have increased := expand_grows schemas _ (rounds_nodup schemas _ count)
            (fun atom member => safe atom (rounds_reachable schemas _ count atom member)) checked
          exact Or.inr (by simpa only [rounds] using Nat.le_trans (Nat.add_le_add_right growing 1) increased)
  have bounded : (rounds schemas (type, kind) (4 * schemas.length)).length ≤ 4 * schemas.length := by
    rw [← atoms_length schemas]
    apply (rounds_nodup schemas _ _).length_le_of_subset
    intro atom member
    exact safe_in_atoms schemas _ atom safe (rounds_reachable schemas _ _ atom member)
  have checked : closed schemas (rounds schemas (type, kind) (4 * schemas.length)) = true := by
    rcases growth (4 * schemas.length) with checked | tooLarge
    · exact checked
    · omega
  have rootIncluded (count : Nat) : (type, kind) ∈ rounds schemas (type, kind) count := by
    induction count with
    | zero => change (type, kind) ∈ [(type, kind)]; simp
    | succ count induction => exact expand_contains schemas _ induction
  simp only [check, checkSupport, support_preserves_bounded_search]
  exact Bool.and_eq_true_iff.mpr ⟨by simpa [rounds] using rootIncluded (4 * schemas.length), checked⟩

end BoundaryV2.Profile.Traits
