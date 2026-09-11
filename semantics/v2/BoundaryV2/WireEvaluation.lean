import BoundaryV2.ProtocolCodec

namespace BoundaryV2.Profile.Wire.Codec

theorem sizedBytes_encode (lengthCodec : Codec Nat) (bytes : Bytes) :
    (sizedBytes lengthCodec).encode bytes = lengthCodec.encode bytes.length ++ bytes := by
  simp [sizedBytes, iso, dependent, fixedBytes, Vector.toList]

theorem sizedBytes_valid (lengthCodec : Codec Nat) (bytes : Bytes) :
    (sizedBytes lengthCodec).valid bytes = lengthCodec.valid bytes.length := by
  simp [sizedBytes, iso, dependent, fixedBytes]

end BoundaryV2.Profile.Wire.Codec

namespace BoundaryV2.Profile.Images

theorem frameBytes_encode (family : Family) (bytes : Bytes) :
    (frameBytes family).encode bytes = family.magic.toList ++ Wire.fixed 2 2 ++ Wire.fixed 2 0 ++
      Wire.fixed 8 bytes.length ++ bytes := by
  simp [frameBytes, Wire.Codec.iso, Wire.Codec.pair, Wire.Codec.constant,
    Wire.Codec.sizedBytes_encode, Wire.Codec.unsignedFixed, Wire.Codec.fixedBytes,
    List.append_assoc]

end BoundaryV2.Profile.Images

namespace BoundaryV2.Profile.Codecs

theorem run_encode : invocationMode.encode .run = [1] := by decide +kernel

theorem continueNone_encode : externalControl.encode (.continueValue none) = [0, 0] := by decide +kernel

theorem rawInput_encode (input : Protocol.Input) :
    rawInput.encode input = invocationMode.encode input.mode ++ Wire.Codec.blob.encode input.image ++
      instanceData.encode input.instanceData ++ externalControl.encode input.control := by
  simp [rawInput, Wire.NonemptyCodec.iso, Wire.NonemptyCodec.pair,
    Wire.Codec.iso, Wire.Codec.pair, Wire.NonemptyCodec.blob, List.append_assoc]

theorem initialArgs_encode (bytes : Bytes) :
    instanceData.encode (.initialArgs bytes) = [0] ++ Wire.Codec.blob.encode bytes := by
  change instanceDataTag.encode .initialArgs ++ Wire.Codec.blob.encode bytes = _
  exact congrArg (· ++ Wire.Codec.blob.encode bytes) (by decide +kernel)

theorem state_encode (bytes : Bytes) :
    instanceData.encode (.state bytes) = [1] ++ Wire.Codec.blob.encode bytes := by
  change instanceDataTag.encode .state ++ Wire.Codec.blob.encode bytes = _
  exact congrArg (· ++ Wire.Codec.blob.encode bytes) (by decide +kernel)

end BoundaryV2.Profile.Codecs

namespace BoundaryV2.Profile.Codecs

theorem graphBlob_encode (blob : Graph.Blob) :
    graphBlob.encode blob = (Wire.Codec.reference .target .schema).encode blob.schema ++
      Wire.Codec.blob.encode blob.bytes := by
  simp [graphBlob, Wire.NonemptyCodec.iso, Wire.NonemptyCodec.pair,
    Wire.NonemptyCodec.reference, Wire.NonemptyCodec.blob, Wire.Codec.iso, Wire.Codec.pair]

theorem rawState_encode (state : Graph.State) :
    rawState.encode state = (Wire.Codec.fixedBytes 32).encode state.programIdentity ++
      graphStatus.encode state.status ++ graphRoots.encode state.roots ++
      node.list.encode state.nodes ++ graphBlob.list.encode state.blobs := by
  simp [rawState, Wire.NonemptyCodec.iso, Wire.NonemptyCodec.pair,
    Wire.NonemptyCodec.fixedBytes, Wire.Codec.iso, Wire.Codec.pair, List.append_assoc]

end BoundaryV2.Profile.Codecs

namespace BoundaryV2.Profile.Codecs

theorem continueSome_encode (bytes : Bytes) :
    externalControl.encode (.continueValue (some bytes)) = [0, 1] ++ Wire.Codec.blob.encode bytes := by
  change externalControlTag.encode .continueValue ++ (Wire.Codec.boolean.encode true ++ Wire.Codec.blob.encode bytes) = _
  have tag : externalControlTag.encode .continueValue = [0] := by decide +kernel
  have present : Wire.Codec.boolean.encode true = [1] := by decide +kernel
  rw [tag, present]
  rfl

theorem requested_encode (snapshot request : Bytes) :
    rawOutcome.encode (.requested snapshot request) = [1] ++ Wire.Codec.blob.encode snapshot ++ Wire.Codec.blob.encode request := by
  change rawOutcomeTag.encode .requested ++ (Wire.Codec.blob.encode snapshot ++ Wire.Codec.blob.encode request) = _
  have tag : rawOutcomeTag.encode .requested = [1] := by decide +kernel
  rw [tag, List.append_assoc]

theorem completed_encode (bytes : Bytes) :
    rawOutcome.encode (.completed bytes) = [3] ++ Wire.Codec.blob.encode bytes := by
  change rawOutcomeTag.encode .completed ++ Wire.Codec.blob.encode bytes = _
  have tag : rawOutcomeTag.encode .completed = [3] := by decide +kernel
  rw [tag]

end BoundaryV2.Profile.Codecs

/- Equivalent forms for proof evaluation of complete byte strings. In particular,
length-delimited encoding retains the byte list directly instead of constructing
and projecting a vector. Each replacement is an ordinary equality theorem;
certificate tooling selects which equations to use. -/

namespace BoundaryV2.Profile.Wire.Codec

private def byteVectorCodec (lengthCodec : Codec Nat) : Codec Bytes :=
  (dependent lengthCodec fixedBytes).iso
    (fun value => value.2.toList)
    (fun bytes => ⟨bytes.length, ⟨bytes.toArray, by simp⟩⟩)
    (by intro bytes; simp [Vector.toList])
    (by intro value; rcases value with ⟨size, ⟨bytes, sizeProof⟩⟩; cases sizeProof; simp [Vector.toList])

def sizedBytesDirect (lengthCodec : Codec Nat) : Codec Bytes where
  valid bytes := lengthCodec.valid bytes.length
  encode bytes := lengthCodec.encode bytes.length ++ bytes
  read := (byteVectorCodec lengthCodec).read
  readExact input value rest accepted := by
    have accepted : (sizedBytes lengthCodec).read input = some (value, rest) := accepted
    simpa only [sizedBytes_encode] using (sizedBytes lengthCodec).readExact input value rest accepted
  readValid input value rest accepted := by
    have accepted : (sizedBytes lengthCodec).read input = some (value, rest) := accepted
    simpa only [sizedBytes_valid] using (sizedBytes lengthCodec).readValid input value rest accepted
  readComplete value rest valid := by
    have valid : (sizedBytes lengthCodec).valid value = true := by simpa only [sizedBytes_valid] using valid
    have complete := (sizedBytes lengthCodec).readComplete value rest valid
    change (sizedBytes lengthCodec).read ((lengthCodec.encode value.length ++ value) ++ rest) = some (value, rest)
    simpa only [sizedBytes_encode] using complete

private theorem ext_fields {α : Type} (first second : Codec α)
    (valid : first.valid = second.valid) (encode : first.encode = second.encode)
    (read : first.read = second.read) : first = second := by
  cases first
  cases second
  cases valid
  cases encode
  cases read
  rfl

theorem sizedBytes_direct (lengthCodec : Codec Nat) :
    sizedBytes lengthCodec = sizedBytesDirect lengthCodec := by
  apply ext_fields
  · funext bytes; exact sizedBytes_valid lengthCodec bytes
  · funext bytes; exact sizedBytes_encode lengthCodec bytes
  · rfl

end BoundaryV2.Profile.Wire.Codec

namespace BoundaryV2.Profile.Wire.Evaluation

/-- Constructor-headed list laws preserve shared byte terms during proof evaluation. -/
theorem bytes_beq_self (bytes : Bytes) : List.beq bytes bytes = true := by change (bytes == bytes) = true; simp
theorem append_nil_eval {α : Type} (xs : List α) : List.append xs [] = xs := List.append_nil _
theorem append_nil_left_eval {α : Type} (xs : List α) : List.append [] xs = xs := rfl
theorem append_cons_eval {α : Type} (x : α) (xs ys : List α) : List.append (x :: xs) ys = x :: List.append xs ys := rfl
theorem length_append_eval {α : Type} (xs ys : List α) : List.length (List.append xs ys) = xs.length + ys.length := List.length_append
theorem map_nil_eval {α β : Type} (f : α → β) : List.map f [] = [] := rfl
theorem map_cons_eval {α β : Type} (f : α → β) (x : α) (xs : List α) : List.map f (x :: xs) = f x :: List.map f xs := rfl
theorem map_append_eval {α β : Type} (f : α → β) (xs ys : List α) : List.map f (List.append xs ys) = List.append (List.map f xs) (List.map f ys) := List.map_append
theorem append_assoc_eval {α : Type} (xs ys zs : List α) :
    List.append (List.append xs ys) zs = List.append xs (List.append ys zs) := List.append_assoc _ _ _
theorem bytes_beq_prefix (common left right : Bytes) :
    List.beq (List.append common left) (List.append common right) = List.beq left right := by
  induction common with
  | nil => rfl
  | cons head tail ih =>
    change ((head == head) && List.beq (List.append tail left) (List.append tail right)) = List.beq left right
    rw [beq_self_eq_true, Bool.true_and, ih]

end BoundaryV2.Profile.Wire.Evaluation
