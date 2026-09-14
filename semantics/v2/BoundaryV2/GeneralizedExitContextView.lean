import BoundaryV2.GeneralizedStateObservations
import BoundaryV2.GeneralizedCleanupCompletion

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- Only transparent administrative callers precede the source frame. Their
finite drain preserves all current resources and retains the enclosing context. -/
theorem ContextRelated.expose_failed_frame
    {source : Source.Context signature algebra program input result}
    {target : Target.Stack signature algebra program input result}
    (related : ContextRelated signature algebra program source target)
    (table : Target.Definitions signature algebra program) (fault : algebra.Fault)
    (store : Target.ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) :
    ∀ {middle} (frame : Source.Frame signature algebra program input middle)
      (rest : Source.Context signature algebra program middle result), source = .push frame rest →
      ∃ targetFrame targetRest count,
        FrameRelated signature algebra program frame targetFrame ∧
        ContextRelated signature algebra program rest targetRest ∧
        Target.ExecutionSteps table ⟨⟨store, .failed fault target⟩, cells, regions⟩ count
          ⟨⟨store, .failed fault (.push targetFrame targetRest)⟩, cells, regions⟩ retained := by
  induction related with
  | done => intro middle frame rest same; cases same
  | push matching context induction =>
    intro middle frame rest same
    cases same
    exact ⟨_, _, 0, matching, context, .refl⟩
  | passthrough bindings context induction =>
    intro middle frame rest same
    obtain ⟨targetFrame, targetRest, count, matching, outside, steps⟩ := induction frame rest same
    exact ⟨targetFrame, targetRest, count + 1, matching, outside, .cons (.cell (.ordinary .callerFault)) steps⟩


theorem ContextRelated.expose_returned_frame
    {source : Source.Context signature algebra program input result}
    {target : Target.Stack signature algebra program input result}
    (related : ContextRelated signature algebra program source target)
    (table : Target.Definitions signature algebra program) (value : Target.RuntimeValue signature algebra program input)
    (store : Target.ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) :
    ∀ {middle} (frame : Source.Frame signature algebra program input middle)
      (rest : Source.Context signature algebra program middle result), source = .push frame rest →
      ∃ targetFrame targetRest count,
        FrameRelated signature algebra program frame targetFrame ∧
        ContextRelated signature algebra program rest targetRest ∧
        Target.ExecutionSteps table ⟨⟨store, .returned value target⟩, cells, regions⟩ count
          ⟨⟨store, .returned value (.push targetFrame targetRest)⟩, cells, regions⟩ retained := by
  induction related with
  | done => intro middle frame rest same; cases same
  | push matching context induction =>
    intro middle frame rest same
    cases same
    exact ⟨_, _, 0, matching, context, .refl⟩
  | passthrough bindings context induction =>
    intro middle frame rest same
    obtain ⟨targetFrame, targetRest, count, matching, outside, steps⟩ := induction value frame rest same
    exact ⟨targetFrame, targetRest, count + 2, matching, outside,
      .cons (.cell (.ordinary .caller)) (.cons (.cell (.ordinary .returned)) steps)⟩

theorem ContextRelated.expose_unwind_frame
    {source : Source.Context signature algebra program input result}
    {target : Target.Stack signature algebra program input result}
    (related : ContextRelated signature algebra program source target)
    (table : Target.Definitions signature algebra program)
    (runtime : ExitComposition.Runtime signature algebra program) (completed : runtime.phase = .finished completion) :
    ∀ {middle} (frame : Source.Frame signature algebra program input middle)
      (rest : Source.Context signature algebra program middle result), source = .push frame rest →
      ∃ targetFrame targetRest count,
        FrameRelated signature algebra program frame targetFrame ∧
        ContextRelated signature algebra program rest targetRest ∧
        ExitComposition.CleanupFrameSteps table (.running (.unwind runtime target)) count
          (.running (.unwind runtime (.push targetFrame targetRest))) retained := by
  rcases runtime with ⟨identity, phase, store, cells, regions, exit⟩
  dsimp only at completed
  subst phase
  induction related with
  | done => intro middle frame rest same; cases same
  | push matching context induction =>
    intro middle frame rest same
    cases same
    exact ⟨_, _, 0, matching, context, .refl⟩
  | passthrough bindings context induction =>
    intro middle frame rest same
    obtain ⟨targetFrame, targetRest, count, matching, outside, steps⟩ := induction frame rest same
    exact ⟨targetFrame, targetRest, count + 1, matching, outside, .cons (.unwind rfl) steps⟩

end BoundaryV2.Generalized.Defunctionalization
