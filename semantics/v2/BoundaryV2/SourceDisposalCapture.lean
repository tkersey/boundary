import BoundaryV2.SourceDisposalShape

namespace BoundaryV2.Profile.Source.Machine
namespace DisposalShape
open DisposalProgress

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem invokeFunction_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after)
    (valid : Valid machine) : Valid after.state := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have shape := createScope_valid _ _ _ _ _ _ _ _ _ scopeOk valid
  exact ⟨by simp [control], by simpa [frame] using valid.2.1, shape.2.2⟩

theorem applyClosure_valid (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, retired, accepted⟩ := accepted
    exact invokeFunction_valid _ _ _ _ _ _ accepted ⟨valid.1, valid.2.1, retire_valid _ _ _ retired valid.2.2⟩
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_valid _ _ _ _ _ _ accepted valid

theorem object_renamed_valid (mapping : Renaming) (stored : Object)
    (valid : ∀ value ∈ object stored, Leaf value) : ∀ value ∈ object (renameObject mapping stored), Leaf value := by
  rw [object_rename]
  intro value member
  obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
  exact rename_leaf _ _ (valid original originalMember)

theorem frames_renamed_valid (mapping : Renaming) (frames : List Frame)
    (valid : ∀ value ∈ frames.flatMap frame, Leaf value) :
    ∀ value ∈ (frames.map (renameFrame mapping)).flatMap frame, Leaf value := by
  simp only [List.flatMap_map, frame_rename, ← List.map_flatMap]
  intro value member
  obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
  exact rename_leaf _ _ (valid original originalMember)

private theorem mapM_preserves (function : α → Except Invalid β) (property : β → Prop)
    (preserves : ∀ input output, function input = .ok output → property output)
    (inputs : List α) (outputs : List β) (accepted : inputs.mapM function = .ok outputs) :
    ∀ output ∈ outputs, property output := by
  induction inputs generalizing outputs with
  | nil => cases accepted; simp
  | cons head tail induction =>
    simp only [List.mapM_cons, bind, except_bind_ok] at accepted
    obtain ⟨first, firstAt, rest, restAt, accepted⟩ := accepted
    cases accepted
    exact fun value member => (List.mem_cons.mp member).elim
      (fun equal => equal ▸ preserves head first firstAt) (induction rest restAt value)

theorem instantiateCapture_valid (machine : State) (context : Context) (saved : Capture)
    (after : State × Capture) (accepted : instantiateCapture machine context saved = .ok after)
    (valid : Valid machine) (captureValid : ∀ value ∈ saved.frames.flatMap frame, Leaf value) :
    Valid after.1 ∧ ∀ value ∈ after.2.frames.flatMap frame, Leaf value := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨objects, objectsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  have objectsTyped : ∀ entry ∈ objects, ∀ value ∈ entry.toList.flatMap object, Leaf value := by
    refine mapM_preserves _ (fun entry : Option Object => ∀ value ∈ entry.toList.flatMap object, Leaf value) ?_ _ _ objectsAt
    intro input output checked
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨stored, looked, rfl⟩ := checked
    simp only [Option.toList_some, List.flatMap_singleton]
    apply object_renamed_valid
    have storedTyped := heap_lookup _ _ _ looked valid.2.2
    cases stored <;> first | exact storedTyped | simp [object]
  refine ⟨⟨valid.1, valid.2.1, ?_⟩, frames_renamed_valid _ _ captureValid⟩
  simp only [HeapValid, List.mem_append]
  intro entry member
  exact member.elim (valid.2.2 entry) (objectsTyped entry)

theorem takeCapture_valid (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after) (valid : Valid machine) :
    Valid after.1 ∧ ∀ value ∈ after.2.frames.flatMap frame, Leaf value := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  have storedTyped := lookupObject_valid _ _ _ _ looked valid.2.2
  cases stored <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨store, retired, rfl⟩ := accepted
    exact ⟨⟨valid.1, valid.2.1, retire_valid _ _ _ retired valid.2.2⟩, storedTyped⟩
  · exact instantiateCapture_valid _ _ _ _ accepted valid storedTyped

theorem activateCapture_valid (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture machine context saved successor = .ok after) (valid : Valid machine)
    (captureValid : ∀ value ∈ saved.frames.flatMap frame, Leaf value) : Valid after := by
  simp only [activateCapture, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none =>
    simp only [Option.isSome_none, Bool.false_or, pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    split
    all_goals refine ⟨valid.1, ?_, valid.2.2⟩
    all_goals simpa only [List.flatMap_append, List.flatMap_cons, List.flatMap_nil, frame,
      List.nil_append, List.append_nil, List.mem_append, forall_eq_or_imp] using
      List.forall_mem_append.mpr ⟨captureValid, valid.2.1⟩
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    refine ⟨valid.1, ?_, valid.2.2⟩
    simpa only [Option.isSome_some, Bool.true_or, if_true, List.flatMap_append, List.flatMap_cons,
      List.flatMap_nil, frame, List.nil_append, List.append_nil] using
      List.forall_mem_append.mpr ⟨captureValid, valid.2.1⟩

theorem resumeValue_valid (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have capturedValid := takeCapture_valid _ _ _ _ captured valid
  have activeValid := activateCapture_valid _ _ _ _ _ activated capturedValid.1 capturedValid.2
  have middleValid := temporary_valid _ _ _ temporaryOk activeValid
  exact finishTemporary_valid _ _ _ finished ⟨middleValid.1, middleValid.2.1, move_valid _ _ _ _ moved middleValid.2.2⟩

theorem resumeComputation_valid (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have capturedValid := takeCapture_valid _ _ _ _ captured valid
  have activeValid := activateCapture_valid _ _ _ _ _ activated capturedValid.1 capturedValid.2
  exact applyClosure_valid _ _ _ _ _ applied activeValid

private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons first rest induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, accepted⟩ := accepted
    exact induction middle accepted (preserved before first middle stepped holds)

theorem installHandler_valid (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after)
    (valid : Valid machine) : Valid after.state := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  let property (pair : Heap × List Located) : Prop := HeapValid pair.1
  have seed : property ({ machine.heap with nextAttachment := machine.heap.nextAttachment + 1 }, []) := valid.2.2
  have allValid := foldlM_preserves _ _ property (by
    intro before item after stepOk beforeTyped
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at stepOk
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := stepOk
    exact allocate_valid _ _ _ _ _ _ _ allocated beforeTyped (by simp [object])) _ _ allocated seed
  apply applyClosure_valid _ _ _ _ _ applied
  exact ⟨valid.1, by simpa [frame] using valid.2.1, allValid⟩

theorem enterRegion_valid (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, ⟨store, value⟩, allocated, applied⟩ := accepted
  have allocatedTyped := allocate_valid { machine.heap with nextRegion := machine.heap.nextRegion + 1 }
    _ _ _ _ _ _ allocated valid.2.2 (by simp [object])
  apply applyClosure_valid _ _ _ _ _ applied
  exact ⟨valid.1, by simpa [frame] using valid.2.1, allocatedTyped⟩

theorem frame_trim (context : Context) (saved : Frame) : frame (trimFrame context saved) = frame saved := by
  cases saved <;> rfl

theorem openRequest_valid (machine : State) (context : Context) (operation : Operation) (operands : List Located)
    (after : Transition) (accepted : openRequest machine context operation operands = .ok after) (valid : Valid machine) :
    Valid after.state := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact valid
  · simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i identity nominal lookup
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, selected, selectedAt, _, _, clause, _, accepted⟩ := accepted
    have reconstructed := selection_reconstructs identity machine.stack selected selectedAt
    have outsideValid : ∀ value ∈ selected.outside.flatMap frame, Leaf value := by
      intro value member
      apply valid.2.1
      simp [reconstructed, List.flatMap_append, member, frame]
    have insideValid : ∀ value ∈ selected.inside.flatMap frame, Leaf value := by
      intro value member
      apply valid.2.1
      simp [reconstructed, List.flatMap_append, member, frame]
    have framesValid : ∀ value ∈ (selected.inside.map (trimFrame context)).flatMap frame, Leaf value := by
      simpa only [List.flatMap_map, frame_trim] using insideValid
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_valid _ _ _ _ _ _ invoked valid
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, shapeAt, accepted⟩ := accepted
      split at accepted <;> try contradiction
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved : moveValues machine.heap (_ :: _) (Custody.Owner.receiver ⟨machine.heap.nextInvocation⟩) = some store :=
        (fromOption_ok _ _ _).mp moved
      have storeValid := move_valid _ _ _ _ moved valid.2.2
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, temporaryOk, ⟨finalStore, token⟩, allocated, staged, stagedOk, invoked⟩ := accepted
        have outsideValid := temporary_valid _ _ _ temporaryOk (show Valid _ from ⟨valid.1, outsideValid, storeValid⟩)
        have allocatedValid := allocate_valid _ _ _ _ _ _ _ allocated outsideValid.2.2 (by
          try split
          all_goals exact framesValid)
        have stagedValid := finishTemporary_valid _ _ _ stagedOk (show Valid { outside with heap := finalStore } from
          ⟨outsideValid.1, outsideValid.2.1, allocatedValid⟩)
        exact invokeFunction_valid _ _ _ _ _ _ invoked stagedValid

theorem executeEffectTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_valid _ _ _ _ _ accepted valid
  all_goals split at accepted <;> try contradiction
  all_goals first
    | exact installHandler_valid _ _ _ _ _ _ _ _ accepted valid
    | exact resumeValue_valid _ _ _ _ _ _ accepted valid
    | exact resumeComputation_valid _ _ _ _ _ accepted valid
    | exact enterRegion_valid _ _ _ _ _ _ accepted valid

theorem installProtection_valid (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after)
    (valid : Valid machine) : Valid after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨bodyType, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  have movedValid := move_valid _ _ _ _ moved valid.2.2
  let record : Cleanup.Obligation .source := ⟨⟨machine.heap.nextObligation⟩, machine.scope, machine.heap.nextObligation,
    cleanup.value, resource.map Located.value, .pending⟩
  let heap := { store with obligations := store.obligations ++ [record], nextObligation := store.nextObligation + 1 }
  have heapValid : HeapValid heap := movedValid
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    apply applyClosure_valid _ _ _ _ _ accepted
    exact ⟨valid.1, by simpa [frame] using valid.2.1, heapValid⟩
  | some resourceValue =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      have allocatedValid := allocate_valid
        { heap with nextRegion := heap.nextRegion + 1, loans := heap.loans ++ [(⟨heap.nextRegion⟩, ⟨machine.heap.nextObligation⟩)] }
        _ _ _ _ _ _ allocated heapValid (by simp [object])
      apply applyClosure_valid _ _ _ _ _ applied
      exact ⟨valid.1, by simpa [frame] using valid.2.1, allocatedValid⟩

theorem beginCleanup_valid (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after)
    (valid : Valid machine) (tailValid : ∀ value ∈ tail.flatMap frame, Leaf value) : Valid after.state := by
  simp only [beginCleanup, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, ⟨_, _⟩, _, _, _, _, _, _, _, transition, applied, rfl⟩ := accepted
  apply applyClosure_valid _ _ _ _ _ applied
  exact ⟨valid.1, by simpa [frame] using tailValid, valid.2.2⟩

end DisposalShape
end BoundaryV2.Profile.Source.Machine
