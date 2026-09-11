import BoundaryV2.SourceEffects

namespace BoundaryV2.Profile.Source.Machine

/-- Selection names the actual dynamic attachment, and no earlier handler
frame carries that identity. Labels and catalog identities play no role. -/
theorem selected_attachment_is_first (identity : AttachmentId) (frames : List Frame)
    (selected : Selection) (found : selectAttachment identity frames = some selected) :
    selected.activation.identity = identity ∧ identity ∉ activeAttachments selected.inside := by
  induction frames generalizing selected with
  | nil => simp [selectAttachment] at found
  | cons frame tail ih =>
    cases frame <;> simp only [selectAttachment] at found
    all_goals first
      | (split at found
         · rename_i same
           cases found
           exact ⟨(beq_iff_eq.mp same).symm, by simp [activeAttachments]⟩
         · rename_i different
           obtain ⟨next, nextFound, rfl⟩ := Option.map_eq_some_iff.mp found
           have nextFirst := ih next nextFound
           refine ⟨nextFirst.1, ?_⟩
           simpa [activeAttachments] using And.intro (by simpa using different) nextFirst.2)
      | (obtain ⟨next, nextFound, rfl⟩ := Option.map_eq_some_iff.mp found
         have nextFirst := ih next nextFound
         exact ⟨nextFirst.1, by simpa [activeAttachments] using nextFirst.2⟩)

theorem source_selection_absent (identity : AttachmentId) (frames : List Frame) :
    selectAttachment identity frames = none ↔ identity ∉ activeAttachments frames := by
  induction frames with
  | nil => simp [selectAttachment, activeAttachments]
  | cons frame tail ih =>
    cases frame
    case handler activation =>
      by_cases same : identity = activation.identity
      · simp [selectAttachment, same, activeAttachments]
      · simpa [selectAttachment, same, activeAttachments] using ih
    all_goals simpa [selectAttachment, activeAttachments] using ih

theorem source_selection_skips_prefix (identity : AttachmentId) (before after : List Frame)
    (absent : identity ∉ activeAttachments before) :
    selectAttachment identity (before ++ after) =
      (selectAttachment identity after).map (fun selected => { selected with inside := before ++ selected.inside }) := by
  induction before with
  | nil => simp
  | cons frame tail ih =>
    cases frame
    case handler activation =>
      have both : identity ≠ activation.identity ∧ identity ∉ activeAttachments tail := by
        simpa [activeAttachments] using absent
      simp only [List.cons_append, selectAttachment, show (identity == activation.identity) = false by simp [both.1],
        Bool.false_eq_true, ↓reduceIte]
      rw [ih both.2]
      cases selectAttachment identity after <;> rfl
    all_goals
      have tailAbsent : identity ∉ activeAttachments tail := by simpa [activeAttachments] using absent
      simp only [List.cons_append, selectAttachment]
      rw [ih tailAbsent]
      cases selectAttachment identity after <;> rfl

theorem source_selection_complete (identity : AttachmentId) (selected : Selection)
    (sameIdentity : selected.activation.identity = identity)
    (first : identity ∉ activeAttachments selected.inside) :
    selectAttachment identity (selected.inside ++ .handler selected.activation :: selected.outside) = some selected := by
  rw [source_selection_skips_prefix _ _ _ first]
  simp only [selectAttachment, sameIdentity, BEq.rfl, ↓reduceIte, Option.map_some, List.append_nil]

theorem source_selection_exact (identity : AttachmentId) (frames : List Frame) (selected : Selection) :
    selectAttachment identity frames = some selected ↔
      frames = selected.inside ++ .handler selected.activation :: selected.outside ∧
      selected.activation.identity = identity ∧ identity ∉ activeAttachments selected.inside := by
  constructor
  · intro found
    exact ⟨selection_reconstructs _ _ _ found, selected_attachment_is_first _ _ _ found⟩
  · rintro ⟨rfl, sameIdentity, first⟩
    exact source_selection_complete _ _ sameIdentity first

private theorem bind_success (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) (accepted : value.bind next = .ok result) :
    ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value with
  | error error => cases accepted
  | ok input => exact ⟨input, rfl, accepted⟩

/-- An explicit source capability selects the first frame carrying its actual
allocation identity, after checking that its effect contract is the requested one. -/
theorem handled_source_request_selects_actual_attachment (state : State) (context : Context)
    (operation : Operation) (operands : List Located) (capability : Located)
    (transition : Transition)
    (supplied : (if operation.capability.isSome then operands.head? else none) = some capability)
    (accepted : openRequest state context operation operands = .ok transition) :
    ∃ reference identity nominal selected,
      lookupObject state capability = .ok (reference, .capability identity nominal) ∧
      nominal = operation.effect ∧ selectAttachment identity state.stack = some selected ∧
      state.stack = selected.inside ++ .handler selected.activation :: selected.outside ∧
      selected.activation.identity = identity ∧ identity ∉ activeAttachments selected.inside := by
  unfold openRequest at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  simp only [supplied] at accepted
  obtain ⟨⟨reference, object⟩, actual, accepted⟩ := bind_success _ _ _ accepted
  cases object <;> try contradiction
  rename_i identity nominal
  obtain ⟨_, nominalAt, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨selected, selectedAt, _⟩ := bind_success _ _ _ accepted
  have same : nominal = operation.effect := by
    unfold require at nominalAt
    split at nominalAt
    · exact beq_iff_eq.mp (by assumption)
    · cases nominalAt
  have selectedAt : selectAttachment identity state.stack = some selected := by
    cases found : selectAttachment identity state.stack with
    | none => simp only [fromOption, found] at selectedAt; cases selectedAt
    | some chosen =>
      simp only [fromOption, found] at selectedAt
      cases selectedAt
      rfl
  exact ⟨reference, identity, nominal, selected, actual, same, selectedAt,
    source_selection_exact _ _ _ |>.mp selectedAt⟩

end BoundaryV2.Profile.Source.Machine
