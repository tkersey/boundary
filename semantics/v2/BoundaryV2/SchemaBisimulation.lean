import BoundaryV2.SchemaEquivalence

namespace BoundaryV2.Profile.SchemaEquivalence

def Aligned (relation : α → β → Prop) (left : List α) (right : List β) : Prop :=
  left.length = right.length ∧ ∀ (index : Nat) a b,
    left[index]? = some a → right[index]? = some b → relation a b

def Step (types : List (Schema space)) (relation : SchemaId space → SchemaId space → Prop)
    (left right : SchemaId space) : Prop :=
  ∃ a b, types[left.value]? = some a ∧ types[right.value]? = some b ∧ label a = label b ∧
    Aligned relation (SchemaAdmission.structuralChildren a) (SchemaAdmission.structuralChildren b)

def Bisimulation (types : List (Schema space)) (relation : SchemaId space → SchemaId space → Prop) : Prop :=
  ∀ left right, relation left right → Step types relation left right

theorem mapChildren_children (rename : SchemaId space → SchemaId space) (shape : Schema space) :
    SchemaAdmission.structuralChildren (mapChildren rename shape) =
      (SchemaAdmission.structuralChildren shape).map rename := by
  cases shape <;> simp [mapChildren, SchemaAdmission.structuralChildren]

theorem label_equal_child_count (left right : Schema space) (same : label left = label right) :
    (SchemaAdmission.structuralChildren left).length = (SchemaAdmission.structuralChildren right).length := by
  have result := congrArg (fun shape => (SchemaAdmission.structuralChildren shape).length) same
  simpa only [label, mapChildren_children, List.length_map] using result

theorem allPairs_member (types : List (Schema space)) (left right : SchemaId space) :
    (left, right) ∈ allPairs types ↔ left.value < types.length ∧ right.value < types.length := by
  cases left
  cases right
  simp [allPairs, List.mem_flatMap]

theorem pairValid_exact (types : List (Schema space)) (pairs : List (Pair space)) (left right : SchemaId space) :
    pairValid types pairs (left, right) = true ↔ Step types (fun a b => (a, b) ∈ pairs) left right := by
  constructor
  · intro valid
    unfold pairValid at valid
    split at valid
    · rename_i a b foundA foundB
      simp only [Bool.and_eq_true, beq_iff_eq] at valid
      refine ⟨a, b, foundA, foundB, valid.1, label_equal_child_count a b valid.1, ?_⟩
      intro index x y foundX foundY
      have member : (x, y) ∈ (SchemaAdmission.structuralChildren a).zip (SchemaAdmission.structuralChildren b) :=
        List.mem_iff_getElem?.mpr ⟨index, List.getElem?_zip_eq_some.mpr ⟨foundX, foundY⟩⟩
      exact List.contains_iff_mem.mp (List.all_eq_true.mp valid.2 (x, y) member)
    · contradiction
  · rintro ⟨a, b, foundA, foundB, same, aligned⟩
    simp only [pairValid, foundA, foundB, same, beq_self_eq_true, Bool.true_and]
    apply List.all_eq_true.mpr
    intro pair member
    obtain ⟨index, found⟩ := List.mem_iff_getElem?.mp member
    have values := List.getElem?_zip_eq_some.mp found
    exact List.contains_iff_mem.mpr (aligned.2 index pair.1 pair.2 values.1 values.2)

theorem step_in_bounds (types : List (Schema space)) (relation : SchemaId space → SchemaId space → Prop)
    (left right : SchemaId space) (step : Step types relation left right) :
    left.value < types.length ∧ right.value < types.length := by
  obtain ⟨_, _, foundA, foundB, _⟩ := step
  exact ⟨(List.getElem?_eq_some_iff.mp foundA).1, (List.getElem?_eq_some_iff.mp foundB).1⟩

/-- Coinduction is justified by the finite pair-deletion implementation.
It assumes local shape/edge preservation, not the desired equivalence. -/
theorem coinduction (types : List (Schema space)) (relation : SchemaId space → SchemaId space → Prop)
    (closed : Bisimulation types relation) (left right : SchemaId space) (related : relation left right) :
    (left, right) ∈ bisimilar types := by
  classical
  let witness := (allPairs types).filter (fun pair => decide (relation pair.1 pair.2))
  have contained : ∀ a b, relation a b → (a, b) ∈ witness := by
    intro a b member
    exact List.mem_filter.mpr ⟨(allPairs_member types a b).mpr
      (step_in_bounds types relation a b (closed a b member)), by simpa using member⟩
  apply bisimilar_greatest types witness (fun _ member => (List.mem_filter.mp member).1) ?_ (contained left right related)
  intro pair member
  have related : relation pair.1 pair.2 := by simpa using (List.mem_filter.mp member).2
  obtain ⟨a, b, foundA, foundB, same, aligned⟩ := closed pair.1 pair.2 related
  apply (pairValid_exact types witness pair.1 pair.2).mpr
  refine ⟨a, b, foundA, foundB, same, aligned.1, ?_⟩
  intro index x y foundX foundY
  exact contained x y (aligned.2 index x y foundX foundY)

theorem bisimilar_is_bisimulation (types : List (Schema space)) :
    Bisimulation types (fun a b => (a, b) ∈ bisimilar types) := by
  intro a b member
  exact (pairValid_exact types _ a b).mp (bisimilar_closed types (a, b) member)

theorem bisimilar_symmetric (types : List (Schema space)) (left right : SchemaId space)
    (related : (left, right) ∈ bisimilar types) : (right, left) ∈ bisimilar types := by
  apply coinduction types (fun a b => (b, a) ∈ bisimilar types) ?_ right left related
  intro a b member
  obtain ⟨sa, sb, foundA, foundB, same, aligned⟩ := bisimilar_is_bisimulation types b a member
  refine ⟨sb, sa, foundB, foundA, same.symm, aligned.1.symm, ?_⟩
  intro index x y foundX foundY
  exact aligned.2 index y x foundY foundX

theorem bisimilar_transitive (types : List (Schema space)) (left middle right : SchemaId space)
    (first : (left, middle) ∈ bisimilar types) (second : (middle, right) ∈ bisimilar types) :
    (left, right) ∈ bisimilar types := by
  apply coinduction types (fun a c => ∃ b, (a, b) ∈ bisimilar types ∧ (b, c) ∈ bisimilar types) ?_
    left right ⟨middle, first, second⟩
  intro a c pair
  obtain ⟨b, ab, bc⟩ := pair
  obtain ⟨sa, sb, foundA, foundB, sameAB, alignedAB⟩ := bisimilar_is_bisimulation types a b ab
  obtain ⟨sb', sc, foundB', foundC, sameBC, alignedBC⟩ := bisimilar_is_bisimulation types b c bc
  have sameB : sb = sb' := Option.some.inj (foundB.symm.trans foundB')
  subst sb'
  refine ⟨sa, sc, foundA, foundC, sameAB.trans sameBC, alignedAB.1.trans alignedBC.1, ?_⟩
  intro index x z foundX foundZ
  have bound : index < (SchemaAdmission.structuralChildren sb).length := by
    have bounded := (List.getElem?_eq_some_iff.mp foundX).1
    rw [← alignedAB.1]
    exact bounded
  let y := (SchemaAdmission.structuralChildren sb)[index]'bound
  have foundY : (SchemaAdmission.structuralChildren sb)[index]? = some y := by simp [y]
  exact ⟨y, alignedAB.2 index x y foundX foundY, alignedBC.2 index y z foundY foundZ⟩

def BoundedChildren (types : List (Schema space)) : Prop :=
  ∀ shape ∈ types, ∀ child ∈ SchemaAdmission.structuralChildren shape, child.value < types.length

theorem valid_has_bounded_children (types : List (Schema space)) (valid : SchemaAdmission.valid types = true) :
    BoundedChildren types := by
  have checked : types.all (SchemaAdmission.referencesValid types) = true := by
    simp only [SchemaAdmission.valid, Bool.and_eq_true] at valid
    exact valid.1.2
  intro shape member child childMember
  have references := List.all_eq_true.mp checked shape member
  simp only [SchemaAdmission.referencesValid, Bool.and_eq_true] at references
  have included : child ∈ SchemaAdmission.references shape := by
    cases shape <;> simp_all [SchemaAdmission.structuralChildren, SchemaAdmission.references]
  simpa using List.all_eq_true.mp references.1 child included

theorem bisimilar_reflexive (types : List (Schema space)) (bounded : BoundedChildren types)
    (id : SchemaId space) (inBounds : id.value < types.length) : (id, id) ∈ bisimilar types := by
  apply coinduction types (fun a b => a = b ∧ a.value < types.length) ?_ id id ⟨rfl, inBounds⟩
  intro a b member
  rcases member with ⟨same, bound⟩
  subst b
  let shape := types[a.value]'bound
  have found : types[a.value]? = some shape := by simp [shape]
  refine ⟨shape, shape, found, found, rfl, rfl, ?_⟩
  intro index x y foundX foundY
  have same : x = y := Option.some.inj (foundX.symm.trans foundY)
  refine ⟨same, bounded shape (List.getElem_mem bound) x (List.mem_of_getElem? foundX)⟩

end BoundaryV2.Profile.SchemaEquivalence
