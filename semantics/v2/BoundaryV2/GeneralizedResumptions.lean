import BoundaryV2.GeneralizedHandlerEntry

namespace BoundaryV2.Generalized

namespace Source

structure SelectedClause (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) {effect : signature.Effect}
    (operation : signature.operation effect) (mode : Mode) (context : List (TypeOf signature))
    (body answer : TypeOf signature) where
  use : Use
  code : Computation signature algebra definitions
    (.continuation mode use effect (signature.result operation) (resumedType mode body answer) ::
      signature.payload operation :: (signature.bodies operation).map BodyType.type ++ context) answer

def Clauses.lookup (operation : signature.operation effect) [DecidableEq (signature.operation effect)]
    (source : Clauses signature algebra definitions effect mode context body answer) :
    Option (SelectedClause signature algebra definitions operation mode context body answer) :=
  match source with
  | .nil => none
  | .cons candidate use code rest =>
    if same : candidate = operation then some ⟨use, by cases same; exact code⟩
    else rest.lookup operation

def Clauses.length : Clauses signature algebra definitions effect mode context body answer → Nat
  | .nil => 0
  | .cons _ _ _ rest => rest.length + 1

/-- The store owns identity and use authority. This payload retains the nominal
attachment and the higher-order context that an admitted use will reenter. -/
structure Resumption (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect))
    (mode : Mode) (effect : signature.Effect) (input answer : TypeOf signature) where
  attachment : Id .attachment
  future : Context signature algebra definitions input answer

def captureResumption (mode : Mode) (effect : signature.Effect) (attachment : Id .attachment)
    (returned : Computation signature algebra definitions (body :: context) answer)
    (clauses : Clauses signature algebra definitions effect mode context body answer)
    (bindings : RuntimeEnvironment signature algebra definitions context)
    (inside : Context signature algebra definitions input body) :
    Resumption signature algebra definitions mode effect input (resumedType mode body answer) :=
  match mode with
  | .deep => ⟨attachment, inside.append (.push (.handler effect .deep attachment returned clauses bindings) .done)⟩
  | .shallow => ⟨attachment, inside⟩

def reenter (saved : Resumption signature algebra definitions mode effect input answer)
    (replacement : Program signature algebra definitions input) : Program signature algebra definitions answer :=
  saved.future.plug replacement

def enterClause (selected : SelectedClause signature algebra definitions operation mode context body answer)
    (controlId : Id .control) (authority : Option (Id .custody × Owner))
    (payload : RuntimeValue signature algebra definitions (signature.payload operation))
    (bodies : RuntimeEnvironment signature algebra definitions ((signature.bodies operation).map BodyType.type))
    (bindings : RuntimeEnvironment signature algebra definitions context) : Program signature algebra definitions answer :=
  .evaluate selected.code (.cons (.continuation controlId authority) (.cons payload (bodies.append bindings)))

end Source

namespace Target

structure SelectedClause (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) {effect : signature.Effect}
    (operation : signature.operation effect) (mode : Mode) (context : List (TypeOf signature))
    (body answer : TypeOf signature) where
  use : Use
  code : Code signature algebra definitions
    (.continuation mode use effect (signature.result operation) (resumedType mode body answer) ::
      signature.payload operation :: (signature.bodies operation).map BodyType.type ++ context) [] answer

/-- Lookup operates on compiled clause data, independently of source lookup. -/
def Clauses.lookup (operation : signature.operation effect) [DecidableEq (signature.operation effect)]
    (target : Clauses signature algebra definitions effect mode context body answer) :
    Option (SelectedClause signature algebra definitions operation mode context body answer) :=
  match target with
  | .nil => none
  | .cons candidate use code rest =>
    if same : candidate = operation then some ⟨use, by cases same; exact code⟩
    else rest.lookup operation

/-- The corresponding payload is entirely first-order stack and identity data. -/
structure Resumption (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect))
    (mode : Mode) (effect : signature.Effect) (input answer : TypeOf signature) where
  attachment : Id .attachment
  future : Stack signature algebra definitions input answer

def captureResumption (mode : Mode) (effect : signature.Effect) (attachment : Id .attachment)
    (returned : Code signature algebra definitions (body :: context) [] answer)
    (clauses : Clauses signature algebra definitions effect mode context body answer)
    (bindings : RuntimeEnvironment signature algebra definitions context)
    (inside : Stack signature algebra definitions input body) :
    Resumption signature algebra definitions mode effect input (resumedType mode body answer) :=
  match mode with
  | .deep => ⟨attachment, inside.append (.push (.handler effect .deep attachment returned clauses bindings) .done)⟩
  | .shallow => ⟨attachment, inside⟩

def reenter (saved : Resumption signature algebra definitions mode effect input answer)
    (value : RuntimeValue signature algebra definitions input) (outside : Stack signature algebra definitions answer result) :
    Configuration signature algebra definitions result := .returned value (saved.future.append outside)

def inject (saved : Resumption signature algebra definitions mode effect input answer)
    (body : Entry signature algebra definitions input) (outside : Stack signature algebra definitions answer result) :
    Configuration signature algebra definitions result := .code body.body body.environment .nil (saved.future.append outside)

def enterClause (selected : SelectedClause signature algebra definitions operation mode context body answer)
    (controlId : Id .control) (authority : Option (Id .custody × Owner))
    (payload : RuntimeValue signature algebra definitions (signature.payload operation))
    (bodies : RuntimeEnvironment signature algebra definitions ((signature.bodies operation).map BodyType.type))
    (bindings : RuntimeEnvironment signature algebra definitions context)
    (outside : Stack signature algebra definitions answer result) : Configuration signature algebra definitions result :=
  .code selected.code (.cons (.continuation controlId authority) (.cons payload (bodies.append bindings))) .nil outside

end Target

namespace Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

def selectedClause (source : Source.SelectedClause signature algebra program operation mode context body answer) :
    Target.SelectedClause signature algebra program operation mode context body answer := ⟨source.use, computation source.code⟩

theorem clause_lookup_corresponds (operation : signature.operation effect) [DecidableEq (signature.operation effect)]
    (source : Source.Clauses signature algebra program effect mode context body answer) :
    (clauses source).lookup operation = (source.lookup operation).map selectedClause := by
  suffices ∀ bound (source : Source.Clauses signature algebra program effect mode context body answer),
      source.length ≤ bound → (clauses source).lookup operation = (source.lookup operation).map selectedClause from
    this source.length source (Nat.le_refl _)
  intro bound
  induction bound with
  | zero =>
    intro source sized
    cases source with
    | nil => rfl
    | cons candidate use code rest => simp [Source.Clauses.length] at sized
  | succ bound induction =>
    intro source sized
    cases source with
    | nil => rfl
    | cons candidate use code rest =>
      simp only [clauses, Source.Clauses.lookup, Target.Clauses.lookup]
      by_cases same : candidate = operation
      · subst candidate
        simp only
        rfl
      · simp only [dif_neg same]
        exact induction rest (by simpa [Source.Clauses.length] using sized)

structure ResumptionRelated (source : Source.Resumption signature algebra program mode effect input answer)
    (target : Target.Resumption signature algebra program mode effect input answer) : Prop where
  attachment : source.attachment = target.attachment
  future : ContextRelated signature algebra program source.future target.future

theorem captured_resumption_corresponds (mode : Mode) (effect : signature.Effect) (attachment : Id .attachment)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (handled : Source.Clauses signature algebra program effect mode context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (inside : ContextRelated signature algebra program sourceInside targetInside) :
    ResumptionRelated (Source.captureResumption mode effect attachment returned handled bindings sourceInside)
      (Target.captureResumption mode effect attachment (computation returned) (clauses handled) (environment bindings) targetInside) := by
  cases mode with
  | deep => exact ⟨rfl, context_composition inside (.push (.handler effect .deep attachment returned handled bindings) .done)⟩
  | shallow => exact ⟨rfl, inside⟩

/-- A source computation in a higher-order context corresponds to target code
and a data stack. This is the entry relation used by subsequent execution laws;
it is not itself a claim of observation equivalence. -/
inductive EntryRelated : Source.Program signature algebra program result → Target.Configuration signature algebra program result → Prop where
  | evaluate (body : Source.Computation signature algebra program context input)
      (bindings : Source.RuntimeEnvironment signature algebra program context)
      (future : ContextRelated signature algebra program sourceFuture targetFuture) :
      EntryRelated (sourceFuture.plug (.evaluate body bindings))
        (.code (computation body) (environment bindings) .nil targetFuture)
  | returned (value : Source.RuntimeValue signature algebra program input)
      (future : ContextRelated signature algebra program sourceFuture targetFuture) :
      EntryRelated (sourceFuture.plug (.returned value)) (.returned (Defunctionalization.value value) targetFuture)

theorem resumption_reentry_corresponds
    (saved : ResumptionRelated (source : Source.Resumption signature algebra program mode effect input answer) target)
    (value : Source.RuntimeValue signature algebra program input)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    EntryRelated (sourceOutside.plug (Source.reenter source (.returned value)))
      (Target.reenter target (Defunctionalization.value value) targetOutside) := by
  have related := EntryRelated.returned value (context_composition saved.future outside)
  simpa only [Source.reenter, Target.reenter, Source.Context.append_plug] using related

/-- The injected computation executes under the saved use-site interpretation.
The clause's outside context begins only after that computation's saved future. -/
theorem computation_injection_corresponds
    (saved : ResumptionRelated (source : Source.Resumption signature algebra program mode effect input answer) target)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    EntryRelated (sourceOutside.plug (Source.reenter source (.evaluate body bindings)))
      (Target.inject target ⟨context, computation body, environment bindings⟩ targetOutside) := by
  have related := EntryRelated.evaluate body bindings (context_composition saved.future outside)
  simpa only [Source.reenter, Target.inject, Source.Context.append_plug] using related

/-- Clause entry preserves the exact continuation/payload/body/capture order
and runs in the outside context. The selected return delimiter is not re-added. -/
theorem operation_clause_entry_corresponds
    (selected : Source.SelectedClause signature algebra program operation mode context body answer)
    (controlId : Id .control) (authority : Option (Id .custody × Owner))
    (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    EntryRelated (sourceOutside.plug (Source.enterClause selected controlId authority payload bodies bindings))
      (Target.enterClause (selectedClause selected) controlId authority (value payload) (environment bodies) (environment bindings) targetOutside) := by
  simpa only [Source.enterClause, Target.enterClause, selectedClause, environment, Environment.map, Value.map, Environment.map_append, value] using
    EntryRelated.evaluate selected.code (.cons (.continuation controlId authority) (.cons payload (bodies.append bindings))) outside

end Defunctionalization
end BoundaryV2.Generalized
