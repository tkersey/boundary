import BoundaryV2.SchemaDescriptor

namespace BoundaryV2.Profile.SchemaDescriptor

open SchemaEquivalence

theorem classes_related (types : List (Schema .target)) (bounded : BoundedChildren types)
    (id : SchemaId .target) (inBounds : id.value < types.length) :
    (classes types id).value < types.length ∧ (id, classes types id) ∈ bisimilar types := by
  have reflexive := bisimilar_reflexive types bounded id inBounds
  cases found : (List.range types.length).find? (fun index => (bisimilar types).contains (id, ⟨index⟩)) with
  | none =>
    have missing := List.find?_eq_none.mp found id.value (List.mem_range.mpr inBounds)
    cases id
    simp [reflexive] at missing
  | some index =>
    have member := List.mem_of_find?_eq_some found
    have related := List.find?_some found
    simp only [classes, representative, found, Option.getD_some]
    exact ⟨List.mem_range.mp member, List.contains_iff_mem.mp related⟩

theorem classes_equal_of_bisimilar (types : List (Schema .target)) (left right : SchemaId .target)
    (related : (left, right) ∈ bisimilar types) : classes types left = classes types right := by
  have predicates : (fun index => (bisimilar types).contains (left, (⟨index⟩ : SchemaId .target))) =
      (fun index => (bisimilar types).contains (right, (⟨index⟩ : SchemaId .target))) := by
    funext index
    apply Bool.eq_iff_iff.mpr
    simp only [List.contains_iff_mem]
    exact ⟨fun h => bisimilar_transitive types right left ⟨index⟩ (bisimilar_symmetric types left right related) h,
      fun h => bisimilar_transitive types left right ⟨index⟩ related h⟩
  unfold classes representative
  rw [predicates]

theorem classes_equal_iff_bisimilar (types : List (Schema .target)) (bounded : BoundedChildren types)
    (left right : SchemaId .target) (leftBound : left.value < types.length) (rightBound : right.value < types.length) :
    classes types left = classes types right ↔ (left, right) ∈ bisimilar types := by
  constructor
  · intro same
    have leftRelated := (classes_related types bounded left leftBound).2
    have rightRelated := (classes_related types bounded right rightBound).2
    rw [← same] at rightRelated
    exact bisimilar_transitive types left (classes types left) right leftRelated
      (bisimilar_symmetric types right (classes types left) rightRelated)
  · exact classes_equal_of_bisimilar types left right

theorem classes_idempotent (types : List (Schema .target)) (bounded : BoundedChildren types)
    (id : SchemaId .target) (inBounds : id.value < types.length) :
    classes types (classes types id) = classes types id :=
  classes_equal_of_bisimilar types (classes types id) id
    (bisimilar_symmetric types id (classes types id) (classes_related types bounded id inBounds).2)

/-- Tags, scalar bounds, enumeration labels, ordered arity, and non-child
internal metadata must agree; child equality alone is insufficient. -/
theorem mapChildren_congr (left right : Schema .target)
    (renameLeft renameRight : SchemaId .target → SchemaId .target)
    (sameLabel : label left = label right)
    (sameChildren : (SchemaAdmission.structuralChildren left).map renameLeft =
      (SchemaAdmission.structuralChildren right).map renameRight) :
    mapChildren renameLeft left = mapChildren renameRight right := by
  cases left <;> cases right <;>
    simp_all [label, mapChildren, SchemaAdmission.structuralChildren]

private theorem mapped_equal_of_aligned (left right : List (SchemaId .target))
    (rename : SchemaId .target → SchemaId .target)
    (aligned : Aligned (fun a b => rename a = rename b) left right) :
    left.map rename = right.map rename := by
  apply List.ext_getElem
  · simpa using aligned.1
  · intro index leftBound rightBound
    simp only [List.length_map] at leftBound rightBound
    simp only [List.getElem_map]
    exact aligned.2 index left[index] right[index]
      (by simp) (by simp)

theorem representative_preserves_shape (types : List (Schema .target)) (bounded : BoundedChildren types)
    (id : SchemaId .target) (shape : Schema .target) (found : types[id.value]? = some shape) :
    ∃ representativeShape, types[(classes types id).value]? = some representativeShape ∧
      mapChildren (classes types) shape = mapChildren (classes types) representativeShape := by
  have related := (classes_related types bounded id (List.getElem?_eq_some_iff.mp found).1).2
  obtain ⟨original, representativeShape, originalFound, representativeFound, same, aligned⟩ :=
    bisimilar_is_bisimulation types id (classes types id) related
  have originalEq : original = shape := Option.some.inj (originalFound.symm.trans found)
  subst original
  refine ⟨representativeShape, representativeFound, mapChildren_congr shape representativeShape _ _ same ?_⟩
  apply mapped_equal_of_aligned
  refine ⟨aligned.1, ?_⟩
  intro index a b foundA foundB
  exact classes_equal_of_bisimilar types a b (aligned.2 index a b foundA foundB)

end BoundaryV2.Profile.SchemaDescriptor
