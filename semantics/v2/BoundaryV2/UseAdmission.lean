import BoundaryV2.RegionAdmission

namespace BoundaryV2.Profile.Target.Admission

abbrev ConsumedSlots := List Slot

def consumeSlot (program : Program) (slots : List (SchemaId .target)) (consumed : ConsumedSlots)
    (slot : Slot) : Option ConsumedSlots := do
  let type ← slots[slot.value]?
  if Traits.check program.schemas .copy type then some consumed
  else if consumed.contains slot then none else some (slot :: consumed)

def consumeSlots (program : Program) (slots : List (SchemaId .target)) :
    ConsumedSlots → List Slot → Option ConsumedSlots
  | consumed, [] => some consumed
  | consumed, slot :: rest => do
    let consumed ← consumeSlot program slots consumed slot
    consumeSlots program slots consumed rest

def borrowedOperands : Opcode → Bool
  | .variantTag | .sequenceLength | .sequenceGet => true
  | _ => false

def instructionDropValid (program : Program) (slots : List (SchemaId .target)) (instruction : Instruction) : Bool :=
  match instruction.opcode with
  | .select => Traits.check program.schemas .drop instruction.resultType
  | .sequenceSet | .sequenceTake => ((shape program instruction.resultType) >>= element).any
      (Traits.check program.schemas .drop)
  | .field => ((do
      let source ← instruction.operands[0]?
      let source ← slots[source.value]?
      let .product fields ← shape program source | none
      return fields.zipIdx.all (fun (type, index) =>
        index == instruction.immediate || Traits.check program.schemas .drop type)) : Option Bool).getD false
  | _ => true

def instructionUses (program : Program) (slots : List (SchemaId .target)) (consumed : ConsumedSlots)
    (instruction : Instruction) : Option ConsumedSlots :=
  if borrowedOperands instruction.opcode then
    if instruction.operands.all (fun slot => slot.value < slots.length && !consumed.contains slot) &&
      (instruction.opcode != .sequenceGet || ((do
        let source ← instruction.operands[0]?
        let source ← slots[source.value]?
        let source ← shape program source
        let item ← element source
        return Traits.check program.schemas .copy item) : Option Bool).getD false)
    then some consumed else none
  else if instructionDropValid program slots instruction then consumeSlots program slots consumed instruction.operands
  else none

def instructionsUse (program : Program) (slots : List (SchemaId .target)) :
    ConsumedSlots → List Instruction → Option ConsumedSlots
  | consumed, [] => some consumed
  | consumed, instruction :: rest => do
    let consumed ← instructionUses program slots consumed instruction
    instructionsUse program slots consumed rest

def usesFinished (program : Program) (slots : List (SchemaId .target)) (consumed : ConsumedSlots) : Bool :=
  slots.zipIdx.all (fun (type, index) => consumed.contains ⟨index⟩ || Traits.check program.schemas .drop type)

def captureSlotValid (program : Program) (slots : List (SchemaId .target)) (effect : EffectId .target)
    (slot : Slot) : Bool := ((do
  let type ← slots[slot.value]?
  let declaration ← program.effects[effect.value]?
  return (declaration.controlUse != .multi || Traits.check program.schemas .clone type) &&
    program.handlers.all (fun handler => handler.clauses.all (fun clause =>
      clause.effect != effect || (resumption program clause.resumption).any
        (fun signature => signature.captureBound.contains type)))) : Option Bool).getD false

def controlUsesValid (program : Program) (slots : List (SchemaId .target))
    (effects : List (EffectId .target)) (edge : Edge) : Bool :=
  effects.all (fun effect => edge.arguments.all (fun argument => match argument with
    | .slot slot => captureSlotValid program slots effect slot
    | .returned => true))

def edgeArgumentsUse (program : Program) (slots : List (SchemaId .target)) :
    ConsumedSlots → Nat → List (Argument × SchemaId .target) → Option (ConsumedSlots × Nat)
  | consumed, count, [] => some (consumed, count)
  | consumed, count, (argument, type) :: rest =>
    match argument with
    | .slot slot => do
      let consumed ← consumeSlot program slots consumed slot
      edgeArgumentsUse program slots consumed count rest
    | .returned =>
      if count == 0 || Traits.check program.schemas .copy type then
        edgeArgumentsUse program slots consumed (count + 1) rest
      else none

def edgeUses (program : Program) (slots : List (SchemaId .target)) (consumed : ConsumedSlots)
    (edge : Edge) (result : Option (SchemaId .target)) : Option ConsumedSlots := do
  let target ← program.blocks[edge.block.value]?
  if edge.arguments.length != target.parameters.length then none else do
    let (consumed, returnedCount) ← edgeArgumentsUse program slots consumed 0 (edge.arguments.zip target.parameters)
    if result.all (fun type => returnedCount != 0 || Traits.check program.schemas .drop type) then some consumed
    else none

def finishUses (program : Program) (slots : List (SchemaId .target)) (result : Option ConsumedSlots) : Bool :=
  result.any (usesFinished program slots)

def terminalUses (program : Program) (facts : EffectFacts) (block : Block) (consumed : ConsumedSlots) : Bool :=
  let slots := blockSlots block
  match block.terminator with
  | .fail _ => true -- The abrupt edge transfers all remaining custody to unwinding.
  | .returnValue slot => finishUses program slots (consumeSlot program slots consumed slot)
  | .jump edge | .yieldValue edge => finishUses program slots (edgeUses program slots consumed edge none)
  | .branch condition yes no =>
    (consumeSlot program slots consumed condition).any (fun consumed =>
      finishUses program slots (edgeUses program slots consumed yes none) &&
      finishUses program slots (edgeUses program slots consumed no none))
  | .switchVariant value cases => ((do
    let consumed ← consumeSlot program slots consumed value
    let type ← slots[value.value]?
    let .sum fields ← shape program type | none
    return cases.length == fields.length && (cases.zip fields).all (fun (edge, result) =>
      finishUses program slots (edgeUses program slots consumed edge (some result)))) : Option Bool).getD false
  | .unpackProduct value _ arguments =>
    finishUses program slots (consumeSlots program slots consumed (value :: arguments))
  | .call callee arguments edge => ((do
    let consumed ← consumeSlots program slots consumed arguments
    let callee ← program.functions[callee.value]?
    return controlUsesValid program slots callee.effects edge &&
      finishUses program slots (edgeUses program slots consumed edge (some callee.result))) : Option Bool).getD false
  | .perform operation => ((do
    let consumed ← consumeSlots program slots consumed
      ([operation.payload] ++ operation.bodies ++ operation.capability.toList ++ operation.useSiteCapabilities)
    let effect ← program.effects[operation.effect.value]?
    return controlUsesValid program slots [operation.effect] operation.next &&
      controlUsesValid program slots effect.useSiteEffects operation.next &&
      finishUses program slots (edgeUses program slots consumed operation.next (some effect.result))) : Option Bool).getD false
  | .apply closure arguments edge => ((do
    let consumed ← consumeSlots program slots consumed (closure :: arguments)
    let signature ← slotComputation program slots closure
    return controlUsesValid program slots signature.effects edge &&
      finishUses program slots (edgeUses program slots consumed edge (some signature.result))) : Option Bool).getD false
  | .handle handler body arguments state edge => ((do
    let consumed ← consumeSlots program slots consumed ([body] ++ arguments ++ state)
    let handler ← program.handlers[handler.value]?
    let signature ← slotComputation program slots body
    return signature.effects.all (fun effect => discharged facts handler signature effect ||
      (controlUsesValid program slots [effect] edge && state.all (captureSlotValid program slots effect))) &&
      controlUsesValid program slots handler.effects edge &&
      finishUses program slots (edgeUses program slots consumed edge (some handler.answer))) : Option Bool).getD false
  | .resumeValue token argument edge | .resumeComputation token argument edge => ((do
    let consumed ← consumeSlots program slots consumed [token, argument]
    let signature ← slotResumption program slots token
    return controlUsesValid program slots signature.effects edge &&
      finishUses program slots (edgeUses program slots consumed edge (some signature.answer))) : Option Bool).getD false
  | .resumeWith token argument handler state edge => ((do
    let consumed ← consumeSlots program slots consumed ([token, argument] ++ state)
    let signature ← slotResumption program slots token
    let successor ← program.handlers[handler.value]?
    return signature.effects.all (fun effect =>
      let escapes := !signature.handled.contains effect || signature.escaping.contains effect
      !escapes || (controlUsesValid program slots [effect] edge &&
        state.all (captureSlotValid program slots effect))) &&
      controlUsesValid program slots successor.effects edge &&
      finishUses program slots (edgeUses program slots consumed edge (some successor.answer))) : Option Bool).getD false
  | .withRegion _ body arguments edge => ((do
    let consumed ← consumeSlots program slots consumed (body :: arguments)
    let body ← slotComputation program slots body
    return controlUsesValid program slots body.effects edge &&
      finishUses program slots (edgeUses program slots consumed edge (some body.result))) : Option Bool).getD false
  | .protect body cleanup arguments resource _ edge => ((do
    let consumed ← consumeSlots program slots consumed ([body, cleanup] ++ resource.toList ++ arguments)
    let body ← slotComputation program slots body
    let cleanup ← slotComputation program slots cleanup
    return controlUsesValid program slots body.effects edge && controlUsesValid program slots cleanup.effects edge &&
      finishUses program slots (edgeUses program slots consumed edge (some body.result))) : Option Bool).getD false
  | .dispose owned edge => ((do
    let consumed ← consumeSlot program slots consumed owned
    let signature ← slotResumption program slots owned
    return controlUsesValid program slots signature.effects edge &&
      finishUses program slots (edgeUses program slots consumed edge none)) : Option Bool).getD false
  | .forward _ => false

def blockUsesValid (program : Program) (facts : EffectFacts) (block : Block) : Bool :=
  (instructionsUse program (blockSlots block) [] block.instructions).any (terminalUses program facts block)

theorem consume_preserves_old (program : Program) (slots : List (SchemaId .target))
    (consumed next : ConsumedSlots) (slot : Slot)
    (accepted : consumeSlot program slots consumed slot = some next) : consumed ⊆ next := by
  unfold consumeSlot at accepted
  cases found : slots[slot.value]? with
  | none => simp [found] at accepted
  | some type =>
    by_cases copy : Traits.check program.schemas .copy type = true
    · have equal : consumed = next := by simpa [found, copy] using accepted
      exact equal ▸ List.Subset.refl consumed
    · have equal : ¬slot ∈ consumed ∧ slot :: consumed = next := by simpa [found, copy] using accepted
      rw [← equal.2]
      exact List.subset_cons_self slot consumed

theorem consumed_noncopy_rejected (program : Program) (slots : List (SchemaId .target))
    (consumed : ConsumedSlots) (slot : Slot) (type : SchemaId .target)
    (found : slots[slot.value]? = some type) (exclusive : Traits.check program.schemas .copy type = false)
    (already : slot ∈ consumed) : consumeSlot program slots consumed slot = none := by
  simp [consumeSlot, found, exclusive, already]

theorem noncopy_consumed_once (program : Program) (slots : List (SchemaId .target))
    (consumed next : ConsumedSlots) (slot : Slot) (type : SchemaId .target)
    (found : slots[slot.value]? = some type) (exclusive : Traits.check program.schemas .copy type = false)
    (accepted : consumeSlot program slots consumed slot = some next) :
    slot ∉ consumed ∧ next = slot :: consumed ∧ consumeSlot program slots next slot = none := by
  by_cases prior : slot ∈ consumed
  · simp [consumed_noncopy_rejected program slots consumed slot type found exclusive prior] at accepted
  · have equality : next = slot :: consumed := by
      simpa [consumeSlot, found, exclusive, prior] using accepted.symm
    refine ⟨prior, equality, ?_⟩
    exact consumed_noncopy_rejected program slots next slot type found exclusive (by simp [equality])

end BoundaryV2.Profile.Target.Admission
