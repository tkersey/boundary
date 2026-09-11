import BoundaryV2.SchemaDependencies
import BoundaryV2.ControlAdmission

namespace BoundaryV2.Profile.Target.Admission

def argumentType (slots : List (SchemaId .target)) (returned : Option (SchemaId .target)) :
    Argument → Option (SchemaId .target)
  | .slot slot => slots[slot.value]?
  | .returned => returned

def argumentTypes (slots : List (SchemaId .target)) (returned : Option (SchemaId .target)) :
    List Argument → Option (List (SchemaId .target))
  | [] => some []
  | first :: rest => do
    let type ← argumentType slots returned first
    let rest ← argumentTypes slots returned rest
    return type :: rest

def argumentsValid (slots : List (SchemaId .target)) (supplied : List Slot)
    (expected : List (SchemaId .target)) : Bool := slotTypes slots supplied == some expected

def edgeValid (program : Program) (owner : FunctionId .target) (slots : List (SchemaId .target))
    (edge : Edge) (returned : Option (SchemaId .target)) : Bool :=
  (program.blocks[edge.block.value]?).any (fun target =>
    target.function == owner && argumentTypes slots returned edge.arguments == some target.parameters)

def blockSlots (block : Block) : List (SchemaId .target) :=
  block.parameters ++ block.instructions.map Instruction.resultType

def slotComputation (program : Program) (slots : List (SchemaId .target)) (slot : Slot) :
    Option (ComputationType .target) := slots[slot.value]? >>= computation program

def slotResumption (program : Program) (slots : List (SchemaId .target)) (slot : Slot) :
    Option (ResumptionType .target) := slots[slot.value]? >>= resumption program

def controlContext (program : Program) : ControlAdmission.Context .target :=
  ⟨declarationContext program, program.handlers, program.roots.failure⟩

abbrev covers := @ControlAdmission.covers .target
def continuationEffect (program : Program) := ControlAdmission.continuationEffect (controlContext program)
def deepHandlerEffects (program : Program) := ControlAdmission.deepHandlerEffects (controlContext program)
def capturedRegion (program : Program) := ControlAdmission.capturedRegion (controlContext program)
def cleanupInfoValid (program : Program) := ControlAdmission.cleanupInfoValid (controlContext program)
def effectsAllowCleanup (program : Program) := ControlAdmission.effectsAllowCleanup (controlContext program)

def protectionTypes (program : Program) (function : Function) (slots : List (SchemaId .target))
    (body cleanup : ComputationType .target) (arguments : List Slot) (resource : Option Slot)
    (loanRegion : Option (RegionId .target)) : Bool := ((do
  let loaned := resource.toList.length
  let info ← cleanup.parameters[0]?
  let general := body.parameters.length ≥ loaned && cleanup.parameters.length == 1 + loaned &&
    shape program cleanup.result == some .unit &&
    argumentsValid slots arguments (body.parameters.drop loaned) && cleanupInfoValid program info &&
    subset body.effects function.effects && subset cleanup.effects function.effects &&
    subset cleanup.regions function.regions && effectsAllowCleanup program body.effects &&
    effectsAllowCleanup program cleanup.effects
  match resource with
  | none => return general && loanRegion.isNone && subset body.regions function.regions
  | some slot =>
    let type ← slots[slot.value]?
    let _ ← resourceDescriptor program type
    let region ← loanRegion
    let borrowed ← body.parameters[0]?
    return general && region.value < program.scopes.regionCount && cleanup.parameters[1]? == some type &&
      shape program borrowed == some (.internal (.borrowed type region)) &&
      (body.regions.filter (· != region)).all function.regions.contains &&
      capturedRegion program body.effects region) : Option Bool).getD false

def terminatorValid (program : Program) (facts : EffectFacts) (block : Block) : Bool := ((do
  let function ← program.functions[block.function.value]?
  let slots := blockSlots block
  match block.terminator with
  | .returnValue slot => return slots[slot.value]? == some function.result
  | .fail slot => return slots[slot.value]? == some program.roots.failure
  | .jump next | .yieldValue next => return edgeValid program block.function slots next none
  | .branch condition yes no =>
    let type ← slots[condition.value]?
    return shape program type == some .boolean && edgeValid program block.function slots yes none &&
      edgeValid program block.function slots no none
  | .switchVariant value cases =>
    let type ← slots[value.value]?
    let .sum fields ← shape program type | none
    return cases.length == fields.length && (cases.zip fields).all (fun (next, payload) =>
      edgeValid program block.function slots next (some payload))
  | .unpackProduct value target arguments =>
    let type ← slots[value.value]?
    let .product fields ← shape program type | none
    let target ← program.blocks[target.value]?
    let arguments ← slotTypes slots arguments
    return target.function == block.function && target.parameters == fields ++ arguments
  | .call callee arguments next =>
    let callee ← program.functions[callee.value]?
    return argumentsValid slots arguments callee.parameters && subset callee.effects function.effects &&
      edgeValid program block.function slots next (some callee.result)
  | .perform operation =>
    let effect ← program.effects[operation.effect.value]?
    let explicit := match operation.capability with
      | none => effect.external
      | some slot => (slots[slot.value]?).any (fun type => capability program type operation.effect)
    let evidence := (slotTypes slots operation.useSiteCapabilities).any (fun types =>
      types.length == effect.useSiteEffects.length &&
      (types.zip effect.useSiteEffects).all (fun (type, effect) => capability program type effect))
    return explicit && argumentsValid slots operation.bodies effect.bodies && evidence &&
      function.effects.contains operation.effect && subset effect.useSiteEffects function.effects &&
      slots[operation.payload.value]? == some effect.payload &&
      edgeValid program block.function slots operation.next (some effect.result)
  | .apply closure arguments next =>
    let signature ← slotComputation program slots closure
    return argumentsValid slots arguments signature.parameters && subset signature.effects function.effects &&
      subset signature.regions function.regions && edgeValid program block.function slots next (some signature.result)
  | .handle handler body arguments state next =>
    let handler ← program.handlers[handler.value]?
    let body ← slotComputation program slots body
    return subset body.regions function.regions && body.result == handler.input &&
      body.parameters.length == handler.clauses.length + arguments.length &&
      ((body.parameters.take handler.clauses.length).zip handler.clauses).all
        (fun (type, clause) => capability program type clause.effect) &&
      argumentsValid slots arguments (body.parameters.drop handler.clauses.length) &&
      argumentsValid slots state handler.state &&
      body.effects.all (fun effect =>
        let escapes := !discharged facts handler body effect
        (!escapes || function.effects.contains effect) && continuationEffect program handler effect escapes) &&
      subset handler.effects function.effects && deepHandlerEffects program handler &&
      edgeValid program block.function slots next (some handler.answer)
  | .resumeValue token argument next =>
    let signature ← slotResumption program slots token
    return slots[argument.value]? == some signature.input && subset signature.effects function.effects &&
      edgeValid program block.function slots next (some signature.answer)
  | .resumeWith token argument handler state next =>
    let signature ← slotResumption program slots token
    let successor ← program.handlers[handler.value]?
    return signature.mode == .shallow && slots[argument.value]? == some signature.input &&
      successor.input == signature.answer && successor.clauses.map Clause.effect == signature.handled &&
      signature.effects.all (fun effect =>
        let escapes := !covers successor effect || signature.escaping.contains effect
        (!escapes || function.effects.contains effect) && continuationEffect program successor effect escapes) &&
      subset successor.effects function.effects && deepHandlerEffects program successor &&
      argumentsValid slots state successor.state && edgeValid program block.function slots next (some successor.answer)
  | .resumeComputation token closure next =>
    let signature ← slotResumption program slots token
    let thunk ← slotComputation program slots closure
    let effect ← program.effects[signature.effect.value]?
    return thunk.result == signature.input && thunk.parameters.length == effect.useSiteEffects.length &&
      (thunk.parameters.zip effect.useSiteEffects).all (fun (type, effect) => capability program type effect) &&
      subset thunk.effects effect.useSiteEffects && subset signature.effects function.effects &&
      edgeValid program block.function slots next (some signature.answer)
  | .dispose token next =>
    let signature ← slotResumption program slots token
    return signature.use != .multi && subset signature.effects function.effects &&
      edgeValid program block.function slots next none
  | .protect body cleanup arguments resource loanRegion next =>
    let body ← slotComputation program slots body
    let cleanup ← slotComputation program slots cleanup
    return protectionTypes program function slots body cleanup arguments resource loanRegion &&
      edgeValid program block.function slots next (some body.result)
  | .withRegion region body arguments next =>
    let body ← slotComputation program slots body
    let regionType ← body.parameters[0]?
    return region.value < program.scopes.regionCount && body.parameters.length == arguments.length + 1 &&
      shape program regionType == some (.internal (.region region)) &&
      subset (body.regions.filter (· != region)) function.regions &&
      argumentsValid slots arguments (body.parameters.drop 1) && subset body.effects function.effects &&
      capturedRegion program body.effects region && edgeValid program block.function slots next (some body.result)
  | .forward _ => return false -- This reserved wire tag is rejected by baseline BPI2 admission.
  ) : Option Bool).getD false

theorem edge_interface (program : Program) (owner : FunctionId .target) (slots : List (SchemaId .target))
    (edge : Edge) (returned : Option (SchemaId .target))
    (accepted : edgeValid program owner slots edge returned = true) :
    ∃ target, program.blocks[edge.block.value]? = some target ∧ target.function = owner ∧
      argumentTypes slots returned edge.arguments = some target.parameters := by
  simpa [edgeValid, Option.any_eq_true, Bool.and_eq_true] using accepted

theorem argumentTypes_exact (slots : List (SchemaId .target)) (returned : Option (SchemaId .target))
    (arguments : List Argument) (types : List (SchemaId .target)) :
    argumentTypes slots returned arguments = some types ↔
      arguments.map (argumentType slots returned) = types.map some := by
  induction arguments generalizing types with
  | nil => cases types <;> simp [argumentTypes]
  | cons argument arguments ih =>
    cases found : argumentType slots returned argument with
    | none => cases types <;> simp [argumentTypes, found]
    | some type =>
      cases tail : argumentTypes slots returned arguments with
      | none =>
        have absent : ∀ (rest : List (SchemaId .target)),
            arguments.map (argumentType slots returned) ≠ rest.map some := by
          intro rest same
          have impossible := (ih rest).mpr same
          simp [tail] at impossible
        cases types <;> simp [argumentTypes, found, tail, absent]
      | some rest =>
        have same := (ih rest).mp tail
        cases types <;> simp [argumentTypes, found, tail, same,
          List.map_inj_right (fun _ _ => Option.some.inj)]

theorem edge_no_missing_return (program : Program) (owner : FunctionId .target)
    (slots : List (SchemaId .target)) (edge : Edge)
    (accepted : edgeValid program owner slots edge none = true) : .returned ∉ edge.arguments := by
  obtain ⟨target, _, _, found⟩ := edge_interface program owner slots edge none accepted
  have aligned := (argumentTypes_exact slots none edge.arguments target.parameters).mp found
  intro member
  have present : (none : Option (SchemaId .target)) ∈ target.parameters.map some := by
    rw [← aligned]
    exact List.mem_map.mpr ⟨.returned, member, rfl⟩
  simp at present

end BoundaryV2.Profile.Target.Admission
