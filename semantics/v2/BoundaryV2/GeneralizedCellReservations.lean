import BoundaryV2.GeneralizedCellLowering
import BoundaryV2.GeneralizedControlCreation

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body Before After : List (TypeOf signature) → TypeOf signature → Type}

mutual
  def Value.controlReferences : {type : TypeOf signature} → Value signature algebra Body type → List (Id .control)
    | _, .datum _ | _, .cell _ _ | _, .exit _ => []
    | _, .pair first second => first.controlReferences ++ second.controlReferences
    | _, .left value | _, .right value | _, .package _ _ value => value.controlReferences
    | _, .closure _ captured _ => captured.controlReferences
    | _, .continuation identity _ => [identity]

  def Environment.controlReferences : {types : List (TypeOf signature)} → Environment signature algebra Body types → List (Id .control)
    | _, .nil => []
    | _, .cons value rest => value.controlReferences ++ rest.controlReferences
end

mutual
  theorem Value.controlReferences_map (body : ∀ context type, Before context type → After context type)
      {type : TypeOf signature} (value : Value signature algebra Before type) :
      (value.map body).controlReferences = value.controlReferences := by
    cases value with
    | datum datum | cell identity region | exit information | continuation identity authority => rfl
    | pair first second => simp only [Value.map, Value.controlReferences,
        Value.controlReferences_map body first, Value.controlReferences_map body second]
    | left value | right value | package token owner value => exact Value.controlReferences_map body value
    | closure code captured authority => exact Environment.controlReferences_map body captured
  termination_by sizeOf value

  theorem Environment.controlReferences_map (body : ∀ context type, Before context type → After context type)
      {types : List (TypeOf signature)} (values : Environment signature algebra Before types) :
      (values.map body).controlReferences = values.controlReferences := by
    cases values with
    | nil => rfl
    | cons value rest => simp only [Environment.map, Environment.controlReferences,
        Value.controlReferences_map body value, Environment.controlReferences_map body rest]
  termination_by sizeOf values
end

/-- Cell payloads remain physical holders after their evaluating fields move
away. Their grants, aliases, and stored continuation references reserve names
for subsequent control creation, including references in dormant captures. -/
def Cells.reservations (cells : Cells signature algebra Body) : UseScope.ReservedNames :=
  ⟨cells.flatMap (fun cell => cell.value.controlReferences), UseScope.custodyNames cells.fields⟩

theorem Cells.reservations_mapBodies (body : ∀ context type, Before context type → After context type)
    (cells : Cells signature algebra Before) : (cells.mapBodies body).reservations = cells.reservations := by
  unfold reservations
  rw [mapBodies_fields]
  have controls : (cells.mapBodies body).flatMap (fun cell => cell.value.controlReferences) =
      cells.flatMap (fun cell => cell.value.controlReferences) := by
    induction cells with
    | nil => rfl
    | cons first rest induction =>
      simp only [Cells.mapBodies, List.map_cons, List.flatMap_cons, Cell.map, Value.controlReferences_map]
      exact congrArg (first.value.controlReferences ++ ·) induction
  rw [controls]

theorem Cells.owning_tokens_reserved (cells : Cells signature algebra Body)
    (member : token ∈ UseScope.tokens cells.fields) : token ∈ cells.reservations.custody :=
  UseScope.tokens_are_supported _ _ member

theorem fresh_control_grant_avoids_cells (owner : Owner) (store : UseScope.ControlStore Future)
    (cells : Cells signature algebra Body) :
    (UseScope.freshControlView owner store cells.reservations).authority ∉ UseScope.tokens cells.fields := by
  intro member
  exact UseScope.reserved_grant_is_fresh owner store cells.reservations
    (List.mem_append_left _ (cells.owning_tokens_reserved member))

end BoundaryV2.Generalized
