import BoundaryV2.GeneralizedFutureRelocation

namespace BoundaryV2.Generalized.Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

def relocateTypedAcquisition (relocation : UseScope.Relocation)
    (acquired : UseScope.TypedAcquisition (ControlPayload signature algebra program) shape) :
    UseScope.TypedAcquisition (ControlPayload signature algebra program) shape :=
  ⟨relocateControlHeap relocation acquired.store, acquired.future.relocate relocation⟩

theorem unpack_relocated_control (relocation : UseScope.Relocation) (shape : ControlShape signature)
    (packed : Sigma (ControlPayload signature algebra program)) :
    UseScope.unpackControl shape (relocateControlPayload relocation packed) =
      (UseScope.unpackControl shape packed).map (Resumption.relocate relocation) := by
  cases packed with
  | mk original future =>
    by_cases same : original = shape
    · subst original
      simp only [relocateControlPayload, UseScope.unpack_control_exact, Option.map_some]
    · simp only [relocateControlPayload, UseScope.unpack_control_wrong_shape same, Option.map_none]

theorem typed_acquisition_relocation (relocation : UseScope.Relocation) (shape : ControlShape signature)
    (view : UseScope.ControlView) (store : ControlHeap signature algebra program)
    (faithful : UseScope.LookupRelocation relocation view store) :
    UseScope.acquireAt shape (view.relocate relocation) (relocateControlHeap relocation store) =
      (UseScope.acquireAt shape view store).map (relocateTypedAcquisition relocation) := by
  unfold UseScope.acquireAt relocateControlHeap
  rw [UseScope.acquire_relocate relocation (relocateControlPayload relocation) view store faithful]
  cases UseScope.acquire view store with
  | none => rfl
  | some acquired =>
    simp only [Option.map_some, Option.bind_some, UseScope.Acquisition.relocate]
    rw [unpack_relocated_control]
    cases UseScope.unpackControl shape acquired.future <;> rfl

theorem owned_resumption_relocation (relocation : UseScope.Relocation) (shape : ControlShape signature)
    (view : UseScope.ControlView) (store : ControlHeap signature algebra program)
    (value : RuntimeValue signature algebra program shape.input) (outside : Stack signature algebra program shape.answer result)
    (faithful : UseScope.LookupRelocation relocation view store) :
    resumeControl shape (view.relocate relocation) (relocateControlHeap relocation store)
        (relocateValue relocation value) (outside.relocate relocation) =
      (resumeControl shape view store value outside).map (ControlState.relocate relocation) := by
  unfold resumeControl
  rw [typed_acquisition_relocation relocation shape view store faithful]
  cases UseScope.acquireAt shape view store with
  | none => rfl
  | some acquired =>
    simp only [Option.map_some, relocateTypedAcquisition, ControlState.relocate,
      relocation_commutes_with_reentry]

theorem owned_injection_relocation (relocation : UseScope.Relocation) (shape : ControlShape signature)
    (view : UseScope.ControlView) (store : ControlHeap signature algebra program)
    (body : Entry signature algebra program shape.input) (outside : Stack signature algebra program shape.answer result)
    (faithful : UseScope.LookupRelocation relocation view store) :
    injectControl shape (view.relocate relocation) (relocateControlHeap relocation store)
        (body.relocate relocation) (outside.relocate relocation) =
      (injectControl shape view store body outside).map (ControlState.relocate relocation) := by
  unfold injectControl
  rw [typed_acquisition_relocation relocation shape view store faithful]
  cases UseScope.acquireAt shape view store with
  | none => rfl
  | some acquired =>
    simp only [Option.map_some, relocateTypedAcquisition, ControlState.relocate,
      relocation_commutes_with_injection]

theorem owned_successor_relocation (relocation : UseScope.Relocation)
    (view : UseScope.ControlView) (store : ControlHeap signature algebra program)
    (value : RuntimeValue signature algebra program input)
    (returned : Code signature algebra program (body :: context) [] answer)
    (clauses : Clauses signature algebra program effect .deep context body answer)
    (bindings : RuntimeEnvironment signature algebra program context) (outside : Stack signature algebra program answer result)
    (faithful : UseScope.LookupRelocation relocation view store) :
    resumeControlWith (view.relocate relocation) (relocateControlHeap relocation store) (relocateValue relocation value)
        (returned.relocate relocation) (clauses.relocate relocation) (relocateEnvironment relocation bindings) (outside.relocate relocation) =
      (resumeControlWith view store value returned clauses bindings outside).map (ControlState.relocate relocation) := by
  unfold resumeControlWith
  rw [typed_acquisition_relocation relocation _ view store faithful]
  cases UseScope.acquireAt ⟨.shallow, effect, input, body⟩ view store with
  | none => rfl
  | some acquired =>
    simp only [Option.map_some, relocateTypedAcquisition, ControlState.relocate,
      relocation_commutes_with_successor]

end BoundaryV2.Generalized.Target
