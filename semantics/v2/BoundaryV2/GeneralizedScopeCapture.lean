import BoundaryV2.GeneralizedScopes
import BoundaryV2.GeneralizedOwnership

namespace BoundaryV2.Generalized.UseScope

mutual
  def Field.borrowedScopes : Field → List (Id .scope)
    | .borrowed scope => [scope]
    | .owned _ _ | .alias _ => []
    | .group fields | .closure fields | .continuation _ fields | .package fields | .cleanup _ fields => borrowedScopes fields
  def borrowedScopes : List Field → List (Id .scope)
    | [] => []
    | field :: rest => field.borrowedScopes ++ borrowedScopes rest
end

structure ScopedPackage where
  lifetime : Scope.Retained
  fields : State

/-- This local package operation moves the selected physical fields and their
owned scope subtree together. Borrow checks inspect the actual field tree,
including dormant closures, continuations, packages, and cleanup captures.
The enclosing ownership interpretation supplies `ownedScope`; this operation
does not infer which subtree a value owns or dependencies embedded in its code. -/
def packageScoped (ownedScope destination : Id .scope) (forest : Scope.Forest)
    (before selected after retained : List Field) (spent : List (Id .custody)) : Option ScopedPackage :=
  (Scope.retain ownedScope destination (borrowedScopes selected) forest).map fun lifetime =>
    ⟨lifetime, package before selected after retained spent⟩

theorem scoped_package_preserves_ownership
    (valid : Valid ⟨before ++ selected ++ after, retained, spent⟩)
    (accepted : packageScoped ownedScope destination forest before selected after retained spent = some result) : Valid result.fields := by
  obtain ⟨lifetime, _, rfl⟩ := Option.map_eq_some_iff.mp accepted
  exact package_preserves_ownership _ _ _ _ _ valid

theorem scoped_package_preserves_scope_forest (valid : Scope.Valid forest)
    (accepted : packageScoped ownedScope destination forest before selected after retained spent = some result) : Scope.Valid result.lifetime.forest := by
  obtain ⟨lifetime, moved, rfl⟩ := Option.map_eq_some_iff.mp accepted
  exact Scope.retain_preserves_validity valid moved

theorem scoped_package_checks_all_borrows
    (accepted : packageScoped ownedScope destination forest before selected after retained spent = some result) :
    ∃ owned remaining, Scope.detach ownedScope forest = some (owned, remaining) ∧
      ∀ dependency ∈ borrowedScopes selected,
        dependency ∈ owned.names ∨ Scope.permitsBorrow remaining destination dependency = true := by
  obtain ⟨lifetime, moved, _⟩ := Option.map_eq_some_iff.mp accepted
  obtain ⟨owned, remaining, detached, _, checked⟩ := Scope.retain_checks_dependencies moved
  exact ⟨owned, remaining, detached, checked⟩

end BoundaryV2.Generalized.UseScope
