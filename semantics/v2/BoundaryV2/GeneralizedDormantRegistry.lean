import BoundaryV2.GeneralizedTemplateRegistry

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

def Source.Multi.Record.image (record : Record signature algebra program) : Image signature algebra program record.shape :=
  ⟨record.saved, record.cells, record.dormant, record.attachments, record.regions, record.scopes⟩

def Target.Multi.Record.image (record : Record signature algebra program) : Image signature algebra program record.shape :=
  ⟨record.saved, record.cells, record.dormant, record.attachments, record.regions, record.scopes⟩

namespace Source.Multi

mutual
  /-- Admit and install the complete owned snapshot forest. No partial registry
  escapes if any node fails admission or would replace an existing binding. -/
  def registerRecord : Record signature algebra program → Registry signature algebra program → Option (Registry signature algebra program)
    | record@(.mk identity _ _ _ dormant _ _ _), registry =>
      (admit record.image).bind fun template =>
        (TemplateRegistry.insert identity template registry).bind (registerRecords dormant)
  def registerRecords : List (Record signature algebra program) → Registry signature algebra program → Option (Registry signature algebra program)
    | [], registry => some registry
    | first :: rest, registry => (registerRecord first registry).bind (registerRecords rest)
end

end Source.Multi

namespace Target.Multi

mutual
  def registerRecord : Record signature algebra program → Registry signature algebra program → Option (Registry signature algebra program)
    | record@(.mk identity _ _ _ dormant _ _ _), registry =>
      (admit record.image).bind fun template =>
        (TemplateRegistry.insert identity template registry).bind (registerRecords dormant)
  def registerRecords : List (Record signature algebra program) → Registry signature algebra program → Option (Registry signature algebra program)
    | [], registry => some registry
    | first :: rest, registry => (registerRecord first registry).bind (registerRecords rest)
end

end Target.Multi

namespace Defunctionalization

theorem dormant_image_corresponds (record : Source.Multi.Record signature algebra program) :
    HEq (templateRecord record).image (templateImage record.image) := by
  cases record
  simp only [templateRecord, Source.Multi.Record.image, Target.Multi.Record.image, templateImage, template_records_map]
  rfl

mutual
  theorem dormant_registration_corresponds (record : Source.Multi.Record signature algebra program)
      (registry : Source.Multi.Registry signature algebra program) :
      Target.Multi.registerRecord (templateRecord record) (templateRegistry registry) =
        (Source.Multi.registerRecord record registry).map templateRegistry := by
    cases record with
    | mk identity shape saved localCells dormant attachments regions scopes =>
      simp only [Target.Multi.registerRecord, Source.Multi.registerRecord, templateRecord,
        Target.Multi.Record.image, Source.Multi.Record.image]
      have imageEq :
          (⟨templateFuture saved, cells localCells, templateRecords dormant, attachments, regions, scopes⟩ :
            Target.Multi.Image signature algebra program shape) =
          templateImage (⟨saved, localCells, dormant, attachments, regions, scopes⟩ : Source.Multi.Image signature algebra program shape) := by
        simp only [templateImage, template_records_map]
      rw [imageEq]
      change (Target.Multi.admit (templateImage (⟨saved, localCells, dormant, attachments, regions, scopes⟩ :
        Source.Multi.Image signature algebra program shape))).bind _ = _
      rw [template_admission_corresponds]
      cases Source.Multi.admit (⟨saved, localCells, dormant, attachments, regions, scopes⟩ : Source.Multi.Image signature algebra program shape) with
      | none => rfl
      | some admitted =>
        simp only [Option.map_some, Option.bind_some, templateRegistry, TemplateRegistry.insert_map]
        cases TemplateRegistry.insert identity admitted registry with
        | none => rfl
        | some after => exact dormant_registrations_correspond dormant after
  termination_by sizeOf record
  decreasing_by all_goals (cases record <;> simp_all <;> omega)

  theorem dormant_registrations_correspond (records : List (Source.Multi.Record signature algebra program))
      (registry : Source.Multi.Registry signature algebra program) :
      Target.Multi.registerRecords (templateRecords records) (templateRegistry registry) =
        (Source.Multi.registerRecords records registry).map templateRegistry := by
    cases records with
    | nil => rfl
    | cons first rest =>
      simp only [templateRecords, Target.Multi.registerRecords, Source.Multi.registerRecords,
        dormant_registration_corresponds first registry]
      cases Source.Multi.registerRecord first registry with
      | none => rfl
      | some after => exact dormant_registrations_correspond rest after
  termination_by sizeOf records
end

end Defunctionalization

namespace Target.Multi

variable [DecidableEq (ControlShape signature)]

mutual
  theorem registerRecord_preserves_existing (record : Record signature algebra program)
      {registry after : Registry signature algebra program} {old : Template signature algebra program shape}
      (accepted : registerRecord record registry = some after)
      (present : TemplateRegistry.lookup shape identity registry = some old) :
      TemplateRegistry.lookup shape identity after = some old := by
    cases record with
    | mk name codeShape saved cells dormant attachments regions scopes =>
      obtain ⟨template, _, inserted⟩ := Option.bind_eq_some_iff.mp accepted
      obtain ⟨middle, inserted, rest⟩ := Option.bind_eq_some_iff.mp inserted
      exact registerRecords_preserves_existing dormant rest (TemplateRegistry.inserted_lookup_preserves_existing inserted present)
  termination_by sizeOf record
  decreasing_by all_goals (cases record <;> simp_all <;> omega)

  theorem registerRecords_preserves_existing (records : List (Record signature algebra program))
      {registry after : Registry signature algebra program} {old : Template signature algebra program shape}
      (accepted : registerRecords records registry = some after)
      (present : TemplateRegistry.lookup shape identity registry = some old) :
      TemplateRegistry.lookup shape identity after = some old := by
    cases records with
    | nil => cases accepted; exact present
    | cons first rest =>
      obtain ⟨middle, inserted, later⟩ := Option.bind_eq_some_iff.mp accepted
      exact registerRecords_preserves_existing rest later (registerRecord_preserves_existing first inserted present)
  termination_by sizeOf records
end

end Target.Multi

namespace Source.Multi

variable [DecidableEq (ControlShape signature)]

mutual
  theorem registerRecord_preserves_existing (record : Record signature algebra program)
      {registry after : Registry signature algebra program} {old : Template signature algebra program shape}
      (accepted : registerRecord record registry = some after)
      (present : TemplateRegistry.lookup shape identity registry = some old) :
      TemplateRegistry.lookup shape identity after = some old := by
    cases record with
    | mk name codeShape saved cells dormant attachments regions scopes =>
      obtain ⟨template, _, inserted⟩ := Option.bind_eq_some_iff.mp accepted
      obtain ⟨middle, inserted, rest⟩ := Option.bind_eq_some_iff.mp inserted
      exact registerRecords_preserves_existing dormant rest (TemplateRegistry.inserted_lookup_preserves_existing inserted present)
  termination_by sizeOf record
  decreasing_by all_goals (cases record <;> simp_all <;> omega)

  theorem registerRecords_preserves_existing (records : List (Record signature algebra program))
      {registry after : Registry signature algebra program} {old : Template signature algebra program shape}
      (accepted : registerRecords records registry = some after)
      (present : TemplateRegistry.lookup shape identity registry = some old) :
      TemplateRegistry.lookup shape identity after = some old := by
    cases records with
    | nil => cases accepted; exact present
    | cons first rest =>
      obtain ⟨middle, inserted, later⟩ := Option.bind_eq_some_iff.mp accepted
      exact registerRecords_preserves_existing rest later (registerRecord_preserves_existing first inserted present)
  termination_by sizeOf records
end

end Source.Multi
end BoundaryV2.Generalized
