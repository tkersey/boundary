import BoundaryV2.GeneralizedTypeEquality
import BoundaryV2.GeneralizedFields
import BoundaryV2.GeneralizedFreshNames

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body : List (TypeOf signature) → TypeOf signature → Type}

/-- Cells are physical holders. Accessors return views; the stored value's
owning fields are enumerated here, rather than in every alias to the cell. -/
structure Cell (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (Body : List (TypeOf signature) → TypeOf signature → Type) where
  identity : Id .cell
  region : Id .region
  type : TypeOf signature
  value : Value signature algebra Body type

abbrev Cells (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (Body : List (TypeOf signature) → TypeOf signature → Type) := List (Cell signature algebra Body)

namespace Cells

def lookup (identity : Id .cell) : Cells signature algebra Body → Option (Cell signature algebra Body)
  | [] => none
  | cell :: rest => if cell.identity = identity then some cell else lookup identity rest

def read [DecidableEq (TypeOf signature)] (identity : Id .cell) (region : Id .region) (type : TypeOf signature)
    (cells : Cells signature algebra Body) : Option (Value signature algebra Body type) :=
  (lookup identity cells).bind fun cell =>
    if cell.region = region then
      if same : cell.type = type then some (same ▸ cell.value) else none
    else none

/-- Replacing an existing cell returns its former value. The caller retains
that value for the declared drop/cleanup operation; it is never silently lost. -/
def exchange [DecidableEq (TypeOf signature)] (identity : Id .cell) (region : Id .region)
    (value : Value signature algebra Body type) : Cells signature algebra Body →
    Option (Value signature algebra Body type × Cells signature algebra Body)
  | [] => none
  | cell :: rest =>
    if cell.identity = identity then
      if cell.region = region then
        if same : cell.type = type then some (same ▸ cell.value, ⟨identity, region, type, value⟩ :: rest) else none
      else none
    else (exchange identity region value rest).map fun (old, tail) => (old, cell :: tail)

def fields (cells : Cells signature algebra Body) : List UseScope.Field := cells.map (fun cell => cell.value.owningField)

def identities (cells : Cells signature algebra Body) : List (Id .cell) := cells.map Cell.identity

structure Allocation (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (Body : List (TypeOf signature) → TypeOf signature → Type) where
  identity : Id .cell
  cells : Cells signature algebra Body

/-- Reserved names include any additional retained aliases supplied by the
enclosing scope. Freshness is computed from them and the actual cell records. -/
def allocate (region : Id .region) (value : Value signature algebra Body type)
    (cells : Cells signature algebra Body) (reserved : List (Id .cell)) : Allocation signature algebra Body :=
  let identity : Id .cell := ⟨FreshNames.bound (identities cells ++ reserved)⟩
  ⟨identity, ⟨identity, region, type, value⟩ :: cells⟩

theorem allocation_is_fresh (region : Id .region) (value : Value signature algebra Body type)
    (cells : Cells signature algebra Body) (reserved : List (Id .cell)) :
    (allocate region value cells reserved).identity ∉ identities cells ++ reserved := by
  intro member
  have impossible := FreshNames.member_below_bound member
  exact Nat.lt_irrefl _ impossible

theorem allocation_preserves_existing_lookup (region : Id .region) (value : Value signature algebra Body type)
    (cells : Cells signature algebra Body) (reserved : List (Id .cell))
    (existing : identity ∈ identities cells ++ reserved) :
    lookup identity (allocate region value cells reserved).cells = lookup identity cells := by
  have different : (allocate region value cells reserved).identity ≠ identity := by
    intro same
    exact allocation_is_fresh region value cells reserved (same ▸ existing)
  exact if_neg different

theorem allocation_holds_value_fields (region : Id .region) (value : Value signature algebra Body type)
    (cells : Cells signature algebra Body) (reserved : List (Id .cell)) :
    fields (allocate region value cells reserved).cells = value.owningField :: fields cells := rfl

theorem successive_allocations_are_distinct (firstRegion secondRegion : Id .region)
    (firstValue : Value signature algebra Body firstType) (secondValue : Value signature algebra Body secondType)
    (cells : Cells signature algebra Body) (firstReserved secondReserved : List (Id .cell)) :
    let first := allocate firstRegion firstValue cells firstReserved
    first.identity ≠ (allocate secondRegion secondValue first.cells secondReserved).identity := by
  dsimp only
  intro same
  apply allocation_is_fresh secondRegion secondValue (allocate firstRegion firstValue cells firstReserved).cells secondReserved
  rw [← same]
  simp only [allocate, identities, List.map_cons, List.cons_append, List.mem_cons, true_or]

theorem lookup_identifies (found : lookup identity cells = some cell) : cell.identity = identity ∧ cell ∈ cells := by
  induction cells with
  | nil => simp [lookup] at found
  | cons first rest induction =>
    simp only [lookup] at found
    split at found
    · rename_i same
      cases found
      exact ⟨same, List.mem_cons_self⟩
    · obtain ⟨same, member⟩ := induction found
      exact ⟨same, List.mem_cons_of_mem _ member⟩

theorem read_has_region_and_type [DecidableEq (TypeOf signature)]
    {cells : Cells signature algebra Body} {type : TypeOf signature} {value : Value signature algebra Body type}
    (accepted : read identity region type cells = some value) :
    ∃ cell, lookup identity cells = some cell ∧ cell.region = region ∧ cell.type = type := by
  obtain ⟨cell, found, accepted⟩ := Option.bind_eq_some_iff.mp accepted
  split at accepted
  · rename_i regionMatches
    split at accepted
    · rename_i typeMatches
      exact ⟨cell, found, regionMatches, typeMatches⟩
    · contradiction
  · contradiction

theorem read_newest [DecidableEq (TypeOf signature)] (identity : Id .cell) (region : Id .region)
    (value : Value signature algebra Body type) (rest : Cells signature algebra Body) :
    read identity region type (⟨identity, region, type, value⟩ :: rest) = some value := by
  simp [read, lookup]

theorem lookup_other_cons (different : first.identity ≠ identity) :
    lookup identity (first :: rest) = lookup identity rest := by simp only [lookup, if_neg different]

theorem exchange_preserves_identities [DecidableEq (TypeOf signature)]
    {value : Value signature algebra Body type} {cells after : Cells signature algebra Body}
    (accepted : exchange identity region value cells = some (old, after)) : identities after = identities cells := by
  induction cells generalizing after with
  | nil => simp [exchange] at accepted
  | cons first rest induction =>
    simp only [exchange] at accepted
    split at accepted
    · rename_i sameId
      split at accepted
      · split at accepted
        · cases accepted
          simp only [identities, List.map_cons, sameId]
        · contradiction
      · contradiction
    · obtain ⟨⟨previous, tail⟩, exchanged, mapped⟩ := Option.map_eq_some_iff.mp accepted
      cases mapped
      simp only [identities, List.map_cons]
      exact congrArg (first.identity :: ·) (induction exchanged)

theorem exchange_read [DecidableEq (TypeOf signature)]
    {value : Value signature algebra Body type} {cells after : Cells signature algebra Body}
    (accepted : exchange identity region value cells = some (old, after)) : read identity region type after = some value := by
  induction cells generalizing after with
  | nil => simp [exchange] at accepted
  | cons first rest induction =>
    simp only [exchange] at accepted
    split at accepted
    · split at accepted
      · split at accepted
        · cases accepted
          exact read_newest _ _ _ _
        · contradiction
      · contradiction
    · rename_i different
      obtain ⟨⟨previous, tail⟩, exchanged, mapped⟩ := Option.map_eq_some_iff.mp accepted
      cases mapped
      simpa only [read, lookup, if_neg different] using induction exchanged

theorem exchange_preserves_other_lookup [DecidableEq (TypeOf signature)]
    {value : Value signature algebra Body type} {cells after : Cells signature algebra Body}
    (accepted : exchange identity region value cells = some (old, after)) (different : other ≠ identity) :
    lookup other after = lookup other cells := by
  induction cells generalizing after with
  | nil => simp [exchange] at accepted
  | cons first rest induction =>
    simp only [exchange] at accepted
    split at accepted
    · rename_i sameId
      split at accepted
      · split at accepted
        · cases accepted
          simp only [lookup, sameId, if_neg (Ne.symm different)]
        · contradiction
      · contradiction
    · obtain ⟨⟨previous, tail⟩, exchanged, mapped⟩ := Option.map_eq_some_iff.mp accepted
      cases mapped
      simp only [lookup]
      split
      · rfl
      · exact induction exchanged

theorem exchange_without_owners_preserves_inventory [DecidableEq (TypeOf signature)]
    {value old : Value signature algebra Body type} {cells after : Cells signature algebra Body}
    (accepted : exchange identity region value cells = some (old, after))
    (newUnowned : value.owningField.tokens = []) (oldUnowned : old.owningField.tokens = []) :
    UseScope.tokens (fields after) = UseScope.tokens (fields cells) := by
  induction cells generalizing after with
  | nil => simp [exchange] at accepted
  | cons first rest induction =>
    cases first with
    | mk firstId firstRegion firstType contents =>
      simp only [exchange] at accepted
      split at accepted
      · split at accepted
        · split at accepted
          · rename_i sameType
            cases sameType
            cases accepted
            simp only [fields, List.map_cons, UseScope.tokens, newUnowned, oldUnowned]
          · contradiction
        · contradiction
      · obtain ⟨⟨previous, tail⟩, exchanged, mapped⟩ := Option.map_eq_some_iff.mp accepted
        cases mapped
        simp only [fields, List.map_cons, UseScope.tokens]
        exact congrArg (contents.owningField.tokens ++ ·) (induction exchanged)

end Cells
end BoundaryV2.Generalized
