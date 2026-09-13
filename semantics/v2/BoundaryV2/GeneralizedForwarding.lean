import BoundaryV2.GeneralizedProgramRelation

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

def Source.Clauses.operations : Source.Clauses signature algebra program effect mode context body answer → List (signature.operation effect)
  | .nil => []
  | .cons operation _ _ rest => operation :: rest.operations

def Target.Clauses.operations : Target.Clauses signature algebra program effect mode context body answer → List (signature.operation effect)
  | .nil => []
  | .cons operation _ _ rest => operation :: rest.operations

/-- Forwarding preserves every frame. A matching handler permits it only for
an operation absent from its clauses; a wrong-family collision is not external. -/
inductive Source.Forwards (operation : signature.operation effect) (attachment : Id .attachment) :
    {input result : TypeOf signature} → Source.Context signature algebra program input result → Prop where
  | done : Forwards operation attachment .done
  | bind (next : Source.RuntimeValue signature algebra program input → Source.Program signature algebra program middle)
      (description : Source.BindDescription signature algebra program input middle)
      (tail : Forwards operation attachment rest) : Forwards operation attachment (.push (.bind next description) rest)
  | region (identity : Id .region) (tail : Forwards operation attachment rest) : Forwards operation attachment (.push (.region identity) rest)
  | protection (identity : Id .obligation) (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
      (bindings : Source.RuntimeEnvironment signature algebra program context) (tail : Forwards operation attachment rest) :
      Forwards operation attachment (.push (.protection identity cleanup bindings) rest)
  | different (otherEffect : signature.Effect) (mode : Mode) (identity : Id .attachment)
      (returned : Source.Computation signature algebra program (input :: context) middle)
      (clauses : Source.Clauses signature algebra program otherEffect mode context input middle)
      (bindings : Source.RuntimeEnvironment signature algebra program context)
      (different : attachment ≠ identity) (tail : Forwards operation attachment rest) :
      Forwards operation attachment (.push (.handler otherEffect mode identity returned clauses bindings) rest)
  | unhandled (mode : Mode)
      (returned : Source.Computation signature algebra program (input :: context) middle)
      (clauses : Source.Clauses signature algebra program effect mode context input middle)
      (bindings : Source.RuntimeEnvironment signature algebra program context)
      (absent : operation ∉ clauses.operations) (tail : Forwards operation attachment rest) :
      Forwards operation attachment (.push (.handler effect mode attachment returned clauses bindings) rest)

/-- The first-order check reads target frames and target clause identities.
It does not invoke the source interpreter. -/
inductive Target.Forwards (operation : signature.operation effect) (attachment : Id .attachment) :
    {input result : TypeOf signature} → Target.Stack signature algebra program input result → Prop where
  | done : Forwards operation attachment .done
  | returnTo (next : Target.Code signature algebra program context (input :: operands) middle)
      (bindings : Target.RuntimeEnvironment signature algebra program context)
      (values : Target.RuntimeEnvironment signature algebra program operands)
      (tail : Forwards operation attachment rest) : Forwards operation attachment (.push (.returnTo next bindings values) rest)
  | region (identity : Id .region) (tail : Forwards operation attachment rest) : Forwards operation attachment (.push (.region identity) rest)
  | protection (identity : Id .obligation) (cleanup : Target.Code signature algebra program (.exit :: context) [] .unit)
      (bindings : Target.RuntimeEnvironment signature algebra program context) (tail : Forwards operation attachment rest) :
      Forwards operation attachment (.push (.protection identity cleanup bindings) rest)
  | different (otherEffect : signature.Effect) (mode : Mode) (identity : Id .attachment)
      (returned : Target.Code signature algebra program (input :: context) [] middle)
      (clauses : Target.Clauses signature algebra program otherEffect mode context input middle)
      (bindings : Target.RuntimeEnvironment signature algebra program context)
      (different : attachment ≠ identity) (tail : Forwards operation attachment rest) :
      Forwards operation attachment (.push (.handler otherEffect mode identity returned clauses bindings) rest)
  | unhandled (mode : Mode)
      (returned : Target.Code signature algebra program (input :: context) [] middle)
      (clauses : Target.Clauses signature algebra program effect mode context input middle)
      (bindings : Target.RuntimeEnvironment signature algebra program context)
      (absent : operation ∉ clauses.operations) (tail : Forwards operation attachment rest) :
      Forwards operation attachment (.push (.handler effect mode attachment returned clauses bindings) rest)

theorem Defunctionalization.clause_operations (source : Source.Clauses signature algebra program effect mode context body answer) :
    (clauses source).operations = source.operations := by
  suffices ∀ bound (source : Source.Clauses signature algebra program effect mode context body answer),
      source.length ≤ bound → (clauses source).operations = source.operations from this source.length source (Nat.le_refl _)
  intro bound
  induction bound with
  | zero =>
    intro source sized
    cases source with
    | nil => rfl
    | cons operation use body rest => simp [Source.Clauses.length] at sized
  | succ bound induction =>
    intro source sized
    cases source with
    | nil => rfl
    | cons operation use body rest =>
      simp only [clauses, Source.Clauses.operations, Target.Clauses.operations,
        induction rest (by simpa [Source.Clauses.length] using sized)]

theorem Source.Clauses.lookup_none_iff [DecidableEq (signature.operation effect)]
    (source : Source.Clauses signature algebra program effect mode context body answer) :
    source.lookup operation = none ↔ operation ∉ source.operations := by
  cases source with
  | nil => simp [lookup, operations]
  | cons candidate use body rest =>
    by_cases same : candidate = operation
    · subst candidate
      simp [lookup, operations]
    · simp [lookup, operations, same, Ne.symm same, lookup_none_iff rest]
termination_by source.length
decreasing_by simp_all [Source.Clauses.length]

theorem Defunctionalization.forwarding_corresponds
    (related : ContextRelated signature algebra program source target) :
    Source.Forwards operation attachment source ↔ Target.Forwards operation attachment target := by
  induction related with
  | done => exact ⟨fun _ => .done, fun _ => .done⟩
  | passthrough bindings rest induction =>
    constructor
    · intro sourceForward
      exact .returnTo _ _ _ (induction.mp sourceForward)
    · intro targetForward
      cases targetForward with
      | returnTo next bindings values tail => exact induction.mpr tail
  | push frame rest induction =>
    cases frame with
    | bind body bindings =>
      constructor
      · intro forward; cases forward with
        | bind next description tail => exact .returnTo _ _ _ (induction.mp tail)
      · intro forward; cases forward with
        | returnTo next bindings values tail => exact .bind _ _ (induction.mpr tail)
    | region identity =>
      constructor
      · intro forward; cases forward with
        | region identity tail => exact .region _ (induction.mp tail)
      · intro forward; cases forward with
        | region identity tail => exact .region _ (induction.mpr tail)
    | protection identity cleanup bindings =>
      constructor
      · intro forward; cases forward with
        | protection identity cleanup bindings tail => exact .protection _ _ _ (induction.mp tail)
      · intro forward; cases forward with
        | protection identity cleanup bindings tail => exact .protection _ _ _ (induction.mpr tail)
    | handler effect mode identity returned clauses bindings =>
      constructor
      · intro forward; cases forward with
        | different effect mode identity returned clauses bindings different tail => exact .different _ _ _ _ _ _ different (induction.mp tail)
        | unhandled mode returned clauses bindings absent tail => exact .unhandled _ _ _ _ (by simpa only [clause_operations] using absent) (induction.mp tail)
      · intro forward; cases forward with
        | different effect mode identity returned clauses bindings different tail => exact .different _ _ _ _ _ _ different (induction.mpr tail)
        | unhandled mode returned clauses bindings absent tail => exact .unhandled _ _ _ _ (by simpa only [clause_operations] using absent) (induction.mpr tail)

theorem Source.Forwards.append (first : Source.Forwards operation attachment inside)
    (second : Source.Forwards operation attachment outside) : Source.Forwards operation attachment (inside.append outside) := by
  induction first with
  | done => exact second
  | bind next description tail induction => exact .bind next description (induction second)
  | region identity tail induction => exact .region identity (induction second)
  | protection identity cleanup bindings tail induction => exact .protection identity cleanup bindings (induction second)
  | different effect mode identity returned clauses bindings different tail induction =>
    exact .different effect mode identity returned clauses bindings different (induction second)
  | unhandled mode returned clauses bindings absent tail induction => exact .unhandled mode returned clauses bindings absent (induction second)

theorem Source.Forwards.append_right
    (inside : Source.Context signature algebra program input middle)
    (outside : Source.Context signature algebra program middle result)
    (forward : Source.Forwards operation attachment (inside.append outside)) : Source.Forwards operation attachment outside := by
  suffices ∀ bound {input middle} (inside : Source.Context signature algebra program input middle),
      inside.length ≤ bound → ∀ (outside : Source.Context signature algebra program middle result),
      Source.Forwards operation attachment (inside.append outside) → Source.Forwards operation attachment outside from
    this inside.length inside (Nat.le_refl _) outside forward
  intro bound
  induction bound with
  | zero =>
    intro input middle inside sized outside forward
    cases inside with
    | done => exact forward
    | push frame rest => simp [Source.Context.length] at sized
  | succ bound induction =>
    intro input middle inside sized outside forward
    cases inside with
    | done => exact forward
    | push frame rest =>
      have smaller : rest.length ≤ bound := by simpa [Source.Context.length] using sized
      cases forward with
      | bind next description tail | region identity tail | protection identity cleanup bindings tail => exact induction rest smaller outside tail
      | different effect mode identity returned clauses bindings different tail | unhandled mode returned clauses bindings absent tail =>
        exact induction rest smaller outside tail

theorem Source.Forwards.expose_request
    {operation : signature.operation effect} {attachment : Id .attachment}
    {outside : Source.Context signature algebra program input result}
    (forward : Source.Forwards operation attachment outside)
    (table : Source.Definitions signature algebra program)
    (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (saved : Source.Context signature algebra program (signature.result operation) input) :
    Source.Steps table (outside.plug (.request operation attachment payload bodies saved)) outside.length
      (.request operation attachment payload bodies (saved.append outside)) := by
  classical
  induction forward with
  | done => simpa only [Source.Context.plug, Source.Context.length, Source.Context.append_done] using
      (Source.Steps.refl (table := table) (program := Source.Program.request operation attachment payload bodies saved))
  | bind next description tail induction =>
    simpa only [Source.Context.append_associative, Source.Context.append, Source.Context.plug, Source.Frame.plug, Source.Context.length] using
      Source.Steps.cons (Source.Step.in_context .bindRequest _) (induction _)
  | region identity tail induction =>
    simpa only [Source.Context.append_associative, Source.Context.append, Source.Context.plug, Source.Frame.plug, Source.Context.length] using
      Source.Steps.cons (Source.Step.in_context .regionRequest _) (induction _)
  | protection identity cleanup bindings tail induction =>
    simpa only [Source.Context.append_associative, Source.Context.append, Source.Context.plug, Source.Frame.plug, Source.Context.length] using
      Source.Steps.cons (Source.Step.in_context .protectionRequest _) (induction _)
  | different effect mode identity returned clauses bindings different tail induction =>
    simpa only [Source.Context.append_associative, Source.Context.append, Source.Context.plug, Source.Frame.plug, Source.Context.length] using
      Source.Steps.cons (Source.Step.in_context (.handlerForward different) _) (induction _)
  | unhandled mode returned clauses bindings absent tail induction =>
    simpa only [Source.Context.append_associative, Source.Context.append, Source.Context.plug, Source.Frame.plug, Source.Context.length] using
      Source.Steps.cons (Source.Step.in_context (.handlerUnhandled ((Source.Clauses.lookup_none_iff clauses).mpr absent)) _) (induction _)

theorem Target.Forwards.of_no_selection
    (operation : signature.operation effect) (attachment : Id .attachment)
    (future : Target.Stack signature algebra program input result)
    (absent : Target.select attachment future = none) : Target.Forwards operation attachment future := by
  induction future with
  | done => exact .done
  | push frame rest induction =>
    cases frame with
    | returnTo next bindings operands =>
      apply Target.Forwards.returnTo next bindings operands
      apply induction
      simpa only [Target.select, Option.map_eq_none_iff] using absent
    | region identity =>
      apply Target.Forwards.region identity
      apply induction
      simpa only [Target.select, Option.map_eq_none_iff] using absent
    | protection identity cleanup bindings =>
      apply Target.Forwards.protection identity cleanup bindings
      apply induction
      simpa only [Target.select, Option.map_eq_none_iff] using absent
    | handler effect mode identity returned clauses bindings =>
      by_cases same : attachment = identity
      · simp only [Target.select, if_pos same] at absent
        contradiction
      · apply Target.Forwards.different effect mode identity returned clauses bindings same
        apply induction
        simpa only [Target.select, if_neg same, Option.map_eq_none_iff] using absent

/-- Whether the nearest nominal delimiter contains this operation. Forwarding
additionally checks the rest of the stack before exposing a residual request. -/
def Target.Handles (operation : signature.operation effect) (attachment : Id .attachment)
    (future : Target.Stack signature algebra program input result) : Prop :=
  ∃ (mode : Mode) (context : List (TypeOf signature)) (body answer : TypeOf signature)
    (returned : Target.Code signature algebra program (body :: context) [] answer)
    (clauses : Target.Clauses signature algebra program effect mode context body answer)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (inside : Target.Stack signature algebra program input body)
    (outside : Target.Stack signature algebra program answer result),
      Target.select attachment future = some ⟨effect, mode, attachment, body, answer, context, returned, clauses, bindings, inside, outside⟩ ∧
      operation ∈ clauses.operations

private theorem Target.Handles.of_prepend
    (frame : Target.Frame signature algebra program input middle)
    (future : Target.Stack signature algebra program middle result)
    (selection : Target.select attachment (.push frame future) = (Target.select attachment future).map (Target.Selection.prepend frame))
    (handled : Target.Handles operation attachment (.push frame future)) : Target.Handles operation attachment future := by
  obtain ⟨mode, context, body, answer, returned, clauses, bindings, inside, outside, selected, member⟩ := handled
  rw [selection] at selected
  obtain ⟨chosen, chosenAt, same⟩ := Option.map_eq_some_iff.mp selected
  cases chosen
  cases same
  exact ⟨_, _, _, _, _, _, _, _, _, chosenAt, member⟩

theorem Target.Forwards.not_handles (forward : Target.Forwards operation attachment future) :
    ¬ Target.Handles operation attachment future := by
  induction forward with
  | done =>
    rintro ⟨mode, context, body, answer, returned, clauses, bindings, inside, outside, selected, _⟩
    contradiction
  | returnTo next bindings values tail induction | region identity tail induction | protection identity cleanup bindings tail induction =>
    intro handled
    exact induction (Target.Handles.of_prepend _ _ rfl handled)
  | different effect mode identity returned clauses bindings different tail induction =>
    intro handled
    exact induction (Target.Handles.of_prepend _ _ (by simp only [Target.select, if_neg different]) handled)
  | unhandled mode returned clauses bindings absent tail induction =>
    rintro ⟨mode, context, body, answer, returned, clauses, bindings, inside, outside, selected, member⟩
    simp only [Target.select, if_true] at selected
    cases selected
    exact absent member

end BoundaryV2.Generalized
