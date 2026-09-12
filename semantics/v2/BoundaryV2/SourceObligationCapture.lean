import BoundaryV2.SourceObligationLocations

namespace BoundaryV2.Profile.Source.Machine
namespace ObligationLocations

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem clone_frame_empty (source : Module) (saved : Frame) (safe : frameCloneSafe source saved = true) : frame saved = [] := by
  cases saved <;> simp_all [frameCloneSafe, frame]

theorem clone_capture_empty (source : Module) (saved : Capture) (safe : captureCloneSafe source saved = true) :
    saved.frames.flatMap frame = [] := by
  apply List.flatMap_eq_nil_iff.mpr
  intro frame member
  exact clone_frame_empty source frame (List.all_eq_true.mp (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp safe).1).1 frame member)

theorem renamed_clone_empty (source : Module) (mapping : Renaming) (saved : Capture)
    (safe : captureCloneSafe source saved = true) : (renameCapture mapping saved).frames.flatMap frame = [] := by
  apply List.flatMap_eq_nil_iff.mpr
  intro renamed member
  obtain ⟨original, originalAt, rfl⟩ := List.mem_map.mp member
  have clone := List.all_eq_true.mp (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp safe).1).1 original originalAt
  cases original <;> simp_all [frameCloneSafe, renameFrame, frame]

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

theorem instantiateCapture_parts (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated)) :
    fields after = fields machine ∧ after.heap.obligations = machine.heap.obligations ∧
      instantiated.frames.flatMap frame = [] := by
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
  have empty : copied.flatMap (fun entry => entry.toList.flatMap object) = [] := by
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
      simp only [Option.toList_some, List.flatMap_singleton, renameObject, object]
      exact renamed_clone_empty context.source _ inner (clone_safe_has_no_captured_custody _ _ _ safe).1
  refine ⟨?_, rfl, ?_⟩
  · simp only [fields, List.flatMap_append, empty, List.append_nil]
  · exact renamed_clone_empty context.source _ saved (CloneTraits.instantiation_root_safe _ _ _ _ _ original)

theorem takeCapture_valid (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after) (valid : Valid machine) :
    (fields after.1 ++ after.2.frames.flatMap frame).Perm (expected after.1.heap) := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  case oneShot saved =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨heap, retired, rfl⟩ := accepted
    obtain ⟨partition, obligations⟩ := retire_parts _ _ _ _ _ looked retired
    simpa only [object, expected, obligations] using partition.symm.trans valid
  case multiTemplate saved =>
    obtain ⟨same, obligations, empty⟩ := instantiateCapture_parts _ _ _ _ _ accepted
    simpa only [Valid, same, empty, List.append_nil, expected, obligations] using valid

theorem activated_stack_valid (machine : State) (saved : Capture) (delimiter : Activation) (reinstall : Bool)
    (valid : (fields machine ++ saved.frames.flatMap frame).Perm (expected machine.heap)) :
    Valid {machine with
      stack := saved.frames ++ (if reinstall then [.handler delimiter] else []) ++ [.restore machine.invocation machine.scope] ++ machine.stack
      scope := saved.scope
      invocation := saved.invocation} := by
  have empty : (if reinstall then [Frame.handler delimiter] else []).flatMap frame = [] := by split <;> rfl
  simp only [Valid, fields, List.flatMap_append, empty, List.flatMap_cons, frame, List.flatMap_nil,
    List.append_nil, List.nil_append, List.append_assoc]
  exact (List.perm_append_comm (l₁ := saved.frames.flatMap frame) (l₂ := fields machine)).trans valid

theorem activateCapture_valid (machine after : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment))
    (accepted : activateCapture machine context saved successor = .ok after)
    (valid : (fields machine ++ saved.frames.flatMap frame).Perm (expected machine.heap)) : Valid after := by
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
    (accepted : resumeValue machine context token argument successor = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, saved⟩, taken, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨temporary, owner⟩, reserved, store, moved, finished⟩ := accepted
  have next := activateCapture_valid _ _ _ _ _ activated (takeCapture_valid _ _ _ _ taken valid)
  exact finishTemporary_valid _ _ _ finished (move_valid _ _ _ _ moved (temporary_valid _ _ _ reserved next))

theorem resumeComputation_valid (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  exact applyClosure_valid _ _ _ _ _ applied (activateCapture_valid _ _ _ _ _ activated (takeCapture_valid _ _ _ _ captured valid))

end ObligationLocations
end BoundaryV2.Profile.Source.Machine
