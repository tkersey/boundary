import BoundaryV2.GeneralizedScopeClosure
import BoundaryV2.GeneralizedExitCompletion

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Support of the computation that actually survives an exit. Administrative
return metadata is handled by the same collector used for fresh installation. -/
def Target.Configuration.referenceSupport : Target.Configuration signature algebra program result → List Reference
  | .code body bindings values outside => body.references ++ Target.environmentReferences bindings ++
      Target.environmentReferences values ++ outside.installationReferences
  | .returned value outside => Target.valueReferences value ++ outside.installationReferences
  | .requested _ attachment payload bodies outside => .name .attachment attachment ::
      (Target.valueReferences payload ++ Target.environmentReferences bodies ++ outside.installationReferences)
  | .failed _ outside => outside.installationReferences
  | .yielded next => next.referenceSupport

namespace ExitComposition

def Resolution.referenceSupport : Resolution signature algebra program result → List Reference
  | .reenter state _ => Target.storeReferences state.control.store ++ Target.cellsReferences state.cells ++
      state.control.configuration.referenceSupport
  | .unwind runtime outside => Target.storeReferences runtime.store ++ Target.cellsReferences runtime.cells ++
      outside.installationReferences

structure LifetimeExit (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  resolution : Resolution signature algebra program result
  retired : Scope.Tree
  forest : Scope.Forest

/-- The lifetime owner supplies the scope being exited and any additional
roots, such as retained template registries. Cleanup must finish first; its
actual surviving state then determines whether that lifetime may close. -/
def finishLifetime (wanted : Id .scope) (forest : Scope.Forest)
    (scope : ScopeExit signature algebra program result) (external : List Reference) : Option (LifetimeExit signature algebra program result) :=
  (finish scope).bind fun resolution =>
    (Scope.closeSupported wanted forest (referenceNames (resolution.referenceSupport ++ external) .scope)).map
      fun (retired, remaining) => ⟨resolution, retired, remaining⟩

theorem lifetime_exit_follows_completed_cleanup
    (accepted : finishLifetime wanted forest scope external = some result) :
    finish scope = some result.resolution ∧
      Scope.closeSupported wanted forest (referenceNames (result.resolution.referenceSupport ++ external) .scope) =
        some (result.retired, result.forest) := by
  obtain ⟨resolution, completed, accepted⟩ := Option.bind_eq_some_iff.mp accepted
  obtain ⟨⟨retired, remaining⟩, closed, result⟩ := Option.map_eq_some_iff.mp accepted
  cases result
  exact ⟨completed, closed⟩

theorem pending_cleanup_cannot_close_its_lifetime
    (scope : ScopeExit signature algebra program result) (pending : scope.cleanup.phase = .pending body) :
    finishLifetime wanted forest scope external = none := by
  simp only [finishLifetime, pending_cleanup_cannot_reenter scope pending, Option.bind_none]

theorem running_cleanup_cannot_close_its_lifetime
    (scope : ScopeExit signature algebra program result) (running : scope.cleanup.phase = .running cursor location) :
    finishLifetime wanted forest scope external = none := by
  simp only [finishLifetime, unfinished_cleanup_cannot_reenter scope running, Option.bind_none]

theorem lifetime_exit_preserves_all_surviving_dependencies
    (accepted : finishLifetime wanted forest scope external = some result) :
    ∀ dependency ∈ referenceNames (result.resolution.referenceSupport ++ external) .scope,
      dependency ∈ Scope.names result.forest :=
  (Scope.supported_close_is_actual_detachment (lifetime_exit_follows_completed_cleanup accepted).2).2

theorem lifetime_exit_excludes_closed_dependencies (valid : Scope.Valid forest)
    (accepted : finishLifetime wanted forest scope external = some result) :
    ∀ dependency ∈ referenceNames (result.resolution.referenceSupport ++ external) .scope,
      dependency ∉ result.retired.names :=
  Scope.supported_close_excludes_retired_dependencies valid (lifetime_exit_follows_completed_cleanup accepted).2

theorem lifetime_exit_preserves_validity (valid : Scope.Valid forest)
    (accepted : finishLifetime wanted forest scope external = some result) : Scope.Valid result.forest :=
  Scope.supported_close_preserves_validity valid (lifetime_exit_follows_completed_cleanup accepted).2

/-- The checked close does not rewrite failure history, cancellation, the
returned value, physical resources, or the saved outside continuation. -/
theorem lifetime_exit_keeps_the_exact_resolution
    (completed : finish scope = some resolution)
    (accepted : finishLifetime wanted forest scope external = some result) : result.resolution = resolution := by
  have actual := (lifetime_exit_follows_completed_cleanup accepted).1
  rw [completed] at actual
  exact (Option.some.inj actual).symm

end ExitComposition
end BoundaryV2.Generalized
