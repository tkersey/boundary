import BoundaryV2.GeneralizedSourceExecution

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

namespace Source

/-- Ordinary work may proceed inside a retained scope. These rules do not close
the scope or discharge its cleanup: those are separate exit transitions. -/
theorem Step.under_frame {before after : Program signature algebra program input} (step : Step (table : Definitions signature algebra program) before after)
    (frame : Frame signature algebra program input result) :
    Step table (frame.plug before) (frame.plug after) := by
  cases frame with
  | bind next => exact .bindStep step
  | handler effect mode attachment returned clauses bindings => exact .handlerStep step
  | region identity => exact .regionStep step
  | protection identity cleanup bindings => exact .protectionStep step

theorem Step.in_context {before after : Program signature algebra program input} (step : Step (table : Definitions signature algebra program) before after)
    (outside : Context signature algebra program input result) :
    Step table (outside.plug before) (outside.plug after) := by
  cases outside with
  | done => exact step
  | push frame rest => exact (step.under_frame frame).in_context rest
termination_by outside.length
decreasing_by simp_all [Context.length]

theorem Steps.in_context {before after : Program signature algebra program input} (steps : Steps (table : Definitions signature algebra program) before count after)
    (outside : Context signature algebra program input result) :
    Steps table (outside.plug before) count (outside.plug after) := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (step.in_context outside) induction

theorem Frame.forward_yield (table : Definitions signature algebra program)
    (frame : Frame signature algebra program input result) (body : Program signature algebra program input) :
    Step table (frame.plug (.yielded body)) (.yielded (frame.plug body)) := by
  cases frame with
  | bind next => exact .bindYield
  | handler effect mode attachment returned clauses bindings => exact .handlerYield
  | region identity => exact .regionYield
  | protection identity cleanup bindings => exact .protectionYield

/-- A yield crosses each enclosing frame once, preserving the entire suspended
future. Region and protection frames remain present; no cleanup is discharged. -/
theorem Context.forward_yield (table : Definitions signature algebra program)
    (outside : Context signature algebra program input result) (body : Program signature algebra program input) :
    Steps table (outside.plug (.yielded body)) outside.length (.yielded (outside.plug body)) := by
  cases outside with
  | done => exact .refl
  | push frame rest => exact .cons ((frame.forward_yield table body).in_context rest) (rest.forward_yield table (frame.plug body))
termination_by outside.length
decreasing_by simp_all [Context.length]

end Source

namespace Target

/-- Enclosing a first-order state appends frames to its actual future,
including a parked request or authored yield. No evaluator callback is added. -/
def Configuration.in_context (outside : Stack signature algebra program input result) :
    Configuration signature algebra program input → Configuration signature algebra program result
  | .code body bindings operands future => .code body bindings operands (future.append outside)
  | .returned value future => .returned value (future.append outside)
  | .requested operation attachment payload bodies future =>
    .requested operation attachment payload bodies (future.append outside)
  | .failed fault future => .failed fault (future.append outside)
  | .yielded next => .yielded (next.in_context outside)

theorem Configuration.in_context_done (configuration : Configuration signature algebra program result) :
    configuration.in_context .done = configuration := by
  induction configuration <;> simp_all only [Configuration.in_context, Stack.append_done]

theorem Configuration.in_context_compose (configuration : Configuration signature algebra program input)
    (inside : Stack signature algebra program input middle) (outside : Stack signature algebra program middle result) :
    (configuration.in_context inside).in_context outside = configuration.in_context (inside.append outside) := by
  induction configuration <;> simp_all only [Configuration.in_context, Stack.append_associative]

theorem CallStep.in_context {before after : Configuration signature algebra program input} (step : CallStep (table : Definitions signature algebra program) before after)
    (outside : Stack signature algebra program input result) :
    CallStep table (before.in_context outside) (after.in_context outside) := by
  cases step with
  | operand step => exact .operand step
  | returned => exact .returned
  | enter => exact .enter
  | branchLeft selected => exact .branchLeft selected
  | branchRight selected => exact .branchRight selected
  | block => exact .block
  | named => exact .named
  | closure => exact .closure
  | dispatch => exact .dispatch
  | attach => exact .attach
  | handlerReturned => exact .handlerReturned
  | caller => exact .caller
  | callerFault => exact .callerFault
  | handlerFault => exact .handlerFault
  | fault => exact .fault
  | yield => exact .yield

theorem CallSteps.in_context {before after : Configuration signature algebra program input} (steps : CallSteps (table : Definitions signature algebra program) before count after)
    (outside : Stack signature algebra program input result) :
    CallSteps table (before.in_context outside) count (after.in_context outside) := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (step.in_context outside) induction

end Target

namespace Defunctionalization

theorem EntryRelated.in_context
    (entry : EntryRelated (source : Source.Program signature algebra program input) target)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    EntryRelated (sourceOutside.plug source) (target.in_context targetOutside) := by
  cases entry with
  | evaluate body bindings future =>
    simpa only [Target.Configuration.in_context, Source.Context.append_plug] using
      EntryRelated.evaluate body bindings (context_composition future outside)
  | returned value future =>
    simpa only [Target.Configuration.in_context, Source.Context.append_plug] using
      EntryRelated.returned value (context_composition future outside)
  | failed fault future =>
    simpa only [Target.Configuration.in_context, Source.Context.append_plug] using
      EntryRelated.failed fault (context_composition future outside)
  | requested operation attachment payload bodies future =>
    simpa only [Target.Configuration.in_context, Source.Context.append_plug] using
      EntryRelated.requested operation attachment payload bodies (context_composition future outside)

/-- Finite corresponding executions compose with every represented enclosing
context without adding execution fuel or replacing its handler interpretation.
The local execution hypotheses are the already-proved constructor laws; this
lifting lemma alone is not the missing whole-computation adequacy theorem. -/
theorem corresponding_executions_in_context
    {sourceBefore sourceAfter : Source.Program signature algebra program input}
    {targetBefore targetAfter : Target.Configuration signature algebra program input}
    (table : Source.Definitions signature algebra program)
    (sourceSteps : Source.Steps table sourceBefore sourceCount sourceAfter)
    (targetSteps : Target.CallSteps (definitions table) targetBefore targetCount targetAfter)
    (entry : EntryRelated (sourceBefore : Source.Program signature algebra program input) targetBefore)
    (exit : EntryRelated (sourceAfter : Source.Program signature algebra program input) targetAfter)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Source.Steps table (sourceOutside.plug sourceBefore) sourceCount (sourceOutside.plug sourceAfter) ∧
      Target.CallSteps (definitions table) (targetBefore.in_context targetOutside) targetCount (targetAfter.in_context targetOutside) ∧
      EntryRelated (sourceOutside.plug sourceBefore) (targetBefore.in_context targetOutside) ∧
      EntryRelated (sourceOutside.plug sourceAfter) (targetAfter.in_context targetOutside) :=
  ⟨sourceSteps.in_context _, targetSteps.in_context _, entry.in_context outside, exit.in_context outside⟩

end Defunctionalization
end BoundaryV2.Generalized
