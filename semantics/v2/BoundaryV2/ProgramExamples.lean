import BoundaryV2.ProgramAdmission
import BoundaryV2.ProgramInterning

namespace BoundaryV2.Profile.Target.Canonical.Examples

set_option maxRecDepth 4096

def unitProgram : Program := {
  roots := ⟨1, 0, 0, 0⟩
  schemas := [.unit]
  constants := []
  effects := []
  functions := [⟨0, [0], 0, [], []⟩]
  blocks := [⟨0, [0], [], .returnValue 0⟩] }

def unitWitness : Admission.Witness := ⟨[], ⟨[], [⟨0, []⟩]⟩⟩

private def effect (identity : Bytes) : Effect .target := { identity := identity, payload := 0, result := 0 }

private theorem reference_literal (n : Nat) : (OfNat.ofNat n : Ref space domain) = ⟨n⟩ := rfl

theorem unit_discovery : discover unitProgram = some [⟨.function, 0⟩, ⟨.block, 0⟩, ⟨.schema, 0⟩] := by
  simp [discover, catalogReferences, kinds, count, rootReferences, unitProgram, walk, nodeReferences,
    functionReferences, blockReferences, schemaReferences, references, effectRow, terminatorReferences,
    interned, orderOf, reference_literal]

theorem unit_canonical : check unitProgram = true := by
  rw [check, unit_discovery]
  decide +kernel

theorem unit_schemas_admitted : SchemaAdmission.valid unitProgram.schemas = true := by
  have first : SchemaAdmission.widthRound unitProgram.schemas [SchemaAdmission.infinity] = [0] := by decide +kernel
  have fixed : SchemaAdmission.widthRound unitProgram.schemas [0] = [0] := by decide +kernel
  have widths : SchemaAdmission.widths unitProgram.schemas = [0] := by
    change SchemaAdmission.widthLoop _ [SchemaAdmission.infinity] = [0]
    rw [← SchemaAdmission.widthLoop_round, first]
    exact SchemaAdmission.widthLoop_of_fixed _ _ fixed
  rw [SchemaAdmission.valid, widths]
  decide +kernel

theorem unit_admitted : Admission.check unitProgram unitWitness = true := by
  unfold Admission.check Admission.declarationsValid
  rw [unit_schemas_admitted]
  decide +kernel

theorem unit_image_exact_round_trip :
    CertifiedImage.decode (Images.encodeImage unitProgram) unitWitness = some unitProgram := by
  apply CertifiedImage.canonical_encode_decode
  exact ⟨by unfold Images.WireAdmitted; decide +kernel, by decide +kernel,
    (Admission.check_exact _ _).mp unit_admitted, (check_exact _).mp unit_canonical⟩

theorem unused_schema_rejects_numbering : check { unitProgram with schemas := [.unit, .unit] } = false := by
  have discovery : discover { unitProgram with schemas := [.unit, .unit] } =
      some [⟨.function, 0⟩, ⟨.block, 0⟩, ⟨.schema, 0⟩] := by
    change walk _ [⟨.schema, 0⟩, ⟨.schema, 1⟩, ⟨.function, 0⟩, ⟨.block, 0⟩]
      [⟨.function, 0⟩, ⟨.schema, 0⟩, ⟨.schema, 0⟩] [] = _
    simp [walk, unitProgram, nodeReferences, functionReferences, blockReferences, schemaReferences,
      references, effectRow, terminatorReferences, interned, orderOf, reference_literal]
  rw [check, discovery]
  decide +kernel

theorem unused_region_bound_rejects_without_enumeration :
    completeOrder { unitProgram with scopes := { regionCount := wordLimit - 1 } }
      [⟨.function, 0⟩, ⟨.block, 0⟩, ⟨.schema, 0⟩] = false := by decide +kernel

theorem identical_bytes_different_schema_not_interned :
    interned { unitProgram with constants := [⟨0, []⟩, ⟨1, []⟩] } [⟨.constant, 0⟩] ⟨.constant, 1⟩ = false := by
  decide +kernel

theorem differing_last_byte_not_interned :
    interned { unitProgram with constants := [⟨0, [1, 2, 3, 4]⟩, ⟨0, [1, 2, 3, 5]⟩] }
      [⟨.constant, 0⟩] ⟨.constant, 1⟩ = false := by decide +kernel

theorem same_schema_and_full_bytes_interned :
    interned { unitProgram with constants := [⟨0, [1, 2, 3, 4]⟩, ⟨0, [1, 2, 3, 4]⟩] }
      [⟨.constant, 0⟩] ⟨.constant, 1⟩ = true := by decide +kernel

theorem equal_text_effect_row_stable :
    effectRow { unitProgram with effects := [effect [120], effect [120]] } [1, 0] =
      [⟨.effect, 1⟩, ⟨.effect, 0⟩] := by
  simp [effectRow, List.mergeSort, bytesLE, effect, references, reference_literal]

theorem distinct_effect_row_lexicographic :
    effectRow { unitProgram with effects := [effect [120, 0], effect [120]] } [0, 1] =
      [⟨.effect, 1⟩, ⟨.effect, 0⟩] := by
  simp [effectRow, List.mergeSort, bytesLE, effect, references, reference_literal]

theorem equal_text_effects_retain_distinct_ids :
    catalogMap { unitProgram with effects := [effect [120], effect [120]] }
      [⟨.effect, 1⟩, ⟨.effect, 0⟩] .effect 0 ≠
    catalogMap { unitProgram with effects := [effect [120], effect [120]] }
      [⟨.effect, 1⟩, ⟨.effect, 0⟩] .effect 1 := by decide +kernel

end BoundaryV2.Profile.Target.Canonical.Examples
