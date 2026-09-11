import BoundaryV2.SourceValues

namespace BoundaryV2.Profile.Source.Usage

/-- Reads cover every path. Consumed variables cover normal returns only:
an abrupt branch transfers its remaining ownership to unwinding. -/
structure Summary where
  reads : List VariableId := []
  consumed : List VariableId := []
  normal : Bool := true
  valid : Bool := true
  deriving DecidableEq, Repr

def invalid : Summary := { valid := false }

def union (left right : List VariableId) : List VariableId := (left ++ right).eraseDups

/-- The second computation can read only owners that survived the first.
This includes borrows, even though a borrow does not consume its operand. -/
def sequence (first second : Summary) : Summary :=
  if first.normal then {
    reads := union first.reads second.reads
    consumed := if second.normal then union first.consumed second.consumed else []
    normal := second.normal
    valid := first.valid && second.valid && !first.consumed.any second.reads.contains }
  else first

def alternative (left right : Summary) : Summary := {
  reads := union left.reads right.reads
  consumed := union (if left.normal then left.consumed else []) (if right.normal then right.consumed else [])
  normal := left.normal || right.normal
  valid := left.valid && right.valid }

def copyable (source : Module) (var : VariableId) : Bool :=
  (source.variables[var.value]?).any (Traits.check source.schemas .copy)

def readVariable (source : Module) (borrow : Bool) (id : VariableId) : Summary :=
  if copyable source id then {} else
    { reads := [id], consumed := if borrow then [] else [id] }

def variables (source : Module) (ids : List VariableId) : Summary :=
  ids.foldl (fun summary id => sequence summary (readVariable source false id)) {}

def binding (ids : List VariableId) (body : Summary) : Summary := {
  body with
  reads := body.reads.filter (fun id => !ids.contains id)
  consumed := body.consumed.filter (fun id => !ids.contains id) }

abbrev ValueRow := Summary × Summary

def lookupValue (rows : List ValueRow) (borrow : Bool) (id : SourceValueId) : Summary :=
  match rows[id.value]? with
  | none => invalid
  | some row => if borrow then row.2 else row.1

def operands (rows : List ValueRow) (borrow : Bool) (ids : List SourceValueId) : Summary :=
  ids.foldl (fun summary id => sequence summary (lookupValue rows borrow id)) {}

abbrev borrowsOperands := Machine.observes

def valueRow (source : Module) (captures : Analysis.Facts) (rows : List ValueRow)
    (value : Source.Value) : ValueRow :=
  match value.expression with
  | .variable id => (readVariable source false id, readVariable source true id)
  | .literal _ => ({}, {})
  | .lambda function =>
    let summary := variables source (Analysis.captures captures function)
    (summary, summary)
  | .primitive opcode arguments _ _ =>
    let summary := operands rows (borrowsOperands opcode) arguments
    (summary, summary)

def valueRows (source : Module) (captures : Analysis.Facts) : List ValueRow :=
  source.values.foldl (fun rows value => rows ++ [valueRow source captures rows value]) []

def lookupTerm (rows : List Summary) (id : TermId) : Summary := rows[id.value]?.getD invalid

def termRow (source : Module) (captures : Analysis.Facts) (values : List ValueRow)
    (rows : List Summary) (term : Term) : Summary :=
  match term with
  | .bind id value next => sequence (lookupTerm rows value) (binding [id] (lookupTerm rows next))
  | .conditional condition yes no => sequence (lookupValue values false condition)
      (alternative (lookupTerm rows yes) (lookupTerm rows no))
  | .yieldThen next => lookupTerm rows next
  | .matchSum value cases =>
    let branches := cases.map (fun (id, body) => binding [id] (lookupTerm rows body))
    let choices := branches.foldl alternative { normal := false }
    sequence (lookupValue values false value) choices
  | .unpackProduct value ids body =>
    sequence (lookupValue values false value) (binding ids (lookupTerm rows body))
  | .call function arguments =>
    sequence (operands values false arguments) (variables source (Analysis.captures captures function))
  | .fail value => { lookupValue values false value with normal := false, consumed := [] }
  | _ => operands values false (Analysis.termValues term)

def termRows (source : Module) (captures : Analysis.Facts) (values : List ValueRow) : List Summary :=
  source.terms.foldl (fun rows term => rows ++ [termRow source captures values rows term]) []

/-- Check ordered reads and consumption at every function body, including
functions unreachable from entry. Unused syntax rows do not execute by
themselves. Recursive calls consume their lexical captures and arguments.
Unused-value disposal and capture bounds remain separate obligations. -/
def check (source : Module) (captures : Analysis.Facts) : Bool :=
  let values := valueRows source captures
  let terms := termRows source captures values
  source.functions.all (fun function => function.body.all (fun body => (lookupTerm terms body).valid))

theorem sequence_checks_reads (first second : Summary) (continues : first.normal = true)
    (accepted : (sequence first second).valid = true) :
    first.valid = true ∧ second.valid = true ∧
      ∀ id ∈ first.consumed, id ∉ second.reads := by
  simpa [sequence, continues, Bool.and_eq_true, List.any_eq_false, and_assoc] using accepted

theorem borrowing_a_consumed_variable_rejects (source : Module) (id : VariableId)
    (exclusive : copyable source id = false) :
    (sequence (readVariable source false id) (readVariable source true id)).valid = false := by
  simp [sequence, readVariable, exclusive]

theorem mutually_exclusive_consumptions_admitted (source : Module) (id : VariableId) :
    (alternative (readVariable source false id) (readVariable source false id)).valid = true := by
  simp [alternative, readVariable]
  split <;> rfl

end BoundaryV2.Profile.Source.Usage
