import BoundaryV2.TargetEffects

namespace BoundaryV2.Profile.Target.Machine

/-- A structural path to the selected allocation. Every preceding node is an
actual frame with a different identity; the endpoint is an active attachment. -/
inductive SelectedAttachmentPath (store : Store schemas) (selected : NodeId) :
    Option NodeId → List NodeId → Prop where
  | here (handler : NodeId) (outer parent region : Option NodeId)
      (actual : store.lookup selected = some (.attachment handler outer parent .active region)) :
      SelectedAttachmentPath store selected (some selected) []
  | there (cursor : NodeId) (record : Graph.Node) (skipped : List NodeId)
      (different : cursor ≠ selected) (actual : store.lookup cursor = some record)
      (frame : Graph.isFrame record = true)
      (rest : SelectedAttachmentPath store selected (Graph.frameParent record) skipped) :
      SelectedAttachmentPath store selected (some cursor) (cursor :: skipped)

theorem selected_path_reaches_active (path : SelectedAttachmentPath store selected current skipped) :
    ∃ handler outer parent region,
      store.lookup selected = some (.attachment handler outer parent .active region) := by
  induction path with
  | here handler outer parent region actual => exact ⟨handler, outer, parent, region, actual⟩
  | there _ _ _ _ _ _ _ ih => exact ih

theorem selected_path_skips_only_other_frames
    (path : SelectedAttachmentPath store selected current skipped) :
    ∀ cursor ∈ skipped, cursor ≠ selected ∧
      ∃ record, store.lookup cursor = some record ∧ Graph.isFrame record = true := by
  induction path with
  | here => simp
  | there cursor record skipped different actual frame _ ih =>
    intro candidate member
    rcases List.mem_cons.mp member with same | later
    · subst candidate; exact ⟨different, record, actual, frame⟩
    · exact ih candidate later

theorem selected_path_unique
    (left : SelectedAttachmentPath store selected current first)
    (right : SelectedAttachmentPath store selected current second) : first = second := by
  induction left generalizing second with
  | here handler outer parent region actual =>
    cases right with
    | here => rfl
    | there _ _ _ different => exact False.elim (different rfl)
  | there cursor record skipped different actual frame _ ih =>
    cases right with
    | here => exact False.elim (different rfl)
    | there _ nextRecord nextSkipped _ nextActual _ nextPath =>
      have same : record = nextRecord := Option.some.inj (actual.symm.trans nextActual)
      subst nextRecord
      exact congrArg (cursor :: ·) (ih nextPath)

theorem selectAttachmentAt_sound (store : Store schemas) (selected : NodeId)
    (count : Nat) (current : Option NodeId)
    (accepted : selectAttachmentAt store selected count current = .ok ()) :
    ∃ skipped, skipped.length < count ∧ SelectedAttachmentPath store selected current skipped := by
  induction count generalizing current with
  | zero => simp [selectAttachmentAt] at accepted
  | succ count ih =>
    cases current with
    | none => simp [selectAttachmentAt] at accepted
    | some cursor =>
      cases actual : store.lookup cursor with
      | none => simp [selectAttachmentAt, actual, fromOption, bind, Except.bind] at accepted
      | some record =>
        by_cases same : cursor = selected
        · subst cursor
          cases record <;> simp only [selectAttachmentAt, actual, fromOption, bind, Except.bind,
            BEq.rfl, ↓reduceIte] at accepted
          all_goals try contradiction
          rename_i handler outer parent phase region
          cases phase <;> simp [require] at accepted
          exact ⟨[], Nat.zero_lt_succ _, .here handler outer parent region actual⟩
        · have different : (cursor == selected) = false := by simp [same]
          cases frame : Graph.isFrame record with
          | false => simp [selectAttachmentAt, actual, different, fromOption, require, frame, bind, Except.bind] at accepted
          | true =>
            have rest : selectAttachmentAt store selected count (Graph.frameParent record) = .ok () := by
              simpa [selectAttachmentAt, actual, different, fromOption, require, frame,
                bind, Except.bind] using accepted
            obtain ⟨skipped, shorter, path⟩ := ih _ rest
            exact ⟨cursor :: skipped, by simpa using Nat.succ_lt_succ shorter,
              .there cursor record skipped same actual frame path⟩

theorem selectAttachmentAt_complete (path : SelectedAttachmentPath store selected current skipped)
    (enough : skipped.length < count) : selectAttachmentAt store selected count current = .ok () := by
  induction path generalizing count with
  | here handler outer parent region actual =>
    cases count with
    | zero => simp at enough
    | succ count => simp [selectAttachmentAt, actual, fromOption, require, bind, Except.bind]
  | there cursor record skipped different actual frame _ ih =>
    cases count with
    | zero => simp at enough
    | succ count =>
      have shorter : skipped.length < count := by simpa using enough
      simpa [selectAttachmentAt, actual, fromOption, require, frame, different, bind, Except.bind] using ih shorter

/-- The finite walk budget measures graph links only. It neither truncates
program execution nor changes which attachment identity is selected. -/
theorem selectAttachmentAt_exact (store : Store schemas) (selected : NodeId)
    (count : Nat) (current : Option NodeId) :
    selectAttachmentAt store selected count current = .ok () ↔
      ∃ skipped, skipped.length < count ∧ SelectedAttachmentPath store selected current skipped :=
  ⟨selectAttachmentAt_sound store selected count current,
    fun ⟨_, enough, path⟩ => selectAttachmentAt_complete path enough⟩

theorem selection_budget_extension (accepted : selectAttachmentAt store selected count current = .ok ())
    (larger : count ≤ next) : selectAttachmentAt store selected next current = .ok () := by
  obtain ⟨skipped, enough, path⟩ := selectAttachmentAt_sound _ _ _ _ accepted
  exact selectAttachmentAt_complete path (Nat.lt_of_lt_of_le enough larger)

private theorem bind_success (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) (accepted : value.bind next = .ok result) :
    ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value with
  | error error => cases accepted
  | ok input => exact ⟨input, rfl, accepted⟩

/-- Handled execution cannot bypass selection: its capability names an active
attachment on the actual dynamic parent chain, including non-tail frames. -/
theorem handled_perform_selects_actual_attachment (context : Context)
    (state : State context.program) (control : Graph.Control)
    (operation : Perform) (values : List Graph.Value) (after : State context.program)
    (accepted : performHandled context state control operation values = .ok after) :
    ∃ selectedSlot capability selected skipped,
      operation.capability = some selectedSlot ∧
      slot values selectedSlot = .ok capability ∧
      valueReference capability = .ok selected ∧
      skipped.length < state.store.nodes.length + 1 ∧
      SelectedAttachmentPath state.store selected control.parent skipped := by
  unfold performHandled at accepted
  obtain ⟨selectedSlot, slotAt, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨capability, capabilityAt, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨selected, selectedAt, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨checked, selectedPath, _⟩ := bind_success _ _ _ accepted
  cases checked
  obtain ⟨skipped, bound, path⟩ := selectAttachmentAt_sound _ _ _ _ selectedPath
  refine ⟨selectedSlot, capability, selected, skipped, ?_, capabilityAt, selectedAt, bound, path⟩
  cases optionAt : operation.capability <;> simp_all [fromOption]

end BoundaryV2.Profile.Target.Machine
