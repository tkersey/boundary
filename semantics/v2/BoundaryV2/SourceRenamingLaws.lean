import BoundaryV2.SourceActivationLaws

namespace BoundaryV2.Profile.Source.Machine

def renameSelection (mapping : Renaming) (selection : Selection) : Selection :=
  ⟨selection.inside.map (renameFrame mapping), renameActivation mapping selection.activation,
    selection.outside.map (renameFrame mapping)⟩

/-- The required separation concerns the requested identity and the actual
active delimiters. Ambient identities need not select any delimiter. -/
theorem selection_rename (mapping : Renaming) (identity : AttachmentId) (frames : List Frame)
    (separated : ∀ active ∈ activeAttachments frames,
      renamed mapping.attachments identity = renamed mapping.attachments active ↔ identity = active) :
    selectAttachment (renamed mapping.attachments identity) (frames.map (renameFrame mapping)) =
      (selectAttachment identity frames).map (renameSelection mapping) := by
  induction frames with
  | nil => rfl
  | cons frame tail induction =>
    have tailSeparated : ∀ active ∈ activeAttachments tail,
        renamed mapping.attachments identity = renamed mapping.attachments active ↔ identity = active := by
      intro active member
      exact separated active (by cases frame <;> simp_all [activeAttachments])
    have rest := induction tailSeparated
    cases frame <;> simp only [List.map_cons, renameFrame, selectAttachment]
    all_goals first
      | (rename_i activation
         have same := separated activation.identity (by simp [activeAttachments])
         have compared : (renamed mapping.attachments identity ==
             (renameActivation mapping activation).identity) = (identity == activation.identity) := by
           simp only [renameActivation]
           exact Bool.eq_iff_iff.mpr (by simpa using same)
         rw [compared]
         split
         · rfl
         · rw [rest]; cases selectAttachment identity tail <;> rfl)
      | (rw [rest]; cases selectAttachment identity tail <;> rfl)

/-- Concrete allocation preserves distinction both within its captured binder
set and across the boundary to every old outside identity. -/
theorem fresh_map_injective_on_local_and_old (space : Space) (domain : Domain) (start : Nat)
    (locals : List (Ref space domain)) (left right : Ref space domain)
    (leftSupported : left ∈ locals ∨ left.value < start)
    (rightSupported : right ∈ locals ∨ right.value < start) :
    renamed (freshMap space domain start locals) left = renamed (freshMap space domain start locals) right ↔
      left = right := by
  constructor
  · intro equal
    by_cases leftLocal : left ∈ locals
    · by_cases rightLocal : right ∈ locals
      · exact source_activation_injective _ _ _ _ _ _ leftLocal rightLocal equal
      · have old := rightSupported.resolve_left rightLocal
        rw [renamed_outside_fresh_map _ _ _ _ _ rightLocal] at equal
        exact False.elim (source_activation_avoids_old_identities _ _ _ _ _ _ leftLocal old equal)
    · rw [renamed_outside_fresh_map _ _ _ _ _ leftLocal] at equal
      by_cases rightLocal : right ∈ locals
      · have old := leftSupported.resolve_left leftLocal
        exact False.elim (source_activation_avoids_old_identities _ _ _ _ _ _ rightLocal old equal.symm)
      · simpa only [renamed_outside_fresh_map _ _ _ _ _ rightLocal] using equal
  · intro equal
    exact congrArg _ equal

theorem selection_fresh_activation (mapping : Renaming) (start : Nat) (locals : List AttachmentId)
    (identity : AttachmentId) (frames : List Frame)
    (allocated : mapping.attachments = freshMap .runtime .attachment start locals)
    (requestSupported : identity ∈ locals ∨ identity.value < start)
    (activeSupported : ∀ active ∈ activeAttachments frames, active ∈ locals ∨ active.value < start) :
    selectAttachment (renamed mapping.attachments identity) (frames.map (renameFrame mapping)) =
      (selectAttachment identity frames).map (renameSelection mapping) := by
  apply selection_rename
  intro active member
  rw [allocated]
  exact fresh_map_injective_on_local_and_old _ _ _ _ _ _ requestSupported (activeSupported active member)

private theorem bind_success (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) (accepted : value.bind next = .ok result) :
    ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value with
  | error error => cases accepted
  | ok input => exact ⟨input, rfl, accepted⟩

/-- The commuting square uses the allocation and rewritten capture returned
by the actual instantiator, including its recursively discovered dormant
templates. A requested ambient identity may remain residual on both sides. -/
theorem instantiation_selection_commutes (state after : State) (context : Context)
    (capture instantiated : Capture) (identity : AttachmentId)
    (accepted : instantiateCapture state context capture = .ok (after, instantiated)) :
    let dormant := (cloneSupport state.heap capture).filterMap (fun node => match state.heap.lookup node with
      | some (.multiTemplate inner) => some inner | _ => none)
    let locals := (capture.delimiter.identity :: activeAttachments capture.frames ++
      dormant.flatMap (fun inner => inner.delimiter.identity :: activeAttachments inner.frames)).eraseDups
    identity ∈ locals ∨ identity.value < state.heap.nextAttachment →
      ∃ mapping : Renaming,
        mapping.attachments = freshMap .runtime .attachment state.heap.nextAttachment locals ∧
        instantiated = renameCapture mapping capture ∧
        after.heap.nextAttachment = state.heap.nextAttachment + locals.length ∧
        selectAttachment (renamed mapping.attachments identity) instantiated.frames =
          (selectAttachment identity capture.frames).map (renameSelection mapping) := by
  dsimp only
  intro requestSupported
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  cases accepted
  refine ⟨_, rfl, rfl, rfl, ?_⟩
  apply selection_fresh_activation _ _ _ _ _ rfl requestSupported
  intro active member
  exact Or.inl (by simp [member])

end BoundaryV2.Profile.Source.Machine
