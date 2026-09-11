import BoundaryV2.PrimitiveAdmission

namespace BoundaryV2.Profile.Target.Admission

def primitiveContext (program : Program) : PrimitiveAdmission.Context .target where
  schemas := program.schemas
  constants := program.constants
  failure := program.roots.failure
  resources := program.scopes.resources
  constructor index := do
    let constructor ← program.constructors[index]?
    let capture ← program.scopes.captures[constructor.capture.value]?
    return (constructor.schema, capture.fields)

def primitiveOperation (instruction : Instruction) : PrimitiveAdmission.Operation .target :=
  ⟨instruction.opcode, instruction.resultType, instruction.immediate, instruction.failures⟩

def shape (program : Program) (id : SchemaId .target) : Option (Schema .target) :=
  program.schemas[id.value]?

abbrev integer := @PrimitiveAdmission.integer .target
abbrev isText := @PrimitiveAdmission.isText .target
abbrev isBytes := @PrimitiveAdmission.isBytes .target
abbrev blobMaximum := @PrimitiveAdmission.blobMaximum .target
abbrev element := @PrimitiveAdmission.element .target
abbrev collectionBound := @PrimitiveAdmission.collectionBound .target

def optional (program : Program) := PrimitiveAdmission.optional (primitiveContext program)
def conversionCanFail (program : Program) := PrimitiveAdmission.conversionCanFail (primitiveContext program)
def requiredFaults (program : Program) := PrimitiveAdmission.requiredFaults (primitiveContext program)
def failuresValid (program : Program) (instruction : Instruction) :=
  PrimitiveAdmission.failuresValid (primitiveContext program) (primitiveOperation instruction)
def cloneCompatible (program : Program) := PrimitiveAdmission.cloneCompatible (primitiveContext program)
def resourceDescriptor (program : Program) := PrimitiveAdmission.resourceDescriptor (primitiveContext program)
def resourceInstruction (program : Program) := PrimitiveAdmission.resourceInstruction (primitiveContext program)
def instructionType (program : Program) (owner : FunctionId .target) (instruction : Instruction) :=
  PrimitiveAdmission.operationType (primitiveContext program) owner (primitiveOperation instruction)

def slotTypes (slots : List (SchemaId .target)) : List Slot → Option (List (SchemaId .target))
  | [] => some []
  | reference :: references => do
    let type ← slots[reference.value]?
    let rest ← slotTypes slots references
    return type :: rest

def instructionValid (program : Program) (owner : FunctionId .target)
    (slots : List (SchemaId .target)) (instruction : Instruction) : Bool :=
  (slotTypes slots instruction.operands).any fun operands =>
    instruction.resultType.value < program.schemas.length &&
    failuresValid program instruction operands && instructionType program owner instruction operands

def instructionSlots (block : Block) (index : Nat) : List (SchemaId .target) :=
  block.parameters ++ (block.instructions.take index).map Instruction.resultType

def blockInstructionsValid (program : Program) (block : Block) : Bool :=
  block.function.value < program.functions.length &&
  block.parameters.all (fun parameter => parameter.value < program.schemas.length) &&
  block.instructions.zipIdx.all (fun (instruction, index) =>
    instructionValid program block.function (instructionSlots block index) instruction)

theorem failures_exact (program : Program) (instruction : Instruction) (operands : List (SchemaId .target))
    (accepted : failuresValid program instruction operands = true) :
    instruction.failures.map InstructionFailure.kind =
        requiredFaults program instruction.opcode instruction.resultType operands ∧
    ∀ failure ∈ instruction.failures, ∃ value,
      program.constants[failure.value.value]? = some value ∧ value.schema = program.roots.failure := by
  simpa [failuresValid, PrimitiveAdmission.failuresValid, primitiveOperation,
    primitiveContext, requiredFaults, Bool.and_eq_true, List.all_eq_true, Option.any_eq_true] using accepted

theorem slotTypes_exact (slots : List (SchemaId .target)) (references : List Slot)
    (types : List (SchemaId .target)) : slotTypes slots references = some types ↔
    references.map (fun reference => slots[reference.value]?) = types.map some := by
  induction references generalizing types with
  | nil => cases types <;> simp [slotTypes]
  | cons reference references ih =>
    cases found : slots[reference.value]? with
    | none => cases types <;> simp [slotTypes, found]
    | some type =>
      cases tail : slotTypes slots references with
      | none =>
        have absent : ∀ (rest : List (SchemaId .target)), references.map (fun reference => slots[reference.value]?) ≠ rest.map some := by
          intro rest same
          have impossible := (ih rest).mpr same
          simp [tail] at impossible
        cases types <;> simp [slotTypes, found, tail, absent]
      | some rest =>
        have same := (ih rest).mp tail
        cases types <;> simp [slotTypes, found, tail, same, List.map_inj_right (fun _ _ => Option.some.inj)]

theorem instruction_operands_defined (program : Program) (owner : FunctionId .target)
    (slots : List (SchemaId .target)) (instruction : Instruction)
    (accepted : instructionValid program owner slots instruction = true) :
    ∀ reference ∈ instruction.operands, reference.value < slots.length := by
  obtain ⟨types, found, _⟩ := (Option.any_eq_true _ _).mp accepted
  have aligned := (slotTypes_exact slots instruction.operands types).mp found
  intro reference member
  have present : slots[reference.value]? ∈ types.map some := by
    rw [← aligned]
    exact List.mem_map.mpr ⟨reference, member, rfl⟩
  obtain ⟨type, _, lookup⟩ := List.mem_map.mp present
  have lookup := lookup.symm
  exact List.getElem?_eq_some_iff.mp lookup |>.1

theorem accepted_fault_binding (program : Program) (owner : FunctionId .target)
    (slots : List (SchemaId .target)) (instruction : Instruction)
    (accepted : instructionValid program owner slots instruction = true) :
    ∃ operands, slotTypes slots instruction.operands = some operands ∧
      instruction.failures.map InstructionFailure.kind =
        requiredFaults program instruction.opcode instruction.resultType operands ∧
      ∀ failure ∈ instruction.failures, ∃ value,
        program.constants[failure.value.value]? = some value ∧ value.schema = program.roots.failure := by
  obtain ⟨operands, found, accepted⟩ := (Option.any_eq_true _ _).mp accepted
  simp only [Bool.and_eq_true] at accepted
  exact ⟨operands, found, failures_exact program instruction operands accepted.1.2⟩

theorem accepted_instruction (program : Program) (block : Block) (index : Nat) (instruction : Instruction)
    (accepted : blockInstructionsValid program block = true)
    (found : block.instructions[index]? = some instruction) :
    instructionValid program block.function (instructionSlots block index) instruction = true := by
  simp only [blockInstructionsValid, Bool.and_eq_true] at accepted
  apply List.all_eq_true.mp accepted.2 (instruction, index)
  exact List.mem_iff_getElem?.mpr ⟨index, by simpa using found⟩

theorem block_no_forward_operand (program : Program) (block : Block) (index : Nat) (instruction : Instruction)
    (accepted : blockInstructionsValid program block = true)
    (found : block.instructions[index]? = some instruction) :
    ∀ reference ∈ instruction.operands, reference.value < block.parameters.length + index := by
  have checked := accepted_instruction program block index instruction accepted found
  have inside := (List.getElem?_eq_some_iff.mp found).1
  intro reference member
  have defined := instruction_operands_defined program block.function (instructionSlots block index)
    instruction checked reference member
  simpa [instructionSlots, Nat.min_eq_left (Nat.le_of_lt inside)] using defined

end BoundaryV2.Profile.Target.Admission
