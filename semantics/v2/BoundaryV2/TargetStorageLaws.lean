import BoundaryV2.TargetState

namespace BoundaryV2.Profile.Target.Machine

theorem load_blob_reads_checked_meaning (store : Store schemas) (schema : SchemaId .target)
    (reference : BlobId) (blob : StoredBlob schemas) (shape : Schema .target)
    (found : store.blobs[reference.value]? = some blob)
    (typed : schemas[schema.value]? = some shape) (nonScalar : scalarWidth shape = none)
    (sameSchema : blob.raw.schema = schema) :
    loadValue store ⟨schema, .blob reference⟩ = .ok blob.meaning := by
  simp [loadValue, expandValue, typed, found, fromOption, sameSchema, nonScalar,
    require, bind, Except.bind]
  rfl

/-- Interning compares complete schema/byte pairs. Equal raw pairs cannot
silently substitute a different logical value, including recursive schemas. -/
theorem interned_blob_has_same_meaning (schemas : List (Schema .target)) (blob : StoredBlob schemas)
    (value : SemanticValue) (valid : Profile.Value.externalValid schemas value = true)
    (same : blob.raw = ⟨value.schema, Profile.Value.encode schemas value⟩) : blob.meaning = value := by
  apply Profile.Value.checked_candidates_unique schemas blob.raw.schema blob.raw.bytes
    blob.meaning value blob.checked
  simp [Profile.Value.checkExternal, same, valid]

/-- All externally admitted aggregates, text and bytes survive the actual
store/load path. This covers both a new blob and reuse of an existing blob. -/
theorem external_blob_store_load (before after : Store schemas) (value : SemanticValue)
    (stored : Graph.Value) (shape : Schema .target)
    (typed : schemas[value.schema.value]? = some shape) (nonScalar : scalarWidth shape = none)
    (accepted : storeExternal before value = .ok (after, stored)) : loadValue after stored = .ok value := by
  have valid : Profile.Value.externalValid schemas value = true := by
    cases checked : Profile.Value.externalValid schemas value with
    | false => simp [storeExternal, checked] at accepted
    | true => rfl
  simp only [storeExternal, valid, dite_true, typed, fromOption, bind, Except.bind, nonScalar] at accepted
  split at accepted
  · rename_i index found
    cases accepted
    obtain ⟨bound, equal, _⟩ := List.findIdx?_eq_some_iff_getElem.mp found
    have same : before.blobs[index].raw = ⟨value.schema, Profile.Value.encode schemas value⟩ := by
      simpa using equal
    have located : before.blobs[index]? = some before.blobs[index] := List.getElem?_eq_getElem bound
    have meaning := interned_blob_has_same_meaning schemas before.blobs[index] value valid same
    rw [load_blob_reads_checked_meaning _ _ _ _ _ located typed nonScalar (congrArg Graph.Blob.schema same), meaning]
  · cases accepted
    let blob : StoredBlob schemas := ⟨⟨value.schema, Profile.Value.encode schemas value⟩,
      value, by simp [Profile.Value.checkExternal, valid]⟩
    exact load_blob_reads_checked_meaning _ _ _ blob _ (by simp [blob]) typed nonScalar rfl

private theorem scalar_value_of_width (schemas : List (Schema .target)) (value : SemanticValue)
    (shape : Schema .target) (width : Nat) (typed : schemas[value.schema.value]? = some shape)
    (scalar : scalarWidth shape = some width) (valid : Profile.Value.treeValid schemas value = true) :
    ∃ number, value = .scalar value.schema number := by
  cases value <;> try exact ⟨_, rfl⟩
  all_goals cases shape <;>
    simp_all [scalarWidth, Profile.Value.scalarWidth, Profile.Value.schema, Profile.Value.treeValid,
      Profile.Value.blobValid, Profile.Value.blobMaximum, Profile.Value.sequenceLengthValid]

private theorem padded_scalar_bytes (bytes : Bytes) (width : Nat)
    (size : bytes.length = width) (bounded : width ≤ 8) :
    ((bytes ++ List.replicate 8 0).take 8).take width = bytes ∧
      (((bytes ++ List.replicate 8 0).take 8).drop width).all (· == 0) = true := by
  have padding : (bytes ++ List.replicate 8 0).take 8 = bytes ++ List.replicate (8 - width) 0 := by
    rw [List.take_append, List.take_of_length_le (by omega), List.take_replicate, size,
      Nat.min_eq_left (by omega)]
  rw [padding, ← size]
  simp

theorem external_scalar_store_load (before after : Store schemas) (value : SemanticValue)
    (stored : Graph.Value) (shape : Schema .target) (width : Nat)
    (typed : schemas[value.schema.value]? = some shape) (scalar : scalarWidth shape = some width)
    (accepted : storeExternal before value = .ok (after, stored)) : loadValue after stored = .ok value := by
  have valid : Profile.Value.externalValid schemas value = true := by
    cases checked : Profile.Value.externalValid schemas value with
    | false => simp [storeExternal, checked] at accepted
    | true => rfl
  have tree := (Bool.and_eq_true_iff.mp valid).2
  obtain ⟨number, form⟩ := scalar_value_of_width schemas value shape width typed scalar tree
  have scalarValid : Profile.Value.scalarValid shape number = true := by
    rw [form] at tree
    simpa [Profile.Value.treeValid, typed] using tree
  have decoded := Profile.Value.scalar_complete schemas value.schema shape number [] typed scalarValid
  have encoded : Profile.Value.encode schemas (.scalar value.schema number) = Profile.Value.encode schemas value := by
    exact congrArg (Profile.Value.encode schemas) form.symm
  rw [encoded, List.append_nil] at decoded
  simp only [storeExternal, valid, dite_true, typed, fromOption, bind, Except.bind, scalar] at accepted
  have sizeChecked : (Profile.Value.encode schemas value).length = width ∧ width ≤ 8 := by
    by_cases size : ((Profile.Value.encode schemas value).length == width && decide (width ≤ 8)) = true
    · simpa using size
    · simp [require, size] at accepted
  simp only [require, show ((Profile.Value.encode schemas value).length == width && decide (width ≤ 8)) = true
    by simpa using sizeChecked, ite_true] at accepted
  split at accepted
  · cases accepted
    have padding := padded_scalar_bytes (Profile.Value.encode schemas value) width sizeChecked.1 sizeChecked.2
    simp only [loadValue, expandValue, typed, scalar, fromOption, bind, Except.bind, Vector.toList]
    rw [padding.1, padding.2, decoded]
    simp [require, Profile.Value.checkExternal, valid, ← form]
    rfl
  · cases accepted

theorem external_store_load (before after : Store schemas) (value : SemanticValue)
    (stored : Graph.Value) (accepted : storeExternal before value = .ok (after, stored)) :
    loadValue after stored = .ok value := by
  cases typed : schemas[value.schema.value]? with
  | none =>
    unfold storeExternal at accepted
    split at accepted <;> simp [typed, fromOption, bind, Except.bind] at accepted
  | some shape =>
    cases width : scalarWidth shape with
    | none => exact external_blob_store_load _ _ _ _ _ typed width accepted
    | some count => exact external_scalar_store_load _ _ _ _ _ _ typed width accepted

theorem every_external_value_can_be_stored (store : Store schemas) (value : SemanticValue)
    (valid : Profile.Value.externalValid schemas value = true) :
    ∃ after stored, storeExternal store value = .ok (after, stored) ∧ loadValue after stored = .ok value := by
  have tree := (Bool.and_eq_true_iff.mp valid).2
  have schemaPresent : ∃ shape, schemas[value.schema.value]? = some shape := by
    cases typed : schemas[value.schema.value]? with
    | some shape => exact ⟨shape, rfl⟩
    | none => cases value <;> simp [Profile.Value.treeValid, Profile.Value.schema] at tree typed <;> simp_all
  obtain ⟨shape, typed⟩ := schemaPresent
  have stored : ∃ after result, storeExternal store value = .ok (after, result) := by
    cases classified : scalarWidth shape with
    | none =>
      simp only [storeExternal, valid, dite_true, typed, fromOption, bind, Except.bind, classified]
      split <;> exact ⟨_, _, rfl⟩
    | some width =>
      obtain ⟨number, form⟩ := scalar_value_of_width schemas value shape width typed classified tree
      have size : (Profile.Value.encode schemas value).length = width := by
        rw [form]
        cases shape <;> simp only [scalarWidth, Profile.Value.scalarWidth] at classified <;>
          cases classified <;> simp [Profile.Value.encode, typed, Scalars.integerType, Wire.fixed_length] <;> rfl
      have bounded : width ≤ 8 := by
        cases shape <;> simp only [scalarWidth, Profile.Value.scalarWidth] at classified <;>
          cases classified <;> decide
      have padded : ((Profile.Value.encode schemas value ++ List.replicate 8 0).take 8).length = 8 := by
        simp [List.length_take, size]
      simp only [storeExternal, valid, dite_true, typed, fromOption, bind, Except.bind, classified,
        size, beq_self_eq_true, Bool.true_and, require,
        show decide (width ≤ 8) = true from decide_eq_true bounded, ite_true, padded, dite_true]
      exact ⟨_, _, rfl⟩
  obtain ⟨after, result, accepted⟩ := stored
  exact ⟨after, result, accepted, external_store_load _ _ _ _ accepted⟩

end BoundaryV2.Profile.Target.Machine
