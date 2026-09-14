import BoundaryV2.GeneralizedValues
import BoundaryV2.GeneralizedOwnership

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body Before After : List (TypeOf signature) → TypeOf signature → Type}

/-- Project physical fields, including those stored inside a closure or package.
Unlike `roots`, this traverses inline owning containers. References to separately
stored continuations contribute their grant only; the saved control record is
enumerated at its own physical storage position. -/
def Datum.owningField : {type : TypeOf signature} → Datum (Effect := signature.Effect) algebra type → UseScope.Field
  | _, .leaf _ | _, .unit | _, .capability _ | _, .region _ => .group []
  | _, .pair first second => .group [first.owningField, second.owningField]
  | _, .left value | _, .right value => value.owningField
  | _, .resource _ token owner => .owned token owner
  | _, .borrowed _ scope => .borrowed scope

def authorityFields (authority : Option (Id .custody × Owner)) : List UseScope.Field :=
  authority.toList.map fun (token, owner) => .owned token owner

mutual
  def Value.owningField : {type : TypeOf signature} → Value signature algebra Body type → UseScope.Field
    | _, .datum datum => datum.owningField
    | _, .pair left right => .group [left.owningField, right.owningField]
    | _, .left value | _, .right value => value.owningField
    | _, .closure _ captured authority => .group (authorityFields authority ++ [.closure captured.owningFields])
    | _, .continuation _ authority => .group (authorityFields authority)
    | _, .package token owner value => .group [.owned token owner, .package [value.owningField]]
    | _, .cell _ _ | _, .exit _ => .group []

  def Environment.owningFields : {types : List (TypeOf signature)} → Environment signature algebra Body types → List UseScope.Field
    | _, .nil => []
    | _, .cons value rest => value.owningField :: rest.owningFields
end

mutual
  theorem Value.map_preserves_owning_fields (transform : ∀ context type, Before context type → After context type)
      {type : TypeOf signature} (value : Value signature algebra Before type) :
      (value.map transform).owningField = value.owningField := by
    cases value with
    | datum datum => rfl
    | pair left right => simp only [Value.map, Value.owningField,
        Value.map_preserves_owning_fields transform left, Value.map_preserves_owning_fields transform right]
    | left value | right value => exact Value.map_preserves_owning_fields transform value
    | closure body captured authority => simp only [Value.map, Value.owningField,
        Environment.map_preserves_owning_fields transform captured]
    | continuation reference authority => rfl
    | package token owner value => simp only [Value.map, Value.owningField, Value.map_preserves_owning_fields transform value]
    | cell reference region => rfl
    | exit information => rfl
  termination_by sizeOf value

  theorem Environment.map_preserves_owning_fields (transform : ∀ context type, Before context type → After context type)
      {types : List (TypeOf signature)} (values : Environment signature algebra Before types) :
      (values.map transform).owningFields = values.owningFields := by
    cases values with
    | nil => rfl
    | cons value rest => simp only [Environment.map, Environment.owningFields,
        Value.map_preserves_owning_fields transform value, Environment.map_preserves_owning_fields transform rest]
  termination_by sizeOf values
end

theorem Environment.append_owning_fields
    (first : Environment signature algebra Body left) (second : Environment signature algebra Body right) :
    (first.append second).owningFields = first.owningFields ++ second.owningFields := by
  induction left with
  | nil => cases first; rfl
  | cons type types induction =>
    cases first with
    | cons value rest => simp only [Environment.append, Environment.owningFields, List.cons_append, induction rest]

namespace UseScope

/-- Active and retained environments are two physical holders. Every inline
field is enumerated once at its storage position, without deduplication. -/
def ofEnvironments (active : Environment signature algebra Body activeTypes)
    (retained : Environment signature algebra Body retainedTypes) (spent : List (Id .custody)) : State :=
  ⟨active.owningFields, retained.owningFields, spent⟩

theorem map_preserves_physical_state (transform : ∀ context type, Before context type → After context type)
    (active : Environment signature algebra Before activeTypes) (retained : Environment signature algebra Before retainedTypes)
    (spent : List (Id .custody)) :
    ofEnvironments (active.map transform) (retained.map transform) spent = ofEnvironments active retained spent := by
  simp only [ofEnvironments, Environment.map_preserves_owning_fields]

theorem capture_environment_preserves_ownership
    (before : Environment signature algebra Body beforeTypes) (selected : Environment signature algebra Body selectedTypes)
    (after : Environment signature algebra Body afterTypes) (retained : List Field) (spent : List (Id .custody))
    (controlId : Id .control)
    (valid : Valid ⟨((before.append selected).append after).owningFields, retained, spent⟩) :
    Valid (capture before.owningFields selected.owningFields after.owningFields retained spent controlId) := by
  apply capture_preserves_ownership
  simpa only [Environment.append_owning_fields] using valid

theorem package_environment_preserves_ownership
    (before : Environment signature algebra Body beforeTypes) (selected : Environment signature algebra Body selectedTypes)
    (after : Environment signature algebra Body afterTypes) (retained : List Field) (spent : List (Id .custody))
    (valid : Valid ⟨((before.append selected).append after).owningFields, retained, spent⟩) :
    Valid (package before.owningFields selected.owningFields after.owningFields retained spent) := by
  apply package_preserves_ownership
  simpa only [Environment.append_owning_fields] using valid

theorem pair_preserves_duplicate_occurrences (resource : Id .resource) (token : Id .custody) (owner : Owner)
    (name : ResourceName) :
    (Value.owningField (Body := Body) (signature := signature) (algebra := algebra)
      (Value.pair (.datum (Datum.resource (name := name) resource token owner))
        (.datum (Datum.resource (name := name) resource token owner)))).tokens = [token, token] := rfl

end UseScope
end BoundaryV2.Generalized
