import BoundaryV2.EffectsSelection

namespace BoundaryV2.Effects

open Core

mutual
  /-- Reference occurrences include dormant templates; repeated occurrences are
  aliases, not additional allocations. Ordinary number values are not IDs. -/
  def Frame.references : Frame A r a s b → List Nat
    | .bind _ _ capabilities => capabilities.toList
    | .delimiter identity _ _ => [identity]
    | .region | .post _ _ => []
    | .repeat template _ _ _ _ _ => template.references

  def Stack.references : Stack A r a s b → List Nat
    | .done => []
    | .push frame rest => frame.references ++ rest.references
end

theorem renaming_covers_dormant_references (rename : Nat → Nat) (stack : Stack A r a s b) :
    (stack.rename rename).references = stack.references.map rename := by
  induction stack using Stack.rec
    (motive_1 := fun _ _ _ _ frame => (frame.rename rename).references = frame.references.map rename) with
  | bind => simp [Frame.rename, Frame.references, Vector.toList_map]
  | delimiter | region | post | done => rfl
  | «repeat» template heap arguments acc fold env ih => exact ih
  | push frame rest ihFrame ihRest =>
    simp only [Stack.rename, Stack.references, List.map_append, ihFrame, ihRest]

theorem renameLocal_outside (ids : List Nat) (fresh identity : Nat) (outside : identity ∉ ids) :
    renameLocal ids fresh identity = identity := by simp [renameLocal, outside]

theorem renameLocal_interval (ids : List Nat) (fresh identity : Nat) (inside : identity ∈ ids) :
    fresh ≤ renameLocal ids fresh identity ∧ renameLocal ids fresh identity < fresh + ids.length := by
  have bound := List.idxOf_lt_length_of_mem inside
  simp only [renameLocal, if_pos inside]
  omega

theorem renameLocal_injective_on_binders (ids : List Nat) (fresh left right : Nat)
    (leftLocal : left ∈ ids) (rightLocal : right ∈ ids)
    (same : renameLocal ids fresh left = renameLocal ids fresh right) : left = right := by
  have indexEq : ids.idxOf left = ids.idxOf right := by
    simpa only [renameLocal, if_pos leftLocal, if_pos rightLocal, Nat.add_left_cancel_iff] using same
  have positions : (⟨ids.idxOf left, List.idxOf_lt_length_of_mem leftLocal⟩ : Fin ids.length) =
      ⟨ids.idxOf right, List.idxOf_lt_length_of_mem rightLocal⟩ := Fin.ext indexEq
  have values := congrArg (fun index : Fin ids.length => ids[index]) positions
  simpa using values

theorem activation_intervals_are_disjoint (template : Stack A r a s b) (fresh first second : Nat)
    (firstLocal : first ∈ template.attachments) (secondLocal : second ∈ template.attachments) :
    renameLocal template.attachments fresh first <
      renameLocal template.attachments (template.activate fresh).2 second := by
  have firstBound := renameLocal_interval template.attachments fresh first firstLocal
  have secondBound := renameLocal_interval template.attachments
    (fresh + template.attachments.length) second secondLocal
  simpa only [Stack.activate] using Nat.lt_of_lt_of_le firstBound.2 secondBound.1

theorem activation_preserves_outside_support (template : Stack A r a s b) (fresh identity : Nat)
    (outside : identity ∉ template.attachments) :
    renameLocal template.attachments fresh identity = identity :=
  renameLocal_outside _ _ _ outside

def Selected.rename (rename : Nat → Nat) (selected : Selected A r a s b) : Selected A r a s b :=
  ⟨selected.atRegion, selected.body, selected.answer, selected.ctx, rename selected.identity,
    selected.inside.rename rename, selected.handler, selected.env, selected.outsideStack.rename rename⟩

theorem selection_equivariant (rename : Nat → Nat) (requested : Nat) (stack : Stack A r a s b)
    (separated : ∀ active ∈ stack.attachments, rename requested = rename active ↔ requested = active) :
    select (rename requested) (stack.rename rename) = (select requested stack).map (Selected.rename rename) := by
  induction stack using Stack.spine_induction with
  | done => rfl
  | push frame rest ih =>
    cases frame with
    | delimiter actual handler env =>
      have head := separated actual (by simp [Stack.attachments])
      have tail : ∀ active ∈ rest.attachments, rename requested = rename active ↔ requested = active := by
        intro active member
        exact separated active (by simp [Stack.attachments, member])
      by_cases same : requested = actual
      · simp [select, Stack.rename, Frame.rename, same, Selected.rename]
      · have different : rename requested ≠ rename actual := fun equal => same (head.mp equal)
        simp [select, Stack.rename, Frame.rename, same, different, ih tail,
          Selected.rename, Selected.prepend, Option.map_map, Function.comp_def]
    | bind | region | post | «repeat» =>
      simp [select, Stack.rename, Frame.rename, ih separated,
        Selected.rename, Selected.prepend, Option.map_map, Function.comp_def]

theorem selection_commutes_with_actual_activation (template : Stack A r a s b)
    (fresh requested : Nat) (reserved : requested < fresh) :
    select (renameLocal template.attachments fresh requested) (template.activate fresh).1 =
      (select requested template).map (Selected.rename (renameLocal template.attachments fresh)) := by
  apply selection_equivariant
  intro active member
  constructor
  · intro equal
    by_cases requestedLocal : requested ∈ template.attachments
    · exact renameLocal_injective_on_binders _ _ _ _ requestedLocal member equal
    · have bound := renameLocal_interval template.attachments fresh active member
      rw [renameLocal_outside _ _ _ requestedLocal] at equal
      omega
  · intro equal
    rw [equal]

def nestedAliasTemplate (ownedId sharedId : Nat) : Stack Expr 0 .number 0 .number :=
  .push (.delimiter ownedId ⟨.ref .here, .dispose (.literal (.number 0))⟩ .nil)
    (.push (.repeat
      (.push (.bind (.perform 0 (.literal (.number 1))) .nil #[ownedId, sharedId].toVector) .done)
      .done [] (.number 0) (.ref .here) .nil) .done)

theorem activation_remaps_nested_alias_and_preserves_shared_identity :
    (nestedAliasTemplate 0 7).activate 10 = (nestedAliasTemplate 10 7, 11) := by
  simp [nestedAliasTemplate, Stack.activate, Stack.attachments, Stack.rename, Frame.rename, renameLocal]

end BoundaryV2.Effects
