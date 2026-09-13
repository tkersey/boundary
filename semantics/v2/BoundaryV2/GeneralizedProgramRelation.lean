import BoundaryV2.GeneralizedContextExecution

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Relate a higher-order program to its current first-order execution state.
The outside stack is explicit, so entering an arbitrary clause or lexical bind
can reuse the same relation. Constructors describe code and captured data;
none assumes that the two programs have equal observations. -/
inductive ProgramRelated : {input result : TypeOf signature} →
    Source.Program signature algebra program input → Target.Stack signature algebra program input result →
    Target.Configuration signature algebra program result → Prop where
  | evaluate (body : Source.Computation signature algebra program context input)
      (bindings : Source.RuntimeEnvironment signature algebra program context)
      (outside : Target.Stack signature algebra program input result) :
      ProgramRelated (.evaluate body bindings) outside (.code (computation body) (environment bindings) .nil outside)
  | returned (value : Source.RuntimeValue signature algebra program input)
      (outside : Target.Stack signature algebra program input result) :
      ProgramRelated (.returned value) outside (.returned (Defunctionalization.value value) outside)
  | failed (fault : algebra.Fault) (outside : Target.Stack signature algebra program input result) :
      ProgramRelated (.failed fault) outside (.failed fault outside)
  | bind (body : Source.Computation signature algebra program (input :: context) answer)
      (bindings : Source.RuntimeEnvironment signature algebra program context)
      (inner : ProgramRelated source (.push (.returnTo (.enter (computation body)) (environment bindings) .nil) outside) target) :
      ProgramRelated (.bind source (fun value => .evaluate body (.cons value bindings))) outside target
  | handler (effect : signature.Effect) (mode : Mode) (attachment : Id .attachment)
      (returned : Source.Computation signature algebra program (input :: context) answer)
      (clauses : Source.Clauses signature algebra program effect mode context input answer)
      (bindings : Source.RuntimeEnvironment signature algebra program context)
      (inner : ProgramRelated source (.push (.handler effect mode attachment (computation returned)
        (Defunctionalization.clauses clauses) (environment bindings)) outside) target) :
      ProgramRelated (.handler effect mode attachment returned clauses bindings source) outside target
  | region (identity : Id .region)
      (inner : ProgramRelated source (.push (.region identity) outside) target) :
      ProgramRelated (.region identity source) outside target
  | protection (identity : Id .obligation)
      (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
      (bindings : Source.RuntimeEnvironment signature algebra program context)
      (inner : ProgramRelated source (.push (.protection identity (computation cleanup) (environment bindings)) outside) target) :
      ProgramRelated (.protection identity cleanup bindings source) outside target
  | requested (operation : signature.operation effect) (attachment : Id .attachment)
      (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
      (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
      {sourceFuture : Source.Context signature algebra program (signature.result operation) input}
      {targetFuture : Target.Stack signature algebra program (signature.result operation) input}
      (saved : ContextRelated signature algebra program sourceFuture targetFuture)
      (outside : Target.Stack signature algebra program input result) :
      ProgramRelated (.request operation attachment payload bodies sourceFuture) outside
        (.requested operation attachment (value payload) (environment bodies) (targetFuture.append outside))
  | yielded (inner : ProgramRelated source outside target) : ProgramRelated (.yielded source) outside (.yielded target)
  | passthrough (bindings : Source.RuntimeEnvironment signature algebra program context)
      (inner : ProgramRelated source (.push (.returnTo .ret (environment bindings) .nil) outside) target) :
      ProgramRelated source outside target

theorem ProgramRelated.in_context
    {inside : Target.Stack signature algebra program input middle}
    {target : Target.Configuration signature algebra program middle}
    (related : ProgramRelated (source : Source.Program signature algebra program input) inside target)
    (outside : Target.Stack signature algebra program middle result) :
    ProgramRelated source (inside.append outside) (target.in_context outside) := by
  induction related with
  | evaluate body bindings future => exact .evaluate body bindings _
  | returned value future => exact .returned value _
  | failed fault future => exact .failed fault _
  | bind body bindings inner induction => exact .bind body bindings (induction outside)
  | handler effect mode attachment returned clauses bindings inner induction =>
    exact .handler effect mode attachment returned clauses bindings (induction outside)
  | region identity inner induction => exact .region identity (induction outside)
  | protection identity cleanup bindings inner induction => exact .protection identity cleanup bindings (induction outside)
  | requested operation attachment payload bodies saved future =>
    simpa only [Target.Configuration.in_context, Target.Stack.append_associative] using
      ProgramRelated.requested operation attachment payload bodies saved (future.append outside)
  | yielded inner induction => exact .yielded (induction outside)
  | passthrough bindings inner induction => exact .passthrough bindings (induction outside)

/-- Reify the enclosing context into the source program while closing the
target's outside parameter. This preserves the actual suspended target state. -/
theorem ContextRelated.close_program
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {source : Source.Program signature algebra program input}
    {target : Target.Configuration signature algebra program result}
    (related : ProgramRelated source targetOutside target) :
    ProgramRelated (sourceOutside.plug source) .done target := by
  induction outside with
  | done => exact related
  | passthrough bindings rest induction => exact induction (.passthrough bindings related)
  | push frame rest induction =>
    cases frame with
    | bind body bindings => exact induction (.bind body bindings related)
    | handler effect mode attachment returned clauses bindings => exact induction (.handler effect mode attachment returned clauses bindings related)
    | region identity => exact induction (.region identity related)
    | protection identity cleanup bindings => exact induction (.protection identity cleanup bindings related)

theorem EntryRelated.as_program
    (related : EntryRelated (source : Source.Program signature algebra program result) target) :
    ProgramRelated source .done target := by
  cases related with
  | evaluate body bindings outside => exact outside.close_program (.evaluate body bindings _)
  | returned value outside => exact outside.close_program (.returned value _)
  | failed fault outside => exact outside.close_program (.failed fault _)

theorem ProgramRelated.returned_drains
    (related : ProgramRelated (source : Source.Program signature algebra program input) outside target)
    (table : Target.Definitions signature algebra program)
    (returned : Source.RuntimeValue signature algebra program input) (same : source = .returned returned) :
    ∃ count, Target.CallSteps table target count (.returned (value returned) outside) := by
  induction related with
  | returned value future => cases same; exact ⟨0, .refl⟩
  | passthrough bindings inner induction =>
    obtain ⟨count, steps⟩ := induction returned same
    exact ⟨count + 2, steps.trans (return_passthrough_takes_two_steps table _ (environment bindings) .nil _)⟩
  | evaluate | failed | bind | handler | region | protection | requested | yielded => cases same

theorem ProgramRelated.failed_drains
    (related : ProgramRelated (source : Source.Program signature algebra program input) outside target)
    (table : Target.Definitions signature algebra program)
    (fault : algebra.Fault) (same : source = .failed fault) :
    ∃ count, Target.CallSteps table target count (.failed fault outside) := by
  induction related with
  | failed failure future => cases same; exact ⟨0, .refl⟩
  | passthrough bindings inner induction =>
    obtain ⟨count, steps⟩ := induction same
    exact ⟨count + 1, steps.trans (.single .callerFault)⟩
  | evaluate | returned | bind | handler | region | protection | requested | yielded => cases same

theorem ProgramRelated.yielded_view
    (related : ProgramRelated (source : Source.Program signature algebra program input) outside target)
    (next : Source.Program signature algebra program input) (same : source = .yielded next) :
    ∃ targetNext, target = .yielded targetNext ∧ ProgramRelated next outside targetNext := by
  induction related with
  | yielded inner induction => cases same; exact ⟨_, rfl, inner⟩
  | passthrough bindings inner induction =>
    obtain ⟨nextTarget, rfl, nextRelated⟩ := induction next same
    exact ⟨nextTarget, rfl, .passthrough bindings nextRelated⟩
  | evaluate | returned | failed | bind | handler | region | protection | requested => cases same

theorem ProgramRelated.requested_view
    (related : ProgramRelated (source : Source.Program signature algebra program input) outside target)
    (operation : signature.operation effect) (attachment : Id .attachment)
    (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (sourceFuture : Source.Context signature algebra program (signature.result operation) input)
    (same : source = .request operation attachment payload bodies sourceFuture) :
    ∃ targetFuture, ContextRelated signature algebra program sourceFuture targetFuture ∧
      target = .requested operation attachment (value payload) (environment bodies) (targetFuture.append outside) := by
  induction related with
  | requested original identity originalPayload originalBodies saved future => cases same; exact ⟨_, saved, rfl⟩
  | passthrough bindings inner induction =>
    obtain ⟨future, saved, targetAt⟩ := induction sourceFuture same
    refine ⟨future.append (.push (.returnTo .ret (environment bindings) .nil) .done), ?_, ?_⟩
    · simpa only [Source.Context.append_done] using context_composition saved (.passthrough bindings .done)
    · simpa only [Target.Stack.append_associative, Target.Stack.append] using targetAt
  | evaluate | returned | failed | bind | handler | region | protection | yielded => cases same

end BoundaryV2.Generalized.Defunctionalization
