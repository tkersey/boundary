import BoundaryV2.SourceRegionIdentity

namespace BoundaryV2.Profile.Source.Machine
namespace RegionIdentities

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem ref_eq {left right : Ref space domain} (same : left.value = right.value) : left = right := by
  cases left; cases right
  simpa only [Ref.mk.injEq] using same

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]



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

private theorem rename_identity (mapping : Renaming) (object : Object) :
    identity (renameObject mapping object) = (identity object).map (renamed mapping.regions) := by
  cases object <;> rfl

private theorem frozen_identity (saved : Capture) (dormant : List Capture) (node : NodeId) (object : Object) :
    identity (frozenObject saved dormant node object) = identity object := by
  cases object <;> rfl

theorem instantiateCapture_unique (machine : State) (context : Context) (saved : Capture) (after : State × Capture)
    (formed : Unique machine.heap) (bounded : IdentitySupport.Valid machine)
    (accepted : instantiateCapture machine context saved = .ok after) : Unique after.1.heap := by
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
  let resultHeap := {machine.heap with objects := machine.heap.objects ++ objects}
  change Unique resultHeap
  have origin (node : NodeId) (regionIdentity : RegionInstanceId) (found : atNode resultHeap node = some regionIdentity) :
      atNode machine.heap node = some regionIdentity ∨
      ∃ index original oldRegionIdentity, copyNodes[index]? = some original ∧
        atNode machine.heap original = some oldRegionIdentity ∧ oldRegionIdentity ∈ regions ∧
        regionIdentity = renamed mapping.regions oldRegionIdentity ∧ node.value = machine.heap.objects.length + index := by
    by_cases old : node.value < machine.heap.objects.length
    · exact Or.inl (by simpa only [atNode, resultHeap, Heap.lookup, List.getElem?_append_left old] using found)
    · have high := Nat.le_of_not_gt old
      obtain ⟨stored, found, regionAt⟩ := Option.bind_eq_some_iff.mp found
      simp only [resultHeap, Heap.lookup, List.getElem?_append_right high] at found
      obtain ⟨entry, atOutput, storedAt⟩ := Option.bind_eq_some_iff.mp found
      cases entry with
      | none => contradiction
      | some storedEntry =>
        cases storedAt
        obtain ⟨original, atInput, checked⟩ := mapM_at_output _ _ _ objectsAt _ _ atOutput
        simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq, Option.some.injEq] at checked
        obtain ⟨originalObject, originalAt, equal⟩ := checked
        cases equal
        change identity (renameObject mapping (frozenObject saved dormant original originalObject)) = some regionIdentity at regionAt
        rw [rename_identity, frozen_identity] at regionAt
        cases originalObject <;> try contradiction
        rename_i oldRegionIdentity schema region content
        simp only [identity, Option.map_some, Option.some.injEq] at regionAt
        refine Or.inr ⟨node.value - machine.heap.objects.length, original, oldRegionIdentity, atInput, ?_, ?_, regionAt.symm, by omega⟩
        · simp [atNode, originalAt, identity]
        · have copied := (List.mem_filter.mp (List.mem_of_getElem? atInput)).2
          simp only [originalAt, List.contains_iff_mem, List.mem_eraseDups, List.mem_append,
            List.mem_flatMap, List.mem_filterMap] at copied
          dsimp only [regions, dormant, support]
          simp only [List.mem_eraseDups, List.mem_append, List.mem_flatMap, List.mem_filterMap]
          rcases copied with belongs | ⟨inner, ⟨innerNode, innerMember, selected⟩, belongs⟩
          · exact Or.inl belongs
          · refine Or.inr ⟨inner, ⟨innerNode, innerMember, ?_⟩, belongs⟩
            cases actual : machine.heap.lookup innerNode with
            | none => simp [actual] at selected
            | some object =>
              cases object <;> simp [actual] at selected ⊢
              exact selected
  intro left right regionIdentity first second
  rcases origin left regionIdentity first with firstOld | ⟨firstIndex, firstOriginal, firstRegionIdentity, firstAt, firstRegionIdentityAt, firstInside, firstRenamed, firstIndexEq⟩
  · rcases origin right regionIdentity second with secondOld | ⟨secondIndex, secondOriginal, secondRegionIdentity, secondAt, secondRegionIdentityAt, secondInside, secondRenamed, secondIndexEq⟩
    · exact formed _ _ _ firstOld secondOld
    · have before := identity_bounded bounded.heap firstOld
      have fresh := (source_activation_interval .runtime .regionInstance machine.heap.nextRegion regions secondRegionIdentity secondInside).1
      change machine.heap.nextRegion ≤ (renamed mapping.regions secondRegionIdentity).value at fresh
      rw [← secondRenamed] at fresh
      omega
  · rcases origin right regionIdentity second with secondOld | ⟨secondIndex, secondOriginal, secondRegionIdentity, secondAt, secondRegionIdentityAt, secondInside, secondRenamed, secondIndexEq⟩
    · have before := identity_bounded bounded.heap secondOld
      have fresh := (source_activation_interval .runtime .regionInstance machine.heap.nextRegion regions firstRegionIdentity firstInside).1
      change machine.heap.nextRegion ≤ (renamed mapping.regions firstRegionIdentity).value at fresh
      rw [← firstRenamed] at fresh
      omega
    · have sameCell := source_activation_injective .runtime .regionInstance machine.heap.nextRegion regions
        firstRegionIdentity secondRegionIdentity firstInside secondInside (firstRenamed.symm.trans secondRenamed)
      have sameNode := formed firstOriginal secondOriginal firstRegionIdentity firstRegionIdentityAt (sameCell ▸ secondRegionIdentityAt)
      have firstBound := (List.getElem?_eq_some_iff.mp firstAt).1
      have sameIndex : firstIndex = secondIndex :=
        (List.getElem?_inj firstBound uniqueNodes).mp (firstAt.trans (sameNode ▸ secondAt).symm)
      apply ref_eq
      omega

theorem allocate_nonregion_unique (heap after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (result : Located)
    (accepted : allocateObject heap schema stored owner exclusive = some (after, result))
    (nonregion : identity stored = none) (formed : Unique heap) : Unique after :=
  allocate_unique _ _ _ _ _ _ _ accepted formed (by simp [nonregion])

theorem makeClosureWithValues_unique (machine : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (values : List Located) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) : Unique after.state.heap := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, store, moved, ⟨finalStore, result⟩, allocated, finished⟩ := accepted
  exact finishTemporary_unique (allocate_nonregion_unique _ _ _ _ _ _ _ allocated rfl
    (move_unique (temporary_unique formed temporaryOk) moved)) finished

theorem makeClosure_unique (machine : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : makeClosure machine context schema function bindings = .ok after) : Unique after.state.heap := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨values, _, created⟩ := accepted
  exact makeClosureWithValues_unique _ _ _ _ _ _ formed created

theorem createScope_unique (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (bindings : Environment)
    (after : State) (entered : Environment) (formed : Unique machine.heap)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered)) : Unique after.heap := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact formed
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at accepted
    obtain ⟨_, _, store, moved, rfl, rfl⟩ := accepted
    have next := move_unique formed moved
    exact next

theorem invokeFunction_unique (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) : Unique after.state.heap := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, ⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_unique _ _ _ _ _ _ _ _ _ formed created
  exact next

theorem applyClosure_unique (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition) (formed : Unique machine.heap)
    (accepted : applyClosure machine context closure arguments = .ok after) : Unique after.state.heap := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  obtain ⟨⟨schema, token, reference⟩, _⟩ := CellStability.lookupObject_reference _ _ _ _ looked
  rw [reference] at accepted
  cases token with
  | none =>
    simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_unique _ _ _ _ _ _ formed accepted
  | some token =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, retired, accepted⟩ := accepted
    exact invokeFunction_unique _ _ _ _ _ _ (retire_unique _ _ _ retired formed) accepted

theorem takeCapture_unique (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (formed : Unique machine.heap) (bounded : IdentitySupport.Valid machine)
    (accepted : takeCapture machine context token = .ok after) : Unique after.1.heap := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
  cases stored <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨heap, retired, rfl⟩ := accepted
    exact retire_unique _ _ _ retired formed
  · exact instantiateCapture_unique _ _ _ _ formed bounded accepted

theorem activateCapture_unique (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (formed : Unique machine.heap)
    (accepted : activateCapture machine context saved successor = .ok after) : Unique after.heap := by
  simp only [activateCapture, bind, except_bind_ok, pure, Except.pure] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none => cases accepted; exact formed
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    exact formed

theorem resumeValue_unique (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (formed : Unique machine.heap) (bounded : IdentitySupport.Valid machine)
    (accepted : resumeValue machine context token argument successor = .ok after) : Unique after.state.heap := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, saved⟩, captured, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨temporary, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  exact finishTemporary_unique (move_unique (temporary_unique
    (activateCapture_unique _ _ _ _ _ (takeCapture_unique _ _ _ _ formed bounded captured) activated) temporaryOk) moved) finished

theorem resumeComputation_unique (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (formed : Unique machine.heap) (bounded : IdentitySupport.Valid machine)
    (accepted : resumeComputation machine context token computation = .ok after) : Unique after.state.heap := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, saved⟩, captured, active, activated, applied⟩ := accepted
  exact applyClosure_unique _ _ _ _ _
    (activateCapture_unique _ _ _ _ _ (takeCapture_unique _ _ _ _ formed bounded captured) activated) applied

end RegionIdentities
end BoundaryV2.Profile.Source.Machine
