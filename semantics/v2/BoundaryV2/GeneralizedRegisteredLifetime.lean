import BoundaryV2.GeneralizedScopeClosure
import BoundaryV2.GeneralizedRegisteredResume

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Runtime-held template bindings and dormant/active futures are mandatory
roots of the lifetime check, even if no current operand references them. -/
def Source.Multi.Runtime.closeLifetime (wanted : Id .scope) (forest : Scope.Forest)
    (runtime : Runtime signature algebra program result)
    (outside : Context signature algebra program input result)
    (returned : RuntimeValue signature algebra program input) (external : List Reference) :
    Option (Scope.Tree × Scope.Forest) :=
  Source.closeLifetime wanted forest runtime.control.store runtime.arena.cells outside returned
    (registryReferences runtime.registry ++ runtime.arena.references ++ external)

def Target.Multi.Runtime.closeLifetime (wanted : Id .scope) (forest : Scope.Forest)
    (runtime : Runtime signature algebra program result)
    (outside : Stack signature algebra program input result)
    (returned : RuntimeValue signature algebra program input) (external : List Reference) :
    Option (Scope.Tree × Scope.Forest) :=
  Target.closeLifetime wanted forest runtime.control.store runtime.arena.cells outside returned
    (registryReferences runtime.registry ++ runtime.arena.references ++ external)

theorem Defunctionalization.registered_lifetime_closure_corresponds
    (wanted : Id .scope) (forest : Scope.Forest)
    {source : Source.Multi.Runtime signature algebra program result}
    {target : Target.Multi.Runtime signature algebra program result}
    (related : MultiDataRelated source target)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (returned : Source.RuntimeValue signature algebra program input) (external : List Reference) :
    target.closeLifetime wanted forest targetOutside (value returned) external =
      source.closeLifetime wanted forest sourceOutside returned external := by
  unfold Source.Multi.Runtime.closeLifetime Target.Multi.Runtime.closeLifetime
  rw [related.registry, registry_reference_support, related.arena, template_arena_references]
  exact lifetime_closure_corresponds wanted forest related.store source.arena.cells outside returned _

end BoundaryV2.Generalized
