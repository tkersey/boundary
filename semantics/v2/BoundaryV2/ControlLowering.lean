import BoundaryV2.Control

namespace BoundaryV2.Control.Target

open Core

/-- A closed first-order block with one typed parameter and one result. -/
abbrev Block (input output : Ty) := Code [input] [input] [] [output]

def Block.run (block : Block a b) (value : Value a) : Value b :=
  match (Core.Code.run block (.cons value .nil) .nil).2 with
  | .cons result .nil => result

inductive Frame : Ty → Ty → Type where
  | block : Block a b → Frame a b
  | delimiter : Nat → Block a b → Frame a b
  | region : Nat → Frame a a

def Frame.run : Frame a b → Value a → Value b
  | .block code, value => code.run value
  | .delimiter _ code, value => code.run value
  | .region _, value => value

inductive Stack : Ty → Ty → Type where
  | done : Stack a a
  | push : Frame a b → Stack b c → Stack a c

def Stack.append : Stack a b → Stack b c → Stack a c
  | .done, after => after
  | .push frame rest, after => .push frame (rest.append after)

def Stack.run : Stack a b → Value a → Value b
  | .done, value => value
  | .push frame rest, value => rest.run (frame.run value)

def compileFrame : Control.Frame a b → Frame a b
  | .bind expression => .block (Core.compile expression [])
  | .delimiter attachment returned => .delimiter attachment (Core.compile returned [])
  | .region owner => .region owner

def compileContext : Context a b → Stack a b
  | .done => .done
  | .push frame rest => .push (compileFrame frame) (compileContext rest)

theorem compiled_block_preserves_value (expression : Expr [a] b) (value : Value a) :
    Block.run (Core.compile expression []) value = expression.eval (.cons value .nil) := by
  unfold Block.run
  rw [Core.compile_preserves_value_and_scope]
  rfl

theorem compiled_frame_preserves_value (frame : Control.Frame a b) (value : Value a) :
    (compileFrame frame).run value = frame.run value := by
  cases frame with
  | bind expression => exact compiled_block_preserves_value expression value
  | delimiter _ expression => exact compiled_block_preserves_value expression value
  | region _ => rfl

theorem compilation_preserves_composition (before : Context a b) (after : Context b c) :
    compileContext (before.append after) = (compileContext before).append (compileContext after) := by
  induction before with
  | done => rfl
  | push frame rest ih => simp [Context.append, compileContext, Stack.append, ih]

theorem compiled_context_preserves_value (context : Context a b) (value : Value a) :
    (compileContext context).run value = context.run value := by
  induction context with
  | done => rfl
  | push frame rest ih =>
    simp [compileContext, Stack.run, compiled_frame_preserves_value, Context.run, ih]

structure Selection (input output : Ty) where
  body : Ty
  answer : Ty
  attachment : Nat
  inside : Stack input body
  returned : Block body answer
  outside : Stack answer output

def Selection.prepend (selected : Selection b c) (frame : Frame a b) : Selection a c :=
  { selected with inside := .push frame selected.inside }

def select (attachment : Nat) : Stack a b → Option (Selection a b)
  | .done => none
  | .push (.delimiter actual returned) rest =>
    if attachment = actual then
      some ⟨_, _, actual, .done, returned, rest⟩
    else (select attachment rest).map (fun selected => selected.prepend (.delimiter actual returned))
  | .push frame rest =>
    (select attachment rest).map (fun selected => selected.prepend frame)

def compileSelection (selected : Control.Selection a b) : Selection a b :=
  ⟨selected.body, selected.answer, selected.attachment, compileContext selected.inside,
    Core.compile selected.returned [], compileContext selected.outside⟩

theorem compilation_preserves_selection (context : Context a b) (attachment : Nat) :
    select attachment (compileContext context) =
      (Control.select attachment context).map compileSelection := by
  induction context with
  | done => rfl
  | push frame rest ih =>
    cases frame with
    | bind expression =>
      simp only [compileContext, compileFrame, select, Control.select, ih]
      cases Control.select attachment rest <;> rfl
    | region owner =>
      simp only [compileContext, compileFrame, select, Control.select, ih]
      cases Control.select attachment rest <;> rfl
    | delimiter actual returned =>
      simp only [compileContext, compileFrame, select, Control.select]
      split
      · rfl
      · rw [ih]
        cases Control.select attachment rest <;> rfl

def Selection.capture (selected : Selection a b) (mode : Mode) :
    Stack a (mode.result selected.body selected.answer) :=
  match mode with
  | .deep => selected.inside.append
      (.push (.delimiter selected.attachment selected.returned) .done)
  | .shallow => selected.inside

theorem compilation_preserves_capture (selected : Control.Selection a b) (mode : Mode) :
    (compileSelection selected).capture mode = compileContext (selected.capture mode) := by
  cases mode with
  | deep =>
    simp only [Selection.capture, Control.Selection.capture, compileSelection]
    rw [compilation_preserves_composition]
    rfl
  | shallow => rfl

theorem compilation_preserves_non_tail_resume (selected : Control.Selection a b)
    (mode : Mode) (argument : Value a)
    (post : Expr [mode.result selected.body selected.answer] selected.answer) :
    (((compileSelection selected).capture mode).append
      (.push (.block (Core.compile post [])) (compileContext selected.outside))).run argument =
      selected.resume mode argument post := by
  rw [compilation_preserves_capture]
  change ((compileContext (selected.capture mode)).append
    (compileContext (.push (.bind post) selected.outside))).run argument = _
  rw [← compilation_preserves_composition, compiled_context_preserves_value]
  exact non_tail_resume_retains_both_continuations selected mode argument post

/-- The source has an evaluation context; the target has explicit blocks and
return frames. This one-step relation is independent of either full evaluator. -/
structure SourcePosition (output : Ty) where
  input : Ty
  value : Value input
  context : Context input output

structure Position (output : Ty) where
  input : Ty
  value : Value input
  stack : Stack input output

inductive SourceReturn (output : Ty) where
  | running : SourcePosition output → SourceReturn output
  | returned : Value output → SourceReturn output

inductive Return (output : Ty) where
  | running : Position output → Return output
  | returned : Value output → Return output

def sourceStep : SourcePosition output → SourceReturn output
  | ⟨_, value, .done⟩ => .returned value
  | ⟨_, value, .push frame rest⟩ => .running ⟨_, frame.run value, rest⟩

def step : Position output → Return output
  | ⟨_, value, .done⟩ => .returned value
  | ⟨_, value, .push frame rest⟩ => .running ⟨_, frame.run value, rest⟩

def compilePosition (position : SourcePosition output) : Position output :=
  ⟨position.input, position.value, compileContext position.context⟩

def compileReturn : SourceReturn output → Return output
  | .running position => .running (compilePosition position)
  | .returned value => .returned value

theorem return_step_simulation (position : SourcePosition output) :
    step (compilePosition position) = compileReturn (sourceStep position) := by
  rcases position with ⟨input, value, context⟩
  cases context with
  | done => rfl
  | push frame rest =>
    simp [step, sourceStep, compileReturn, compilePosition, compileContext,
      compiled_frame_preserves_value]

/-- These budgets count observations in a proof, not execution fuel. The
transition definitions above contain no fuel or history counter. -/
def sourceSteps : Nat → SourceReturn output → SourceReturn output
  | 0, state => state
  | _ + 1, .returned value => .returned value
  | n + 1, .running position => sourceSteps n (sourceStep position)

def steps : Nat → Return output → Return output
  | 0, state => state
  | _ + 1, .returned value => .returned value
  | n + 1, .running position => steps n (step position)

theorem return_trace_simulation (count : Nat) (state : SourceReturn output) :
    steps count (compileReturn state) = compileReturn (sourceSteps count state) := by
  induction count generalizing state with
  | zero => rfl
  | succ count ih =>
    cases state with
    | returned value => rfl
    | running position =>
      change steps count (step (compilePosition position)) = _
      rw [return_step_simulation, ih]
      rfl

end BoundaryV2.Control.Target
