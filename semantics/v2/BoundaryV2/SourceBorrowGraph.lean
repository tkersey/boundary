import BoundaryV2.SourceResults

namespace BoundaryV2.Profile.Source.Borrow

abbrev ValueRef := Nat
abbrev Environment := List (VariableId × ValueRef)

/-- Source-derived dependency data, not executable target code. References are
local to one function; lexical shadowing gets a fresh binding. -/
inductive Invocation where
  | call : FunctionId .source → Environment → List ValueRef → Invocation
  | apply : ValueRef → List ValueRef → Invocation
  | perform : EffectId .source → Option ValueRef → ValueRef → List ValueRef → List ValueRef → Invocation
  | handle : HandlerId .source → Environment → ValueRef → List ValueRef → List ValueRef → Invocation
  | resumeValue : ValueRef → ValueRef → Invocation
  | resumeWith : ValueRef → ValueRef → HandlerId .source → Environment → List ValueRef → Invocation
  | resumeComputation : ValueRef → ValueRef → Invocation
  | withRegion : RegionId .source → ValueRef → List ValueRef → Invocation
  | protect : ValueRef → ValueRef → List ValueRef → Option ValueRef → Option (RegionId .source) → Invocation
  | dispose : ValueRef → Invocation
  deriving DecidableEq, Repr

inductive Expression where
  | parameter : Nat → Expression
  | captured : VariableId → Expression
  | literal : ConstantId .source → Expression
  | primitive : Opcode → List ValueRef → Nat → Expression
  | closure : FunctionId .source → Environment → Expression
  | invocation : Invocation → Expression
  | project : ValueRef → Nat → Expression
  | alternative : List ValueRef → Expression
  | failure : ValueRef → Expression
  deriving DecidableEq, Repr

structure Node where
  schema : SchemaId .source
  expression : Expression
  deriving DecidableEq, Repr

structure Function where
  nodes : Array Node
  returned : Option ValueRef
  deriving DecidableEq, Repr

def Invocation.inputs : Invocation → List ValueRef
  | .call _ environment arguments => environment.map Prod.snd ++ arguments
  | .apply computation arguments => computation :: arguments
  | .perform _ capability payload bodies sites => capability.toList ++ payload :: bodies ++ sites
  | .handle _ environment body arguments state => environment.map Prod.snd ++ body :: arguments ++ state
  | .resumeValue token argument | .resumeComputation token argument => [token, argument]
  | .resumeWith token argument _ environment state => [token, argument] ++ environment.map Prod.snd ++ state
  | .withRegion _ body arguments => body :: arguments
  | .protect body cleanup arguments resource _ => [body, cleanup] ++ arguments ++ resource.toList
  | .dispose value => [value]

def Expression.inputs : Expression → List ValueRef
  | .parameter _ | .captured _ | .literal _ => []
  | .primitive _ arguments _ | .alternative arguments => arguments
  | .closure _ environment => environment.map Prod.snd
  | .invocation call => call.inputs
  | .project value _ | .failure value => [value]

def Function.ordered (function : Function) : Bool :=
  function.nodes.toList.zipIdx.all (fun (node, index) => node.expression.inputs.all (· < index)) &&
    function.returned.all (· < function.nodes.size)

theorem ordered_input_precedes (function : Function) (accepted : function.ordered = true)
    (node : Node) (index input : Nat) (found : function.nodes.toList[index]? = some node)
    (member : input ∈ node.expression.inputs) : input < index := by
  simp only [Function.ordered, Bool.and_eq_true] at accepted
  have nodes := accepted.1
  have entry : (node, index) ∈ function.nodes.toList.zipIdx := List.mk_mem_zipIdx_iff_getElem?.mpr found
  have inputs := List.all_eq_true.mp nodes (node, index) entry
  exact of_decide_eq_true (List.all_eq_true.mp inputs input member)

abbrev Builder := StateT (Array Node) (Except Unit)

private def checked (value : Option α) : Builder α := do
  match value with
  | none => throw ()
  | some value => return value

private def var (environment : Environment) (id : VariableId) : Builder ValueRef :=
  checked ((environment.find? (fun binding => binding.1 == id)).map Prod.snd)

private def emit (schema : SchemaId .source) (expression : Expression) : Builder ValueRef := do
  let nodes ← get
  set (nodes.push ⟨schema, expression⟩)
  return nodes.size

private def capture (facts : Analysis.Facts) (environment : Environment)
    (function : FunctionId .source) : Builder Environment :=
  (Analysis.captures facts function).mapM fun id => do return (id, ← var environment id)

private def handlerEnvironment (source : Module) (facts : Analysis.Facts)
    (environment : Environment) (id : HandlerId .source) : Builder Environment := do
  let handler ← checked source.handlers[id.value]?
  let variables := ((handler.returnFunction :: handler.clauses.map Clause.function).flatMap
    (Analysis.captures facts)).eraseDups
  variables.mapM fun id => do return (id, ← var environment id)

/-- Source expressions refer only to earlier syntax rows. Calls remain graph
edges and never execute the called function during admission. -/
def value (source : Module) (facts : Analysis.Facts) (environment : Environment)
    (id : SourceValueId) : Builder ValueRef := do
  let code ← checked source.values[id.value]?
  match code.expression with
  | .variable id => var environment id
  | .literal id => emit code.schema (.literal id)
  | .lambda function => emit code.schema (.closure function (← capture facts environment function))
  | .primitive opcode arguments immediate _ =>
    let operands ← arguments.mapM fun child => do
      if _earlier : child.value < id.value then value source facts environment child else throw ()
    if opcode == .computation then
      let (function, _) ← checked (Analysis.constructors source)[immediate]?
      let names := Analysis.captures facts function
      if names.length != operands.length then throw ()
      emit code.schema (.closure function (names.zip operands))
    else emit code.schema (.primitive opcode operands immediate)
termination_by id.value

private def values (source : Module) (facts : Analysis.Facts) (environment : Environment)
    (arguments : List SourceValueId) : Builder (List ValueRef) :=
  arguments.mapM (value source facts environment)

private def result (results : List (Option (SchemaId .source))) (id : TermId) : Builder (SchemaId .source) := do
  checked (← checked results[id.value]?)

private def merge (schema : SchemaId .source) (branches : List (Option ValueRef)) : Builder (Option ValueRef) :=
  match branches.filterMap id with
  | [] => pure none
  | [one] => pure (some one)
  | alternatives => return some (← emit schema (.alternative alternatives))

private def invoke (results : List (Option (SchemaId .source))) (id : TermId)
    (invocation : Invocation) : Builder (Option ValueRef) := do
  return some (← emit (← result results id) (.invocation invocation))

def term (source : Module) (facts : Analysis.Facts) (results : List (Option (SchemaId .source))) :
    Environment → TermId → Builder (Option ValueRef)
  | environment, id => do
    let code ← checked source.terms[id.value]?
    let descend (environment : Environment) (child : TermId) : Builder (Option ValueRef) :=
      if _earlier : child.value < id.value then term source facts results environment child else throw ()
    let argument := value source facts environment
    let arguments := values source facts environment
    match code with
    | .value id => return some (← argument id)
    | .bind id first next =>
      match ← descend environment first with
      | none => return none
      | some bound => descend ((id, bound) :: environment) next
    | .yieldThen next => descend environment next
    | .conditional condition yes no =>
      let _ ← argument condition
      let left ← descend environment yes
      let right ← descend environment no
      if left.isNone && right.isNone then return none
      merge (← result results id) [left, right]
    | .call function inputs =>
      invoke results id (.call function (← capture facts environment function) (← arguments inputs))
    | .apply computation inputs => invoke results id (.apply (← argument computation) (← arguments inputs))
    | .perform operation =>
      invoke results id (.perform operation.effect (← operation.capability.mapM argument)
        (← argument operation.payload) (← arguments operation.bodies) (← arguments operation.useSiteCapabilities))
    | .handle handler body inputs stored =>
      invoke results id (.handle handler (← handlerEnvironment source facts environment handler)
        (← argument body) (← arguments inputs) (← arguments stored))
    | .resumeValue token input => invoke results id (.resumeValue (← argument token) (← argument input))
    | .resumeWith token input handler stored =>
      invoke results id (.resumeWith (← argument token) (← argument input) handler
        (← handlerEnvironment source facts environment handler) (← arguments stored))
    | .resumeComputation token body => invoke results id (.resumeComputation (← argument token) (← argument body))
    | .withRegion region body inputs => invoke results id (.withRegion region (← argument body) (← arguments inputs))
    | .protect body cleanup inputs resource region =>
      invoke results id (.protect (← argument body) (← argument cleanup) (← arguments inputs)
        (← resource.mapM argument) region)
    | .dispose input => invoke results id (.dispose (← argument input))
    | .fail input =>
      let _ ← emit source.failure (.failure (← argument input))
      return none
    | .matchSum input cases =>
      let scrutinee ← argument input
      let branches ← cases.zipIdx.mapM fun ((variableId, branch), index) => do
        let schema ← checked source.variables[variableId.value]?
        let bound ← emit schema (.project scrutinee index)
        descend ((variableId, bound) :: environment) branch
      if branches.all Option.isNone then return none
      merge (← result results id) branches
    | .unpackProduct input variables body =>
      let scrutinee ← argument input
      let bindings ← variables.zipIdx.mapM fun (variableId, index) => do
        let schema ← checked source.variables[variableId.value]?
        let bound ← emit schema (.project scrutinee index)
        return (variableId, bound)
      descend (bindings ++ environment) body

termination_by _ id => id.value

private def function (source : Module) (facts : Analysis.Facts) (results : List (Option (SchemaId .source)))
    (id : FunctionId .source) : Builder (Option ValueRef) := do
  let function ← checked source.functions[id.value]?
  let captured ← (Analysis.captures facts id).mapM fun var => do
    let schema ← checked source.variables[var.value]?
    let value ← emit schema (.captured var)
    return (var, value)
  let parameters ← function.parameters.zipIdx.mapM fun (var, index) => do
    let schema ← checked source.variables[var.value]?
    let value ← emit schema (.parameter index)
    return (var, value)
  let body ← checked function.body
  term source facts results (parameters ++ captured) body

def build (source : Module) (facts : Analysis.Facts) : Except Unit (Array Function) := do
  let some results := Analysis.inferResults source | throw ()
  let functions ← (List.range source.functions.length).mapM fun index => do
    let (returned, nodes) ← (function source facts results ⟨index⟩).run #[]
    let graph : Function := { nodes := nodes, returned := returned }
    if !graph.ordered then throw ()
    return graph
  return functions.toArray

end BoundaryV2.Profile.Source.Borrow
