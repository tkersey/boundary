import BoundaryV2.GeneralizedControlPayload
import BoundaryV2.GeneralizedSuccessor

namespace BoundaryV2.Generalized

namespace Source

structure ControlState (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  store : ControlHeap signature algebra program
  computation : Program signature algebra program result

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

def resumeControl (shape : ControlShape signature) (view : UseScope.ControlView)
    (store : ControlHeap signature algebra program) (value : RuntimeValue signature algebra program shape.input)
    (outside : Context signature algebra program shape.answer result) : Option (ControlState signature algebra program result) :=
  (UseScope.acquireAt shape view store).map fun acquired =>
    ⟨acquired.store, outside.plug (reenter acquired.future (.returned value))⟩

def resumeControlWith (view : UseScope.ControlView) (store : ControlHeap signature algebra program)
    (value : RuntimeValue signature algebra program input)
    (returned : Computation signature algebra program (body :: context) answer)
    (clauses : Clauses signature algebra program effect .deep context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Context signature algebra program answer result) : Option (ControlState signature algebra program result) :=
  (UseScope.acquireAt ⟨.shallow, effect, input, body⟩ view store).map fun acquired =>
    ⟨acquired.store, reenterWith acquired.future value returned clauses bindings outside⟩

end Source

namespace Target

structure ControlState (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  store : ControlHeap signature algebra program
  configuration : Configuration signature algebra program result

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

def resumeControl (shape : ControlShape signature) (view : UseScope.ControlView)
    (store : ControlHeap signature algebra program) (value : RuntimeValue signature algebra program shape.input)
    (outside : Stack signature algebra program shape.answer result) : Option (ControlState signature algebra program result) :=
  (UseScope.acquireAt shape view store).map fun acquired => ⟨acquired.store, reenter acquired.future value outside⟩

def resumeControlWith (view : UseScope.ControlView) (store : ControlHeap signature algebra program)
    (value : RuntimeValue signature algebra program input)
    (returned : Code signature algebra program (body :: context) [] answer)
    (clauses : Clauses signature algebra program effect .deep context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Stack signature algebra program answer result) : Option (ControlState signature algebra program result) :=
  (UseScope.acquireAt ⟨.shallow, effect, input, body⟩ view store).map fun acquired =>
    ⟨acquired.store, reenterWith acquired.future value returned clauses bindings outside⟩

theorem resume_control_preserves_ownership {store : ControlHeap signature algebra program}
    (valid : UseScope.ControlStore.Valid store)
    (accepted : resumeControl shape view store value outside = some result) :
    UseScope.ControlStore.Valid result.store := by
  obtain ⟨acquired, consumed, rfl⟩ := Option.map_eq_some_iff.mp accepted
  exact (UseScope.acquire_at_consumes_before_entry valid consumed).1

theorem successor_control_preserves_ownership {store : ControlHeap signature algebra program}
    (valid : UseScope.ControlStore.Valid store)
    (accepted : resumeControlWith view store value returned clauses bindings outside = some result) :
    UseScope.ControlStore.Valid result.store := by
  obtain ⟨acquired, consumed, rfl⟩ := Option.map_eq_some_iff.mp accepted
  exact (UseScope.acquire_at_consumes_before_entry valid consumed).1

end Target

namespace Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

structure ControlStateRelated (source : Source.ControlState signature algebra program result)
    (target : Target.ControlState signature algebra program result) : Prop where
  store : ControlHeapRelated source.store target.store
  entry : EntryRelated source.computation target.configuration

variable [DecidableEq (ControlShape signature)]

theorem resume_control_corresponds
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore) (shape : ControlShape signature)
    (view : UseScope.ControlView) (input : Source.RuntimeValue signature algebra program shape.input)
    {sourceOutside : Source.Context signature algebra program shape.answer result}
    {targetOutside : Target.Stack signature algebra program shape.answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Option.Rel ControlStateRelated (Source.resumeControl shape view sourceStore input sourceOutside)
      (Target.resumeControl shape view targetStore (value input) targetOutside) := by
  have acquired := UseScope.acquire_at_corresponds controlPayloadRelated stores shape view
  unfold Source.resumeControl Target.resumeControl
  generalize sourceAt : UseScope.acquireAt shape view sourceStore = sourceTaken at acquired ⊢
  generalize targetAt : UseScope.acquireAt shape view targetStore = targetTaken at acquired ⊢
  cases acquired with
  | none => exact .none
  | some matching => exact .some ⟨matching.store, resumption_reentry_corresponds matching.future input outside⟩

theorem successor_control_corresponds
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore) (view : UseScope.ControlView)
    (inputValue : Source.RuntimeValue signature algebra program input)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect .deep context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Option.Rel ControlStateRelated (Source.resumeControlWith view sourceStore inputValue returned clauses bindings sourceOutside)
      (Target.resumeControlWith view targetStore (value inputValue) (computation returned) (Defunctionalization.clauses clauses)
        (environment bindings) targetOutside) := by
  have acquired := UseScope.acquire_at_corresponds controlPayloadRelated stores ⟨.shallow, effect, input, body⟩ view
  unfold Source.resumeControlWith Target.resumeControlWith
  generalize sourceAt : UseScope.acquireAt ⟨.shallow, effect, input, body⟩ view sourceStore = sourceTaken at acquired ⊢
  generalize targetAt : UseScope.acquireAt ⟨.shallow, effect, input, body⟩ view targetStore = targetTaken at acquired ⊢
  cases acquired with
  | none => exact .none
  | some matching => exact .some ⟨matching.store,
      successor_handler_reentry_corresponds matching.future inputValue returned clauses bindings outside⟩

end Defunctionalization
end BoundaryV2.Generalized
