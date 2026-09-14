import BoundaryV2.GeneralizedControlCorrespondence
import BoundaryV2.GeneralizedResumptions
import BoundaryV2.GeneralizedTypeEquality

namespace BoundaryV2.Generalized

/-- A registry holds every continuation shape together. Shape is stored data,
not a parameter that prevents a clause from creating a differently typed future. -/
structure ControlShape (signature : Signature) where
  mode : Mode
  effect : signature.Effect
  input : TypeOf signature
  answer : TypeOf signature

instance [DecidableEq signature.Data] [DecidableEq signature.Effect] : DecidableEq (ControlShape signature) := by
  intro first second
  cases first with
  | mk mode effect input answer => cases second with
    | mk nextMode nextEffect nextInput nextAnswer =>
      exact decidable_of_iff' (mode = nextMode ∧ effect = nextEffect ∧ input = nextInput ∧ answer = nextAnswer)
        (by simp only [ControlShape.mk.injEq])

abbrev Source.ControlPayload (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) :=
  Source.Resumption signature algebra program shape.mode shape.effect shape.input shape.answer

abbrev Target.ControlPayload (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) :=
  Target.Resumption signature algebra program shape.mode shape.effect shape.input shape.answer

abbrev Source.ControlHeap (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) :=
  UseScope.ControlStore (Sigma (Source.ControlPayload signature algebra program))

abbrev Target.ControlHeap (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) :=
  UseScope.ControlStore (Sigma (Target.ControlPayload signature algebra program))

namespace UseScope

variable {Index : Type} {Payload SourcePayload TargetPayload : Index → Type}

def unpackControl [DecidableEq Index] (shape : Index) (packed : Sigma Payload) : Option (Payload shape) :=
  if same : packed.fst = shape then some (same ▸ packed.snd) else none

theorem unpack_control_exact [DecidableEq Index] (shape : Index) (payload : Payload shape) :
    unpackControl shape ⟨shape, payload⟩ = some payload := by simp [unpackControl]

theorem unpack_control_wrong_shape [DecidableEq Index] (different : original ≠ requested) (payload : Payload original) :
    unpackControl requested ⟨original, payload⟩ = none := by simp [unpackControl, different]

structure TypedAcquisition (Payload : Index → Type) (shape : Index) where
  store : ControlStore (Sigma Payload)
  future : Payload shape

/-- A rejected type check returns no successor state. No consumed state escapes
from this pure operation until both authority and the complete shape match. -/
def acquireAt [DecidableEq Index] (shape : Index) (view : ControlView) (store : ControlStore (Sigma Payload)) :
    Option (TypedAcquisition Payload shape) :=
  (acquire view store).bind fun acquired =>
    (unpackControl shape acquired.future).map fun future => ⟨acquired.store, future⟩

theorem acquire_at_recovers_typed_future [DecidableEq Index] {shape : Index}
    {store after : ControlStore (Sigma Payload)} {future : Payload shape}
    (accepted : acquire view store = some ⟨after, ⟨shape, future⟩⟩) :
    acquireAt shape view store = some (⟨after, future⟩ : TypedAcquisition Payload shape) := by
  simp only [acquireAt, accepted, Option.bind_some, unpack_control_exact, Option.map_some]

theorem acquire_at_consumes_before_entry [DecidableEq Index] {shape : Index} {store : ControlStore (Sigma Payload)}
    {result : TypedAcquisition Payload shape}
    (valid : ControlStore.Valid store)
    (accepted : acquireAt shape view store = some result) :
    ControlStore.Valid result.store ∧ view.authority ∉ inventory result.store.fields ∧
      acquireAt shape view result.store = none := by
  obtain ⟨acquired, consumed, unpacked⟩ := Option.bind_eq_some_iff.mp accepted
  obtain ⟨future, _, rfl⟩ := Option.map_eq_some_iff.mp unpacked
  exact ⟨acquire_preserves_ownership valid consumed, acquired_authority_not_live valid consumed,
    by simp only [acquireAt, acquired_view_cannot_repeat valid consumed, Option.bind_none]⟩

inductive PackedControlRelated (related : ∀ shape, SourcePayload shape → TargetPayload shape → Prop) :
    Sigma SourcePayload → Sigma TargetPayload → Prop where
  | same : related shape source target → PackedControlRelated related ⟨shape, source⟩ ⟨shape, target⟩

theorem unpack_control_corresponds [DecidableEq Index]
    (related : ∀ shape, SourcePayload shape → TargetPayload shape → Prop)
    (packed : PackedControlRelated related source target) (shape : Index) :
    Option.Rel (related shape) (unpackControl shape source) (unpackControl shape target) := by
  cases packed with
  | @same original source target matching =>
    by_cases equal : original = shape
    · subst original
      simp only [unpack_control_exact]
      exact .some matching
    · simp only [unpack_control_wrong_shape equal]
      exact .none

structure TypedAcquisition.Related (related : ∀ shape, SourcePayload shape → TargetPayload shape → Prop)
    (source : TypedAcquisition SourcePayload shape) (target : TypedAcquisition TargetPayload shape) : Prop where
  store : ControlStore.Related (PackedControlRelated related) source.store target.store
  future : related shape source.future target.future

theorem acquire_at_corresponds [DecidableEq Index]
    (related : ∀ shape, SourcePayload shape → TargetPayload shape → Prop)
    (stores : ControlStore.Related (PackedControlRelated related) source target) (shape : Index) (view : ControlView) :
    Option.Rel (TypedAcquisition.Related related) (acquireAt shape view source) (acquireAt shape view target) := by
  have acquired := acquire_corresponds (PackedControlRelated related) stores view
  unfold acquireAt
  generalize sourceAt : acquire view source = sourceTaken at acquired ⊢
  generalize targetAt : acquire view target = targetTaken at acquired ⊢
  cases acquired with
  | none => exact .none
  | @some sourceEntry targetEntry matching =>
    have unpacked := unpack_control_corresponds related matching.future shape
    dsimp only [Option.bind]
    generalize sourceAt : unpackControl shape sourceEntry.future = sourceValue at unpacked ⊢
    generalize targetAt : unpackControl shape targetEntry.future = targetValue at unpacked ⊢
    cases unpacked with
    | none => exact .none
    | some futures => exact .some ⟨matching.store, futures⟩

end UseScope

namespace Defunctionalization

def controlPayloadRelated (shape : ControlShape signature)
    (source : Source.ControlPayload signature algebra program shape)
    (target : Target.ControlPayload signature algebra program shape) : Prop := ResumptionRelated source target

abbrev ControlHeapRelated (source : Source.ControlHeap signature algebra program)
    (target : Target.ControlHeap signature algebra program) :=
  UseScope.ControlStore.Related (UseScope.PackedControlRelated controlPayloadRelated) source target

end Defunctionalization
end BoundaryV2.Generalized
