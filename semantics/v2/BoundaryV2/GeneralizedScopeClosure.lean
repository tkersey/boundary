import BoundaryV2.GeneralizedScopeCapture
import BoundaryV2.GeneralizedInstallationSupport

namespace BoundaryV2.Generalized

namespace Scope

/-- Closing publishes a successor forest only when every surviving borrowed
scope remains live. Retained owned subtrees have already moved out of the
closing subtree through `retain`; they are not deleted with their creator. -/
def closeSupported (wanted : Id .scope) (forest : Forest) (dependencies : List (Id .scope)) :
    Option (Tree × Forest) :=
  (close wanted forest).bind fun (retired, remaining) =>
    if dependencies.all (fun dependency => dependency ∈ names remaining) then some (retired, remaining) else none

theorem supported_close_is_actual_detachment
    (accepted : closeSupported wanted forest dependencies = some (retired, remaining)) :
    close wanted forest = some (retired, remaining) ∧ ∀ dependency ∈ dependencies, dependency ∈ names remaining := by
  obtain ⟨⟨removed, after⟩, detached, accepted⟩ := Option.bind_eq_some_iff.mp accepted
  dsimp only at accepted
  split at accepted
  · rename_i supported
    cases accepted
    exact ⟨detached, by simpa only [List.all_eq_true, decide_eq_true_eq] using supported⟩
  · cases accepted

theorem supported_close_preserves_validity (valid : Valid forest)
    (accepted : closeSupported wanted forest dependencies = some (retired, remaining)) : Valid remaining := by
  have detached := (supported_close_is_actual_detachment accepted).1
  have all := (detach_names forest detached).nodup_iff.mp valid
  exact (List.nodup_append.mp all).2.1

theorem supported_close_excludes_retired_dependencies (valid : Valid forest)
    (accepted : closeSupported wanted forest dependencies = some (retired, remaining)) :
    ∀ dependency ∈ dependencies, dependency ∉ retired.names := by
  obtain ⟨detached, supported⟩ := supported_close_is_actual_detachment accepted
  intro dependency member removed
  exact closed_scopes_are_removed valid detached dependency removed (supported dependency member)

theorem supported_close_rejects_a_surviving_borrow (valid : Valid forest)
    (detached : close wanted forest = some (retired, remaining))
    (survives : dependency ∈ dependencies) (removed : dependency ∈ retired.names) :
    closeSupported wanted forest dependencies = none := by
  have absent := closed_scopes_are_removed valid detached dependency removed
  unfold closeSupported
  rw [detached]
  simp only [Option.bind_some]
  split
  · rename_i allowed
    have all : ∀ scope ∈ dependencies, scope ∈ names remaining := by
      simpa only [List.all_eq_true, decide_eq_true_eq] using allowed
    exact False.elim (absent (all dependency survives))
  · rfl

end Scope

namespace UseScope

/-- Fields are the actual surviving physical field tree. Extra support belongs
to saved code, returned views, and other declared roots; it does not replace
the references collected from those physical fields. -/
def closeScoped (wanted : Id .scope) (forest : Scope.Forest) (fields : List Field) (extra : List Reference) :
    Option (Scope.Tree × Scope.Forest) :=
  Scope.closeSupported wanted forest (borrowedScopes fields ++ referenceNames extra .scope)

theorem scoped_close_preserves_every_field_borrow
    (accepted : closeScoped wanted forest fields extra = some (retired, remaining)) :
    ∀ dependency ∈ borrowedScopes fields, dependency ∈ Scope.names remaining := by
  obtain ⟨_, supported⟩ := Scope.supported_close_is_actual_detachment accepted
  exact fun dependency member => supported dependency (List.mem_append_left _ member)

theorem scoped_close_preserves_code_dependencies
    (accepted : closeScoped wanted forest fields extra = some (retired, remaining)) :
    ∀ dependency ∈ referenceNames extra .scope, dependency ∈ Scope.names remaining := by
  obtain ⟨_, supported⟩ := Scope.supported_close_is_actual_detachment accepted
  exact fun dependency member => supported dependency (List.mem_append_right _ member)

end UseScope

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Scope liveness is checked against concrete surviving control, cells,
caller frames, and returned values. Region-to-scope association and any
additional external roots remain the enclosing lifetime owner's obligations. -/
def Source.closeLifetime (wanted : Id .scope) (forest : Scope.Forest)
    (store : ControlHeap signature algebra program)
    (cells : Cells signature algebra (Computation signature algebra program))
    (outside : Context signature algebra program input result)
    (returned : RuntimeValue signature algebra program input) (external : List Reference) :
    Option (Scope.Tree × Scope.Forest) :=
  UseScope.closeScoped wanted forest (store.fields.active ++ store.fields.retained ++ cells.fields)
    (storeReferences store ++ cellsReferences cells ++ outside.referenceSupport ++ valueReferences returned ++ external)

def Target.closeLifetime (wanted : Id .scope) (forest : Scope.Forest)
    (store : ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (outside : Stack signature algebra program input result)
    (returned : RuntimeValue signature algebra program input) (external : List Reference) :
    Option (Scope.Tree × Scope.Forest) :=
  UseScope.closeScoped wanted forest (store.fields.active ++ store.fields.retained ++ cells.fields)
    (storeReferences store ++ cellsReferences cells ++ outside.installationReferences ++ valueReferences returned ++ external)

theorem Defunctionalization.lifetime_closure_corresponds
    (wanted : Id .scope) (forest : Scope.Forest)
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (returned : Source.RuntimeValue signature algebra program input) (external : List Reference) :
    Target.closeLifetime wanted forest targetStore (cells sourceCells) targetOutside (value returned) external =
      Source.closeLifetime wanted forest sourceStore sourceCells sourceOutside returned external := by
  simp only [Target.closeLifetime, Source.closeLifetime, stores.fields, store_reference_support stores,
    cell_installation_support, context_reference_support outside, value_reference_support]
  congr 2
  exact Cells.mapBodies_fields _ sourceCells

end BoundaryV2.Generalized
