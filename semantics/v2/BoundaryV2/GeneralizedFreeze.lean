import BoundaryV2.GeneralizedCloneView
import BoundaryV2.GeneralizedInstallationSupport

namespace BoundaryV2.Generalized

def UseScope.captureCanFreeze (fields : List UseScope.Field) : Bool :=
  (UseScope.tokens fields).isEmpty && (referenceNames (UseScope.fieldsReferences fields) .obligation).isEmpty

namespace Target.Multi

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)]

/-- The capture owner supplies the local lifetime partition. Actual cell and
record contents are selected from the current arena rather than supplied anew. -/
structure Partition where
  attachments : List (Id .attachment)
  regions : List (Id .region)
  scopes : List (Id .scope)
  dormant : List (Id .control)

mutual
  def Record.cloneView : Record signature algebra program → Record signature algebra program
    | .mk identity shape saved cells dormant attachments regions scopes =>
      ⟨identity, shape, { saved with future := saved.future.cloneView }, cells,
        recordsCloneView dormant, attachments, regions, scopes⟩
  def recordsCloneView : List (Record signature algebra program) → List (Record signature algebra program)
    | [] => []
    | first :: rest => first.cloneView :: recordsCloneView rest
end

def Partition.image (partition : Partition) (saved : ControlPayload signature algebra program shape)
    (arena : Arena signature algebra program) : Image signature algebra program shape :=
  ⟨{ saved with future := saved.future.cloneView },
    arena.cells.filter (fun cell => partition.regions.contains cell.region),
    (arena.dormant.filter (fun record => partition.dormant.contains record.identity)).map Record.cloneView,
    partition.attachments, partition.regions, partition.scopes⟩

def Partition.remaining (partition : Partition) (arena : Arena signature algebra program) : Arena signature algebra program :=
  { arena with
    cells := arena.cells.filter (fun cell => !partition.regions.contains cell.region)
    dormant := arena.dormant.filter (fun record => !partition.dormant.contains record.identity) }

structure Frozen (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) where
  identity : Id .control
  template : Template signature algebra program shape
  store : ControlHeap signature algebra program
  arena : Arena signature algebra program

/-- The returned reference is paired with its actual immutable template. The
registry owner must retain that binding when placing the reference in a value. -/
def Frozen.value (frozen : Frozen signature algebra program shape) :
    RuntimeValue signature algebra program (.continuation shape.mode .multi shape.effect shape.input shape.answer) :=
  .continuation frozen.identity none

abbrev captureCanFreeze := UseScope.captureCanFreeze

/-- No consumed successor escapes a failed admission. Successful conversion
uses the actual registered future and preserves the current outer arena. -/
def freezeOwned (shape : ControlShape signature) (view : UseScope.ControlView)
    (store : ControlHeap signature algebra program) (arena : Arena signature algebra program)
    (partition : Partition) : Option (Frozen signature algebra program shape) :=
  (UseScope.takeCapture view.identity store.fields.retained).bind fun (captured, _) =>
    if captureCanFreeze captured then
      (UseScope.acquireAt shape view store).bind fun acquired =>
        (admit (partition.image acquired.future arena)).map fun template =>
          ⟨view.identity, template, acquired.store, partition.remaining arena⟩
    else none

variable {shape : ControlShape signature} {view : UseScope.ControlView}
  {store : ControlHeap signature algebra program} {arena : Arena signature algebra program}
  {partition : Partition} {frozen : Frozen signature algebra program shape}

theorem frozen_future_is_the_acquired_future
    (accepted : freezeOwned shape view store arena partition = some frozen) :
    ∃ captured retained acquired,
      UseScope.takeCapture view.identity store.fields.retained = some (captured, retained) ∧
      captureCanFreeze captured = true ∧
      UseScope.acquireAt shape view store = some acquired ∧
      frozen.template.image = partition.image acquired.future arena ∧
      frozen.store = acquired.store ∧ frozen.arena = partition.remaining arena := by
  obtain ⟨⟨captured, retained⟩, selected, accepted⟩ := Option.bind_eq_some_iff.mp accepted
  dsimp only at accepted
  split at accepted
  · rename_i allowed
    obtain ⟨acquired, used, accepted⟩ := Option.bind_eq_some_iff.mp accepted
    obtain ⟨template, admitted, result⟩ := Option.map_eq_some_iff.mp accepted
    cases result
    unfold admit at admitted
    split at admitted
    · cases admitted
      exact ⟨captured, retained, acquired, selected, allowed, used, rfl, rfl, rfl⟩
    · cases admitted
  · cases accepted

theorem freeze_preserves_ownership_and_consumes_original
    (valid : UseScope.ControlStore.Valid store)
    (accepted : freezeOwned shape view store arena partition = some frozen) :
    UseScope.ControlStore.Valid frozen.store ∧
      view.authority ∉ UseScope.inventory frozen.store.fields ∧
      UseScope.acquireAt shape view frozen.store = none := by
  obtain ⟨_, _, acquired, _, _, used, _, same, _⟩ := frozen_future_is_the_acquired_future accepted
  rw [same]
  exact UseScope.acquire_at_consumes_before_entry valid used

theorem freeze_rejects_owned_capture
    (selected : UseScope.takeCapture view.identity store.fields.retained = some (captured, retained))
    (owned : UseScope.tokens captured ≠ []) : freezeOwned shape view store arena partition = none := by
  simp [freezeOwned, selected, captureCanFreeze, UseScope.captureCanFreeze, owned]

theorem frozen_capture_has_no_owner_or_obligation
    (accepted : freezeOwned shape view store arena partition = some frozen) :
    ∃ captured retained,
      UseScope.takeCapture view.identity store.fields.retained = some (captured, retained) ∧
      UseScope.tokens captured = [] ∧ referenceNames (UseScope.fieldsReferences captured) .obligation = [] := by
  obtain ⟨captured, retained, _, selected, allowed, _, _, _, _⟩ := frozen_future_is_the_acquired_future accepted
  simp only [captureCanFreeze, UseScope.captureCanFreeze, Bool.and_eq_true, List.isEmpty_iff] at allowed
  exact ⟨captured, retained, selected, allowed⟩

theorem frozen_local_cells_are_actual_current_cells
    (accepted : freezeOwned shape view store arena partition = some frozen) :
    frozen.template.image.cells = arena.cells.filter (fun cell => partition.regions.contains cell.region) ∧
      frozen.arena.cells = arena.cells.filter (fun cell => !partition.regions.contains cell.region) := by
  obtain ⟨_, _, acquired, _, _, _, image, _, remaining⟩ := frozen_future_is_the_acquired_future accepted
  exact ⟨congrArg Image.cells image, congrArg Arena.cells remaining⟩

theorem freeze_partitions_cell_storage
    (accepted : freezeOwned shape view store arena partition = some frozen) :
    arena.cells.Perm (frozen.template.image.cells ++ frozen.arena.cells) := by
  obtain ⟨captured, remaining⟩ := frozen_local_cells_are_actual_current_cells accepted
  rw [captured, remaining]
  exact (List.filter_append_perm _ _).symm

end Target.Multi
end BoundaryV2.Generalized
