import BoundaryV2.GeneralizedSourceExecution

namespace BoundaryV2.Generalized

namespace Source

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {definitions : List (BodyType signature.Data signature.Effect)}

inductive Observation (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | returned : RuntimeValue signature algebra definitions result → Observation signature algebra definitions result
  | failed : algebra.Fault → Observation signature algebra definitions result
  | yielded : Program signature algebra definitions result → Observation signature algebra definitions result
  | requested : (operation : signature.operation effect) → Id .attachment →
    RuntimeValue signature algebra definitions (signature.payload operation) →
    RuntimeEnvironment signature algebra definitions ((signature.bodies operation).map BodyType.type) →
    Context signature algebra definitions (signature.result operation) result → Observation signature algebra definitions result

/-- Only a root request is externally visible in the higher-order source.
Handlers and binds interpret/forward their child requests before this rule applies. -/
inductive HeadObservation : Program signature algebra definitions result → Observation signature algebra definitions result → Prop where
  | returned : HeadObservation (.returned value) (.returned value)
  | failed : HeadObservation (.failed fault) (.failed fault)
  | yielded : HeadObservation (.yielded next) (.yielded next)
  | requested : HeadObservation (.request operation attachment payload bodies future) (.requested operation attachment payload bodies future)

/-- Finite derivations, not execution fuel. No observation is manufactured when
reduction diverges or when a required transition has not been established. -/
def Observes (table : Definitions signature algebra definitions) (program : Program signature algebra definitions result)
    (observation : Observation signature algebra definitions result) : Prop :=
  ∃ count final, Steps table program count final ∧ HeadObservation final observation

theorem Observes.prepend (steps : Steps table before count after) (observed : Observes table after observation) :
    Observes table before observation := by
  obtain ⟨rest, final, tail, head⟩ := observed
  exact ⟨count + rest, final, steps.trans tail, head⟩

end Source

namespace Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {definitions : List (BodyType signature.Data signature.Effect)}

def Clauses.operations : Clauses signature algebra definitions effect mode context body answer → List (signature.operation effect)
  | .nil => []
  | .cons operation _ _ rest => operation :: rest.operations

/-- A dispatch packet is still internal when the nearest attachment handles
its operation. Merely reaching `Configuration.requested` is not an external event. -/
def Handles (operation : signature.operation effect) (attachment : Id .attachment)
    (future : Stack signature algebra definitions (signature.result operation) result) : Prop :=
  ∃ (mode : Mode) (context : List (TypeOf signature)) (body answer : TypeOf signature)
    (returned : Code signature algebra definitions (body :: context) [] answer)
    (clauses : Clauses signature algebra definitions effect mode context body answer)
    (bindings : RuntimeEnvironment signature algebra definitions context)
    (inside : Stack signature algebra definitions (signature.result operation) body)
    (outside : Stack signature algebra definitions answer result),
      select attachment future = some ⟨effect, mode, attachment, body, answer, context, returned, clauses, bindings, inside, outside⟩ ∧
      operation ∈ clauses.operations

inductive Observation (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | returned : RuntimeValue signature algebra definitions result → Observation signature algebra definitions result
  | failed : algebra.Fault → Observation signature algebra definitions result
  | yielded : Configuration signature algebra definitions result → Observation signature algebra definitions result
  | requested : (operation : signature.operation effect) → Id .attachment →
    RuntimeValue signature algebra definitions (signature.payload operation) →
    RuntimeEnvironment signature algebra definitions ((signature.bodies operation).map BodyType.type) →
    Stack signature algebra definitions (signature.result operation) result → Observation signature algebra definitions result

inductive HeadObservation : Configuration signature algebra definitions result → Observation signature algebra definitions result → Prop where
  | returned : HeadObservation (.returned value .done) (.returned value)
  | failed : HeadObservation (.failed fault .done) (.failed fault)
  | yielded : HeadObservation (.yielded next) (.yielded next)
  | requested : ¬ Handles operation attachment future →
      HeadObservation (.requested operation attachment payload bodies future) (.requested operation attachment payload bodies future)

def Observes (table : Definitions signature algebra definitions) (configuration : Configuration signature algebra definitions result)
    (observation : Observation signature algebra definitions result) : Prop :=
  ∃ count final, CallSteps table configuration count final ∧ HeadObservation final observation

theorem Observes.prepend (steps : CallSteps table before count after) (observed : Observes table after observation) :
    Observes table before observation := by
  obtain ⟨rest, final, tail, head⟩ := observed
  exact ⟨count + rest, final, steps.trans tail, head⟩

theorem no_selection_is_external (operation : signature.operation effect) (attachment : Id .attachment)
    (future : Stack signature algebra definitions (signature.result operation) result)
    (absent : select attachment future = none) : ¬ Handles operation attachment future := by
  rintro ⟨mode, context, body, answer, returned, clauses, bindings, inside, outside, selected, _⟩
  rw [absent] at selected
  contradiction

theorem handled_dispatch_is_not_external (handled : Handles operation attachment future) :
    ¬ HeadObservation (.requested operation attachment payload bodies future)
      (.requested operation attachment payload bodies future) := by
  intro observed
  cases observed with
  | requested external => exact external handled

end Target

namespace Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Request correspondence retains the complete typed future as well as the
operation, attachment, payload, and scoped computation arguments. -/
inductive ObservationRelated : Source.Observation signature algebra program result → Target.Observation signature algebra program result → Prop where
  | returned (value : Source.RuntimeValue signature algebra program result) :
      ObservationRelated (.returned value) (.returned (Defunctionalization.value value))
  | failed (fault : algebra.Fault) : ObservationRelated (.failed fault) (.failed fault)
  | yielded (next : EntryRelated source target) : ObservationRelated (.yielded source) (.yielded target)
  | requested (operation : signature.operation effect) (attachment : Id .attachment)
      (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
      (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
      {sourceFuture : Source.Context signature algebra program (signature.result operation) result}
      {targetFuture : Target.Stack signature algebra program (signature.result operation) result}
      (future : ContextRelated signature algebra program sourceFuture targetFuture) :
      ObservationRelated (.requested operation attachment payload bodies sourceFuture)
        (.requested operation attachment (value payload) (environment bodies) targetFuture)

/-- Every return-only administrative stack matched with an empty source
context drains in finitely many actual target instructions. -/
theorem empty_context_return_drains (table : Target.Definitions signature algebra program)
    (future : ContextRelated signature algebra program (.done : Source.Context signature algebra program result result) target)
    (value : Target.RuntimeValue signature algebra program result) :
    ∃ count, Target.CallSteps table (.returned value target) count (.returned value .done) := by
  cases future with
  | done => exact ⟨0, .refl⟩
  | passthrough bindings rest =>
    obtain ⟨count, steps⟩ := empty_context_return_drains table rest value
    exact ⟨2 + count, (return_passthrough_takes_two_steps table value (environment bindings) .nil _).trans steps⟩
termination_by sizeOf target

theorem empty_future_preserves_every_response (table : Source.Definitions signature algebra program)
    (future : ContextRelated signature algebra program (.done : Source.Context signature algebra program result result) target)
    (response : Source.RuntimeValue signature algebra program result) :
    Source.Observes table (.returned response) (.returned response) ∧
      Target.Observes (definitions table) (.returned (value response) target) (.returned (value response)) := by
  obtain ⟨count, steps⟩ := empty_context_return_drains (definitions table) future (value response)
  exact ⟨⟨0, _, .refl, .returned⟩, ⟨count, _, steps, .returned⟩⟩

end Defunctionalization
end BoundaryV2.Generalized
