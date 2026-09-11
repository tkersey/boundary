import BoundaryV2.BorrowQueries

namespace BoundaryV2.Profile.Target.Borrow

def pairs (values owners : List Source) (bound : Bound) : List Constraint :=
  values.flatMap (fun value => owners.map (fun owner => ⟨value, owner, bound⟩))

def originSources (program : Program) (witness : Witness) (start : BlockId) (traces : List Trace) :
    Option (List Source) := do
  let parts ← traces.mapM (fun trace => sourcesAt program witness ⟨start, .origin trace⟩)
  return parts.flatten

def relation (program : Program) (witness : Witness) (start block : BlockId)
    (value owner : Slot) (bound : Bound) : Option (List Constraint) := do
  let type ← slotType program block value
  if Traits.check program.schemas .external type then return []
  let values ← sourcesAt program witness ⟨start, .origin (.slot block value [])⟩
  let owners ← sourcesAt program witness ⟨start, .origin (.slot block owner [])⟩
  return pairs values owners bound

def transferConstraint (program : Program) (witness : Witness) (start : BlockId) (binding : Binding)
    (constraint : Constraint) : Option (List Constraint) := do
  let values ← mapInput program binding constraint.value
  let owners ← mapOwner program binding constraint.owner constraint.bound
  if !mappedConstraintValid values owners then none else do
    if values.traces.isEmpty || owners.traces.isEmpty then return []
    let valueSources ← originSources program witness start values.traces
    let ownerSources ← originSources program witness start owners.traces
    return pairs valueSources ownerSources constraint.bound

def transferRequirements (program : Program) (witness : Witness) (start : BlockId) (binding : Binding) :
    Option (List Constraint) := do
  let called ← functionEntry program binding.function
  let constraints ← requirementsAt witness called
  let parts ← constraints.mapM (transferConstraint program witness start binding)
  return parts.flatten

def bodyRequirements (program : Program) (witness : Witness) (start block : BlockId)
    (closure : Slot) (arguments : List Slot) (supplied : Nat) : Option (List Constraint) := do
  let bindings ← bodyBindings program block closure arguments supplied
  let parts ← bindings.mapM (transferRequirements program witness start)
  return parts.flatten

def returnRequirements (program : Program) (witness : Witness) (start block : BlockId) :
    Option (List Constraint) := do
  let code ← program.blocks[block.value]?
  let handler ← match code.terminator with
    | .handle handler .. | .resumeWith _ _ handler .. => program.handlers[handler.value]?
    | _ => none
  let returns ← functionEntry program handler.returnFunction
  let constraints ← requirementsAt witness returns
  let parts ← constraints.mapM fun constraint => do
    let values ← returnInput program witness block constraint.value
    let owners ← returnInput program witness block constraint.owner
    let valueSources ← originSources program witness start values
    let ownerSources ← originSources program witness start owners
    return pairs valueSources ownerSources constraint.bound
  return parts.flatten

def operationRequirements (program : Program) (witness : Witness) (start block : BlockId)
    (operation : Perform) : Option (List Constraint) := do
  match operation.capability with
  | none => return []
  | some capability =>
    let captures := program.handlers.any (fun handler => handler.clauses.any
      (fun clause => clause.effect == operation.effect && !clause.direct))
    let directConstraints ← if captures then do
      let parts ← (operation.payload :: operation.bodies).mapM
        (fun value => relation program witness start block value capability .clause)
      pure parts.flatten
    else some []
    let inherited ← (operationBindings program block operation).mapM (transferRequirements program witness start)
    return directConstraints ++ inherited.flatten

def terminatorRequirements (program : Program) (witness : Witness) (start block : BlockId)
    (term : Terminator) : Option (List Constraint) := do
  match term with
  | .call function arguments _ =>
    transferRequirements program witness start { block := block, function := function, arguments := arguments }
  | .apply closure arguments _ => bodyRequirements program witness start block closure arguments 0
  | .withRegion _ body arguments _ => bodyRequirements program witness start block body arguments 1
  | .protect body cleanup arguments resource _ _ =>
    let body ← bodyRequirements program witness start block body arguments resource.toList.length
    let cleanup ← bodyRequirements program witness start block cleanup [] (1 + resource.toList.length)
    return body ++ cleanup
  | .handle handler body arguments _ _ =>
    let handler ← program.handlers[handler.value]?
    let body ← bodyRequirements program witness start block body arguments handler.clauses.length
    let returns ← returnRequirements program witness start block
    return body ++ returns
  | .perform operation | .forward operation => operationRequirements program witness start block operation
  | .resumeValue token argument _ => relation program witness start block argument token .capture
  | .resumeWith token argument _ state _ =>
    let directConstraints ← (argument :: state).mapM (fun value => relation program witness start block value token .capture)
    let returns ← returnRequirements program witness start block
    return directConstraints.flatten ++ returns
  | .resumeComputation token closure _ =>
    let captured ← relation program witness start block closure token .capture
    let body ← bodyRequirements program witness start block closure [] 0
    return captured ++ body
  | .returnValue _ | .jump _ | .branch .. | .switchVariant .. | .unpackProduct ..
  | .yieldValue _ | .fail _ | .dispose .. => return []

def requirementsStep (program : Program) (witness : Witness) (start : BlockId) : Option (List Constraint) := do
  let parts ← (reachable program start).mapM fun block => do
    let code ← program.blocks[block.value]?
    let directConstraints ← code.instructions.mapM fun instruction => do
      if instruction.opcode == .cellNew || instruction.opcode == .cellSet then
        let value ← instruction.operands[1]?
        let owner ← instruction.operands[0]?
        relation program witness start block value owner .region
      else some []
    let control ← terminatorRequirements program witness start block code.terminator
    return directConstraints.flatten ++ control
  return parts.flatten

def requirementsRowValid (program : Program) (witness : Witness) (row : RequirementsRow) : Bool :=
  row.start.value < program.blocks.length &&
    (requirementsStep program witness row.start).any (fun constraints => Admission.subset constraints row.constraints)

def scopedBindings (program : Program) (block : BlockId) (term : Terminator) : Option (List Binding) :=
  match term with
  | .handle handler body arguments _ _ => do
    let handler ← program.handlers[handler.value]?
    bodyBindings program block body arguments handler.clauses.length
  | .withRegion _ body arguments _ => bodyBindings program block body arguments 1
  | .protect body _ arguments resource _ _ => bodyBindings program block body arguments resource.toList.length
  | _ => some []

def scopedResultValid (program : Program) (witness : Witness) (binding : Binding) : Bool := ((do
  let start ← functionEntry program binding.function
  let sources ← sourcesAt program witness ⟨start, .returned []⟩
  return sources.all (fun source => (mapInput program binding source).any (fun mapped => mapped.fresh.isNone))) : Option Bool).getD false

def scopedResultsValid (program : Program) (witness : Witness) : Bool :=
  program.blocks.zipIdx.all (fun (block, index) =>
    (scopedBindings program ⟨index⟩ block.terminator).any (fun bindings => bindings.all (scopedResultValid program witness)))

/-- A finite closed analysis certificate. Query facts are checked by local trace
closure; requirements and scoped results are independently rederived. None of
the native generator's success flags is an input to this Boolean checker. -/
def check (program : Program) (witness : Witness) : Bool :=
  decide (witness.queries.map QueryRow.query).Nodup &&
  decide (witness.requirements.map RequirementsRow.start).Nodup &&
  program.functions.all (fun function => (requirementsAt witness function.entry).isSome) &&
  witness.queries.all (queryRowValid program witness) &&
  witness.requirements.all (requirementsRowValid program witness) && scopedResultsValid program witness

theorem requirements_closed (program : Program) (witness : Witness) (row : RequirementsRow)
    (accepted : requirementsRowValid program witness row = true) :
    ∃ constraints, requirementsStep program witness row.start = some constraints ∧ constraints ⊆ row.constraints := by
  simp only [requirementsRowValid, Bool.and_eq_true, Option.any_eq_true] at accepted
  obtain ⟨constraints, found, included⟩ := accepted.2
  refine ⟨constraints, found, ?_⟩
  intro constraint member
  exact List.contains_iff_mem.mp (List.all_eq_true.mp included constraint member)

theorem scopedResult_excludes_fresh (program : Program) (witness : Witness) (binding : Binding)
    (accepted : scopedResultValid program witness binding = true) :
    ∃ start sources, functionEntry program binding.function = some start ∧
      sourcesAt program witness ⟨start, .returned []⟩ = some sources ∧
      ∀ source ∈ sources, ∃ mapped, mapInput program binding source = some mapped ∧ mapped.fresh = none := by
  unfold scopedResultValid at accepted
  cases entry : functionEntry program binding.function with
  | none => simp [entry] at accepted
  | some start =>
    cases found : sourcesAt program witness ⟨start, .returned []⟩ with
    | none => simp [entry, found] at accepted
    | some sources =>
      refine ⟨start, sources, rfl, found, ?_⟩
      simpa [entry, found, List.all_eq_true, Option.any_eq_true] using accepted

theorem check_covers_rows (program : Program) (witness : Witness) (accepted : check program witness = true) :
    (∀ row ∈ witness.queries, queryRowValid program witness row = true) ∧
    (∀ row ∈ witness.requirements, requirementsRowValid program witness row = true) ∧
      scopedResultsValid program witness = true := by
  simp only [check, Bool.and_eq_true] at accepted
  exact ⟨List.all_eq_true.mp accepted.1.1.2, List.all_eq_true.mp accepted.1.2, accepted.2⟩

end BoundaryV2.Profile.Target.Borrow
