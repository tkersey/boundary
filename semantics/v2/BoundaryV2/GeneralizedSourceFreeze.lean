import BoundaryV2.GeneralizedSourceTemplates
import BoundaryV2.GeneralizedControlMapping

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)]

namespace Source.Multi

abbrev DescribedHeap (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) :=
  UseScope.ControlStore (Sigma (Future signature algebra program))

/-- This projection is the ordinary source control heap, with actual callback
futures. Descriptions retain the bodies and captures that produced those callbacks. -/
def sourceHeap (store : DescribedHeap signature algebra program) : ControlHeap signature algebra program :=
  store.mapFuture (UseScope.mapPacked (fun _ => Future.payload))

structure Frozen (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) where
  identity : Id .control
  template : Template signature algebra program shape
  store : DescribedHeap signature algebra program
  arena : Arena signature algebra program

def Frozen.value (frozen : Frozen signature algebra program shape) :
    RuntimeValue signature algebra program (.continuation shape.mode .multi shape.effect shape.input shape.answer) :=
  .continuation frozen.identity none

def freezeOwned (shape : ControlShape signature) (view : UseScope.ControlView)
    (store : DescribedHeap signature algebra program) (arena : Arena signature algebra program)
    (partition : Target.Multi.Partition) : Option (Frozen signature algebra program shape) :=
  (UseScope.takeCapture view.identity store.fields.retained).bind fun (captured, _) =>
    if UseScope.captureCanFreeze captured then
      (UseScope.acquireAt shape view store).bind fun acquired =>
        (admit (partitionImage partition acquired.future arena)).map fun template =>
          ⟨view.identity, template, acquired.store, remainingArena partition arena⟩
    else none

/-- Successful freezing uses the same higher-order future and successor heap
as acquiring the original source continuation, without executing that future. -/
theorem frozen_source_is_the_actual_acquisition
    {store : DescribedHeap signature algebra program} {arena : Arena signature algebra program}
    {frozen : Frozen signature algebra program shape}
    (accepted : freezeOwned shape view store arena partition = some frozen) :
    UseScope.acquireAt shape view (sourceHeap store) =
      some ⟨sourceHeap frozen.store, frozen.template.image.saved.payload⟩ := by
  obtain ⟨⟨captured, retained⟩, _, accepted⟩ := Option.bind_eq_some_iff.mp accepted
  dsimp only at accepted
  split at accepted
  · obtain ⟨acquired, consumed, accepted⟩ := Option.bind_eq_some_iff.mp accepted
    obtain ⟨template, admitted, result⟩ := Option.map_eq_some_iff.mp accepted
    cases result
    unfold admit at admitted
    split at admitted
    · cases admitted
      simp only [sourceHeap, UseScope.acquire_at_map, consumed, Option.map_some,
        UseScope.TypedAcquisition.mapFuture, partitionImage]
    · cases admitted
  · cases accepted

theorem freeze_consumes_actual_source_ownership
    {store : DescribedHeap signature algebra program} {arena : Arena signature algebra program}
    {frozen : Frozen signature algebra program shape}
    (valid : UseScope.ControlStore.Valid (sourceHeap store))
    (accepted : freezeOwned shape view store arena partition = some frozen) :
    UseScope.ControlStore.Valid (sourceHeap frozen.store) ∧
      view.authority ∉ UseScope.inventory (sourceHeap frozen.store).fields ∧
      UseScope.acquireAt shape view (sourceHeap frozen.store) = none :=
  UseScope.acquire_at_consumes_before_entry valid (frozen_source_is_the_actual_acquisition accepted)

end Source.Multi

namespace Defunctionalization

def templateHeap (source : Source.Multi.DescribedHeap signature algebra program) : Target.ControlHeap signature algebra program :=
  source.mapFuture (UseScope.mapPacked (fun _ => templateFuture))

def describedPayloadRelated (shape : ControlShape signature)
    (source : Source.Multi.Future signature algebra program shape)
    (target : Target.ControlPayload signature algebra program shape) : Prop :=
  controlPayloadRelated shape source.payload target

abbrev DescribedHeapRelated (source : Source.Multi.DescribedHeap signature algebra program)
    (target : Target.ControlHeap signature algebra program) :=
  UseScope.ControlStore.Related (UseScope.PackedControlRelated describedPayloadRelated) source target

omit [DecidableEq (ControlShape signature)] in
/-- Enriching the relation with authored descriptions does not replace the
actual source heap or require the target to have canonical frames. -/
theorem described_heap_related_iff (source : Source.Multi.DescribedHeap signature algebra program)
    (target : Target.ControlHeap signature algebra program) :
    DescribedHeapRelated source target ↔ ControlHeapRelated (Source.Multi.sourceHeap source) target := by
  have packed (first : Sigma (Source.Multi.Future signature algebra program))
      (second : Sigma (Target.ControlPayload signature algebra program)) :
      UseScope.PackedControlRelated controlPayloadRelated
        (UseScope.mapPacked (fun _ => Source.Multi.Future.payload) first) second ↔
      UseScope.PackedControlRelated describedPayloadRelated first second := by
    cases first with
    | mk shape saved =>
      constructor <;> intro related <;> cases related with
      | same matching => exact .same matching
  simpa only [Source.Multi.sourceHeap, ControlHeapRelated, DescribedHeapRelated, packed] using
    (UseScope.ControlStore.related_map_left_iff
      (UseScope.mapPacked (fun _ => Source.Multi.Future.payload))
      (UseScope.PackedControlRelated controlPayloadRelated) source target).symm

omit [DecidableEq (ControlShape signature)] in
theorem described_payload_clone_view (source : Source.Multi.Future signature algebra program shape)
    {target : Target.ControlPayload signature algebra program shape}
    (related : describedPayloadRelated shape source target) :
    { target with future := target.future.cloneView } = templateFuture source := by
  unfold templateFuture
  congr 1
  · exact related.attachment.symm
  · exact (capture_of_related_context source.capture related.future).symm

omit [DecidableEq (ControlShape signature)] in
theorem related_partition_image (partition : Target.Multi.Partition)
    (source : Source.Multi.Future signature algebra program shape)
    {target : Target.ControlPayload signature algebra program shape}
    (related : describedPayloadRelated shape source target)
    (arena : Source.Multi.Arena signature algebra program) :
    partition.image target (templateArena arena) = templateImage (Source.Multi.partitionImage partition source arena) := by
  rw [← partition_image_corresponds partition source arena]
  unfold Target.Multi.Partition.image
  congr 1
  rw [described_payload_clone_view source related]
  simp only [templateFuture, compiled_capture_is_already_a_clone_view]

def frozen (source : Source.Multi.Frozen signature algebra program shape) : Target.Multi.Frozen signature algebra program shape :=
  ⟨source.identity, template source.template, templateHeap source.store, templateArena source.arena⟩

structure FrozenRelated (source : Source.Multi.Frozen signature algebra program shape)
    (target : Target.Multi.Frozen signature algebra program shape) : Prop where
  identity : target.identity = source.identity
  template : target.template = Defunctionalization.template source.template
  store : DescribedHeapRelated source.store target.store
  arena : target.arena = templateArena source.arena

/-- Freeze relates arbitrary matching target frames. Only the captured image
uses its clone view; unrelated live controls keep their actual representations. -/
theorem freeze_owned_related (shape : ControlShape signature) (view : UseScope.ControlView)
    {source : Source.Multi.DescribedHeap signature algebra program} {target : Target.ControlHeap signature algebra program}
    (stores : DescribedHeapRelated source target) (arena : Source.Multi.Arena signature algebra program)
    (partition : Target.Multi.Partition) :
    Option.Rel FrozenRelated (Source.Multi.freezeOwned shape view source arena partition)
      (Target.Multi.freezeOwned shape view target (templateArena arena) partition) := by
  unfold Source.Multi.freezeOwned Target.Multi.freezeOwned
  rw [← stores.fields]
  cases selectionResult : UseScope.takeCapture view.identity source.fields.retained with
  | none => exact .none
  | some saved =>
    rcases saved with ⟨captured, retained⟩
    dsimp only [Option.bind]
    split
    · have acquired := UseScope.acquire_at_corresponds describedPayloadRelated stores shape view
      generalize sourceAt : UseScope.acquireAt shape view source = sourceTaken at acquired ⊢
      generalize targetAt : UseScope.acquireAt shape view target = targetTaken at acquired ⊢
      cases acquired with
      | none => exact .none
      | @some sourceAcquired targetAcquired matching =>
        simp only [related_partition_image partition sourceAcquired.future matching.future arena,
          template_admission_corresponds]
        cases Source.Multi.admit (Source.Multi.partitionImage partition sourceAcquired.future arena) with
        | none => exact .none
        | some admitted =>
          exact .some ⟨rfl, rfl, matching.store, remaining_arena_corresponds partition arena⟩
    · exact .none

omit [DecidableEq (ControlShape signature)] in
theorem template_heap_correspondence (source : Source.Multi.DescribedHeap signature algebra program) :
    ControlHeapRelated (Source.Multi.sourceHeap source) (templateHeap source) := by
  have records : ∀ (items : List (UseScope.ControlInfo (Sigma (Source.Multi.Future signature algebra program)))),
      UseScope.ControlInfosRelated (UseScope.PackedControlRelated controlPayloadRelated)
        (items.map (UseScope.ControlInfo.mapFuture (UseScope.mapPacked (fun _ => Source.Multi.Future.payload))))
        (items.map (UseScope.ControlInfo.mapFuture (UseScope.mapPacked (fun _ => templateFuture)))) := by
    intro items
    induction items with
    | nil => exact .nil
    | cons first rest induction =>
      exact .cons ⟨rfl, rfl, rfl, .same (template_future_correspondence first.future.snd)⟩ induction
  exact ⟨rfl, records source.controls, records source.disposing⟩

/-- Conversion preserves and reflects successful freezes and every refusal:
the target checks the independently compiled captures, consumes the same
physical grant, and partitions the same current cells and dormant records. -/
theorem freeze_owned_corresponds (shape : ControlShape signature) (view : UseScope.ControlView)
    (store : Source.Multi.DescribedHeap signature algebra program) (arena : Source.Multi.Arena signature algebra program)
    (partition : Target.Multi.Partition) :
    Target.Multi.freezeOwned shape view (templateHeap store) (templateArena arena) partition =
      (Source.Multi.freezeOwned shape view store arena partition).map frozen := by
  unfold Target.Multi.freezeOwned Source.Multi.freezeOwned
  change (UseScope.takeCapture view.identity store.fields.retained).bind _ = _
  cases selectionResult : UseScope.takeCapture view.identity store.fields.retained with
  | none => rfl
  | some selected =>
    rcases selected with ⟨captured, retained⟩
    dsimp only [Option.bind]
    split
    · simp only [templateHeap, UseScope.acquire_at_map]
      cases acquisitionResult : UseScope.acquireAt shape view store with
      | none => rfl
      | some acquired =>
        simp only [Option.map_some, UseScope.TypedAcquisition.mapFuture,
          partition_image_corresponds, template_admission_corresponds]
        cases Source.Multi.admit (Source.Multi.partitionImage partition acquired.future arena) with
        | none => rfl
        | some admitted =>
          simp only [Option.map_some, frozen, remaining_arena_corresponds, templateHeap]
    · rfl

end Defunctionalization
end BoundaryV2.Generalized
