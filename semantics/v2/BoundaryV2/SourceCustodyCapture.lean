import BoundaryV2.SourceCustodyStorage

namespace BoundaryV2.Profile.Source.Machine
namespace CustodyCoverage

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem instantiateCapture_valid (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated)) (valid : Valid machine) :
    Valid after := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  apply Covered.mono _ _ _ valid
  intro field member
  simp only [fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.heapFields,
    List.flatMap_append, List.mem_append] at member ⊢
  grind only []

theorem takeCapture_covered (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after) (valid : Valid machine) :
    Covered after.1.heap.custody (fields after.1 ++ after.2.frames.flatMap QueueCustody.frameFields) := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  case oneShot saved =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨heap, retired, rfl⟩ := accepted
    have next := retireObject_covered machine heap token node _ [] looked retired (by simpa [Valid] using valid)
    simpa only [OwningFields.object, List.nil_append, List.append_nil,
      QueueCustody.objectFields, DisposalShape.object, QueueCustody.capture_fields] using next
  case multiTemplate saved =>
    exact Covered.mono _ _ _ (instantiateCapture_valid _ _ _ _ _ accepted valid)
      (fun _ member => List.mem_append_left _ member)

theorem activated_stack_valid (machine : State) (saved : Capture) (delimiter : Activation) (reinstall : Bool)
    (valid : Covered machine.heap.custody (fields machine ++ saved.frames.flatMap QueueCustody.frameFields)) :
    Valid {machine with
      stack := saved.frames ++ (if reinstall then [.handler delimiter] else []) ++ [.restore machine.invocation machine.scope] ++ machine.stack
      scope := saved.scope
      invocation := saved.invocation} := by
  apply Covered.mono _ _ _ valid
  intro field member
  simp only [fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.heapFields,
    List.flatMap_append, List.mem_append] at member ⊢
  grind only []

theorem activateCapture_valid (machine after : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment))
    (accepted : activateCapture machine context saved successor = .ok after)
    (valid : Covered machine.heap.custody (fields machine ++ saved.frames.flatMap QueueCustody.frameFields)) : Valid after := by
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

theorem takeCapture_control (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after) : after.1.control = machine.control := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨_, stored⟩, _, accepted⟩ := accepted
  cases stored <;> try contradiction
  case oneShot saved =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    rfl
  case multiTemplate saved =>
    have shape := (OwnerLocations.instantiation_shape _ _ _ _ _ accepted).1
    rw [shape]

theorem activateCapture_control (machine after : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment))
    (accepted : activateCapture machine context saved successor = .ok after) : after.control = machine.control := by
  simp only [activateCapture, bind, except_bind_ok, pure, Except.pure] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none => cases accepted; rfl
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    rfl

theorem resumeValue_valid (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, saved⟩, taken, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨temporary, owner⟩, reserved, store, moved, finished⟩ := accepted
  have captured := takeCapture_covered _ _ _ _ taken valid
  have next := activateCapture_valid _ _ _ _ _ activated captured
  have temporaryCover := temporary_covered active temporary owner [] reserved (by simpa [Valid] using next)
  have movedCover := moveValues_covered _ _ _ _ _ moved (by simpa using temporaryCover)
  rw [← move_fields _ _ _ _ moved] at movedCover
  have done := finishTemporary_covered _ _ [] _ finished (by
      rw [temporary_control _ _ _ reserved, activateCapture_control _ _ _ _ _ activated,
        takeCapture_control _ _ _ _ taken]
      exact empty) (by simpa using movedCover)
  simpa only [Valid, List.append_nil] using done

theorem resumeComputation_valid (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = [])
    (contracts : ClosureContracts.Valid context machine.heap.objects) : Valid after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have next := activateCapture_valid _ _ _ _ _ activated (takeCapture_covered _ _ _ _ captured valid)
  apply applyClosure_valid _ _ _ _ _ applied next ?_ ?_
  · rw [activateCapture_control _ _ _ _ _ activated, takeCapture_control _ _ _ _ captured]
    exact empty
  · exact ClosureContracts.activateCapture_valid _ _ _ _ _ activated
      (ClosureContracts.takeCapture_valid _ _ _ _ captured contracts)

end CustodyCoverage
end BoundaryV2.Profile.Source.Machine
