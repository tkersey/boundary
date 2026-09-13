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

def frozen (source : Source.Multi.Frozen signature algebra program shape) : Target.Multi.Frozen signature algebra program shape :=
  ⟨source.identity, template source.template, templateHeap source.store, templateArena source.arena⟩

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
