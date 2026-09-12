import BoundaryV2.GeneralizedResumptions
import BoundaryV2.GeneralizedControlStore

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
