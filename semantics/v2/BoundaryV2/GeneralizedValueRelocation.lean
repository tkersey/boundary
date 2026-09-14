import BoundaryV2.GeneralizedCodeRelocation
import BoundaryV2.GeneralizedFields

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Before After : List (TypeOf signature) → TypeOf signature → Type}

def relocateAuthority (relocation : UseScope.Relocation) (authority : Option (Id .custody × Owner)) :
    Option (Id .custody × Owner) := authority.map fun (token, owner) => (relocation.name .custody token, relocation.owner owner)

mutual
  def Value.relocate (relocation : UseScope.Relocation)
      (body : ∀ context type, Before context type → After context type) :
      {type : TypeOf signature} → Value signature algebra Before type → Value signature algebra After type
    | _, .datum datum => .datum (datum.relocate relocation)
    | _, .pair first second => .pair (first.relocate relocation body) (second.relocate relocation body)
    | _, .left value => .left (value.relocate relocation body)
    | _, .right value => .right (value.relocate relocation body)
    | _, .closure code captured authority =>
      .closure (body _ _ code) (captured.relocate relocation body) (relocateAuthority relocation authority)
    | _, .continuation identity authority => .continuation (relocation.name .control identity) (relocateAuthority relocation authority)
    | _, .package token owner value =>
      .package (relocation.name .custody token) (relocation.owner owner) (value.relocate relocation body)
    | _, .cell identity region => .cell (relocation.name .cell identity) (relocation.name .region region)
    | _, .exit information => .exit information

  def Environment.relocate (relocation : UseScope.Relocation)
      (body : ∀ context type, Before context type → After context type) :
      {types : List (TypeOf signature)} → Environment signature algebra Before types → Environment signature algebra After types
    | _, .nil => .nil
    | _, .cons value rest => .cons (value.relocate relocation body) (rest.relocate relocation body)
end

theorem Environment.relocate_append (relocation : UseScope.Relocation)
    (body : ∀ context type, Before context type → After context type)
    (first : Environment signature algebra Before left) (second : Environment signature algebra Before right) :
    (first.append second).relocate relocation body = (first.relocate relocation body).append (second.relocate relocation body) := by
  induction left with
  | nil => cases first; rfl
  | cons type rest induction => cases first with
    | cons value tail => simp only [Environment.append, Environment.relocate, induction tail]

theorem Environment.relocate_lookup (relocation : UseScope.Relocation)
    (body : ∀ context type, Before context type → After context type)
    (reference : Variable types type) (values : Environment signature algebra Before types) :
    (values.relocate relocation body).lookup reference = (values.lookup reference).relocate relocation body := by
  induction reference with
  | here => cases values; rfl
  | there reference induction => cases values; exact induction _

theorem Environment.relocate_selection (relocation : UseScope.Relocation)
    (body : ∀ context type, Before context type → After context type)
    (selection : Selection context captured) (values : Environment signature algebra Before context) :
    (values.select selection).relocate relocation body = (values.relocate relocation body).select selection := by
  induction selection with
  | nil => rfl
  | cons reference rest induction =>
    simp only [Environment.select, Environment.relocate, Environment.relocate_lookup, induction]

theorem Datum.relocate_owning_field (relocation : UseScope.Relocation)
    (datum : Datum (Effect := signature.Effect) algebra type) :
    (datum.relocate relocation).owningField = datum.owningField.relocate relocation := by
  induction datum <;> simp_all only [Datum.relocate, Datum.owningField,
    UseScope.Field.relocate, UseScope.relocateFields]

theorem relocate_authority_fields (relocation : UseScope.Relocation) (authority : Option (Id .custody × Owner)) :
    authorityFields (relocateAuthority relocation authority) = UseScope.relocateFields relocation (authorityFields authority) := by
  cases authority with
  | none => rfl
  | some pair => cases pair; rfl

mutual
  theorem Value.relocate_owning_field (relocation : UseScope.Relocation)
      (body : ∀ context type, Before context type → After context type)
      {type : TypeOf signature} (value : Value signature algebra Before type) :
      (value.relocate relocation body).owningField = value.owningField.relocate relocation := by
    cases value with
    | datum datum => exact datum.relocate_owning_field relocation
    | pair first second => simp only [Value.relocate, Value.owningField, UseScope.Field.relocate, UseScope.relocateFields,
        Value.relocate_owning_field relocation body first, Value.relocate_owning_field relocation body second]
    | left value | right value => exact Value.relocate_owning_field relocation body value
    | closure code captured authority => simp only [Value.relocate, Value.owningField, UseScope.Field.relocate,
        UseScope.relocate_fields_append, UseScope.relocateFields, relocate_authority_fields,
        Environment.relocate_owning_fields relocation body captured]
    | continuation identity authority => simp only [Value.relocate, Value.owningField, UseScope.Field.relocate, relocate_authority_fields]
    | package token owner value => simp only [Value.relocate, Value.owningField, UseScope.Field.relocate, UseScope.relocateFields,
        Value.relocate_owning_field relocation body value]
    | cell identity region | exit information => rfl
  termination_by sizeOf value

  theorem Environment.relocate_owning_fields (relocation : UseScope.Relocation)
      (body : ∀ context type, Before context type → After context type)
      {types : List (TypeOf signature)} (values : Environment signature algebra Before types) :
      (values.relocate relocation body).owningFields = UseScope.relocateFields relocation values.owningFields := by
    cases values with
    | nil => rfl
    | cons value rest => simp only [Environment.relocate, Environment.owningFields, UseScope.relocateFields,
        Value.relocate_owning_field relocation body value, Environment.relocate_owning_fields relocation body rest]
  termination_by sizeOf values
end

end BoundaryV2.Generalized
