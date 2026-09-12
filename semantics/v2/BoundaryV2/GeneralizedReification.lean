import BoundaryV2.GeneralizedSelection

namespace BoundaryV2.Generalized.Defunctionalization

/-- A source continuation function is represented by a target return-code
record. Handler clauses and their environments are translated as ordinary code. -/
inductive FrameRelated (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) :
    Source.Frame signature algebra program input output → Target.Frame signature algebra program input output → Prop where
  | bind (body : Source.Computation signature algebra program (input :: context) output)
      (captured : Source.RuntimeEnvironment signature algebra program context) :
      FrameRelated signature algebra program (.bind (fun value => .evaluate body (.cons value captured)))
        (.returnTo (.enter (computation body)) (environment captured) .nil)
  | handler (effect : signature.Effect) (mode : Mode) (identity : Id .attachment)
      (returned : Source.Computation signature algebra program (body :: context) answer)
      (handled : Source.Clauses signature algebra program effect mode context body answer)
      (captured : Source.RuntimeEnvironment signature algebra program context) :
      FrameRelated signature algebra program (.handler effect mode identity returned handled captured)
        (.handler effect mode identity (computation returned) (clauses handled) (environment captured))
  | region (identity : Id .region) : FrameRelated signature algebra program (.region identity) (.region identity)
  | protection (identity : Id .obligation) (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
      (captured : Source.RuntimeEnvironment signature algebra program context) :
      FrameRelated signature algebra program (.protection identity cleanup captured)
        (.protection identity (computation cleanup) (environment captured))

inductive ContextRelated (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) :
    Source.Context signature algebra program input output → Target.Stack signature algebra program input output → Prop where
  | done : ContextRelated signature algebra program .done .done
  | push : FrameRelated signature algebra program first second → ContextRelated signature algebra program rest after →
      ContextRelated signature algebra program (.push first rest) (.push second after)

theorem context_composition (first : ContextRelated signature algebra program sourceFirst targetFirst)
    (second : ContextRelated signature algebra program sourceSecond targetSecond) :
    ContextRelated signature algebra program (sourceFirst.append sourceSecond) (targetFirst.append targetSecond) := by
  induction first with
  | done => exact second
  | push frame rest induction => exact .push frame (induction second)

/-- This relation retains every selected component, including the different
body and answer types, the effectful clause bodies, and both context halves. -/
inductive SelectionRelated (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) :
    Source.Selection signature algebra program input output → Target.Selection signature algebra program input output → Prop where
  | selected (effect : signature.Effect) (mode : Mode) (identity : Id .attachment)
      (returned : Source.Computation signature algebra program (body :: context) answer)
      (handled : Source.Clauses signature algebra program effect mode context body answer)
      (captured : Source.RuntimeEnvironment signature algebra program context)
      (inside : ContextRelated signature algebra program sourceInside targetInside)
      (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
      SelectionRelated signature algebra program
        ⟨effect, mode, identity, body, answer, context, returned, handled, captured, sourceInside, sourceOutside⟩
        ⟨effect, mode, identity, body, answer, context, computation returned, clauses handled, environment captured, targetInside, targetOutside⟩

theorem SelectionRelated.prepend (frame : FrameRelated signature algebra program first second)
    (selected : SelectionRelated signature algebra program source target) :
    SelectionRelated signature algebra program (Source.Selection.prepend first source) (Target.Selection.prepend second target) := by
  cases selected with
  | selected effect mode identity returned handled captured inside outside =>
    exact .selected effect mode identity returned handled captured (.push frame inside) outside

private theorem selection_options_prepend (frame : FrameRelated signature algebra program first second)
    (selected : Option.Rel (SelectionRelated signature algebra program) source target) :
    Option.Rel (SelectionRelated signature algebra program)
      (source.map (Source.Selection.prepend first)) (target.map (Target.Selection.prepend second)) := by
  cases selected with
  | none => exact .none
  | some selected => exact .some (SelectionRelated.prepend frame selected)

/-- The independently implemented selectors agree for every represented context,
including their effectful handler code and the captured/outside halves. -/
theorem selection_corresponds (wanted : Id .attachment)
    (related : ContextRelated signature algebra program source target) :
    Option.Rel (SelectionRelated signature algebra program) (Source.select wanted source) (Target.select wanted target) := by
  induction related with
  | done => exact .none
  | push frame rest induction =>
    cases frame with
    | bind body captured => exact selection_options_prepend (.bind body captured) induction
    | region identity => exact selection_options_prepend (.region identity) induction
    | protection identity cleanup captured => exact selection_options_prepend (.protection identity cleanup captured) induction
    | handler effect mode identity returned handled captured =>
      simp only [Source.select, Target.select]
      by_cases same : wanted = identity
      · simp only [same, if_true]
        exact .some (.selected effect mode identity returned handled captured .done rest)
      · simp only [same, if_false]
        exact selection_options_prepend (.handler effect mode identity returned handled captured) induction

def capturedSource (mode : Mode) (inside : Source.Context signature algebra program input body)
    (delimiter : Source.Frame signature algebra program body answer) :
    Source.Context signature algebra program input (resumedType mode body answer) :=
  match mode with
  | .deep => inside.append (.push delimiter .done)
  | .shallow => inside

def capturedTarget (mode : Mode) (inside : Target.Stack signature algebra program input body)
    (delimiter : Target.Frame signature algebra program body answer) :
    Target.Stack signature algebra program input (resumedType mode body answer) :=
  match mode with
  | .deep => inside.append (.push delimiter .done)
  | .shallow => inside

/-- Deep capture retains the typed return delimiter; shallow capture stops
before it. Body-result and handler-answer types remain separate indices. -/
theorem capture_corresponds (mode : Mode) (inside : ContextRelated signature algebra program sourceInside targetInside)
    (delimiter : FrameRelated signature algebra program sourceDelimiter targetDelimiter) :
    ContextRelated signature algebra program (capturedSource mode sourceInside sourceDelimiter)
      (capturedTarget mode targetInside targetDelimiter) := by
  cases mode with
  | deep => exact context_composition inside (.push delimiter .done)
  | shallow => exact inside

/-- The resumed context and the clause's later computation are both retained.
The clause body is arbitrary syntax and may perform further operations. -/
theorem non_tail_caller_corresponds
    (inside : ContextRelated signature algebra program (sourceInside : Source.Context signature algebra program input answer) targetInside)
    (later : Source.Computation signature algebra program (answer :: context) result)
    (captured : Source.RuntimeEnvironment signature algebra program context) :
    ContextRelated signature algebra program
      (sourceInside.append (.push (.bind (fun value => .evaluate later (.cons value captured))) .done))
      (targetInside.append (.push (.returnTo (.enter (computation later)) (environment captured) .nil) .done)) :=
  context_composition inside (.push (.bind later captured) .done)

theorem non_tail_source_keeps_both_computations (inside : Source.Context signature algebra program input answer)
    (replacement : Source.Program signature algebra program input)
    (later : Source.Computation signature algebra program (answer :: context) result)
    (captured : Source.RuntimeEnvironment signature algebra program context) :
    (inside.append (.push (.bind (fun value => .evaluate later (.cons value captured))) .done)).plug replacement =
      Source.Program.bind (inside.plug replacement) (fun value => .evaluate later (.cons value captured)) :=
  Source.Context.append_plug _ _ _

end BoundaryV2.Generalized.Defunctionalization
