import BoundaryV2.GeneralizedCaptureRelocation

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

namespace Source.Multi

def Image.locals (image : Image signature algebra program shape) : (domain : Domain) → List (Id domain)
  | .attachment => image.attachments
  | .region => image.regions
  | .scope => image.scopes
  | .cell => Cells.identities image.cells
  | .control => image.dormant.map Record.identity
  | .resource | .custody | .occurrence | .obligation => []

def Arena.references (arena : Arena signature algebra program) : List Reference :=
  cellsReferences arena.cells ++ arena.dormant.flatMap Record.references ++ arena.active.flatMap (fun future => future.snd.references)

def support (image : Image signature algebra program shape) (arena : Arena signature algebra program)
    (external : List Reference) : List Reference := image.references ++ arena.references ++ external

def allocation (image : Image signature algebra program shape) (arena : Arena signature algebra program)
    (external : List Reference) : UseScope.Relocation where
  name domain := FreshNames.rename (image.locals domain) (FreshNames.bound (referenceNames (support image arena external) domain))
  owner := id

structure Activation (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) where
  saved : Future signature algebra program shape
  arena : Arena signature algebra program

/-- Rebuild source callbacks from consistently renamed authored bodies and
environments. Current shared cells and earlier active branches stay in the arena. -/
def instantiate (template : Template signature algebra program shape) (arena : Arena signature algebra program)
    (external : List Reference) : Activation signature algebra program shape :=
  let relocation := allocation template.image arena external
  let saved := template.image.saved.relocate relocation
  ⟨saved, ⟨template.image.cells.map (relocateCell relocation) ++ arena.cells,
    template.image.dormant.map (Record.relocate relocation) ++ arena.dormant,
    ⟨shape, saved⟩ :: arena.active⟩⟩

theorem allocation_is_injective_on_actual_support (image : Image signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference)
    (firstAt : first ∈ referenceNames (support image arena external) domain)
    (secondAt : second ∈ referenceNames (support image arena external) domain)
    (same : (allocation image arena external).name domain first = (allocation image arena external).name domain second) :
    first = second := FreshNames.injective_on_support firstAt secondAt same

theorem allocated_local_is_fresh (image : Image signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference)
    (isLocal : name ∈ image.locals domain) (present : old ∈ referenceNames (support image arena external) domain) :
    (allocation image arena external).name domain name ≠ old := FreshNames.fresh_from_existing_support isLocal present

theorem external_name_is_unchanged (image : Image signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference) (isExternal : name ∉ image.locals domain) :
    (allocation image arena external).name domain name = name := FreshNames.external_names_unchanged isExternal

end Source.Multi

namespace Defunctionalization

theorem template_arena_references (source : Source.Multi.Arena signature algebra program) :
    (templateArena source).references = source.references := by
  simp only [templateArena, Target.Multi.Arena.references, cell_installation_support,
    List.flatMap_map, template_record_references, Source.Multi.Arena.references,
    Target.Multi.payloadReferences, templateFuture, capture_references, Source.Multi.Future.references]

theorem template_image_locals (source : Source.Multi.Image signature algebra program shape) (domain : Domain) :
    (templateImage source).locals domain = source.locals domain := by
  cases domain <;> simp [Target.Multi.Image.locals, Source.Multi.Image.locals, templateImage,
    cells, Cells.mapBodies, Cells.identities, Cell.map, templateRecord, List.map_map]

/-- Fresh names are computed independently from identical finite support;
neither implementation receives the other's allocation as an assumption. -/
theorem template_allocation_corresponds (source : Source.Multi.Image signature algebra program shape)
    (arena : Source.Multi.Arena signature algebra program) (external : List Reference) :
    Target.Multi.allocation (templateImage source) (templateArena arena) external = Source.Multi.allocation source arena external := by
  unfold Target.Multi.allocation Source.Multi.allocation
  congr 1
  funext domain
  simp only [template_image_locals, Target.Multi.support, Source.Multi.support, template_image_references, template_arena_references]

def templateActivation (source : Source.Multi.Activation signature algebra program shape) : Target.Multi.Activation signature algebra program shape :=
  ⟨templateFuture source.saved, templateArena source.arena⟩

/-- Compiling a source activation yields exactly the independently instantiated
target future, cells, dormant aliases, and active branch inventory. -/
theorem template_instantiation_corresponds (source : Source.Multi.Template signature algebra program shape)
    (arena : Source.Multi.Arena signature algebra program) (external : List Reference) :
    Target.Multi.instantiate (template source) (templateArena arena) external =
      templateActivation (Source.Multi.instantiate source arena external) := by
  unfold Target.Multi.instantiate
  simp only [template]
  rw [template_allocation_corresponds]
  unfold Source.Multi.instantiate
  generalize Source.Multi.allocation source.image arena external = relocation
  simp only [templateImage, templateActivation, template_future_relocation,
    templateArena, cells, Cells.mapBodies, List.map_append, List.map_cons, List.map_map]
  congr 2
  · exact congrArg (· ++ cells arena.cells)
      (List.map_congr_left fun cell _ => cell_relocation_commutes _ cell)
  · exact congrArg (· ++ arena.dormant.map templateRecord)
      (List.map_congr_left fun record _ => template_record_relocation _ record)

theorem activated_source_future_corresponds (source : Source.Multi.Template signature algebra program shape)
    (arena : Source.Multi.Arena signature algebra program) (external : List Reference) :
    controlPayloadRelated shape (Source.Multi.instantiate source arena external).saved.payload
      (Target.Multi.instantiate (template source) (templateArena arena) external).saved := by
  rw [template_instantiation_corresponds]
  exact template_future_correspondence _

end Defunctionalization
end BoundaryV2.Generalized
