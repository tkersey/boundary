import BoundaryV2.GeneralizedCopying

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Before After : List (TypeOf signature) → TypeOf signature → Type}

def Cell.map (body : ∀ context type, Before context type → After context type)
    (cell : Cell signature algebra Before) : Cell signature algebra After :=
  ⟨cell.identity, cell.region, cell.type, cell.value.map body⟩

def Cells.mapBodies (body : ∀ context type, Before context type → After context type)
    (cells : Cells signature algebra Before) : Cells signature algebra After := cells.map (Cell.map body)

theorem Cells.lookup_mapBodies (body : ∀ context type, Before context type → After context type)
    (identity : Id .cell) (cells : Cells signature algebra Before) :
    lookup identity (cells.mapBodies body) = (lookup identity cells).map (Cell.map body) := by
  induction cells with
  | nil => rfl
  | cons first rest induction =>
    simp only [mapBodies, List.map_cons, lookup, Cell.map]
    by_cases same : first.identity = identity
    · simp only [if_pos same, Option.map_some]
      rfl
    · simp only [if_neg same]
      exact induction

theorem Cells.read_mapBodies [DecidableEq (TypeOf signature)]
    (body : ∀ context type, Before context type → After context type)
    (identity : Id .cell) (region : Id .region) (type : TypeOf signature) (cells : Cells signature algebra Before) :
    read identity region type (cells.mapBodies body) = (read identity region type cells).map (Value.map body) := by
  unfold read
  rw [lookup_mapBodies]
  cases lookup identity cells with
  | none => rfl
  | some cell =>
    cases cell with
    | mk cellId cellRegion cellType value =>
      simp only [Option.map_some, Option.bind_some, Cell.map]
      by_cases sameRegion : cellRegion = region
      · simp only [if_pos sameRegion]
        by_cases sameType : cellType = type
        · cases sameType
          simp only [dite_true, Option.map_some]
        · simp only [dif_neg sameType, Option.map_none]
      · simp only [if_neg sameRegion, Option.map_none]

theorem Cells.exchange_mapBodies [DecidableEq (TypeOf signature)]
    (body : ∀ context type, Before context type → After context type)
    (identity : Id .cell) (region : Id .region) (value : Value signature algebra Before type)
    (cells : Cells signature algebra Before) :
    exchange identity region (value.map body) (cells.mapBodies body) =
      (exchange identity region value cells).map (fun pair => (pair.1.map body, pair.2.mapBodies body)) := by
  induction cells with
  | nil => rfl
  | cons first rest induction =>
    cases first with
    | mk cellId cellRegion cellType contents =>
      simp only [mapBodies, List.map_cons, exchange, Cell.map]
      by_cases sameId : cellId = identity
      · simp only [if_pos sameId]
        by_cases sameRegion : cellRegion = region
        · simp only [if_pos sameRegion]
          by_cases sameType : cellType = type
          · cases sameType
            simp only [dite_true, Option.map_some]
            rfl
          · simp only [dif_neg sameType, Option.map_none]
        · simp only [if_neg sameRegion, Option.map_none]
      · simp only [if_neg sameId]
        change (exchange identity region (value.map body) (mapBodies body rest)).map _ = _
        rw [induction]
        cases exchange identity region value rest <;> rfl

theorem Cells.mapBodies_fields (body : ∀ context type, Before context type → After context type)
    (cells : Cells signature algebra Before) : (cells.mapBodies body).fields = cells.fields := by
  induction cells with
  | nil => rfl
  | cons first rest induction =>
    simp only [mapBodies, fields, List.map_cons, Cell.map, Value.map_preserves_owning_fields]
    exact congrArg (first.value.owningField :: ·) induction

theorem Cells.mapBodies_identities (body : ∀ context type, Before context type → After context type)
    (cells : Cells signature algebra Before) : (cells.mapBodies body).identities = cells.identities := by
  induction cells with
  | nil => rfl
  | cons first rest induction =>
    simp only [mapBodies, identities, List.map_cons, Cell.map]
    exact congrArg (first.identity :: ·) induction

theorem Cells.allocate_mapBodies (body : ∀ context type, Before context type → After context type)
    (region : Id .region) (value : Value signature algebra Before type)
    (cells : Cells signature algebra Before) (reserved : List (Id .cell)) :
    (allocate region (value.map body) (cells.mapBodies body) reserved).identity =
        (allocate region value cells reserved).identity ∧
      (allocate region (value.map body) (cells.mapBodies body) reserved).cells =
        (allocate region value cells reserved).cells.mapBodies body := by
  have identities := mapBodies_identities body cells
  dsimp only [mapBodies] at identities
  simp only [allocate, mapBodies, List.map_cons, Cell.map, identities, and_self]

mutual
  theorem Value.copyable_map (body : ∀ context type, Before context type → After context type)
      {type : TypeOf signature} (value : Value signature algebra Before type) :
      (value.map body).copyable = value.copyable := by
    cases value with
    | datum datum | continuation identity authority | package token owner contents | cell identity region | exit information => rfl
    | pair first second => simp only [Value.map, Value.copyable, Value.copyable_map body first, Value.copyable_map body second]
    | left value | right value => exact Value.copyable_map body value
    | closure code captured authority => simp only [Value.map, Value.copyable, Environment.copyable_map body captured]
  termination_by sizeOf value

  theorem Environment.copyable_map (body : ∀ context type, Before context type → After context type)
      {types : List (TypeOf signature)} (values : Environment signature algebra Before types) :
      (values.map body).copyable = values.copyable := by
    cases values with
    | nil => rfl
    | cons value rest => simp only [Environment.map, Environment.copyable, Value.copyable_map body value,
        Environment.copyable_map body rest]
  termination_by sizeOf values
end

theorem Cells.readCopy_mapBodies [DecidableEq (TypeOf signature)]
    (body : ∀ context type, Before context type → After context type)
    (identity : Id .cell) (region : Id .region) (type : TypeOf signature) (cells : Cells signature algebra Before) :
    readCopy identity region type (cells.mapBodies body) = (readCopy identity region type cells).map (Value.map body) := by
  unfold readCopy
  rw [read_mapBodies]
  cases read identity region type cells with
  | none => rfl
  | some value =>
    simp only [Option.map_some, Option.filter, Value.copyable_map]
    split <;> rfl

theorem Cells.writeCopy_mapBodies [DecidableEq (TypeOf signature)]
    (body : ∀ context type, Before context type → After context type)
    (identity : Id .cell) (region : Id .region) (value : Value signature algebra Before type)
    (cells : Cells signature algebra Before) :
    writeCopy identity region (value.map body) (cells.mapBodies body) =
      (writeCopy identity region value cells).map (mapBodies body) := by
  unfold writeCopy
  simp only [Value.copyable_map]
  by_cases allowed : value.copyable = true
  · simp only [if_pos allowed]
    rw [exchange_mapBodies]
    cases exchange identity region value cells with
    | none => rfl
    | some pair =>
      rcases pair with ⟨old, after⟩
      simp only [Option.map_some, Option.bind_some, Value.copyable_map]
      split <;> rfl
  · simp only [if_neg allowed, Option.map_none]

end BoundaryV2.Generalized
