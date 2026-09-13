import BoundaryV2.GeneralizedCaptureDescription

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

namespace Source.Multi

/-- The description retains the authored origin of the actual callback future. -/
structure Future (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) where
  attachment : Id .attachment
  capture : Capture signature algebra program shape.input shape.answer

def Future.payload (future : Future signature algebra program shape) : ControlPayload signature algebra program shape :=
  ⟨future.attachment, future.capture.future⟩

def Future.references (future : Future signature algebra program shape) : List Reference :=
  .name .attachment future.attachment :: future.capture.references

mutual
  structure Record (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (program : List (BodyType signature.Data signature.Effect)) where
    identity : Id .control
    shape : ControlShape signature
    saved : Future signature algebra program shape
    cells : Cells signature algebra (Computation signature algebra program) := []
    dormant : List (Record signature algebra program) := []
    attachments : List (Id .attachment) := []
    regions : List (Id .region) := []
    scopes : List (Id .scope) := []
end

def Record.bare (identity : Id .control) (shape : ControlShape signature)
    (saved : Future signature algebra program shape) : Record signature algebra program := { identity, shape, saved }

mutual
  def Record.references : Record signature algebra program → List Reference
    | .mk identity _ saved cells dormant attachments regions scopes =>
      .name .control identity :: (saved.references ++ cellsReferences cells ++ recordsReferences dormant ++
        attachments.map (.name .attachment) ++ regions.map (.name .region) ++ scopes.map (.name .scope))
  def recordsReferences : List (Record signature algebra program) → List Reference
    | [] => []
    | first :: rest => first.references ++ recordsReferences rest
end

mutual
  def Record.copyable : Record signature algebra program → Bool
    | .mk _ _ saved cells dormant _ _ _ =>
      saved.capture.copyable && cells.all (fun cell => cell.value.copyable) && recordsCopyable dormant
  def recordsCopyable : List (Record signature algebra program) → Bool
    | [] => true
    | first :: rest => first.copyable && recordsCopyable rest
end

mutual
  def Record.locals : Record signature algebra program → (domain : Domain) → List (Id domain)
    | .mk identity _ _ cells dormant attachments regions scopes, domain =>
      (match domain with
        | .attachment => attachments
        | .region => regions
        | .scope => scopes
        | .cell => Cells.identities cells
        | .control => [identity]
        | .resource | .custody | .occurrence | .obligation => []) ++ recordsLocals dormant domain
  def recordsLocals (records : List (Record signature algebra program)) (domain : Domain) : List (Id domain) :=
    match records with
    | [] => []
    | first :: rest => first.locals domain ++ recordsLocals rest domain
end

structure Image (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) where
  saved : Future signature algebra program shape
  cells : Cells signature algebra (Computation signature algebra program)
  dormant : List (Record signature algebra program)
  attachments : List (Id .attachment)
  regions : List (Id .region)
  scopes : List (Id .scope)

def Image.references (image : Image signature algebra program shape) : List Reference :=
  image.saved.references ++ cellsReferences image.cells ++ image.dormant.flatMap Record.references ++
    image.attachments.map (.name .attachment) ++ image.regions.map (.name .region) ++ image.scopes.map (.name .scope)

/-- Admission inspects source bodies, captured values, and live obligations.
It is independent of the compiled image and its admission predicate. -/
def Image.copyable (image : Image signature algebra program shape) : Bool :=
  image.saved.capture.copyable && image.cells.all (fun cell => cell.value.copyable) &&
    recordsCopyable image.dormant &&
    (referenceNames image.references .custody).isEmpty &&
    (referenceNames image.references .obligation).isEmpty

structure Template (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) where
  image : Image signature algebra program shape
  copyable : image.copyable = true

def admit (image : Image signature algebra program shape) : Option (Template signature algebra program shape) :=
  if allowed : image.copyable = true then some ⟨image, allowed⟩ else none

structure Arena (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) where
  cells : Cells signature algebra (Computation signature algebra program)
  dormant : List (Record signature algebra program)
  active : List (Sigma (Future signature algebra program))

def partitionImage (partition : Target.Multi.Partition) (saved : Future signature algebra program shape)
    (arena : Arena signature algebra program) : Image signature algebra program shape :=
  ⟨saved, arena.cells.filter (fun cell => partition.regions.contains cell.region),
    arena.dormant.filter (fun record => partition.dormant.contains record.identity),
    partition.attachments, partition.regions, partition.scopes⟩

def remainingArena (partition : Target.Multi.Partition) (arena : Arena signature algebra program) : Arena signature algebra program :=
  { arena with
    cells := arena.cells.filter (fun cell => !partition.regions.contains cell.region)
    dormant := arena.dormant.filter (fun record => !partition.dormant.contains record.identity) }

end Source.Multi

namespace Defunctionalization

def templateFuture (source : Source.Multi.Future signature algebra program shape) : Target.ControlPayload signature algebra program shape :=
  ⟨source.attachment, capture source.capture⟩

mutual
  def templateRecord : Source.Multi.Record signature algebra program → Target.Multi.Record signature algebra program
    | .mk identity shape saved localCells dormant attachments regions scopes =>
      ⟨identity, shape, templateFuture saved, cells localCells, templateRecords dormant, attachments, regions, scopes⟩
  def templateRecords : List (Source.Multi.Record signature algebra program) → List (Target.Multi.Record signature algebra program)
    | [] => []
    | first :: rest => templateRecord first :: templateRecords rest
end

theorem template_records_map (records : List (Source.Multi.Record signature algebra program)) :
    templateRecords records = records.map templateRecord := by
  induction records with
  | nil => rfl
  | cons first rest induction => exact congrArg (templateRecord first :: ·) induction

theorem template_record_identity (record : Source.Multi.Record signature algebra program) :
    (templateRecord record).identity = record.identity := by cases record; rfl

def templateImage (source : Source.Multi.Image signature algebra program shape) : Target.Multi.Image signature algebra program shape :=
  ⟨templateFuture source.saved, cells source.cells, source.dormant.map templateRecord,
    source.attachments, source.regions, source.scopes⟩

def templateArena (source : Source.Multi.Arena signature algebra program) : Target.Multi.Arena signature algebra program :=
  ⟨cells source.cells, source.dormant.map templateRecord, source.active.map (fun future => ⟨future.fst, templateFuture future.snd⟩)⟩

theorem template_future_correspondence (source : Source.Multi.Future signature algebra program shape) :
    controlPayloadRelated shape source.payload (templateFuture source) :=
  ⟨rfl, capture_correspondence source.capture⟩

mutual
  theorem template_record_references (source : Source.Multi.Record signature algebra program) :
      (templateRecord source).references = source.references := by
    cases source with
    | mk identity shape saved localCells dormant attachments regions scopes =>
      simp only [templateRecord, Target.Multi.Record.references, Target.Multi.payloadReferences,
        templateFuture, capture_references, Source.Multi.Record.references, Source.Multi.Future.references,
        cell_installation_support, template_records_references dormant]
  termination_by sizeOf source
  decreasing_by cases source; simp_all; omega

  theorem template_records_references (records : List (Source.Multi.Record signature algebra program)) :
      Target.Multi.recordsReferences (templateRecords records) = Source.Multi.recordsReferences records := by
    cases records with
    | nil => rfl
    | cons first rest => simp only [templateRecords, Target.Multi.recordsReferences, Source.Multi.recordsReferences,
        template_record_references first, template_records_references rest]
  termination_by sizeOf records
end

mutual
  theorem template_record_copyable (source : Source.Multi.Record signature algebra program) :
      (templateRecord source).copyable = source.copyable := by
    cases source with
    | mk identity shape saved localCells dormant attachments regions scopes =>
      simp only [templateRecord, Target.Multi.Record.copyable, Source.Multi.Record.copyable,
        templateFuture, capture_copyability, cells, Cells.mapBodies, List.all_map, Cell.map,
        Value.copyable_map, template_records_copyable dormant, Function.comp_def]
  termination_by sizeOf source
  decreasing_by cases source; simp_all; omega

  theorem template_records_copyable (records : List (Source.Multi.Record signature algebra program)) :
      Target.Multi.recordsCopyable (templateRecords records) = Source.Multi.recordsCopyable records := by
    cases records with
    | nil => rfl
    | cons first rest => simp only [templateRecords, Target.Multi.recordsCopyable, Source.Multi.recordsCopyable,
        template_record_copyable first, template_records_copyable rest]
  termination_by sizeOf records
end

theorem template_image_references (source : Source.Multi.Image signature algebra program shape) :
    (templateImage source).references = source.references := by
  simp only [templateImage, Target.Multi.Image.references, Target.Multi.payloadReferences,
    templateFuture, capture_references, cell_installation_support, List.flatMap_map,
    template_record_references, Source.Multi.Image.references, Source.Multi.Future.references]

theorem template_copyability (source : Source.Multi.Image signature algebra program shape) :
    (templateImage source).copyable = source.copyable := by
  unfold Target.Multi.Image.copyable Source.Multi.Image.copyable
  rw [template_image_references]
  simp only [templateImage, templateFuture, capture_copyability, cells, Cells.mapBodies, List.all_map,
    Cell.map, Value.copyable_map, ← template_records_map, template_records_copyable, Function.comp_def]

def template (source : Source.Multi.Template signature algebra program shape) : Target.Multi.Template signature algebra program shape :=
  ⟨templateImage source.image, (template_copyability source.image).trans source.copyable⟩

/-- Source admission and target admission have exactly the same outcomes. -/
theorem template_admission_corresponds (source : Source.Multi.Image signature algebra program shape) :
    Target.Multi.admit (templateImage source) = (Source.Multi.admit source).map template := by
  unfold Target.Multi.admit Source.Multi.admit
  simp only [template_copyability]
  split <;> rfl

theorem compiled_capture_is_already_a_clone_view (source : Source.Capture signature algebra program input result) :
    (capture source).cloneView = capture source := by
  induction source with
  | done => rfl
  | bind body bindings rest induction => exact congrArg _ induction
  | handler effect mode identity returned clauses bindings rest induction => exact congrArg _ induction
  | region identity rest induction => exact congrArg _ induction
  | protection identity cleanup bindings rest induction => exact congrArg _ induction

mutual
  theorem compiled_record_is_already_a_clone_view (record : Source.Multi.Record signature algebra program) :
      (templateRecord record).cloneView = templateRecord record := by
    cases record with
    | mk identity shape saved localCells dormant attachments regions scopes =>
      simp only [templateRecord, Target.Multi.Record.cloneView, templateFuture,
        compiled_capture_is_already_a_clone_view, compiled_records_are_already_clone_views dormant]
  termination_by sizeOf record
  decreasing_by cases record; simp_all; omega

  theorem compiled_records_are_already_clone_views (records : List (Source.Multi.Record signature algebra program)) :
      Target.Multi.recordsCloneView (templateRecords records) = templateRecords records := by
    cases records with
    | nil => rfl
    | cons first rest => simp only [templateRecords, Target.Multi.recordsCloneView,
        compiled_record_is_already_a_clone_view first, compiled_records_are_already_clone_views rest]
  termination_by sizeOf records
end

theorem partition_image_corresponds (partition : Target.Multi.Partition)
    (saved : Source.Multi.Future signature algebra program shape) (arena : Source.Multi.Arena signature algebra program) :
    Target.Multi.Partition.image partition (templateFuture saved) (templateArena arena) =
      templateImage (Source.Multi.partitionImage partition saved arena) := by
  simp only [Target.Multi.Partition.image, templateFuture, templateArena, templateImage,
    Source.Multi.partitionImage, compiled_capture_is_already_a_clone_view]
  congr 1
  · simp only [cells, Cells.mapBodies, List.filter_map, Function.comp_def, Cell.map]
  · simp only [List.filter_map, template_record_identity, List.map_map, Function.comp_def,
      compiled_record_is_already_a_clone_view]

theorem remaining_arena_corresponds (partition : Target.Multi.Partition) (arena : Source.Multi.Arena signature algebra program) :
    Target.Multi.Partition.remaining partition (templateArena arena) =
      templateArena (Source.Multi.remainingArena partition arena) := by
  simp only [Target.Multi.Partition.remaining, templateArena, Source.Multi.remainingArena]
  congr 1
  · simp only [cells, Cells.mapBodies, List.filter_map, Function.comp_def, Cell.map]
  · simp only [List.filter_map, Function.comp_def, template_record_identity]

end Defunctionalization
end BoundaryV2.Generalized
