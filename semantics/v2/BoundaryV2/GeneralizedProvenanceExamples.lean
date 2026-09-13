import BoundaryV2.GeneralizedSourceFreeze

namespace BoundaryV2.Generalized.ProvenanceExamples

def signature : Signature where
  Data := Unit
  Effect := Unit
  operation := fun _ => Unit
  payload := fun _ => .unit
  result := fun _ => .leaf ()
  bodies := fun _ => []

def algebra : LeafAlgebra Unit where
  Value := fun _ => Empty
  Fault := Unit
  Reason := Unit
  operation := fun _ _ => Empty
  evaluate := fun operation _ => nomatch operation

theorem no_input (value : Source.RuntimeValue signature algebra [] (.leaf ())) : False := by
  cases value with
  | datum datum => cases datum with
    | leaf impossible => exact nomatch impossible

def safeBody : Source.Computation signature algebra [] [.leaf ()] .unit := .returnValue (.datum .unit)
def exclusiveBody : Source.Computation signature algebra [] [.leaf ()] .unit :=
  .bind (.returnValue (.datum (.resource (name := ⟨0⟩) ⟨5⟩ ⟨6⟩ (.lexical ⟨0⟩ 0)))) (.returnValue (.datum .unit))

def safe : Source.Capture signature algebra [] (.leaf ()) .unit := .bind safeBody .nil .done
def exclusive : Source.Capture signature algebra [] (.leaf ()) .unit := .bind exclusiveBody .nil .done

/-- This remains true: callback equality alone loses authored provenance. -/
theorem bare_callbacks_cannot_distinguish_the_captures :
    (fun value : Source.RuntimeValue signature algebra [] (.leaf ()) => Source.Program.evaluate safeBody (.cons value .nil)) =
      (fun value => Source.Program.evaluate exclusiveBody (.cons value .nil)) := by
  funext value
  exact False.elim (no_input value)

/-- Actual source futures retain their distinct metadata even though the
executable functions above are extensionally equal. -/
theorem actual_source_futures_distinguish_the_captures : safe.future ≠ exclusive.future := by
  intro same
  have refs := (Source.Capture.equal_futures_preserve_provenance same).1
  have custody := congrArg (fun references => referenceNames references .custody) refs
  change ([] : List (Id .custody)) = [⟨6⟩] at custody
  cases custody

abbrev shape : ControlShape signature := ⟨.shallow, (), .leaf (), .unit⟩
def safeImage : Source.Multi.Image signature algebra [] shape := ⟨⟨⟨9⟩, safe⟩, [], [], [⟨9⟩], [], []⟩
def exclusiveImage : Source.Multi.Image signature algebra [] shape := ⟨⟨⟨9⟩, exclusive⟩, [], [], [⟨9⟩], [], []⟩

theorem retained_provenance_preserves_the_distinct_admission_decisions :
    safeImage.copyable = true ∧ exclusiveImage.copyable = false ∧
    (Defunctionalization.templateImage safeImage).copyable = true ∧
    (Defunctionalization.templateImage exclusiveImage).copyable = false := by
  exact ⟨rfl, rfl, rfl, rfl⟩

end BoundaryV2.Generalized.ProvenanceExamples
