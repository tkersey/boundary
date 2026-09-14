import BoundaryV2.GeneralizedRuntimeSupport
import BoundaryV2.GeneralizedCopying

namespace BoundaryV2.Generalized.Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Existing obligations cannot be copied. A protect instruction in dormant
code may create a new obligation later; that is different from this live frame. -/
def Frame.copyable : Frame signature algebra program input result → Bool
  | .returnTo _ bindings operands => bindings.copyable && operands.copyable
  | .handler _ _ _ _ _ bindings => bindings.copyable
  | .region _ => true
  | .protection _ _ _ | .cleanupReturn _ _ _ => false

def Stack.copyable : Stack signature algebra program input result → Bool
  | .done => true
  | .push frame rest => frame.copyable && rest.copyable

namespace Multi

abbrev StoredCells (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) :=
  Cells signature algebra (fun context result => Code signature algebra program context [] result)

mutual
  /-- Owned dormant captures are structural snapshots. References between them
  remain names, so aliases and reference cycles do not recursively unfold. -/
  structure Record (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (program : List (BodyType signature.Data signature.Effect)) where
    identity : Id .control
    shape : ControlShape signature
    saved : ControlPayload signature algebra program shape
    cells : StoredCells signature algebra program := []
    dormant : List (Record signature algebra program) := []
    attachments : List (Id .attachment) := []
    regions : List (Id .region) := []
    scopes : List (Id .scope) := []
end

def Record.bare (identity : Id .control) (shape : ControlShape signature)
    (saved : ControlPayload signature algebra program shape) : Record signature algebra program :=
  { identity, shape, saved }

def payloadReferences (saved : Sigma (ControlPayload signature algebra program)) : List Reference :=
  .name .attachment saved.snd.attachment :: saved.snd.future.references

mutual
  def Record.references : Record signature algebra program → List Reference
    | .mk identity shape saved cells dormant attachments regions scopes =>
      .name .control identity :: (payloadReferences ⟨shape, saved⟩ ++ cellsReferences cells ++
        recordsReferences dormant ++ attachments.map (.name .attachment) ++
        regions.map (.name .region) ++ scopes.map (.name .scope))
  def recordsReferences : List (Record signature algebra program) → List Reference
    | [] => []
    | first :: rest => first.references ++ recordsReferences rest
end

mutual
  def Record.relocate (relocation : UseScope.Relocation) : Record signature algebra program → Record signature algebra program
    | .mk identity shape saved cells dormant attachments regions scopes =>
      ⟨relocation.name .control identity, shape, saved.relocate relocation,
        cells.map (relocateCell relocation), relocateRecords relocation dormant,
        attachments.map (relocation.name .attachment), regions.map (relocation.name .region),
        scopes.map (relocation.name .scope)⟩
  def relocateRecords (relocation : UseScope.Relocation) : List (Record signature algebra program) → List (Record signature algebra program)
    | [] => []
    | first :: rest => first.relocate relocation :: relocateRecords relocation rest
end

mutual
  def Record.copyable : Record signature algebra program → Bool
    | .mk _ _ saved cells dormant _ _ _ =>
      saved.future.copyable && cells.all (fun cell => cell.value.copyable) && recordsCopyable dormant
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

theorem payload_references_relocate (relocation : UseScope.Relocation) (saved : Sigma (ControlPayload signature algebra program)) :
    payloadReferences (relocateControlPayload relocation saved) = (payloadReferences saved).map (Reference.relocate relocation) := by
  simp only [payloadReferences, relocateControlPayload, Resumption.relocate, List.map_cons,
    Reference.relocate, Stack.references_relocate]

mutual
  theorem Record.references_relocate (relocation : UseScope.Relocation) (record : Record signature algebra program) :
      (record.relocate relocation).references = record.references.map (Reference.relocate relocation) := by
    cases record with
    | mk identity shape saved cells dormant attachments regions scopes =>
      simp only [Record.relocate, Record.references, payloadReferences, Resumption.relocate,
        Stack.references_relocate, cells_references_relocate, records_references_relocate relocation dormant,
        List.map_append, List.map_cons, List.map_map, Function.comp_def, Reference.relocate]
  termination_by sizeOf record
  decreasing_by cases record; simp_all; omega

  theorem records_references_relocate (relocation : UseScope.Relocation) (records : List (Record signature algebra program)) :
      recordsReferences (relocateRecords relocation records) = (recordsReferences records).map (Reference.relocate relocation) := by
    cases records with
    | nil => rfl
    | cons first rest => simp only [relocateRecords, recordsReferences, List.map_append,
        Record.references_relocate relocation first, records_references_relocate relocation rest]
  termination_by sizeOf records
end

/-- The capture owner supplies the local attachment/region/scope partition.
Cell and dormant-control identities are derived from the actual stored records.
Borrow retention and region closure retain their separate lifetime premises;
this operation neither authorizes an escape nor infers that partition. -/
structure Image (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) where
  saved : ControlPayload signature algebra program shape
  cells : StoredCells signature algebra program
  dormant : List (Record signature algebra program)
  attachments : List (Id .attachment)
  regions : List (Id .region)
  scopes : List (Id .scope)

def Image.references (image : Image signature algebra program shape) : List Reference :=
  payloadReferences ⟨shape, image.saved⟩ ++ cellsReferences image.cells ++ image.dormant.flatMap Record.references ++
    image.attachments.map (.name .attachment) ++ image.regions.map (.name .region) ++ image.scopes.map (.name .scope)

def Image.locals (image : Image signature algebra program shape) : (domain : Domain) → List (Id domain)
  | .attachment => image.attachments ++ recordsLocals image.dormant .attachment
  | .region => image.regions ++ recordsLocals image.dormant .region
  | .scope => image.scopes ++ recordsLocals image.dormant .scope
  | .cell => Cells.identities image.cells ++ recordsLocals image.dormant .cell
  | .control => recordsLocals image.dormant .control
  | .resource | .custody | .occurrence | .obligation => []

/-- Inspect actual captures and all code constants. A reusable label does not
hide an exclusive value, and an inactive cleanup is still an obligation. -/
def Image.copyable (image : Image signature algebra program shape) : Bool :=
  image.saved.future.copyable && image.cells.all (fun cell => cell.value.copyable) &&
    recordsCopyable image.dormant &&
    (referenceNames image.references .custody).isEmpty &&
    (referenceNames image.references .obligation).isEmpty

structure Template (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) where
  image : Image signature algebra program shape
  copyable : image.copyable = true

def admit (image : Image signature algebra program shape) : Option (Template signature algebra program shape) :=
  if allowed : image.copyable = true then some ⟨image, allowed⟩ else none

/-- The arena retains the actual active futures as well as dormant records.
Each activation therefore sees names allocated by earlier, still-live branches. -/
structure Arena (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) where
  cells : StoredCells signature algebra program
  dormant : List (Record signature algebra program)
  active : List (Sigma (ControlPayload signature algebra program))

def Arena.references (arena : Arena signature algebra program) : List Reference :=
  cellsReferences arena.cells ++ arena.dormant.flatMap Record.references ++ arena.active.flatMap payloadReferences

def support (image : Image signature algebra program shape) (arena : Arena signature algebra program)
    (external : List Reference) : List Reference := image.references ++ arena.references ++ external

/-- Bounds come from finite occurrences in the template and the current arena,
plus explicitly external support. No freshness certificate is an input. -/
def allocation (image : Image signature algebra program shape) (arena : Arena signature algebra program)
    (external : List Reference) : UseScope.Relocation where
  name domain := FreshNames.rename (image.locals domain) (FreshNames.bound (referenceNames (support image arena external) domain))
  owner := id

structure Activation (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) where
  saved : ControlPayload signature algebra program shape
  arena : Arena signature algebra program

/-- Instantiate the saved future, local cells, and every dormant future with
one map. Shared cells come from the current arena, not the captured image. -/
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

theorem instantiation_relocates_entire_future (template : Template signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference) :
    payloadReferences ⟨shape, (instantiate template arena external).saved⟩ =
      (payloadReferences ⟨shape, template.image.saved⟩).map (Reference.relocate (allocation template.image arena external)) :=
  payload_references_relocate (allocation template.image arena external) ⟨shape, template.image.saved⟩

theorem instantiation_keeps_current_cells (template : Template signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference) :
    (instantiate template arena external).arena.cells =
      template.image.cells.map (relocateCell (allocation template.image arena external)) ++ arena.cells := rfl

theorem instantiation_keeps_dormant_aliases (template : Template signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference) :
    (instantiate template arena external).arena.dormant.flatMap Record.references =
      (template.image.dormant.flatMap Record.references).map (Reference.relocate (allocation template.image arena external)) ++
        arena.dormant.flatMap Record.references := by
  simp only [instantiate, List.flatMap_append]
  congr 1
  generalize template.image.dormant = records
  induction records with
  | nil => rfl
  | cons record rest induction =>
    simp only [List.map_cons, List.flatMap_cons, List.map_append, Record.references_relocate, induction]

theorem admitted_template_has_no_custody_or_obligation (template : Template signature algebra program shape) :
    referenceNames template.image.references .custody = [] ∧ referenceNames template.image.references .obligation = [] := by
  have allowed := template.copyable
  simp only [Image.copyable, Bool.and_eq_true, List.isEmpty_iff] at allowed
  exact ⟨allowed.1.2, allowed.2⟩

theorem admitted_cell_has_no_owner (template : Template signature algebra program shape)
    (cell : Cell signature algebra (fun context result => Code signature algebra program context [] result))
    (member : cell ∈ template.image.cells) : cell.value.owningField.tokens = [] := by
  have allowed := template.copyable
  simp only [Image.copyable, Bool.and_eq_true, List.all_eq_true] at allowed
  exact cell.value.copyable_has_no_owner (allowed.1.1.1.2 cell member)

theorem instantiation_does_not_duplicate_cell_owners (template : Template signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference) :
    UseScope.tokens (Cells.fields (instantiate template arena external).arena.cells) =
      UseScope.tokens (Cells.fields arena.cells) := by
  have empty : ∀ cell ∈ template.image.cells,
      (relocateCell (allocation template.image arena external) cell).value.owningField.tokens = [] := by
    intro cell member
    simp only [relocateCell, relocateValue, Value.relocate_owning_field, UseScope.relocate_field_tokens,
      admitted_cell_has_no_owner template cell member, List.map_nil]
  change UseScope.tokens (Cells.fields (template.image.cells.map _ ++ arena.cells)) = _
  simp only [Cells.fields, List.map_append, UseScope.tokens_append]
  suffices UseScope.tokens (List.map (fun cell => cell.value.owningField) (template.image.cells.map
      (relocateCell (allocation template.image arena external)))) = [] by simp only [this, List.nil_append]
  generalize template.image.cells = cells at empty ⊢
  revert empty
  induction cells with
  | nil => intro; rfl
  | cons cell rest induction =>
    intro empty
    simp only [List.map_cons, UseScope.tokens, empty cell (by simp), List.nil_append]
    exact induction (fun value member => empty value (by simp [member]))

theorem cell_identity_is_supported (cells : StoredCells signature algebra program)
    (present : name ∈ Cells.identities cells) : Reference.name .cell name ∈ cellsReferences cells := by
  obtain ⟨cell, member, rfl⟩ := List.mem_map.mp present
  exact List.mem_flatMap.mpr ⟨cell, member, by simp [cellReferences]⟩

theorem arena_cell_is_supported (image : Image signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference)
    (present : name ∈ Cells.identities arena.cells) : name ∈ referenceNames (support image arena external) .cell := by
  apply reference_name_member.mpr
  have member := cell_identity_is_supported arena.cells present
  simp only [support, Arena.references, List.mem_append]
  exact Or.inl (Or.inr (Or.inl (Or.inl member)))

theorem image_cell_is_supported (image : Image signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference)
    (present : name ∈ Cells.identities image.cells) : name ∈ referenceNames (support image arena external) .cell := by
  apply reference_name_member.mpr
  have member := cell_identity_is_supported image.cells present
  simp [support, Image.references, member]

theorem instantiation_preserves_cell_identity_uniqueness (template : Template signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference)
    (localUnique : (Cells.identities template.image.cells).Nodup)
    (currentUnique : (Cells.identities arena.cells).Nodup) :
    (Cells.identities (instantiate template arena external).arena.cells).Nodup := by
  have identities : Cells.identities (instantiate template arena external).arena.cells =
      (Cells.identities template.image.cells).map ((allocation template.image arena external).name .cell) ++ Cells.identities arena.cells := by
    simp only [instantiate, Cells.identities, List.map_append, List.map_map, Function.comp_def, relocateCell]
  rw [identities, List.nodup_append]
  refine ⟨?_, currentUnique, ?_⟩
  · exact UseScope.nodup_map_on _ localUnique (fun first firstAt second secondAt equal =>
      allocation_is_injective_on_actual_support template.image arena external
        (image_cell_is_supported template.image arena external firstAt)
        (image_cell_is_supported template.image arena external secondAt) equal)
  · intro first firstAt second secondAt
    obtain ⟨original, member, rfl⟩ := List.mem_map.mp firstAt
    exact allocated_local_is_fresh template.image arena external (List.mem_append_left _ member)
      (arena_cell_is_supported template.image arena external secondAt)

private theorem lookup_append_of_absent (fresh current : StoredCells signature algebra program)
    (different : ∀ cell ∈ fresh, cell.identity ≠ name) :
    Cells.lookup name (fresh ++ current) = Cells.lookup name current := by
  induction fresh with
  | nil => rfl
  | cons cell rest induction =>
    simp only [List.cons_append, Cells.lookup, if_neg (different cell (by simp))]
    exact induction (fun value member => different value (by simp [member]))

theorem instantiation_preserves_current_cell_lookup (template : Template signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference)
    (present : name ∈ Cells.identities arena.cells) :
    Cells.lookup name (instantiate template arena external).arena.cells = Cells.lookup name arena.cells := by
  apply lookup_append_of_absent
  intro cell member
  obtain ⟨original, stored, rfl⟩ := List.mem_map.mp member
  exact allocated_local_is_fresh template.image arena external
    (List.mem_append_left _ (List.mem_map.mpr ⟨original, stored, rfl⟩)) (arena_cell_is_supported template.image arena external present)

theorem records_references_as_flatMap (records : List (Record signature algebra program)) :
    recordsReferences records = records.flatMap Record.references := by
  induction records with
  | nil => rfl
  | cons first rest induction => exact congrArg (first.references ++ ·) induction

mutual
  theorem Record.local_cell_is_supported (record : Record signature algebra program)
      (present : name ∈ record.locals .cell) : Reference.name .cell name ∈ record.references := by
    cases record with
    | mk identity shape saved localCells dormant attachments regions scopes =>
      rcases List.mem_append.mp present with here | nested
      · have seen := cell_identity_is_supported localCells here
        simp [Record.references, seen]
      · have seen := records_local_cell_is_supported dormant nested
        simp [Record.references, seen]
  termination_by sizeOf record
  decreasing_by all_goals (cases record <;> simp_all <;> omega)

  theorem records_local_cell_is_supported (records : List (Record signature algebra program))
      (present : name ∈ recordsLocals records .cell) : Reference.name .cell name ∈ recordsReferences records := by
    cases records with
    | nil => cases present
    | cons first rest =>
      rcases List.mem_append.mp present with here | later
      · exact List.mem_append_left _ (Record.local_cell_is_supported first here)
      · exact List.mem_append_right _ (records_local_cell_is_supported rest later)
  termination_by sizeOf records
end

theorem instantiation_supports_every_local_cell (template : Template signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference)
    (localCell : name ∈ template.image.locals .cell) :
    (allocation template.image arena external).name .cell name ∈
      referenceNames (support template.image (instantiate template arena external).arena external) .cell := by
  rcases List.mem_append.mp localCell with rootCell | dormantCell
  · apply arena_cell_is_supported
    obtain ⟨cell, member, rfl⟩ := List.mem_map.mp rootCell
    apply List.mem_map.mpr
    exact ⟨relocateCell (allocation template.image arena external) cell,
      List.mem_append_left _ (List.mem_map.mpr ⟨cell, member, rfl⟩), rfl⟩
  · have old := records_local_cell_is_supported template.image.dormant dormantCell
    rw [records_references_as_flatMap] at old
    have present : Reference.name .cell ((allocation template.image arena external).name .cell name) ∈
        (instantiate template arena external).arena.dormant.flatMap Record.references := by
      rw [instantiation_keeps_dormant_aliases]
      exact List.mem_append_left _ (List.mem_map.mpr ⟨Reference.name .cell name, old, rfl⟩)
    apply reference_name_member.mpr
    simp [support, Arena.references, present]

theorem successive_cell_allocations_are_disjoint (template : Template signature algebra program shape)
    (arena : Arena signature algebra program) (external : List Reference)
    (firstLocal : first ∈ template.image.locals .cell) (secondLocal : second ∈ template.image.locals .cell) :
    (allocation template.image arena external).name .cell first ≠
      (allocation template.image (instantiate template arena external).arena external).name .cell second := by
  apply Ne.symm
  apply allocated_local_is_fresh template.image (instantiate template arena external).arena external secondLocal
  exact instantiation_supports_every_local_cell template arena external firstLocal

end Multi
end BoundaryV2.Generalized.Target
