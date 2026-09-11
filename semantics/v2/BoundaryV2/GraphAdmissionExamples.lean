import BoundaryV2.GraphRecordTypes
import BoundaryV2.ProgramExamples
import BoundaryV2.TargetImage

namespace BoundaryV2.Profile.Graph.Admission.Examples

set_option maxRecDepth 4096

open Target.Canonical.Examples (unitProgram unitWitness)

private theorem reference_literal (n : Nat) : (OfNat.ofNat n : Ref space domain) = ⟨n⟩ := rfl

def unitValue : Value := ⟨0, .scalar (Vector.replicate 8 0)⟩
def unitState : State := {
  programIdentity := Protocol.programIdentity unitProgram
  status := .active
  roots := { current := some 0 }
  nodes := [.control ⟨0, [unitValue], none, none, none⟩] }

theorem unit_value_admitted : valueValid unitProgram unitState unitValue 0 = true := by
  simp [valueValid, scalarValue, unitProgram, unitValue, Profile.Value.scalarWidth,
    Profile.Value.readScalar, Profile.Value.checkExternal, Profile.Value.externalValid,
    Profile.Value.treeValid, Profile.Value.encode, Profile.Value.scalarValid]
  decide +kernel
theorem unit_records_admitted : recordsValid unitProgram unitState = true := by
  simp [recordsValid, recordValid, block, unitProgram, unitState, valuesValid,
    parentType, scopeValid, evidenceValid, regionValid, regionContextValid,
    valueScopeValid, valueRegionValid, unitValue, valueValid, scalarValue,
    Profile.Value.scalarWidth, Profile.Value.readScalar, Profile.Value.checkExternal,
    Profile.Value.externalValid, Profile.Value.treeValid, Profile.Value.encode,
    Profile.Value.scalarValid, reference_literal]
  decide +kernel
theorem unit_roots_admitted : rootsValid unitState = true := by decide +kernel
theorem unit_custody_admitted : custody unitProgram unitState = true := by decide +kernel

theorem high_scalar_padding_rejected :
    valueValid unitProgram unitState ⟨0, .scalar ⟨#[0, 0, 0, 0, 0, 0, 0, 1], rfl⟩⟩ 0 = false := by decide +kernel

theorem root_status_requires_pending_record : rootsValid { unitState with status := .parked } = false := by decide +kernel

def cyclicState : State := { unitState with nodes := [.control ⟨0, [unitValue], some 0, none, none⟩] }

theorem concrete_parent_cycle_rejected : ancestry cyclicState (some 0) = none :=
  direct_parent_cycle_rejected cyclicState 0 (.control ⟨0, [unitValue], some 0, none, none⟩) rfl rfl

def duplicateCapture : State := { unitState with nodes := [
  .oneShot ⟨0, none, 2, none, []⟩,
  .multiTemplate ⟨0, none, 2, none, []⟩,
  .attachment 3 none none .suspended none,
  .handler 0 [] none none] }

theorem two_capturers_of_one_delimiter_rejected : capturesUnique duplicateCapture = false := by decide +kernel
theorem uncaptured_suspended_delimiter_rejected :
    capturesUnique { duplicateCapture with nodes := [.attachment 1 none none .suspended none, .handler 0 [] none none] } = false := by
  decide +kernel

def nominalProgram : Target.Program := { unitProgram with
  schemas := [.unit, .internal (.capability 0), .internal (.capability 1)]
  effects := [⟨[120], 0, 0, [], [], .linear, true⟩, ⟨[120], 0, 0, [], [], .linear, true⟩]
  handlers := [⟨.deep, 0, 0, 0, [⟨0, 0, 0, false⟩], none, [], []⟩] }
def nominalState : State := { unitState with nodes := [
  .attachment 1 none none .active none, .handler 0 [] none none] }

theorem matching_nominal_effect_admitted : valueValid nominalProgram nominalState ⟨1, .reference 0⟩ 1 = true := by decide +kernel
theorem same_text_different_effect_rejected : valueValid nominalProgram nominalState ⟨2, .reference 0⟩ 2 = false := by decide +kernel
theorem cell_record_is_not_a_capability :
    valueValid nominalProgram { nominalState with nodes := [.cell 1 0 none] } ⟨1, .reference 0⟩ 1 = false := by decide +kernel

/-- A nested monadic branch must return its local test result, then check the
rest of the record. These regressions distinguish an accidental early return. -/
theorem cancellation_still_checks_text_encoding :
    recordValid unitProgram unitState 0
      (.exit ⟨.cancellation, [], some (.text [255]), none, none, []⟩) = false := by decide +kernel

theorem failure_still_checks_cleanup_failure_types :
    recordValid unitProgram unitState 0
      (.exit ⟨.failure unitValue, [⟨1, .scalar (Vector.replicate 8 0)⟩], none, none, none, []⟩) = false := by
  simp [recordValid, valueValid, unitProgram, reference_literal]

def protectionProgram : Target.Program := { unitProgram with blocks := [
  ⟨0, [0, 0], [], .protect 0 0 [] (some 1) (some 0) ⟨0, []⟩⟩] }
def protectionState : State := { unitState with nodes := [
  .obligation 1 (some unitValue) (some unitValue) .pending,
  .continuation ⟨0, [], none, none, none⟩,
  .region 0 none []] }

theorem loan_match_still_checks_obligation_source :
    recordValid protectionProgram protectionState 3
      (.protection 0 ⟨0⟩ (some 1) none none (some 2)) = false := by decide +kernel

theorem resource_match_still_checks_cleanup_value :
    recordValid protectionProgram unitState 0
      (.obligation 0 (some ⟨1, .scalar (Vector.replicate 8 0)⟩) (some unitValue) .pending) = false := by decide +kernel

end BoundaryV2.Profile.Graph.Admission.Examples
