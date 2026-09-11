import BoundaryV2.SourceBorrowQueries

namespace BoundaryV2.Profile.Source.Borrow

def pairs (values owners : List Origin) (bound : Bound) : List Constraint :=
  values.flatMap (fun value => owners.map (fun owner => ⟨value, owner, bound⟩))

def originTraces (context : Context) (witness : Witness) (traces : List Trace) : Evaluation (List Origin) := do
  return (← traces.mapM (fun trace => originsAt context.source witness ⟨context.current, .origin trace⟩)).flatten

def relation (context : Context) (witness : Witness) (value owner : ValueRef) (bound : Bound) :
    Evaluation (List Constraint) := do
  let type ← require (valueType context value)
  if Traits.check context.source.schemas .external type then return []
  let values ← originsAt context.source witness ⟨context.current, .origin (.value value [])⟩
  let owners ← originsAt context.source witness ⟨context.current, .origin (.value owner [])⟩
  return pairs values owners bound

def transferConstraint (context : Context) (witness : Witness) (binding : Binding)
    (constraint : Constraint) : Evaluation (List Constraint) := do
  let values ← require (mapInput context binding constraint.value)
  let owners ← require (mapOwner context binding constraint.owner constraint.bound)
  if !mappedConstraintValid values owners then throw ()
  if values.traces.isEmpty || owners.traces.isEmpty then return []
  let valueOrigins ← originTraces context witness values.traces
  let ownerOrigins ← originTraces context witness owners.traces
  return pairs valueOrigins ownerOrigins constraint.bound

def transferRequirements (context : Context) (witness : Witness) (binding : Binding) : Evaluation (List Constraint) := do
  let constraints ← requirementsAt witness binding.function
  return (← constraints.mapM (transferConstraint context witness binding)).flatten

def bodyRequirements (context : Context) (witness : Witness) (node closure : ValueRef)
    (arguments : List ValueRef) (supplied : Nat) : Evaluation (List Constraint) := do
  let bindings ← require (bodyBindings context node closure arguments supplied)
  return (← bindings.mapM (transferRequirements context witness)).flatten

def returnRequirements (context : Context) (witness : Witness) (node : ValueRef) : Evaluation (List Constraint) := do
  let code ← require (nodeAt context node)
  let .invocation invocation := code.expression | throw ()
  let handler ← require (match invocation with
    | .handle handler .. | .resumeWith _ _ handler .. => context.source.handlers[handler.value]?
    | _ => none)
  let constraints ← requirementsAt witness handler.returnFunction
  let parts ← constraints.mapM fun constraint => do
    let values ← returnInput context witness node constraint.value
    let owners ← returnInput context witness node constraint.owner
    let valueOrigins ← originTraces context witness values
    let ownerOrigins ← originTraces context witness owners
    return pairs valueOrigins ownerOrigins constraint.bound
  return parts.flatten

def operationRequirements (context : Context) (witness : Witness) (node : ValueRef)
    (operation : Invocation) : Evaluation (List Constraint) := do
  let .perform effect capability payload bodies _ := operation | throw ()
  match capability with
  | none => return []
  | some capability =>
    let captures := context.source.handlers.any (fun handler => handler.clauses.any
      (fun clause => clause.effect == effect && !clause.direct))
    let directConstraints ← if captures then do
      let parts ← (payload :: bodies).mapM (fun value => relation context witness value capability .clause)
      pure parts.flatten
    else pure []
    let inherited ← (operationBindings context node operation).mapM (transferRequirements context witness)
    return directConstraints ++ inherited.flatten

def invocationRequirements (context : Context) (witness : Witness) (node : ValueRef)
    (invocation : Invocation) : Evaluation (List Constraint) := do
  match invocation with
  | .call function environment arguments =>
    transferRequirements context witness { node := node, function := function, environment := environment, arguments := arguments }
  | .apply closure arguments => bodyRequirements context witness node closure arguments 0
  | .withRegion _ body arguments => bodyRequirements context witness node body arguments 1
  | .protect body cleanup arguments resource _ =>
    let body ← bodyRequirements context witness node body arguments resource.toList.length
    let cleanup ← bodyRequirements context witness node cleanup [] (1 + resource.toList.length)
    return body ++ cleanup
  | .handle handler _ body arguments _ =>
    let handler ← require context.source.handlers[handler.value]?
    let body ← bodyRequirements context witness node body arguments handler.clauses.length
    let returns ← returnRequirements context witness node
    return body ++ returns
  | .perform .. => operationRequirements context witness node invocation
  | .resumeValue token argument => relation context witness argument token .capture
  | .resumeWith token argument _ _ state =>
    let directConstraints ← (argument :: state).mapM (fun value => relation context witness value token .capture)
    let returns ← returnRequirements context witness node
    return directConstraints.flatten ++ returns
  | .resumeComputation token closure =>
    let captured ← relation context witness closure token .capture
    let body ← bodyRequirements context witness node closure [] 0
    return captured ++ body
  | .dispose _ => return []

def requirementsStep (context : Context) (witness : Witness) : Evaluation (List Constraint) := do
  let function ← require context.graph[context.current.value]?
  let parts ← function.nodes.toList.zipIdx.mapM fun (code, node) => do
    match code.expression with
    | .primitive opcode operands _ =>
      if opcode == .cellNew || opcode == .cellSet then
        let value ← require operands[1]?
        let owner ← require operands[0]?
        relation context witness value owner .region
      else pure []
    | .invocation invocation => invocationRequirements context witness node invocation
    | _ => pure []
  return parts.flatten

def requirementsRowValid (context : Context) (witness : Witness) (row : RequirementsRow) : Bool :=
  context.current == row.function && evaluated witness (requirementsStep context witness)
    (fun constraints => Admission.subset constraints row.constraints)

def scopedBindings (context : Context) (node : ValueRef) (invocation : Invocation) : Option (List Binding) :=
  match invocation with
  | .handle handler _ body arguments _ => do
    let handler ← context.source.handlers[handler.value]?
    bodyBindings context node body arguments handler.clauses.length
  | .withRegion _ body arguments => bodyBindings context node body arguments 1
  | .protect body _ arguments resource _ => bodyBindings context node body arguments resource.toList.length
  | _ => some []

def scopedResults (context : Context) (witness : Witness) : Evaluation Bool := do
  let function ← require context.graph[context.current.value]?
  let nodes ← function.nodes.toList.zipIdx.mapM fun (code, node) => do
    match code.expression with
    | .invocation invocation =>
      let bindings ← require (scopedBindings context node invocation)
      let checks ← bindings.mapM fun binding => do
        let origins ← originsAt context.source witness ⟨binding.function, .returned []⟩
        return origins.all (fun origin => (mapInput context binding origin).any (fun mapped => mapped.fresh.isNone))
      return checks.all id
    | _ => pure true
  return nodes.all id

def checkGraph (source : Module) (graph : Array Function) (witness : Witness) : Bool :=
  decide (witness.queries.map QueryRow.query).Nodup &&
  decide (witness.requirements.map RequirementsRow.function).Nodup &&
  (List.range source.functions.length).all (fun index => requestPresent witness (.requirements ⟨index⟩)) &&
  witness.queries.all (fun row => queryRowValid ⟨source, graph, row.query.function⟩ witness row) &&
  witness.requirements.all (fun row => requirementsRowValid ⟨source, graph, row.function⟩ witness row) &&
  (List.range source.functions.length).all (fun index => evaluated witness (scopedResults ⟨source, graph, ⟨index⟩⟩ witness) id)

/-- Borrow admission uses source syntax and an independently checked capture
analysis. Neither target instructions nor compiler borrow summaries occur in
its subject. The graph is rebuilt, so a candidate cannot omit a source write. -/
def check (source : Module) (facts : Analysis.Facts) (witness : Witness) : Bool :=
  Analysis.check source facts && match build source facts with
    | .error _ => false
    | .ok graph => checkGraph source graph witness

theorem requirements_closed (context : Context) (witness : Witness) (row : RequirementsRow)
    (accepted : requirementsRowValid context witness row = true) :
    ∃ constraints requests, (requirementsStep context witness).run [] = .ok (constraints, requests) ∧
      requests.all (requestPresent witness) = true ∧ constraints ⊆ row.constraints := by
  simp only [requirementsRowValid, Bool.and_eq_true] at accepted
  obtain ⟨constraints, requests, found, present, included⟩ := evaluated_sound _ _ _ accepted.2
  refine ⟨constraints, requests, found, present, ?_⟩
  intro constraint member
  exact List.contains_iff_mem.mp (List.all_eq_true.mp included constraint member)

theorem check_rebuilds_source (source : Module) (facts : Analysis.Facts) (witness : Witness)
    (accepted : check source facts witness = true) :
    Analysis.check source facts = true ∧ ∃ graph, build source facts = .ok graph ∧ checkGraph source graph witness = true := by
  simp only [check, Bool.and_eq_true] at accepted
  refine ⟨accepted.1, ?_⟩
  cases found : build source facts with
  | error error => simp [found] at accepted
  | ok graph => exact ⟨graph, rfl, by simpa [found] using accepted.2⟩

end BoundaryV2.Profile.Source.Borrow
