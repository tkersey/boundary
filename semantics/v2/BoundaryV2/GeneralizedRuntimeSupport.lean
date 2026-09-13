import BoundaryV2.GeneralizedSupport
import BoundaryV2.GeneralizedFutureRelocation
import BoundaryV2.GeneralizedCells

namespace BoundaryV2.Generalized.Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

def authorityReferences (authority : Option (Id .custody × Owner)) : List Reference :=
  authority.toList.flatMap fun (token, owner) => [.name .custody token, .owner owner]

mutual
  def valueReferences : {type : TypeOf signature} → RuntimeValue signature algebra program type → List Reference
    | _, .datum datum => datum.references
    | _, .pair first second => valueReferences first ++ valueReferences second
    | _, .left value | _, .right value => valueReferences value
    | _, .closure body captured authority => body.references ++ environmentReferences captured ++ authorityReferences authority
    | _, .continuation identity authority => .name .control identity :: authorityReferences authority
    | _, .package token owner value => .name .custody token :: .owner owner :: valueReferences value
    | _, .cell identity region => [.name .cell identity, .name .region region]
    | _, .exit _ => []

  def environmentReferences : {types : List (TypeOf signature)} → RuntimeEnvironment signature algebra program types → List Reference
    | _, .nil => []
    | _, .cons value rest => valueReferences value ++ environmentReferences rest
end

theorem authority_references_relocate (relocation : UseScope.Relocation) (authority : Option (Id .custody × Owner)) :
    authorityReferences (relocateAuthority relocation authority) = (authorityReferences authority).map (Reference.relocate relocation) := by
  cases authority with
  | none => rfl
  | some pair => cases pair; rfl

mutual
  theorem value_references_relocate (relocation : UseScope.Relocation)
      {type : TypeOf signature} (value : RuntimeValue signature algebra program type) :
      valueReferences (relocateValue relocation value) = (valueReferences value).map (Reference.relocate relocation) := by
    cases value with
    | datum datum => exact datum.references_relocate relocation
    | pair first second => simp only [relocateValue, Value.relocate, valueReferences, List.map_append,
        ← value_references_relocate relocation first, ← value_references_relocate relocation second]
    | left value | right value => exact value_references_relocate relocation value
    | closure body captured authority =>
      simp only [relocateValue, Value.relocate, valueReferences, List.map_append, Code.references_relocate,
        authority_references_relocate, ← environment_references_relocate relocation captured]
      rfl
    | continuation identity authority => simp only [relocateValue, Value.relocate, valueReferences,
        List.map_cons, Reference.relocate, authority_references_relocate]
    | package token owner value => simp only [relocateValue, Value.relocate, valueReferences, List.map_cons,
        Reference.relocate, ← value_references_relocate relocation value]
    | cell identity region | exit information => rfl
  termination_by sizeOf value

  theorem environment_references_relocate (relocation : UseScope.Relocation)
      {types : List (TypeOf signature)} (values : RuntimeEnvironment signature algebra program types) :
      environmentReferences (relocateEnvironment relocation values) =
        (environmentReferences values).map (Reference.relocate relocation) := by
    cases values with
    | nil => rfl
    | cons value rest =>
      simp only [relocateEnvironment, Environment.relocate, environmentReferences, List.map_append,
        ← value_references_relocate relocation value, ← environment_references_relocate relocation rest]
      rfl
  termination_by sizeOf values
end

def Frame.references : Frame signature algebra program input result → List Reference
  | .returnTo code bindings operands => code.references ++ environmentReferences bindings ++ environmentReferences operands
  | .handler _ _ attachment returned clauses bindings =>
    .name .attachment attachment :: (returned.references ++ clauses.references ++ environmentReferences bindings)
  | .region identity => [.name .region identity]
  | .protection identity cleanup bindings => .name .obligation identity :: (cleanup.references ++ environmentReferences bindings)

def Stack.references : Stack signature algebra program input result → List Reference
  | .done => []
  | .push frame rest => frame.references ++ rest.references

theorem Frame.references_relocate (relocation : UseScope.Relocation) (frame : Frame signature algebra program input result) :
    (frame.relocate relocation).references = frame.references.map (Reference.relocate relocation) := by
  cases frame <;> simp only [Frame.relocate, Frame.references, List.map_append, List.map_cons,
    List.map_nil, Reference.relocate, Code.references_relocate, Clauses.references_relocate, environment_references_relocate]

theorem Stack.references_relocate (relocation : UseScope.Relocation) (future : Stack signature algebra program input result) :
    (future.relocate relocation).references = future.references.map (Reference.relocate relocation) := by
  induction future with
  | done => rfl
  | push frame rest induction => simp only [Stack.relocate, Stack.references, List.map_append, Frame.references_relocate, induction]

def cellReferences (cell : Cell signature algebra (fun context result => Code signature algebra program context [] result)) : List Reference :=
  .name .cell cell.identity :: .name .region cell.region :: valueReferences cell.value

def cellsReferences (cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)) : List Reference :=
  cells.flatMap cellReferences

def relocateCell (relocation : UseScope.Relocation)
    (cell : Cell signature algebra (fun context result => Code signature algebra program context [] result)) :
    Cell signature algebra (fun context result => Code signature algebra program context [] result) :=
  ⟨relocation.name .cell cell.identity, relocation.name .region cell.region, cell.type, relocateValue relocation cell.value⟩

theorem cell_references_relocate (relocation : UseScope.Relocation)
    (cell : Cell signature algebra (fun context result => Code signature algebra program context [] result)) :
    cellReferences (relocateCell relocation cell) = (cellReferences cell).map (Reference.relocate relocation) := by
  simp only [cellReferences, relocateCell, List.map_cons, Reference.relocate, value_references_relocate]

theorem cells_references_relocate (relocation : UseScope.Relocation)
    (cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)) :
    cellsReferences (cells.map (relocateCell relocation)) = (cellsReferences cells).map (Reference.relocate relocation) := by
  induction cells with
  | nil => rfl
  | cons cell rest induction =>
    simpa only [cellsReferences, List.map_cons, List.flatMap_cons, List.map_append, cell_references_relocate] using
      congrArg (fun tail => (cellReferences cell).map (Reference.relocate relocation) ++ tail) induction

end BoundaryV2.Generalized.Target
