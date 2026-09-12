import BoundaryV2.GeneralizedResumptions
import BoundaryV2.GeneralizedControlCorrespondence

namespace BoundaryV2.Generalized.Source

structure Resumed (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (mode : Mode)
    (effect : signature.Effect) (input answer result : TypeOf signature) where
  store : UseScope.ControlStore (Resumption signature algebra program mode effect input answer)
  computation : Program signature algebra program result

def resumeOwned (view : UseScope.ControlView)
    (store : UseScope.ControlStore (Resumption signature algebra program mode effect input answer))
    (value : RuntimeValue signature algebra program input) (outside : Context signature algebra program answer result) :
    Option (Resumed signature algebra program mode effect input answer result) :=
  (UseScope.acquire view store).map fun acquired => ⟨acquired.store, outside.plug (reenter acquired.future (.returned value))⟩

def injectOwned (view : UseScope.ControlView)
    (store : UseScope.ControlStore (Resumption signature algebra program mode effect input answer))
    (body : Computation signature algebra program context input) (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Context signature algebra program answer result) :
    Option (Resumed signature algebra program mode effect input answer result) :=
  (UseScope.acquire view store).map fun acquired => ⟨acquired.store, outside.plug (reenter acquired.future (.evaluate body bindings))⟩

end BoundaryV2.Generalized.Source

namespace BoundaryV2.Generalized.Target

structure Resumed (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (mode : Mode)
    (effect : signature.Effect) (input answer result : TypeOf signature) where
  store : UseScope.ControlStore (Resumption signature algebra program mode effect input answer)
  configuration : Configuration signature algebra program result

/-- The only future used here is the one returned by acquisition. The resulting
configuration is paired with the state in which its authority is already spent. -/
def resumeOwned (view : UseScope.ControlView)
    (store : UseScope.ControlStore (Resumption signature algebra program mode effect input answer))
    (value : RuntimeValue signature algebra program input) (outside : Stack signature algebra program answer result) :
    Option (Resumed signature algebra program mode effect input answer result) :=
  (UseScope.acquire view store).map fun acquired => ⟨acquired.store, reenter acquired.future value outside⟩

def injectOwned (view : UseScope.ControlView)
    (store : UseScope.ControlStore (Resumption signature algebra program mode effect input answer))
    (body : Entry signature algebra program input) (outside : Stack signature algebra program answer result) :
    Option (Resumed signature algebra program mode effect input answer result) :=
  (UseScope.acquire view store).map fun acquired => ⟨acquired.store, inject acquired.future body outside⟩

theorem resume_owned_consumes_before_entry (valid : UseScope.ControlStore.Valid store)
    (resumed : resumeOwned view store value outside = some result) :
    UseScope.ControlStore.Valid result.store ∧ view.authority ∉ UseScope.inventory result.store.fields ∧
      resumeOwned view result.store value outside = none := by
  obtain ⟨acquired, accepted, rfl⟩ := Option.map_eq_some_iff.mp resumed
  exact ⟨UseScope.acquire_preserves_ownership valid accepted, UseScope.acquired_authority_not_live valid accepted,
    by simp only [resumeOwned, UseScope.acquired_view_cannot_repeat valid accepted, Option.map_none]⟩

theorem injected_computation_consumes_before_entry (valid : UseScope.ControlStore.Valid store)
    (injected : injectOwned view store body outside = some result) :
    UseScope.ControlStore.Valid result.store ∧ view.authority ∉ UseScope.inventory result.store.fields ∧
      injectOwned view result.store body outside = none := by
  obtain ⟨acquired, accepted, rfl⟩ := Option.map_eq_some_iff.mp injected
  exact ⟨UseScope.acquire_preserves_ownership valid accepted, UseScope.acquired_authority_not_live valid accepted,
    by simp only [injectOwned, UseScope.acquired_view_cannot_repeat valid accepted, Option.map_none]⟩

end BoundaryV2.Generalized.Target

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

structure OwnedEntryRelated
    (source : Source.Resumed signature algebra program mode effect input answer result)
    (target : Target.Resumed signature algebra program mode effect input answer result) : Prop where
  store : UseScope.ControlStore.Related ResumptionRelated source.store target.store
  entry : EntryRelated source.computation target.configuration

/-- This relates both acceptance and rejection of an actual store lookup. On
acceptance, the stored futures are entered only after the shared authority has
been consumed. The outside clause caller remains a separate continuation. -/
theorem owned_resumption_corresponds
    {sourceStore : UseScope.ControlStore (Source.Resumption signature algebra program mode effect inputType answer)}
    {targetStore : UseScope.ControlStore (Target.Resumption signature algebra program mode effect inputType answer)}
    (stores : UseScope.ControlStore.Related ResumptionRelated sourceStore targetStore)
    (view : UseScope.ControlView) (input : Source.RuntimeValue signature algebra program inputType)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Option.Rel OwnedEntryRelated (Source.resumeOwned view sourceStore input sourceOutside)
      (Target.resumeOwned view targetStore (value input) targetOutside) := by
  have acquired := UseScope.acquire_corresponds ResumptionRelated stores view
  unfold Source.resumeOwned Target.resumeOwned
  generalize sourceAt : UseScope.acquire view sourceStore = sourceTaken at acquired ⊢
  generalize targetAt : UseScope.acquire view targetStore = targetTaken at acquired ⊢
  cases acquired with
  | none => exact .none
  | some matching => exact .some ⟨matching.store, resumption_reentry_corresponds matching.future input outside⟩

theorem owned_injection_corresponds
    {sourceStore : UseScope.ControlStore (Source.Resumption signature algebra program mode effect inputType answer)}
    {targetStore : UseScope.ControlStore (Target.Resumption signature algebra program mode effect inputType answer)}
    (stores : UseScope.ControlStore.Related ResumptionRelated sourceStore targetStore)
    (view : UseScope.ControlView) (body : Source.Computation signature algebra program context inputType)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Option.Rel OwnedEntryRelated (Source.injectOwned view sourceStore body bindings sourceOutside)
      (Target.injectOwned view targetStore ⟨context, computation body, environment bindings⟩ targetOutside) := by
  have acquired := UseScope.acquire_corresponds ResumptionRelated stores view
  unfold Source.injectOwned Target.injectOwned
  generalize sourceAt : UseScope.acquire view sourceStore = sourceTaken at acquired ⊢
  generalize targetAt : UseScope.acquire view targetStore = targetTaken at acquired ⊢
  cases acquired with
  | none => exact .none
  | some matching => exact .some ⟨matching.store, computation_injection_corresponds matching.future body bindings outside⟩

end BoundaryV2.Generalized.Defunctionalization
