import BoundaryV2.GeneralizedOwnedClause

namespace BoundaryV2.Generalized

namespace Source

/-- The shallow future keeps its original use-site attachment. Its successor
supplies new effectful clauses and may change the body result to another answer
type. The surrounding clause caller remains outside that successor. -/
def reenterWith (saved : Resumption signature algebra program .shallow effect input body)
    (value : RuntimeValue signature algebra program input)
    (returned : Computation signature algebra program (body :: context) answer)
    (clauses : Clauses signature algebra program effect .deep context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Context signature algebra program answer result) : Program signature algebra program result :=
  outside.plug (.handler effect .deep saved.attachment returned clauses bindings (reenter saved (.returned value)))

def resumeOwnedWith (view : UseScope.ControlView)
    (store : UseScope.ControlStore (Resumption signature algebra program .shallow effect input body))
    (value : RuntimeValue signature algebra program input)
    (returned : Computation signature algebra program (body :: context) answer)
    (clauses : Clauses signature algebra program effect .deep context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Context signature algebra program answer result) :
    Option (Resumed signature algebra program .shallow effect input body result) :=
  (UseScope.acquire view store).map fun acquired =>
    ⟨acquired.store, reenterWith acquired.future value returned clauses bindings outside⟩

end Source

namespace Target

def reenterWith (saved : Resumption signature algebra program .shallow effect input body)
    (value : RuntimeValue signature algebra program input)
    (returned : Code signature algebra program (body :: context) [] answer)
    (clauses : Clauses signature algebra program effect .deep context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Stack signature algebra program answer result) : Configuration signature algebra program result :=
  .returned value (saved.future.append (.push (.handler effect .deep saved.attachment returned clauses bindings) outside))

def resumeOwnedWith (view : UseScope.ControlView)
    (store : UseScope.ControlStore (Resumption signature algebra program .shallow effect input body))
    (value : RuntimeValue signature algebra program input)
    (returned : Code signature algebra program (body :: context) [] answer)
    (clauses : Clauses signature algebra program effect .deep context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Stack signature algebra program answer result) :
    Option (Resumed signature algebra program .shallow effect input body result) :=
  (UseScope.acquire view store).map fun acquired =>
    ⟨acquired.store, reenterWith acquired.future value returned clauses bindings outside⟩

theorem successor_consumes_authority_before_entry (valid : UseScope.ControlStore.Valid store)
    (accepted : resumeOwnedWith view store value returned clauses bindings outside = some result) :
    UseScope.ControlStore.Valid result.store ∧ view.authority ∉ UseScope.inventory result.store.fields ∧
      resumeOwnedWith view result.store value returned clauses bindings outside = none := by
  obtain ⟨acquired, consumed, rfl⟩ := Option.map_eq_some_iff.mp accepted
  exact ⟨UseScope.acquire_preserves_ownership valid consumed, UseScope.acquired_authority_not_live valid consumed,
    by simp only [resumeOwnedWith, UseScope.acquired_view_cannot_repeat valid consumed, Option.map_none]⟩

end Target

namespace Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

theorem successor_handler_reentry_corresponds
    {source : Source.Resumption signature algebra program .shallow effect input body}
    {target : Target.Resumption signature algebra program .shallow effect input body}
    (saved : ResumptionRelated source target)
    (inputValue : Source.RuntimeValue signature algebra program input)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect .deep context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    EntryRelated (Source.reenterWith source inputValue returned clauses bindings sourceOutside)
      (Target.reenterWith target (value inputValue) (computation returned) (Defunctionalization.clauses clauses)
        (environment bindings) targetOutside) := by
  have matched := EntryRelated.returned inputValue (context_composition saved.future
    (.push (.handler effect .deep source.attachment returned clauses bindings) outside))
  simpa only [Source.reenterWith, Target.reenterWith, Source.reenter, Source.Context.append_plug,
    Source.Context.plug, Source.Frame.plug, saved.attachment] using matched

theorem owned_successor_corresponds
    {sourceStore : UseScope.ControlStore (Source.Resumption signature algebra program .shallow effect input body)}
    {targetStore : UseScope.ControlStore (Target.Resumption signature algebra program .shallow effect input body)}
    (stores : UseScope.ControlStore.Related ResumptionRelated sourceStore targetStore)
    (view : UseScope.ControlView) (inputValue : Source.RuntimeValue signature algebra program input)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect .deep context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Option.Rel OwnedEntryRelated (Source.resumeOwnedWith view sourceStore inputValue returned clauses bindings sourceOutside)
      (Target.resumeOwnedWith view targetStore (value inputValue) (computation returned) (Defunctionalization.clauses clauses)
        (environment bindings) targetOutside) := by
  have acquired := UseScope.acquire_corresponds ResumptionRelated stores view
  unfold Source.resumeOwnedWith Target.resumeOwnedWith
  generalize sourceAt : UseScope.acquire view sourceStore = sourceTaken at acquired ⊢
  generalize targetAt : UseScope.acquire view targetStore = targetTaken at acquired ⊢
  cases acquired with
  | none => exact .none
  | some matching => exact .some ⟨matching.store,
      successor_handler_reentry_corresponds matching.future inputValue returned clauses bindings outside⟩

end Defunctionalization
end BoundaryV2.Generalized
