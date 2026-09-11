import BoundaryV2.SchemaDescriptor

open BoundaryV2.Profile
open BoundaryV2.Profile.SchemaDescriptor

private def shapes : List (Schema .target) := [
  .unit, .boolean, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .bytes, .text,
  .product [1, 1], .sum [1, 0], .seq 1, .vector 1 3, .internal (.capability 0),
  .array 1 3, .boundedBytes 4, .boundedText 5, .enumeration [0, 2, 4294967295]]

private def cases : List (String × Descriptor) := [
  ("merged-leaves", ⟨0, [.product [1, 2], .u64, .u64]⟩),
  ("permuted-leaves", ⟨1, [.u64, .product [0, 0]]⟩),
  ("merged-cycles", ⟨0, [.product [1, 2], .sum [3, 1], .sum [3, 2], .unit]⟩),
  ("mutual-cycle", ⟨0, [.sum [2, 1], .sum [2, 0], .unit]⟩),
  ("distinct-recursion", ⟨0, [.product [1, 2], .sum [3, 1], .sum [3, 4], .unit, .u64]⟩),
  ("field-order", ⟨0, [.product [1, 2], .u64, .boolean]⟩),
  ("field-order-reversed", ⟨0, [.product [2, 1], .u64, .boolean]⟩),
  ("bounds", ⟨0, [.product [1, 2, 3, 4, 5, 6], .array 7 0, .array 7 1,
    .vector 7 0, .vector 7 1, .boundedBytes 0, .boundedBytes 1, .unit]⟩),
  ("empty-product", ⟨0, [.product []]⟩),
  ("empty-enumeration", ⟨0, [.enumeration []]⟩),
  ("zero-array-cycle", ⟨0, [.array 0 0]⟩),
  ("unproductive-array", ⟨0, [.array 0 1]⟩),
  ("unproductive-product", ⟨0, [.product [0]]⟩),
  ("unproductive-sum", ⟨0, [.sum [0]]⟩),
  ("empty-sum", ⟨0, [.sum []]⟩),
  ("empty-catalog", ⟨0, []⟩),
  ("invalid-root", ⟨1, [.unit]⟩),
  ("invalid-child", ⟨0, [.product [1]]⟩),
  ("invalid-unused-child", ⟨0, [.unit, .product [2]]⟩),
  ("unused-internal", ⟨0, [.unit, .internal (.capability 55)]⟩),
  ("unused-unproductive", ⟨0, [.unit, .sum [1]]⟩),
  ("internal-alternative", ⟨0, [.sum [1, 2], .unit, .internal (.capability 0)]⟩),
  ("unsorted-tags", ⟨0, [.enumeration [2, 1]]⟩),
  ("duplicate-tags", ⟨0, [.enumeration [1, 1]]⟩),
  ("width-sentinel", ⟨0, [.array 1 (wordLimit - 1), .u8]⟩),
  ("width-overflow", ⟨0, [.array 1 (wordLimit - 1), .u64]⟩),
  ("maximum-zero-width", ⟨0, [.array 1 (wordLimit - 1), .unit]⟩)]

private def emit (directory : System.FilePath) (mode name : String) (input : Bytes)
    (expected : Option Bytes) : IO Unit := do
  IO.FS.writeBinFile (directory / s!"{name}.input") ⟨input.toArray⟩
  if let some output := expected then
    IO.FS.writeBinFile (directory / s!"{name}.expected") ⟨output.toArray⟩
  IO.println s!"{mode}\t{name}\t{if expected.isSome then "ok" else "reject"}"

def main (args : List String) : IO UInt32 := do
  let [directory] := args | throw <| IO.userError "usage: schema_conformance.lean <output-directory>"
  let directory : System.FilePath := directory
  let shapeCases := shapes.map fun shape => (Codecs.schemaTagName (Codecs.schemaView .target shape).1, Descriptor.mk 0 [shape, .unit])
  for (name, _) in shapeCases do IO.println s!"tag\t{name}"
  for (name, candidate) in shapeCases ++ cases do
    let input := rawCodec.encode candidate
    if !rawCodec.valid candidate then throw <| IO.userError s!"schema.invalid_fixture: {name}"
    let expected := encode candidate
    emit directory "schema-normalize" s!"schema-normalize-{name}" input expected
    emit directory "schema" s!"schema-admit-{name}" input
      (if (decode input).isSome then some input else none)
    if let some canonical := expected then
      let some normalized := decode canonical | throw <| IO.userError s!"schema.canonical_rejected: {name}"
      if encode normalized != some canonical then throw <| IO.userError s!"schema.not_idempotent: {name}"
      emit directory "schema" s!"schema-canonical-{name}" canonical (some canonical)
  return 0
