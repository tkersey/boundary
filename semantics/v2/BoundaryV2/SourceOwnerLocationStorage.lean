import BoundaryV2.SourceOwnerLocations

namespace BoundaryV2.Profile.Source.Machine
namespace OwnerLocations

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem scopedValue_valid (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, finished⟩ := accepted
  have next := temporary_valid _ _ _ reserved valid
  exact finishTemporary_valid _ _ _ finished next.1 (Or.inl next.2)

theorem allocation_result_ordinary (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value)) (inScope : Scoped owner) : Ordinary value := by
  exact Or.inl ((HoldingOwners.allocation_scopes _ _ _ _ _ _ _ accepted).2.symm ▸ inScope)

theorem makeClosureWithValues_valid (machine : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, reserved, moved, movedAt, ⟨heap, result⟩, allocated, finished⟩ := accepted
  have next := temporary_valid _ _ _ reserved valid
  have movedValid := move_valid _ _ _ _ movedAt next.1
  have allocatedValid := allocation_valid _ _ _ _ _ _ _ allocated movedValid
    (by simp [ObjectValid, objectValues, DisposalShape.object])
  exact finishTemporary_valid _ _ _ finished allocatedValid (allocation_result_ordinary _ _ _ _ _ _ _ allocated next.2)

theorem makeClosure_valid (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨values, _, created⟩ := accepted
  exact makeClosureWithValues_valid _ _ _ _ _ _ created valid

theorem commitPure_valid (machine : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) (after : Transition)
    (accepted : commitPure machine opcode operands result = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, accepted⟩ := accepted
  have next := temporary_valid _ _ _ reserved valid
  split at accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, finished⟩ := accepted
    exact finishTemporary_valid _ _ _ finished next.1 (Or.inl next.2)
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨heap, moved, _, _, custody, _, finished⟩ := accepted
    have movedValid := move_valid _ _ _ _ moved next.1
    have changed := same_storage {middle with heap := heap} {heap with custody := custody} movedValid rfl rfl
    exact finishTemporary_valid _ _ _ finished changed (Or.inl next.2)


theorem createScope_valid (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located)
    (bindings : Environment) (after : State × Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok after)
    (valid : Valid machine) (outer : ∀ binding ∈ bindings, Ordinary binding.located) :
    Valid after.1 ∧ (∀ binding ∈ after.2, Ordinary binding.located) ∧ after.1.heap.objects = machine.heap.objects := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · rename_i reused
    have freeValues := (Bool.and_eq_true_iff.mp reused).2
    cases accepted
    refine ⟨valid, ?_, rfl⟩
    intro binding member
    rcases List.mem_append.mp member with added | original
    · obtain ⟨⟨binder, value⟩, pairAt, rfl⟩ := List.mem_map.mp added
      have free := List.all_eq_true.mp freeValues value (List.of_mem_zip pairAt).2
      exact Or.inr (List.nil_of_isEmpty free)
    · exact outer binding (List.mem_filter.mp original).1
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, heap, moved, rfl⟩ := accepted
    let identity : LexicalScopeId := ⟨machine.heap.nextScope⟩
    let relocated := values.mapIdx (fun index value => retainAt value (.lexical identity index))
    have relocatedOrdinary : ∀ value ∈ relocated, Ordinary value := by
      intro value member
      obtain ⟨index, _, rfl⟩ := List.exists_of_mem_mapIdx member
      exact Or.inl trivial
    have movedValid := move_valid _ _ _ _ moved valid
    have appended := append_scope {machine with heap := heap} ⟨identity, invocation, parent, vars.length, relocated⟩ movedValid relocatedOrdinary
    refine ⟨appended, ?_, ObjectOwners.move_objects machine.heap heap values _ moved⟩
    intro binding member
    rcases List.mem_append.mp member with added | original
    · obtain ⟨⟨binder, value⟩, pairAt, rfl⟩ := List.mem_map.mp added
      exact relocatedOrdinary value (List.of_mem_zip pairAt).2
    · exact outer binding (List.mem_filter.mp original).1

theorem invokeFunction_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after)
    (valid : Valid machine) : Valid after.state := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, body, _, _, _, _, _, _, _, ⟨middle, environment⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ created valid (by simp)
  let record : Invocation := ⟨⟨machine.heap.nextInvocation⟩, function, activeAttachments machine.stack, activeRegions machine.stack⟩
  let heap := {middle.heap with invocations := middle.heap.invocations ++ [record], nextInvocation := middle.heap.nextInvocation + 1}
  have stored := same_storage middle heap next.1 rfl rfl
  have retained : RetainsRetired machine.heap heap := RetainsRetired.of_objects _ _ next.2.2
  have stacked := with_stack {middle with heap := heap} (.invocation machine.invocation machine.scope :: machine.stack) stored
    (by simpa only [List.flatMap_cons, frameValues, List.nil_append] using normal_stack machine valid.1)
    (by
      simp only [List.flatMap_cons, DisposalShape.frame, List.nil_append]
      intro value member
      exact queued_mono machine.heap heap value retained (pending_stack machine valid.2 value member))
  have entered := with_control _ (.term body environment) stacked (by
      intro value member
      obtain ⟨binding, bindingAt, rfl⟩ := List.mem_map.mp member
      exact next.2.1 binding bindingAt) (by simp [DisposalShape.control])
  exact entered

theorem applyClosure_valid (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  obtain ⟨⟨schema, token, reference⟩, _⟩ := CellStability.lookupObject_reference _ _ _ _ looked
  rw [reference] at accepted
  cases token with
  | none =>
    simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_valid _ _ _ _ _ _ accepted valid
  | some token =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, retired, accepted⟩ := accepted
    exact invokeFunction_valid _ _ _ _ _ _ accepted (retire_valid _ _ _ retired valid)


def CaptureValid (heap : Heap) (saved : Capture) : Prop :=
  (∀ value ∈ captureValues saved, Ordinary value) ∧
  (∀ value ∈ saved.frames.flatMap DisposalShape.frame, Queued heap value)

theorem CaptureValid.mono (before after : Heap) (saved : Capture)
    (retained : RetainsRetired before after) (valid : CaptureValid before saved) : CaptureValid after saved :=
  ⟨valid.1, fun value member => queued_mono before after value retained (valid.2 value member)⟩

theorem after_values_subset (after : AfterRelease) (value : Located) (member : value ∈ afterValues after) :
    value.value ∈ ValueInventory.afterRelease after := by
  cases after <;> simp_all [afterValues, ValueInventory.afterRelease]

theorem activation_values_subset (active : Activation) (value : Located) (member : value ∈ activationValues active) :
    value.value ∈ ValueInventory.activation active := by
  simp only [activationValues, ValueInventory.activation, ValueInventory.environment, List.mem_append, List.mem_map] at member ⊢
  grind only []

theorem frame_values_subset (saved : Frame) (value : Located) (member : value ∈ frameValues saved) :
    value.value ∈ ValueInventory.frame saved := by
  cases saved
  case handler active => exact activation_values_subset active value member
  case releaseReturn scope after => exact after_values_subset after value member
  case disposalReturn remaining after invocation scope =>
    exact List.mem_append_right _ (after_values_subset after value member)
  all_goals simp only [frameValues, ValueInventory.frame, ValueInventory.environment, List.mem_append,
    List.mem_map, List.not_mem_nil] at member ⊢
  all_goals first | contradiction | grind only []

theorem capture_values_subset (saved : Capture) (value : Located) (member : value ∈ captureValues saved) :
    value.value ∈ ValueInventory.capture saved := by
  simp only [captureValues, List.mem_append, List.mem_flatMap] at member
  rcases member with (⟨frame, frameAt, member⟩ | active) | capability
  · exact List.mem_append_left _ (List.mem_append_left _ (List.mem_append_left _
      (List.mem_flatMap.mpr ⟨frame, frameAt, frame_values_subset frame value member⟩)))
  · exact List.mem_append_left _ (List.mem_append_left _ (List.mem_append_right _
      (activation_values_subset saved.delimiter value active)))
  · exact List.mem_append_left _ (List.mem_append_right _ (List.mem_map.mpr ⟨value, capability, rfl⟩))

theorem after_rename (mapping : Renaming) (after : AfterRelease) :
    afterValues (renameAfter mapping after) = (afterValues after).map (renameLocated mapping) := by
  cases after <;> rfl

theorem activation_rename (mapping : Renaming) (active : Activation) :
    activationValues (renameActivation mapping active) = (activationValues active).map (renameLocated mapping) := by
  simp [activationValues, renameActivation, renameEnvironment, List.map_map, List.map_append]

theorem frame_rename (mapping : Renaming) (saved : Frame) :
    frameValues (renameFrame mapping saved) = (frameValues saved).map (renameLocated mapping) := by
  cases saved <;> simp [frameValues, renameFrame, renameEnvironment, List.map_map, List.map_append, activation_rename, after_rename, Option.toList_map]

theorem capture_rename (mapping : Renaming) (saved : Capture) :
    captureValues (renameCapture mapping saved) = (captureValues saved).map (renameLocated mapping) := by
  simp [captureValues, renameCapture, List.flatMap_map, frame_rename, activation_rename, List.map_flatMap, List.map_append]

theorem clone_frame_has_no_queue (source : Module) (saved : Frame) (safe : frameCloneSafe source saved = true) :
    DisposalShape.frame saved = [] := by
  cases saved <;> simp_all [DisposalShape.frame, frameCloneSafe]

theorem clone_capture_has_no_queue (source : Module) (saved : Capture) (safe : captureCloneSafe source saved = true) :
    saved.frames.flatMap DisposalShape.frame = [] := by
  have frames := (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp safe).1).1
  exact List.flatMap_eq_nil_iff.mpr (fun frame member => clone_frame_has_no_queue source frame (List.all_eq_true.mp frames frame member))

theorem clone_capture_valid (source : Module) (heap : Heap) (saved : Capture) (safe : captureCloneSafe source saved = true) :
    CaptureValid heap saved := by
  constructor
  · intro value member
    exact Or.inr (CloneTraits.clone_safe_capture_inventory source saved safe value.value (capture_values_subset saved value member)).2
  · simp only [clone_capture_has_no_queue source saved safe, List.not_mem_nil, false_implies, implies_true]

theorem renamed_clone_capture_valid (source : Module) (heap : Heap) (mapping : Renaming) (saved : Capture)
    (safe : captureCloneSafe source saved = true) : CaptureValid heap (renameCapture mapping saved) := by
  constructor
  · intro value member
    rw [capture_rename] at member
    obtain ⟨original, originalAt, rfl⟩ := List.mem_map.mp member
    exact ordinary_rename mapping original ((clone_capture_valid source heap saved safe).1 original originalAt)
  · simp only [renameCapture, List.flatMap_map, DisposalShape.frame_rename, ← List.map_flatMap,
      clone_capture_has_no_queue source saved safe, List.map_nil, List.not_mem_nil, false_implies, implies_true]

theorem trim_frame_normal (context : Context) (saved : Frame) : frameValues (trimFrame context saved) ⊆ frameValues saved := by
  cases saved <;> simp only [trimFrame, frameValues, List.subset_def]
  case binding binder body bindings scope =>
    intro value member
    obtain ⟨binding, bindingAt, rfl⟩ := List.mem_map.mp member
    exact List.mem_map.mpr ⟨binding, (List.mem_filter.mp bindingAt).1, rfl⟩
  case operands intent bindings remaining evaluated =>
    intro value member
    rcases List.mem_append.mp member with scopedValue | operand
    · obtain ⟨binding, bindingAt, rfl⟩ := List.mem_map.mp scopedValue
      exact List.mem_append_left _ (List.mem_map.mpr ⟨binding, (List.mem_filter.mp bindingAt).1, rfl⟩)
    · exact List.mem_append_right _ operand
  all_goals intros; assumption

theorem trim_frame_queued (context : Context) (saved : Frame) :
    DisposalShape.frame (trimFrame context saved) = DisposalShape.frame saved := by
  cases saved <;> rfl


private theorem mapM_output (function : α → Except Invalid β) (inputs : List α) (outputs : List β)
    (accepted : inputs.mapM function = .ok outputs) (output : β) (member : output ∈ outputs) :
    ∃ input ∈ inputs, function input = .ok output := by
  induction inputs generalizing outputs with
  | nil => cases accepted; simp at member
  | cons head tail induction =>
    simp only [List.mapM_cons, bind, except_bind_ok] at accepted
    obtain ⟨first, firstAt, rest, restAt, accepted⟩ := accepted
    cases accepted
    rcases List.mem_cons.mp member with equal | belongs
    · cases equal; exact ⟨head, by simp, firstAt⟩
    · obtain ⟨input, inputMember, checked⟩ := induction rest restAt belongs
      exact ⟨input, by simp [inputMember], checked⟩

theorem instantiation_shape (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated)) :
    after = {machine with heap := after.heap} ∧
      after.heap.scopes.flatMap Scope.holdings = machine.heap.scopes.flatMap Scope.holdings := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨scopes, scopesAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  refine ⟨rfl, ?_⟩
  have empty : scopes.flatMap Scope.holdings = [] := by
    apply List.flatMap_eq_nil_iff.mpr
    intro scope member
    obtain ⟨originalId, _, checked⟩ := mapM_output _ _ _ scopesAt scope member
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨_, _, rfl⟩ := checked
    rfl
  simp only [List.flatMap_append, empty, List.append_nil]

theorem instantiateCapture_valid (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated)) (valid : Valid machine) :
    Valid after ∧ CaptureValid after.heap instantiated := by
  obtain ⟨mapping, _, captureAt, _, inventory⟩ := instantiation_inventory _ _ _ _ _ accepted
  obtain ⟨_, copied, appended⟩ := source_instantiation_retains_old_heap _ _ _ _ _ accepted
  have retained : RetainsRetired machine.heap after.heap := by
    simpa only [RetainsRetired, Heap.lookup, appended] using RetainsRetired.append machine.heap copied
  have shape := instantiation_shape _ _ _ _ _ accepted
  have before := heap_valid machine valid
  have heapValid : HeapValid after.heap := by
    constructor
    · intro entry entryAt stored storedAt
      rcases inventory entry entryAt with original | added
      · exact ObjectValid.mono _ _ _ retained (before.1 entry original stored storedAt)
      · obtain ⟨node, nodeCopied, original, originalAt, rfl⟩ := added
        cases storedAt
        have nodeSupported := (List.mem_filter.mp nodeCopied).1
        cases original <;> try (solve | simp [ObjectValid, objectValues, DisposalShape.object, renameObject, frozenObject])
        case oneShot inner =>
          have impossible := (List.mem_filter.mp nodeCopied).2
          simp [originalAt] at impossible
        case multiTemplate inner =>
          have checked := instantiation_checks_dormant_templates _ _ _ _ _ _ node nodeSupported originalAt accepted
          have safe := (clone_safe_has_no_captured_custody _ _ _ checked).1
          exact renamed_clone_capture_valid context.source after.heap mapping inner safe
    · intro scope scopeAt value member
      have oldMember : value ∈ machine.heap.scopes.flatMap Scope.holdings := by
        rw [← shape.2]
        exact List.mem_flatMap.mpr ⟨scope, scopeAt, member⟩
      obtain ⟨original, originalAt, member⟩ := List.mem_flatMap.mp oldMember
      exact before.2 original originalAt value member
  refine ⟨?_, ?_⟩
  · have next := with_heap_valid machine after.heap valid retained heapValid
    exact (congrArg Valid shape.1).mpr next
  · rw [captureAt]
    exact renamed_clone_capture_valid context.source after.heap mapping saved
      (CloneTraits.instantiation_root_safe _ _ _ _ _ accepted)

end OwnerLocations
end BoundaryV2.Profile.Source.Machine
