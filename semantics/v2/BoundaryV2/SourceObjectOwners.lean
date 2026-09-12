import BoundaryV2.SourceCellIdentityExecution
import BoundaryV2.SourceCloneSupport

namespace BoundaryV2.Profile.Source.Machine
namespace ObjectOwners

/-- Closure captures and exclusive wrappers name their actual physical object
and field offset. Mutable cells have a separate identity and copy contract. -/
def Layout (node : NodeId) : Object → Prop
  | .closure _ _ bindings => ∀ (index : Nat) (binding : Binding), bindings[index]? = some binding →
      binding.located.owner = .closure node index
  | .package _ content | .resource _ content => content.owner = .closure node 0
  | _ => True

def Valid (heap : Heap) : Prop := ∀ node stored, heap.lookup node = some stored → Layout node stored

private theorem ref_eq {left right : Ref space domain} (same : left.value = right.value) : left = right := by
  cases left; cases right
  simpa only [Ref.mk.injEq] using same

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem rename_layout (mapping : Renaming) (node : NodeId) (stored : Object)
    (formed : Layout node stored) : Layout (renamed mapping.nodes node) (renameObject mapping stored) := by
  cases stored <;> simp only [Layout, renameObject] at formed ⊢ <;> try trivial
  case closure schema function bindings =>
    intro index binding found
    simp only [renameEnvironment, List.getElem?_map] at found
    obtain ⟨original, originalAt, rfl⟩ := Option.map_eq_some_iff.mp found
    change renameOwner mapping original.located.owner = .closure (renamed mapping.nodes node) index
    rw [formed index original originalAt]
    rfl
  all_goals simp only [renameLocated, renameOwner, formed]

theorem frozen_layout (node : NodeId) (stored : Object) (saved : Capture) (dormant : List Capture)
    (formed : Layout node stored) : Layout node (frozenObject saved dormant node stored) := by
  cases stored <;> exact formed

theorem append_valid (heap : Heap) (stored : Object) (formed : Valid heap)
    (added : Layout ⟨heap.objects.length⟩ stored) :
    Valid {heap with objects := heap.objects ++ [some stored]} := by
  intro node actual found
  by_cases old : node.value < heap.objects.length
  · exact formed node actual (by simpa only [Heap.lookup, List.getElem?_append_left old] using found)
  · have high := Nat.le_of_not_gt old
    simp only [Heap.lookup, List.getElem?_append_right high] at found
    cases difference : node.value - heap.objects.length with
    | zero =>
      have same : node = ⟨heap.objects.length⟩ := ref_eq (by simp only; omega)
      subst node
      simp only [Nat.sub_self, List.getElem?_cons_zero, Option.bind_some] at found
      cases found
      exact added
    | succ index => simp [difference] at found

theorem set_valid (heap : Heap) (node : NodeId) (replacement : Option Object)
    (bounded : node.value < heap.objects.length) (formed : Valid heap)
    (added : ∀ stored, replacement = some stored → Layout node stored) :
    Valid {heap with objects := heap.objects.set node.value replacement} := by
  intro other stored found
  by_cases equal : node.value = other.value
  · have same : other = node := ref_eq equal.symm
    subst other
    simp only [Heap.lookup, List.getElem?_set_self bounded, Option.bind_some] at found
    exact added stored found
  · exact formed other stored (by simpa only [Heap.lookup, List.getElem?_set_ne equal] using found)

theorem allocation_valid (heap after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (result : Located)
    (accepted : allocateObject heap schema stored owner exclusive = some (after, result))
    (formed : Valid heap) (added : Layout ⟨heap.objects.length⟩ stored) : Valid after := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    exact append_valid heap stored formed added
  · obtain ⟨_, _, rfl, _⟩ := accepted
    exact append_valid heap stored formed added

theorem move_objects (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) : after.objects = before.objects := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  rfl

theorem consume_objects (before after : Heap) (value : Located)
    (accepted : consumeValue before value = some after) : after.objects = before.objects := by
  simp [consumeValue, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  rfl

theorem retire_valid (heap after : Heap) (value : Located)
    (accepted : retireObject heap value = some after) (formed : Valid heap) : Valid after := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  rename_i schema node token reference
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨stored, found, middle, consumed, rfl⟩ := accepted
  have same := consume_objects _ _ _ consumed
  have bounded : node.value < heap.objects.length := by
    simp only [Heap.lookup, Option.bind_eq_some_iff] at found
    obtain ⟨entry, atNode, _⟩ := found
    exact (List.getElem?_eq_some_iff.mp atNode).1
  apply set_valid middle node none
  · simpa only [same] using bounded
  · simpa only [Valid, Heap.lookup, same] using formed
  · intro stored absent; cases absent

theorem temporary_objects (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) : after.heap.objects = machine.heap.objects := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted; rfl

theorem finishTemporary_objects (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) : after.state.heap.objects = machine.heap.objects := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted; rfl

theorem scopedValue_valid (machine : State) (value : SemanticValue) (after : Transition)
    (formed : Valid machine.heap) (accepted : scopedValue machine value = .ok after) : Valid after.state.heap := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, finished⟩ := accepted
  simpa only [Valid, Heap.lookup, finishTemporary_objects _ _ _ finished,
    temporary_objects _ _ _ reserved] using formed

theorem closure_layout (node : NodeId) (schema : SchemaId .source) (function : FunctionId .source)
    (values : List (VariableId × Located)) :
    Layout node (.closure schema function (values.mapIdx fun index (binder, value) =>
      Binding.mk binder (retainAt value (.closure node index)))) := by
  intro index binding found
  simp only [List.getElem?_mapIdx] at found
  obtain ⟨original, _, rfl⟩ := Option.map_eq_some_iff.mp found
  rfl

theorem makeClosureWithValues_valid (machine : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (values : List Located) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) : Valid after.state.heap := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, reserved, store, moved, ⟨finalStore, result⟩, allocated, finished⟩ := accepted
  have middleSame := temporary_objects _ _ _ reserved
  have movedSame := move_objects _ _ _ _ moved
  have next := allocation_valid _ _ _ _ _ _ _ allocated
    (by simpa only [Valid, Heap.lookup, movedSame, middleSame] using formed)
    (by simpa only [movedSame] using closure_layout _ _ _ _)
  simpa only [Valid, Heap.lookup, finishTemporary_objects _ _ _ finished] using next

private theorem mapM_at_output (function : α → Except Invalid β) (inputs : List α) (outputs : List β)
    (accepted : inputs.mapM function = .ok outputs) (index : Nat) (output : β)
    (found : outputs[index]? = some output) :
    ∃ input, inputs[index]? = some input ∧ function input = .ok output := by
  induction inputs generalizing outputs index with
  | nil => cases accepted; simp at found
  | cons head tail induction =>
    simp only [List.mapM_cons, bind, except_bind_ok] at accepted
    obtain ⟨first, firstAt, rest, restAt, accepted⟩ := accepted
    cases accepted
    cases index with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      cases found
      exact ⟨head, rfl, firstAt⟩
    | succ index =>
      obtain ⟨input, inputAt, checked⟩ := induction rest restAt index found
      exact ⟨input, inputAt, checked⟩

private theorem dedup_of_nodup [BEq α] [LawfulBEq α] (values : List α) (unique : values.Nodup) :
    values.eraseDups = values := by
  induction values with
  | nil => rfl
  | cons head tail induction =>
    rw [List.nodup_cons] at unique
    have unchanged : tail.filter (fun value => !value == head) = tail := by
      apply List.filter_eq_self.mpr
      intro value member
      have different : value ≠ head := by intro same; exact unique.1 (same ▸ member)
      simpa using different
    rw [List.eraseDups_cons, unchanged, induction unique.2]

private theorem renamed_fresh_at (space : Space) (domain : Domain) (start : Nat)
    (identities : List (Ref space domain)) (unique : identities.Nodup)
    (index : Nat) (bound : index < identities.length) :
    (renamed (freshMap space domain start identities) identities[index]).value = start + index := by
  have selected := renamed_inside_fresh_map space domain start identities identities[index] (List.getElem_mem bound)
  obtain ⟨position, positionBound, atPosition⟩ := List.mem_mapIdx.mp selected
  have source := congrArg Prod.fst atPosition
  have target := congrArg (fun pair => pair.2.value) atPosition
  simp only [dedup_of_nodup identities unique] at source target positionBound
  have same : position = index := (List.getElem_inj unique).mp source
  simpa [same] using target.symm

theorem instantiateCapture_valid (machine : State) (context : Context) (saved : Capture) (after : State × Capture)
    (formed : Valid machine.heap) (accepted : instantiateCapture machine context saved = .ok after) : Valid after.1.heap := by
  let support := cloneSupport machine.heap saved
  let dormant := support.filterMap (fun node => match machine.heap.lookup node with
    | some (.multiTemplate inner) => some inner | _ => none)
  let scopeIds := (captureScopes saved ++ dormant.flatMap captureScopes).eraseDups
  let invocationIds := (captureInvocations saved ++ dormant.flatMap captureInvocations).eraseDups
  let regions := (saved.localRegions ++ dormant.flatMap Capture.localRegions).eraseDups
  let attachments := (saved.delimiter.identity :: activeAttachments saved.frames ++
    dormant.flatMap (fun inner => inner.delimiter.identity :: activeAttachments inner.frames)).eraseDups
  let copyNodes := support.filter fun node => match machine.heap.lookup node with
    | some (.cell _ _ region _) | some (.region region _ _ _) => regions.contains region
    | some (.capability identity _) => attachments.contains identity
    | some (.closure ..) | some (.multiTemplate _) => true
    | _ => false
  let cells := copyNodes.filterMap (fun node => match machine.heap.lookup node with
    | some (.cell identity _ _ _) => some identity | _ => none)
  let mapping : Renaming := {
    nodes := freshMap .runtime .node machine.heap.objects.length copyNodes
    attachments := freshMap .runtime .attachment machine.heap.nextAttachment attachments
    regions := freshMap .runtime .regionInstance machine.heap.nextRegion regions
    cells := freshMap .runtime .cell machine.heap.nextCell cells
    scopes := freshMap .runtime .lexicalScope machine.heap.nextScope scopeIds
    invocations := freshMap .runtime .invocation machine.heap.nextInvocation invocationIds }
  have uniqueNodes : copyNodes.Nodup :=
    (clone_support_has_one_entry_per_object machine.heap saved).filter _
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨objects, objectsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨scopes, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨invocations, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  change Valid {machine.heap with objects := machine.heap.objects ++ objects}
  intro node stored found
  by_cases old : node.value < machine.heap.objects.length
  · exact formed node stored (by simpa only [Heap.lookup, List.getElem?_append_left old] using found)
  · have high := Nat.le_of_not_gt old
    simp only [Heap.lookup, List.getElem?_append_right high] at found
    obtain ⟨entry, atOutput, storedAt⟩ := Option.bind_eq_some_iff.mp found
    cases entry with
    | none => contradiction
    | some storedEntry =>
      cases storedAt
      obtain ⟨original, atInput, checked⟩ := mapM_at_output _ _ _ objectsAt _ _ atOutput
      simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq, Option.some.injEq] at checked
      obtain ⟨originalObject, originalAt, equal⟩ := checked
      cases equal
      change Layout node (renameObject mapping (frozenObject saved dormant original originalObject))
      have mapped := rename_layout mapping original _ (frozen_layout _ _ saved dormant (formed original originalObject originalAt))
      have same : renamed mapping.nodes original = node := by
        change copyNodes[node.value - machine.heap.objects.length]? = some original at atInput
        obtain ⟨bound, atIndex⟩ := List.getElem?_eq_some_iff.mp atInput
        apply ref_eq
        have position := renamed_fresh_at .runtime .node machine.heap.objects.length copyNodes uniqueNodes
          (node.value - machine.heap.objects.length) bound
        rw [atIndex] at position
        change (renamed mapping.nodes original).value = machine.heap.objects.length + (node.value - machine.heap.objects.length) at position
        omega
      simpa only [same] using mapped

end ObjectOwners
end BoundaryV2.Profile.Source.Machine
