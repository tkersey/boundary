import BoundaryV2.SourceQueueCustody

namespace BoundaryV2.Profile.Source.Machine
namespace QueueCustody

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

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

theorem capture_fields (saved : Capture) :
    (saved.frames.flatMap DisposalShape.frame).filter (fun value => closureOwner value.owner) =
      saved.frames.flatMap frameFields := by
  simp only [List.filter_flatMap]
  rfl

theorem renamed_safe_capture_empty (source : Module) (mapping : Renaming) (saved : Capture)
    (safe : captureCloneSafe source saved = true) :
    (renameCapture mapping saved).frames.flatMap frameFields = [] := by
  rw [← capture_fields]
  simp only [renameCapture, List.flatMap_map, DisposalShape.frame_rename, ← List.map_flatMap,
    OwnerLocations.clone_capture_has_no_queue source saved safe, List.map_nil, List.filter_nil]

theorem instantiateCapture_fields (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated)) :
    fields after = fields machine ∧ after.heap.custody = machine.heap.custody ∧
      instantiated.frames.flatMap frameFields = [] := by
  have original := accepted
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨copied, copiedAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  have empty : copied.flatMap (fun entry => entry.toList.flatMap objectFields) = [] := by
    apply List.flatMap_eq_nil_iff.mpr
    intro entry member
    obtain ⟨node, nodeCopied, checked⟩ := mapM_output _ _ _ copiedAt entry member
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨stored, storedAt, rfl⟩ := checked
    cases stored <;> try (solve | rfl)
    case oneShot inner =>
      have impossible := (List.mem_filter.mp nodeCopied).2
      simp [storedAt] at impossible
    case multiTemplate inner =>
      have safe := instantiation_checks_dormant_templates _ _ _ _ _ _ node
        (List.mem_filter.mp nodeCopied).1 storedAt original
      simp only [Option.toList_some, List.flatMap_singleton, objectFields, renameObject, DisposalShape.object]
      rw [capture_fields]
      exact renamed_safe_capture_empty context.source _ inner (clone_safe_has_no_captured_custody _ _ _ safe).1
  refine ⟨?_, rfl, ?_⟩
  · simp only [fields_components, heapFields, List.flatMap_append, empty, List.append_nil]
  · exact renamed_safe_capture_empty context.source _ saved
      (CloneTraits.instantiation_root_safe _ _ _ _ _ original)

theorem instantiateCapture_valid (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated)) (valid : Valid machine) :
    Linear after.heap (fields after ++ instantiated.frames.flatMap frameFields) := by
  obtain ⟨same, book, empty⟩ := instantiateCapture_fields _ _ _ _ _ accepted
  simpa only [Valid, empty, List.append_nil, same, Linear, current, book] using valid

theorem takeCapture_valid (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after) (valid : Valid machine)
    (ordinary : OwnerLocations.Ordinary token) :
    Linear after.1.heap (fields after.1 ++ after.2.frames.flatMap frameFields) := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  case oneShot saved =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨heap, retired, rfl⟩ := accepted
    have next := retire_ordinary_partition_linear _ _ _ _ _ looked retired valid ordinary
    simpa only [objectFields, DisposalShape.object, capture_fields] using next
  case multiTemplate saved => exact instantiateCapture_valid _ _ _ _ _ accepted valid

theorem activated_stack_valid (machine : State) (saved : Capture) (delimiter : Activation) (reinstall : Bool)
    (valid : Linear machine.heap (fields machine ++ saved.frames.flatMap frameFields)) :
    Valid {machine with
      stack := saved.frames ++ (if reinstall then [.handler delimiter] else []) ++ [.restore machine.invocation machine.scope] ++ machine.stack
      scope := saved.scope
      invocation := saved.invocation} := by
  have empty : (if reinstall then [Frame.handler delimiter] else []).flatMap frameFields = [] := by
    split <;> rfl
  simp only [Valid, fields_components, List.flatMap_append, empty, List.flatMap_cons, frameFields,
    DisposalShape.frame, List.filter_nil, List.flatMap_nil, List.append_nil]
  apply Linear.perm _ (fields machine ++ saved.frames.flatMap frameFields) _ _ valid
  simpa only [fields_components, List.append_assoc] using
    List.Perm.append_left (controlFields machine.control)
      (List.perm_append_comm (l₁ := machine.stack.flatMap frameFields ++ heapFields machine.heap)
        (l₂ := saved.frames.flatMap frameFields))

theorem activateCapture_valid (machine after : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment))
    (accepted : activateCapture machine context saved successor = .ok after)
    (valid : Linear machine.heap (fields machine ++ saved.frames.flatMap frameFields)) : Valid after := by
  simp only [activateCapture, bind, except_bind_ok, pure, Except.pure] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none => cases accepted; exact activated_stack_valid _ _ _ _ valid
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    exact activated_stack_valid _ _ _ _ valid

theorem resumeValue_valid (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) (valid : Valid machine)
    (ordinaryToken : OwnerLocations.Ordinary token) (ordinaryArgument : OwnerLocations.Ordinary argument) : Valid after.state := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, saved⟩, taken, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨temporary, owner⟩, reserved, store, moved, finished⟩ := accepted
  have captured := takeCapture_valid _ _ _ _ taken valid ordinaryToken
  have next := activateCapture_valid _ _ _ _ _ activated captured
  have temporaryValid := temporary_valid _ _ _ reserved next
  exact finishTemporary_valid _ _ _ finished
    (move_ordinary_valid _ _ _ _ moved temporaryValid (by simpa using ordinaryArgument))

end QueueCustody
end BoundaryV2.Profile.Source.Machine
