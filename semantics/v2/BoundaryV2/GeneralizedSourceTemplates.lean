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

structure Record (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) where
  identity : Id .control
  shape : ControlShape signature
  saved : Future signature algebra program shape

def Record.references (record : Record signature algebra program) : List Reference :=
  .name .control record.identity :: record.saved.references

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
    image.dormant.all (fun record => record.saved.capture.copyable) &&
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

def templateRecord (source : Source.Multi.Record signature algebra program) : Target.Multi.Record signature algebra program :=
  ⟨source.identity, source.shape, templateFuture source.saved⟩

def templateImage (source : Source.Multi.Image signature algebra program shape) : Target.Multi.Image signature algebra program shape :=
  ⟨templateFuture source.saved, cells source.cells, source.dormant.map templateRecord,
    source.attachments, source.regions, source.scopes⟩

def templateArena (source : Source.Multi.Arena signature algebra program) : Target.Multi.Arena signature algebra program :=
  ⟨cells source.cells, source.dormant.map templateRecord, source.active.map (fun future => ⟨future.fst, templateFuture future.snd⟩)⟩

theorem template_future_correspondence (source : Source.Multi.Future signature algebra program shape) :
    controlPayloadRelated shape source.payload (templateFuture source) :=
  ⟨rfl, capture_correspondence source.capture⟩

theorem template_record_references (source : Source.Multi.Record signature algebra program) :
    (templateRecord source).references = source.references := by
  simp only [templateRecord, Target.Multi.Record.references, Target.Multi.payloadReferences,
    templateFuture, capture_references, Source.Multi.Record.references, Source.Multi.Future.references]

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
    Cell.map, Value.copyable_map, templateRecord, Function.comp_def]

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

theorem partition_image_corresponds (partition : Target.Multi.Partition)
    (saved : Source.Multi.Future signature algebra program shape) (arena : Source.Multi.Arena signature algebra program) :
    Target.Multi.Partition.image partition (templateFuture saved) (templateArena arena) =
      templateImage (Source.Multi.partitionImage partition saved arena) := by
  simp only [Target.Multi.Partition.image, templateFuture, templateArena, templateImage,
    Source.Multi.partitionImage, compiled_capture_is_already_a_clone_view]
  congr 1
  · simp only [cells, Cells.mapBodies, List.filter_map, Function.comp_def, Cell.map]
  · simp only [List.filter_map, templateRecord, templateFuture, compiled_capture_is_already_a_clone_view,
      List.map_map, Function.comp_def]
    rfl

theorem remaining_arena_corresponds (partition : Target.Multi.Partition) (arena : Source.Multi.Arena signature algebra program) :
    Target.Multi.Partition.remaining partition (templateArena arena) =
      templateArena (Source.Multi.remainingArena partition arena) := by
  simp only [Target.Multi.Partition.remaining, templateArena, Source.Multi.remainingArena]
  congr 1
  · simp only [cells, Cells.mapBodies, List.filter_map, Function.comp_def, Cell.map]
  · simp only [List.filter_map, Function.comp_def, templateRecord]

end Defunctionalization
end BoundaryV2.Generalized
