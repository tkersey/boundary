import BoundaryV2.Traits

namespace BoundaryV2.Profile.Source.Analysis

inductive Node where
  | value : SourceValueId → Node
  | term : TermId → Node
  | function : FunctionId .source → Node
  deriving DecidableEq, Repr

structure Dependency where
  node : Node
  excludes : List VariableId := []
  deriving DecidableEq, Repr

def termValues : Term → List SourceValueId
  | .value value | .dispose value | .fail value => [value]
  | .bind .. | .yieldThen _ => []
  | .conditional condition _ _ => [condition]
  | .call _ arguments => arguments
  | .apply computation arguments => computation :: arguments
  | .perform operation => operation.capability.toList ++ [operation.payload] ++ operation.bodies ++ operation.useSiteCapabilities
  | .handle _ body arguments state => body :: (arguments ++ state)
  | .resumeValue resumption argument | .resumeComputation resumption argument => [resumption, argument]
  | .resumeWith resumption argument _ state => [resumption, argument] ++ state
  | .protect body cleanup arguments resource _ => [body, cleanup] ++ arguments ++ resource.toList
  | .withRegion _ body arguments => body :: arguments
  | .matchSum value _ | .unpackProduct value _ _ => [value]

def termChildren : Term → List (TermId × List VariableId)
  | .bind var value next => [(value, []), (next, [var])]
  | .conditional _ yes no => [(yes, []), (no, [])]
  | .yieldThen next => [(next, [])]
  | .matchSum _ cases => cases.map (fun (var, body) => (body, [var]))
  | .unpackProduct _ variables body => [(body, variables)]
  | .value _ | .call .. | .apply .. | .perform _ | .handle .. | .resumeValue ..
  | .resumeWith .. | .resumeComputation .. | .protect .. | .withRegion .. | .dispose _ | .fail _ => []

def termBinders : Term → List VariableId
  | .bind var _ _ => [var]
  | .matchSum _ cases => cases.map Prod.fst
  | .unpackProduct _ variables _ => variables
  | _ => []

/-- Variable dependencies include lexical calls and lambdas. Call cycles are
legal here; syntax-child cycles are checked separately below. -/
def dependencies (source : Module) : Node → List Dependency
  | .value id => match source.values[id.value]? with
    | some ⟨_, .primitive _ operands _ _⟩ => operands.map (fun operand => ⟨.value operand, []⟩)
    | some ⟨_, .lambda function⟩ => [⟨.function function, []⟩]
    | _ => []
  | .term id => match source.terms[id.value]? with
    | none => []
    | some term =>
      (termValues term).map (fun operand => ⟨.value operand, []⟩) ++
      (termChildren term).map (fun (child, excludes) => ⟨.term child, excludes⟩) ++
      (match term with | .call function _ => [⟨.function function, []⟩] | _ => [])
  | .function id => match source.functions[id.value]? with
    | some function => function.body.toList.map (fun body => ⟨.term body, function.parameters⟩)
    | none => []

def direct (source : Module) : Node → Option VariableId
  | .value id => match source.values[id.value]? with
    | some ⟨_, .variable var⟩ => some var
    | _ => none
  | .term _ | .function _ => none

inductive Free (source : Module) : Node → VariableId → Prop where
  | direct : direct source node = some var → Free source node var
  | through : dependency ∈ dependencies source node → var ∉ dependency.excludes →
      Free source dependency.node var → Free source node var

def allNodes (source : Module) : List Node :=
  (List.range source.values.length).map (fun index => .value ⟨index⟩) ++
  (List.range source.terms.length).map (fun index => .term ⟨index⟩) ++
  (List.range source.functions.length).map (fun index => .function ⟨index⟩)

/-- A rank witnesses an actual finite dependency path to a var occurrence.
Closure is checked as well, excluding both omitted captures and arbitrary
extra variables justified only by a mutually recursive cycle. -/
abbrev Row := List (VariableId × Nat)
structure Facts where
  values : List Row
  terms : List Row
  functions : List Row
  deriving DecidableEq, Repr

def Facts.row (facts : Facts) : Node → Row
  | .value id => facts.values[id.value]?.getD []
  | .term id => facts.terms[id.value]?.getD []
  | .function id => facts.functions[id.value]?.getD []

def Facts.rank (facts : Facts) (node : Node) (var : VariableId) : Option Nat :=
  ((facts.row node).find? (fun entry => entry.1 == var)).map Prod.snd

def factValid (source : Module) (facts : Facts) (node : Node) (var : VariableId) (rank : Nat) : Bool :=
  var.value < source.variables.length &&
  (direct source node == some var ||
    (dependencies source node).any fun dependency =>
      !dependency.excludes.contains var &&
      match facts.rank dependency.node var with
      | some childRank => childRank < rank
      | none => false)

def rowClosed (source : Module) (facts : Facts) (node : Node) : Bool :=
  (match direct source node with
    | none => true
    | some var => (facts.rank node var).isSome) &&
  (dependencies source node).all fun dependency =>
    (facts.row dependency.node).all fun (var, _) =>
      dependency.excludes.contains var || (facts.rank node var).isSome

def rowCheck (source : Module) (facts : Facts) (node : Node) : Bool :=
  decide ((facts.row node).map Prod.fst |>.Pairwise (fun a b => a.value < b.value)) &&
  (facts.row node).all (fun (var, rank) => factValid source facts node var rank) &&
  rowClosed source facts node

def check (source : Module) (facts : Facts) : Bool :=
  facts.values.length == source.values.length && facts.terms.length == source.terms.length &&
  facts.functions.length == source.functions.length && (allNodes source).all (rowCheck source facts)

def captures (facts : Facts) (function : FunctionId .source) : List VariableId :=
  (facts.row (.function function)).map Prod.fst

def inBounds (source : Module) : Node → Prop
  | .value id => id.value < source.values.length
  | .term id => id.value < source.terms.length
  | .function id => id.value < source.functions.length

instance (source : Module) (node : Node) : Decidable (inBounds source node) := by
  cases node <;> unfold inBounds <;> infer_instance

theorem allNodes_member (source : Module) (node : Node) : node ∈ allNodes source ↔ inBounds source node := by
  cases node with
  | value id | term id | function id => cases id <;> simp [allNodes, inBounds, List.mem_map]

private theorem rank_member (facts : Facts) (node : Node) (var : VariableId) (rank : Nat)
    (found : facts.rank node var = some rank) : (var, rank) ∈ facts.row node := by
  unfold Facts.rank at found
  cases search : (facts.row node).find? (fun entry => entry.1 == var) with
  | none => simp [search] at found
  | some selected =>
    have member := List.mem_of_find?_eq_some search
    have selectedVar : selected.1 = var := by simpa using List.find?_some search
    have selectedRank : selected.2 = rank := by simpa [search] using found
    have equal : selected = (var, rank) := Prod.ext selectedVar selectedRank
    simpa [equal] using member

private theorem check_lengths (source : Module) (facts : Facts) (accepted : check source facts = true) :
    facts.values.length = source.values.length ∧ facts.terms.length = source.terms.length ∧
    facts.functions.length = source.functions.length := by
  simp only [check, Bool.and_eq_true, beq_iff_eq] at accepted
  exact ⟨accepted.1.1.1, accepted.1.1.2, accepted.1.2⟩

private theorem outside_row_empty (source : Module) (facts : Facts) (accepted : check source facts = true)
    (node : Node) (outside : ¬ inBounds source node) : facts.row node = [] := by
  obtain ⟨valuesLength, termsLength, functionsLength⟩ := check_lengths source facts accepted
  cases node <;> simp_all [inBounds, Facts.row]

private theorem rank_inBounds (source : Module) (facts : Facts) (accepted : check source facts = true)
    (node : Node) (var : VariableId) (rank : Nat) (found : facts.rank node var = some rank) :
    inBounds source node := by
  by_cases valid : inBounds source node
  · exact valid
  · have empty := outside_row_empty source facts accepted node valid
    simp [Facts.rank, empty] at found

private theorem checked_row (source : Module) (facts : Facts) (accepted : check source facts = true)
    (node : Node) (valid : inBounds source node) : rowCheck source facts node = true := by
  have rows : (allNodes source).all (rowCheck source facts) = true := by
    simp only [check, Bool.and_eq_true] at accepted
    exact accepted.2
  exact List.all_eq_true.mp rows node ((allNodes_member source node).mpr valid)

theorem rank_sound (source : Module) (facts : Facts) (accepted : check source facts = true)
    (node : Node) (var : VariableId) (rank : Nat) (found : facts.rank node var = some rank) :
    Free source node var := by
  induction rank using Nat.strongRecOn generalizing node with
  | ind rank induction =>
    have checked := checked_row source facts accepted node (rank_inBounds source facts accepted node var rank found)
    have allFacts : (facts.row node).all (fun (var, rank) => factValid source facts node var rank) = true := by
      simp only [rowCheck, Bool.and_eq_true] at checked
      exact checked.1.2
    have fact := List.all_eq_true.mp allFacts (var, rank) (rank_member facts node var rank found)
    simp only [factValid, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq] at fact
    rcases fact.2 with direct | inherited
    · exact .direct direct
    · obtain ⟨dependency, member, witnessed⟩ := List.any_eq_true.mp inherited
      have both : var ∉ dependency.excludes ∧
          (match facts.rank dependency.node var with | some childRank => decide (childRank < rank) | none => false) = true := by
        simpa [Bool.and_eq_true] using witnessed
      cases child : facts.rank dependency.node var with
      | none => simp [child] at both
      | some childRank =>
        have smaller : childRank < rank := by simpa [child] using both.2
        exact .through member both.1 (induction childRank smaller dependency.node child)

private theorem outside_dependencies (source : Module) (node : Node) (outside : ¬ inBounds source node) :
    dependencies source node = [] ∧ direct source node = none := by
  cases node <;> simp_all [inBounds, dependencies, direct]

theorem free_complete (source : Module) (facts : Facts) (accepted : check source facts = true)
    (free : Free source node var) : ∃ rank, facts.rank node var = some rank := by
  induction free with
  | direct found =>
    rename_i node var
    have valid : inBounds source node := by
      by_cases valid : inBounds source node
      · exact valid
      · have missing := (outside_dependencies source node valid).2
        simp [missing] at found
    have checked := checked_row source facts accepted node valid
    have closed : rowClosed source facts node = true := by
      simp only [rowCheck, Bool.and_eq_true] at checked
      exact checked.2
    have present : (facts.rank node var).isSome = true := by
      simp [rowClosed, found] at closed
      exact closed.1
    exact Option.isSome_iff_exists.mp present
  | @through parent dependency var member notExcluded childFree induction =>
    obtain ⟨rank, found⟩ := induction
    have valid : inBounds source parent := by
      by_cases valid : inBounds source parent
      · exact valid
      · have missing := (outside_dependencies source parent valid).1
        simp [missing] at member
    have checked := checked_row source facts accepted parent valid
    have closed : (dependencies source parent).all (fun dependency =>
        (facts.row dependency.node).all (fun (var, _) =>
          dependency.excludes.contains var || (facts.rank parent var).isSome)) = true := by
      simp only [rowCheck, rowClosed, Bool.and_eq_true] at checked
      exact checked.2.2
    have dependencyClosed := List.all_eq_true.mp closed dependency member
    have propagated := List.all_eq_true.mp dependencyClosed (var, rank) (rank_member facts dependency.node var rank found)
    have present : (facts.rank parent var).isSome = true := by simpa [notExcluded] using propagated
    exact Option.isSome_iff_exists.mp present

theorem checked_capture_exact (source : Module) (facts : Facts) (accepted : check source facts = true)
    (node : Node) (var : VariableId) :
    (∃ rank, facts.rank node var = some rank) ↔ Free source node var := by
  constructor
  · rintro ⟨rank, found⟩; exact rank_sound source facts accepted node var rank found
  · exact free_complete source facts accepted

def formedValue (source : Module) (index : Nat) (value : Source.Value) : Bool :=
  value.schema.value < source.schemas.length && match value.expression with
  | .variable var => source.variables[var.value]? == some value.schema
  | .literal literal => (source.constants[literal.value]?).map Literal.schema == some value.schema
  | .primitive _ operands _ _ => operands.all (fun operand => operand.value < index)
  | .lambda function => function.value < source.functions.length

def formedTerm (source : Module) (index : Nat) (term : Term) : Bool :=
  (termValues term).all (fun value => value.value < source.values.length) &&
  (termChildren term).all (fun (child, _) => child.value < index) &&
  (termBinders term).all (fun var => var.value < source.variables.length) &&
  (match term with
  | .call function _ => function.value < source.functions.length
  | .perform operation => operation.effect.value < source.effects.length
  | .handle handler .. | .resumeWith _ _ handler _ => handler.value < source.handlers.length
  | .withRegion region .. => region.value < source.regionCount
  | .unpackProduct _ variables _ => decide variables.Nodup
  | _ => true)

/-- The staged format already orders expression/term syntax before its users.
Function references are deliberately not subject to this order. Every declared
node is checked, including declarations unreachable from entry. -/
def formation (source : Module) : Bool :=
  source.entry.value < source.functions.length &&
  source.values.zipIdx.all (fun (value, index) => formedValue source index value) &&
  source.terms.zipIdx.all (fun (term, index) => formedTerm source index term) &&
  source.variables.all (fun type => type.value < source.schemas.length) &&
  source.functions.all (fun function =>
    function.result.value < source.schemas.length &&
    decide function.parameters.Nodup &&
    function.parameters.all (fun var => var.value < source.variables.length) &&
    match function.body with
    | none => false
    | some body => body.value < source.terms.length)

theorem primitive_children_strictly_earlier (source : Module) (index : Nat)
    (type : SchemaId .source) (opcode : Opcode) (operands : List SourceValueId) (immediate : Nat)
    (failures : List (InstructionFailure .source))
    (accepted : formedValue source index ⟨type, .primitive opcode operands immediate failures⟩ = true)
    (member : operand ∈ operands) : operand.value < index := by
  have children : operands.all (fun operand => operand.value < index) = true := by
    have both : type.value < source.schemas.length ∧
        operands.all (fun operand => operand.value < index) = true := by
      simpa [formedValue, Bool.and_eq_true] using accepted
    exact both.2
  simpa using List.all_eq_true.mp children operand member

theorem term_children_strictly_earlier (source : Module) (index : Nat) (term : Term)
    (accepted : formedTerm source index term = true) (member : (child, excluded) ∈ termChildren term) :
    child.value < index := by
  have children : (termChildren term).all (fun (child, _) => child.value < index) = true := by
    simp only [formedTerm, Bool.and_eq_true] at accepted
    exact accepted.1.1.2
  simpa using List.all_eq_true.mp children (child, excluded) member

/-- Raw computation instructions name the first-occurrence constructor catalog.
It is derived from source syntax, including unexecuted branches and every
function declaration. Binding continuations are lowered before their values.
No target program or compiler witness is consulted here. -/
abbrev ConstructorKey := FunctionId .source × SchemaId .source

def valueConstructorRows (source : Module) : List (List ConstructorKey) :=
  source.values.foldl (fun rows value => rows ++ [match value.expression with
    | .lambda function => [(function, value.schema)]
    | .primitive _ operands _ _ => operands.flatMap (fun operand => rows[operand.value]?.getD [])
    | _ => []].map List.eraseDups) []

def constructorRows (source : Module) : List (List ConstructorKey) :=
  let values := valueConstructorRows source
  source.terms.foldl (fun rows term =>
    let children := match term with
      | .bind _ value next => [next, value]
      | _ => (termChildren term).map Prod.fst
    rows ++ [children.flatMap (fun child => rows[child.value]?.getD []) ++
      (termValues term).flatMap (fun value => values[value.value]?.getD [])].map List.eraseDups) []

def constructors (source : Module) : List ConstructorKey :=
  let rows := constructorRows source
  (source.functions.flatMap (fun function => function.body.toList.flatMap
    (fun body => rows[body.value]?.getD []))).eraseDups

theorem constructor_interning_keeps_first_occurrence :
    ([(0, 1), (2, 3), (0, 1)] : List ConstructorKey).eraseDups = [(0, 1), (2, 3)] := by decide

/-- Explicit source disposal introduces a unit adapter literal when the first
unit schema has no existing empty literal. Unreachable syntax does not do so. -/
def hasDisposal (source : Module) : Bool :=
  let rows := source.terms.foldl (fun rows term => rows ++ [
    (match term with | .dispose _ => true | _ => false) ||
    (termChildren term).any (fun (child, _) => rows[child.value]?.getD false)]) []
  source.functions.any (fun function => function.body.toList.any (fun body => rows[body.value]?.getD false))

end BoundaryV2.Profile.Source.Analysis
