import BoundaryV2.SchemaAdmission

namespace BoundaryV2.Profile.SchemaEquivalence

abbrev Pair (space : Space) := SchemaId space × SchemaId space

def mapChildren (rename : SchemaId space → SchemaId space) : Schema space → Schema space
  | .product fields => .product (fields.map rename)
  | .sum fields => .sum (fields.map rename)
  | .seq element => .seq (rename element)
  | .vector element maximum => .vector (rename element) maximum
  | .array element length => .array (rename element) length
  | shape => shape

def label (shape : Schema space) : Schema space := mapChildren (fun _ => 0) shape

def pairValid (types : List (Schema space)) (pairs : List (Pair space)) (pair : Pair space) : Bool :=
  match types[pair.1.value]?, types[pair.2.value]? with
  | some left, some right =>
    label left == label right &&
      ((SchemaAdmission.structuralChildren left).zip (SchemaAdmission.structuralChildren right)).all pairs.contains
  | _, _ => false

def prune (types : List (Schema space)) (pairs : List (Pair space)) : List (Pair space) :=
  pairs.filter (pairValid types pairs)

private theorem prune_decreases (types : List (Schema space)) (pairs : List (Pair space))
    (changed : prune types pairs ≠ pairs) : (prune types pairs).length < pairs.length := by
  have le := List.length_filter_le (pairValid types pairs) pairs
  have ne : (prune types pairs).length ≠ pairs.length := by
    intro equal
    exact changed (List.filter_eq_self.mpr (List.length_filter_eq_length_iff.mp equal))
  change (prune types pairs).length ≤ pairs.length at le
  omega

/-- Start with every pair, then delete precisely the unsupported pairs until
stable. The candidate relation shrinks strictly; recursive types need no fuel. -/
def refine (types : List (Schema space)) (pairs : List (Pair space)) : List (Pair space) :=
  if _unchanged : prune types pairs = pairs then pairs
  else refine types (prune types pairs)
termination_by pairs.length
decreasing_by exact prune_decreases types pairs _unchanged

def allPairs (types : List (Schema space)) : List (Pair space) :=
  (List.range types.length).flatMap (fun left => (List.range types.length).map (fun right => (⟨left⟩, ⟨right⟩)))

def bisimilar (types : List (Schema space)) : List (Pair space) := refine types (allPairs types)

theorem refine_stable (types : List (Schema space)) (pairs : List (Pair space)) :
    prune types (refine types pairs) = refine types pairs := by
  fun_induction refine types pairs with
  | case1 pairs unchanged => exact unchanged
  | case2 pairs changed ih => exact ih

theorem refine_subset (types : List (Schema space)) (pairs : List (Pair space)) :
    refine types pairs ⊆ pairs := by
  fun_induction refine types pairs with
  | case1 pairs unchanged => exact List.Subset.refl _
  | case2 pairs changed ih =>
    intro pair member
    exact (List.mem_filter.mp (ih member)).1

theorem stable_is_closed (types : List (Schema space)) (pairs : List (Pair space))
    (stable : prune types pairs = pairs) :
    ∀ pair ∈ pairs, pairValid types pairs pair = true := List.filter_eq_self.mp stable

private theorem pairValid_monotone (types : List (Schema space)) (small large : List (Pair space))
    (included : small ⊆ large) (pair : Pair space) (accepted : pairValid types small pair = true) :
    pairValid types large pair = true := by
  unfold pairValid at *
  split at accepted
  · rename_i left right foundLeft foundRight
    simp only [Bool.and_eq_true] at accepted ⊢
    refine ⟨accepted.1, List.all_eq_true.mpr ?_⟩
    intro child member
    exact List.contains_iff_mem.mpr (included (List.contains_iff_mem.mp (List.all_eq_true.mp accepted.2 child member)))
  · contradiction

theorem refine_contains_closed (types : List (Schema space)) (pairs closed : List (Pair space))
    (included : closed ⊆ pairs) (supported : ∀ pair ∈ closed, pairValid types closed pair = true) :
    closed ⊆ refine types pairs := by
  fun_induction refine types pairs with
  | case1 pairs unchanged => exact included
  | case2 pairs changed ih =>
    apply ih
    intro pair member
    exact List.mem_filter.mpr ⟨included member,
      pairValid_monotone types closed pairs included pair (supported pair member)⟩

theorem bisimilar_closed (types : List (Schema space)) :
    ∀ pair ∈ bisimilar types, pairValid types (bisimilar types) pair = true :=
  stable_is_closed types _ (refine_stable types _)

theorem bisimilar_greatest (types : List (Schema space)) (pairs : List (Pair space))
    (inBounds : pairs ⊆ allPairs types)
    (closed : ∀ pair ∈ pairs, pairValid types pairs pair = true) : pairs ⊆ bisimilar types :=
  refine_contains_closed types _ pairs inBounds closed

end BoundaryV2.Profile.SchemaEquivalence
