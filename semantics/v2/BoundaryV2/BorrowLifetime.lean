import BoundaryV2.Profile

namespace BoundaryV2.Profile.BorrowLifetime

inductive Ambient where
  | evidence | region
  deriving DecidableEq, Repr

inductive Bound where
  | region | clause | capture
  deriving DecidableEq, Repr

/-- A newly introduced dependency may only be stored under an owner that
selects the other ancestry component. Source and target supply their own
representation-specific owner projections to this single lifetime rule. -/
def compatible (fresh : Option Ambient) (owners : List α) (selected : α → Option Ambient) : Bool :=
  fresh.all (fun component => owners.all (fun owner => (selected owner).any (· != component)))

theorem rejects_same_component (fresh : Option Ambient) (owners : List α) (selected : α → Option Ambient)
    (component : Ambient) (owner : α) (isFresh : fresh = some component)
    (included : owner ∈ owners) (same : selected owner = some component) :
    compatible fresh owners selected = false := by
  apply Bool.eq_false_iff.mpr
  intro accepted
  have every : owners.all (fun owner => (selected owner).any (· != component)) = true := by
    simpa [compatible, isFresh] using accepted
  have this := List.all_eq_true.mp every owner included
  simp [same] at this

theorem accepts_no_fresh_dependency (owners : List α) (selected : α → Option Ambient) :
    compatible none owners selected = true := rfl

theorem accepts_other_component (component : Ambient) :
    compatible (some component) [component] (fun _ => some (match component with
      | .evidence => .region | .region => .evidence)) = true := by
  cases component <;> decide

end BoundaryV2.Profile.BorrowLifetime
