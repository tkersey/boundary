import BoundaryV2.SourceBorrowPaths

namespace BoundaryV2.Profile.Source.Borrow

def sequenceInstruction (context : Context) (path : Path) (opcode : Opcode) (operands : List ValueRef) (_immediate : Nat) :
    Option (List Trace) := do
  let sequence ← operands[0]?
  match opcode with
  | .sequenceConcat =>
    let right ← operands[1]?
    pushValues context [sequence, right] path
  | .sequenceTake => push context sequence path
  | .sequenceAppend | .sequenceSet =>
    match childPath path .element with
    | none => return []
    | some elementPath =>
      let added ← operands[if opcode == .sequenceAppend then 1 else 2]?
      pushes context [.value sequence path, .value added elementPath]
  | .sequencePop =>
    match childPath path (.field 1) with
    | none => return []
    | some present =>
      let item := (childPath present (.field 0)).toList
      let rest := (childPath present (.field 1) >>= fun rest => childPath rest .element).toList
      pushes context ((item ++ rest).map (fun path => .value sequence (prepend .element path)))
  | .sequencePopLast =>
    let rest := (childPath path (.field 0)).toList.map (fun path => .value sequence path)
    let item := (childPath path (.field 1) >>= fun optional => childPath optional (.field 1)).toList.map
      (fun path => .value sequence (prepend .element path))
    pushes context (rest ++ item)
  | _ => none

/-- Reverse dependency transfer for each instruction result. Heap reads also
consult the interprocedural write summary in the enclosing query checker. -/
def primitiveTraces (context : Context) (path : Path) (opcode : Opcode) (operands : List ValueRef) (immediate : Nat) :
    Option (List Trace) := do
  match opcode with
  | .move | .cloneResumption =>
    let source ← operands[0]?
    push context source path
  | .select => pushValues context (operands.drop 1) path
  | .product => match path with
    | [] => pushValues context operands []
    | .field field :: rest => match operands[field]? with
      | none => return []
      | some source => push context source rest
    | _ => return []
  | .field | .variantPayload =>
    let source ← operands[0]?
    push context source (prepend (.field immediate) path)
  | .variant => match path with
    | [] => pushValues context operands []
    | .field field :: rest =>
      if field != immediate then return []
      let source ← operands[0]?
      push context source rest
    | _ => return []
  | .computation => none -- Graph construction resolves its explicit capture fields.
  | .cellNew => match path with
    | [] =>
      let region ← operands[0]?
      push context region []
    | .cellContent :: rest =>
      let value ← operands[1]?
      push context value rest
    | _ => return []
  | .cellGet =>
    let source ← operands[0]?
    push context source (prepend .cellContent path)
  | .sequence => pushValues context operands path.tail
  | .sequenceGet =>
    let source ← operands[0]?
    match path with
    | [] => push context source (prepend .element [])
    | .field 1 :: rest => push context source (prepend .element rest)
    | _ => return []
  | .unpack =>
    let source ← operands[0]?
    push context source (prepend .packageToken path)
  | .package =>
    let source ← operands[0]?
    match path with
    | [] => push context source []
    | .packageToken :: rest => push context source rest
    | _ => return []
  | .sequenceAppend | .sequenceConcat | .sequencePop | .sequenceSet | .sequenceTake | .sequencePopLast =>
    sequenceInstruction context path opcode operands immediate
  | .constant | .integerAdd | .integerSub | .integerMul | .integerDiv | .integerRem
  | .integerBitNot | .integerBitAnd | .integerBitOr | .integerBitXor | .integerConvert | .enumTag
  | .equal | .less | .booleanNot | .variantTag | .sequenceLength | .cellSet
  | .resourcePack | .resourceUnpack | .blobLength | .blobConcat | .blobSlice | .blobCompare
  | .blobByte | .textScalar | .textInteger | .blobFromByte => return []

end BoundaryV2.Profile.Source.Borrow
