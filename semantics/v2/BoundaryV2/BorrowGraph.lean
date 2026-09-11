import BoundaryV2.BorrowMapping

namespace BoundaryV2.Profile.Target.Borrow

inductive Incoming where
  | edge : BlockId → Edge → Option Nat → Incoming
  | product : BlockId → Slot → List Slot → Incoming
  deriving DecidableEq, Repr

def Incoming.source : Incoming → BlockId
  | .edge source _ _ | .product source _ _ => source

def outgoing (source : BlockId) (term : Terminator) : List (BlockId × Incoming) :=
  match term with
  | .jump edge | .yieldValue edge | .call _ _ edge | .apply _ _ edge
  | .handle _ _ _ _ edge | .resumeValue _ _ edge | .resumeWith _ _ _ _ edge
  | .resumeComputation _ _ edge | .dispose _ edge | .protect _ _ _ _ _ edge
  | .withRegion _ _ _ edge => [(edge.block, .edge source edge none)]
  | .perform operation | .forward operation => [(operation.next.block, .edge source operation.next none)]
  | .branch _ yes no => [(yes.block, .edge source yes none), (no.block, .edge source no none)]
  | .switchVariant _ cases => cases.zipIdx.map (fun (edge, index) => (edge.block, .edge source edge (some index)))
  | .unpackProduct value target arguments => [(target, .product source value arguments)]
  | .returnValue _ | .fail _ => []

def incoming (program : Program) (target : BlockId) : List Incoming :=
  program.blocks.zipIdx.flatMap (fun (block, index) =>
    (outgoing ⟨index⟩ block.terminator).filterMap (fun (destination, edge) =>
      if destination == target then some edge else none))

def blockIds (program : Program) : List BlockId :=
  (List.range program.blocks.length).map (fun index => ⟨index⟩)

def reachable (program : Program) (start : BlockId) : List BlockId :=
  let unreachable := FiniteDependency.refine (fun block => block == start)
    (fun block => (incoming program block).map Incoming.source) (blockIds program)
  (blockIds program).filter (fun block => !unreachable.contains block)

def pushes (program : Program) (traces : List Trace) : Option (List Trace) := do
  let parts ← traces.mapM (pushTrace program)
  return parts.flatten

def pushSlots (program : Program) (block : BlockId) (slots : List Slot) (path : Path) : Option (List Trace) :=
  pushes program (slots.map (fun slot => .slot block slot path))

def sequenceInstruction (program : Program) (block : BlockId) (path : Path) (instruction : Instruction) :
    Option (List Trace) := do
  let sequence ← instruction.operands[0]?
  match instruction.opcode with
  | .sequenceConcat =>
    let right ← instruction.operands[1]?
    pushSlots program block [sequence, right] path
  | .sequenceTake => push program block sequence path
  | .sequenceAppend | .sequenceSet =>
    match childPath path .element with
    | none => return []
    | some elementPath =>
      let added ← instruction.operands[if instruction.opcode == .sequenceAppend then 1 else 2]?
      pushes program [.slot block sequence path, .slot block added elementPath]
  | .sequencePop =>
    match childPath path (.field 1) with
    | none => return []
    | some present =>
      let item := (childPath present (.field 0)).toList
      let rest := (childPath present (.field 1) >>= fun rest => childPath rest .element).toList
      pushes program ((item ++ rest).map (fun path => .slot block sequence (prepend .element path)))
  | .sequencePopLast =>
    let rest := (childPath path (.field 0)).toList.map (fun path => .slot block sequence path)
    let item := (childPath path (.field 1) >>= fun optional => childPath optional (.field 1)).toList.map
      (fun path => .slot block sequence (prepend .element path))
    pushes program (rest ++ item)
  | _ => none

/-- Reverse dependency transfer for each instruction result. Heap reads also
consult the interprocedural write summary in the enclosing query checker. -/
def instructionTraces (program : Program) (block : BlockId) (path : Path) (instruction : Instruction) :
    Option (List Trace) := do
  match instruction.opcode with
  | .move | .cloneResumption =>
    let source ← instruction.operands[0]?
    push program block source path
  | .select => pushSlots program block (instruction.operands.drop 1) path
  | .product => match path with
    | [] => pushSlots program block instruction.operands []
    | .field field :: rest => match instruction.operands[field]? with
      | none => return []
      | some source => push program block source rest
    | _ => return []
  | .field | .variantPayload =>
    let source ← instruction.operands[0]?
    push program block source (prepend (.field instruction.immediate) path)
  | .variant => match path with
    | [] => pushSlots program block instruction.operands []
    | .field field :: rest =>
      if field != instruction.immediate then return []
      let source ← instruction.operands[0]?
      push program block source rest
    | _ => return []
  | .computation => match path with
    | [] => pushSlots program block instruction.operands []
    | .environment constructor field :: rest =>
      if constructor.value != instruction.immediate then return []
      let source ← instruction.operands[field]?
      push program block source rest
    | _ => return []
  | .cellNew => match path with
    | [] =>
      let region ← instruction.operands[0]?
      push program block region []
    | .cellContent :: rest =>
      let value ← instruction.operands[1]?
      push program block value rest
    | _ => return []
  | .cellGet =>
    let source ← instruction.operands[0]?
    push program block source (prepend .cellContent path)
  | .sequence => pushSlots program block instruction.operands path.tail
  | .sequenceGet =>
    let source ← instruction.operands[0]?
    match path with
    | [] => push program block source (prepend .element [])
    | .field 1 :: rest => push program block source (prepend .element rest)
    | _ => return []
  | .unpack =>
    let source ← instruction.operands[0]?
    push program block source (prepend .packageToken path)
  | .package =>
    let source ← instruction.operands[0]?
    match path with
    | [] => push program block source []
    | .packageToken :: rest => push program block source rest
    | _ => return []
  | .sequenceAppend | .sequenceConcat | .sequencePop | .sequenceSet | .sequenceTake | .sequencePopLast =>
    sequenceInstruction program block path instruction
  | .constant | .integerAdd | .integerSub | .integerMul | .integerDiv | .integerRem
  | .integerBitNot | .integerBitAnd | .integerBitOr | .integerBitXor | .integerConvert | .enumTag
  | .equal | .less | .booleanNot | .variantTag | .sequenceLength | .cellSet
  | .resourcePack | .resourceUnpack | .blobLength | .blobConcat | .blobSlice | .blobCompare
  | .blobByte | .textScalar | .textInteger | .blobFromByte => return []

theorem blockIds_member (program : Program) (id : BlockId) :
    id ∈ blockIds program ↔ id.value < program.blocks.length := by
  cases id
  simp [blockIds]

theorem outgoing_source (source : BlockId) (term : Terminator) (edge : BlockId × Incoming)
    (member : edge ∈ outgoing source term) : edge.2.source = source := by
  cases term <;> simp [outgoing] at member
  all_goals first
    | (obtain ⟨item, index, inside, equal⟩ := member; subst edge; rfl)
    | (rcases member with equal | equal <;> subst edge <;> rfl)
    | (subst edge; rfl)

theorem incoming_source_bounded (program : Program) (target : BlockId) (edge : Incoming)
    (member : edge ∈ incoming program target) : edge.source.value < program.blocks.length := by
  obtain ⟨⟨block, index⟩, entry, member⟩ := List.mem_flatMap.mp member
  obtain ⟨⟨destination, actual⟩, outgoingMember, selected⟩ := List.mem_filterMap.mp member
  by_cases equalTarget : destination == target
  · simp [equalTarget] at selected
    subst edge
    have source := outgoing_source ⟨index⟩ block.terminator (destination, actual) outgoingMember
    rw [source]
    have entryFound : program.blocks[index]? = some block := List.mk_mem_zipIdx_iff_getElem?.mp entry
    exact (List.getElem?_eq_some_iff.mp entryFound).1
  · simp [equalTarget] at selected

theorem reachable_exact (program : Program) (start target : BlockId)
    (inside : target.value < program.blocks.length) :
    target ∈ reachable program start ↔
      FiniteDependency.Depends (fun block => block == start)
        (fun block => (incoming program block).map Incoming.source) target := by
  classical
  have bounded : ∀ block ∈ blockIds program,
      ∀ child ∈ (incoming program block).map Incoming.source, child ∈ blockIds program := by
    intro block _ child member
    obtain ⟨edge, edgeMember, equal⟩ := List.mem_map.mp member
    subst child
    exact (blockIds_member program edge.source).mpr (incoming_source_bounded program block edge edgeMember)
  have exactness := FiniteDependency.refine_exact (fun block => block == start)
    (fun block => (incoming program block).map Incoming.source) (blockIds program) bounded target
      ((blockIds_member program target).mpr inside)
  simp [reachable, (blockIds_member program target).mpr inside, exactness]

end BoundaryV2.Profile.Target.Borrow
