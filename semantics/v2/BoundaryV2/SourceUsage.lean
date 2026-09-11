import BoundaryV2.SourceValues

namespace BoundaryV2.Profile.Source.Usage

/-- Reads cover every path. Consumed variables cover normal returns only:
an abrupt branch transfers its remaining ownership to unwinding. -/
structure Summary where
  reads : List VariableId := []
  consumed : List VariableId := []
  /-- Consumption on every path represented as returning normally. -/
  consumedAlways : List VariableId := []
  normal : Bool := true
  valid : Bool := true
  /-- Implicit disposal is permitted on every normal path. Abrupt paths
  are checked by the source unwind machine. -/
  disposalValid : Bool := true
  deriving DecidableEq, Repr

def invalid : Summary := { valid := false }

def union (left right : List VariableId) : List VariableId := (left ++ right).eraseDups

/-- The second computation can read only owners that survived the first.
This includes borrows, even though a borrow does not consume its operand. -/
def sequence (first second : Summary) : Summary :=
  if first.normal then {
    reads := union first.reads second.reads
    consumed := if second.normal then union first.consumed second.consumed else []
    consumedAlways := if second.normal then union first.consumedAlways second.consumedAlways else []
    disposalValid := !second.normal || (first.disposalValid && second.disposalValid)
    normal := second.normal
    valid := first.valid && second.valid && !first.consumed.any second.reads.contains }
  else first

def alternative (left right : Summary) : Summary := {
  reads := union left.reads right.reads
  consumed := union (if left.normal then left.consumed else []) (if right.normal then right.consumed else [])
  consumedAlways := if left.normal then
    (if right.normal then left.consumedAlways.filter right.consumedAlways.contains else left.consumedAlways)
    else (if right.normal then right.consumedAlways else [])
  disposalValid := (!left.normal || left.disposalValid) && (!right.normal || right.disposalValid)
  normal := left.normal || right.normal
  valid := left.valid && right.valid }

def copyable (source : Module) (var : VariableId) : Bool :=
  (source.variables[var.value]?).any (Traits.check source.schemas .copy)

def readVariable (source : Module) (borrow : Bool) (id : VariableId) : Summary :=
  if copyable source id then {} else
    { reads := [id], consumed := if borrow then [] else [id], consumedAlways := if borrow then [] else [id] }

def variables (source : Module) (ids : List VariableId) : Summary :=
  ids.foldl (fun summary id => sequence summary (readVariable source false id)) {}

def droppable (source : Module) (var : VariableId) : Bool :=
  (source.variables[var.value]?).any (Traits.check source.schemas .drop)

/-- Retain disposal obligations until the enclosing function result is known.
A later abrupt term can send these holdings through ordinary unwinding. -/
def binding (source : Module) (ids : List VariableId) (body : Summary) : Summary := {
  body with
  reads := body.reads.filter (fun id => !ids.contains id)
  consumed := body.consumed.filter (fun id => !ids.contains id)
  consumedAlways := body.consumedAlways.filter (fun id => !ids.contains id)
  disposalValid := body.disposalValid && (!body.normal || ids.all (fun id => droppable source id || body.consumedAlways.contains id)) }

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
  | .bind id value next => sequence (lookupTerm rows value) (binding source [id] (lookupTerm rows next))
  | .conditional condition yes no => sequence (lookupValue values false condition)
      (alternative (lookupTerm rows yes) (lookupTerm rows no))
  | .yieldThen next => lookupTerm rows next
  | .matchSum value cases =>
    let branches := cases.map (fun (id, body) => binding source [id] (lookupTerm rows body))
    let choices := branches.foldl alternative { normal := false }
    sequence (lookupValue values false value) choices
  | .unpackProduct value ids body =>
    sequence (lookupValue values false value) (binding source ids (lookupTerm rows body))
  | .call function arguments =>
    sequence (operands values false arguments) (variables source (Analysis.captures captures function))
  | .fail value => { lookupValue values false value with normal := false, consumed := [], consumedAlways := [] }
  | _ => operands values false (Analysis.termValues term)

def termRows (source : Module) (captures : Analysis.Facts) (values : List ValueRow) : List Summary :=
  source.terms.foldl (fun rows term => rows ++ [termRow source captures values rows term]) []

/-- Check ordered reads and consumption at every function body, including
functions unreachable from entry. Unused syntax rows do not execute by
themselves. Recursive calls consume their lexical captures and arguments.
Every bound parameter, capture, and lexical variable must be consumed or
droppable on normal function exits. Unwind and borrow preservation remain
separate obligations. -/
def check (source : Module) (captures : Analysis.Facts) : Bool :=
  let values := valueRows source captures
  let terms := termRows source captures values
  source.functions.zipIdx.all (fun (function, index) => function.body.all (fun body =>
    let summary := binding source (function.parameters ++ Analysis.captures captures ⟨index⟩) (lookupTerm terms body)
    summary.valid && (!summary.normal || summary.disposalValid)))

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

theorem alternative_requires_both_returns (left right : Summary)
    (leftNormal : left.normal = true) (rightNormal : right.normal = true) (id : VariableId) :
    id ∈ (alternative left right).consumedAlways ↔
      id ∈ left.consumedAlways ∧ id ∈ right.consumedAlways := by
  simp [alternative, leftNormal, rightNormal]

theorem binding_checks_normal_disposal (source : Module) (ids : List VariableId) (body : Summary)
    (normal : body.normal = true) (valid : (binding source ids body).disposalValid = true)
    (id : VariableId) (member : id ∈ ids) (cannotDrop : droppable source id = false) :
    id ∈ body.consumedAlways := by
  simp only [binding, normal, Bool.not_true, Bool.false_or, Bool.and_eq_true] at valid
  have checked := List.all_eq_true.mp valid.2 id member
  simpa [cannotDrop] using checked

theorem abrupt_successor_requires_no_normal_disposal (first second : Summary)
    (continues : first.normal = true) (abrupt : second.normal = false) :
    (sequence first second).normal = false ∧ (sequence first second).disposalValid = true := by
  simp [sequence, continues, abrupt]

end BoundaryV2.Profile.Source.Usage
