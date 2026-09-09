import Std

namespace BoundaryV2

/-- Token identities and allocation history are separate from their owners. -/
structure Ownership where
  fresh : Nat
  live : List Nat
  spent : List Nat
  deriving DecidableEq, Repr

def Ownership.Valid (s : Ownership) : Prop :=
  s.live.Nodup ∧ s.spent.Nodup ∧
  (∀ t, t ∈ s.live → t ∉ s.spent) ∧
  (∀ t, t ∈ s.live ∨ t ∈ s.spent → t < s.fresh)

def Ownership.empty : Ownership := ⟨0, [], []⟩

def Ownership.capture (s : Ownership) : Ownership :=
  ⟨s.fresh + 1, s.fresh :: s.live, s.spent⟩

/-- Resume, dispose, transfer out, and conversion to multi all consume custody.
The token is removed before the successor control is entered. -/
def Ownership.consume (s : Ownership) (token : Nat) : Option Ownership :=
  if token ∈ s.live then
    some ⟨s.fresh, s.live.erase token, token :: s.spent⟩
  else none

theorem ownership_empty_valid : Ownership.empty.Valid := by
  simp [Ownership.empty, Ownership.Valid]

theorem capture_preserves_ownership (s : Ownership) (h : s.Valid) :
    s.capture.Valid := by
  rcases h with ⟨hl, hs, hd, hb⟩
  have fresh_live : s.fresh ∉ s.live := by
    intro h
    have := hb s.fresh (Or.inl h)
    omega
  have fresh_spent : s.fresh ∉ s.spent := by
    intro h
    have := hb s.fresh (Or.inr h)
    omega
  refine ⟨List.nodup_cons.mpr ⟨fresh_live, hl⟩, hs, ?_, ?_⟩
  · intro t ht
    rcases List.mem_cons.mp ht with rfl | ht
    · exact fresh_spent
    · exact hd t ht
  · intro t ht
    change t < s.fresh + 1
    rcases ht with ht | ht
    · rcases List.mem_cons.mp ht with rfl | ht
      · omega
      · have := hb t (Or.inl ht); omega
    · have := hb t (Or.inr ht); omega

theorem consume_preserves_ownership (s s' : Ownership) (token : Nat)
    (h : s.Valid) (step : s.consume token = some s') : s'.Valid := by
  unfold Ownership.consume at step
  split at step
  next present =>
    cases step
    rcases h with ⟨hl, hs, hd, hb⟩
    refine ⟨hl.erase token, List.nodup_cons.mpr ⟨hd token present, hs⟩, ?_, ?_⟩
    · intro t ht spent
      rcases List.mem_cons.mp spent with rfl | spent
      · exact hl.not_mem_erase ht
      · exact hd t (List.mem_of_mem_erase ht) spent
    · intro t ht
      rcases ht with ht | ht
      · exact hb t (Or.inl (List.mem_of_mem_erase ht))
      · rcases List.mem_cons.mp ht with rfl | ht
        · exact hb t (Or.inl present)
        · exact hb t (Or.inr ht)
  next absent => contradiction

theorem consumed_token_cannot_resume (s s' : Ownership) (token : Nat)
    (h : s.Valid) (step : s.consume token = some s') :
    s'.consume token = none := by
  unfold Ownership.consume at step
  split at step
  next present =>
    cases step
    simp only [Ownership.consume]
    rw [if_neg h.1.not_mem_erase]
  next absent => contradiction

/-- Multi templates do not enter the linear ownership ledger. Each activation
gets a new, separately consumed one-shot control identity. -/
def Ownership.activateMulti (s : Ownership) : Ownership := s.capture

theorem multi_activations_are_distinct (s : Ownership) :
    s.fresh ≠ s.activateMulti.fresh := by
  simp [Ownership.activateMulti, Ownership.capture]

theorem multi_activation_preserves_ownership (s : Ownership) (h : s.Valid) :
    s.activateMulti.Valid := capture_preserves_ownership s h

/-- Region paths are lexical: the suffix is outside the capture boundary. -/
structure RegionView where
  inside : List Nat
  outside : List Nat
  deriving DecidableEq, Repr

def RegionView.clone (v : RegionView) (rename : Nat → Nat) : RegionView :=
  ⟨v.inside.map rename, v.outside⟩

theorem clone_preserves_outer_regions (v : RegionView) (rename : Nat → Nat) :
    (v.clone rename).outside = v.outside := rfl

theorem clone_preserves_aliases (rename : Nat → Nat) (a b : Nat) (h : a = b) :
    rename a = rename b := congrArg rename h

theorem clone_preserves_distinctions (rename : Nat → Nat)
    (injective : Function.Injective rename) (a b : Nat) :
    rename a = rename b ↔ a = b := ⟨fun h => injective h, congrArg rename⟩

/-- A borrowed dependency is valid only while its lexical owner is live. -/
def InScope (owners dependencies : List Nat) : Prop :=
  ∀ r, r ∈ dependencies → r ∈ owners

theorem enter_region_preserves_scope (owners dependencies : List Nat) (r : Nat)
    (h : InScope owners dependencies) : InScope (r :: owners) dependencies := by
  intro x hx
  exact List.mem_cons_of_mem r (h x hx)

theorem exit_region_preserves_scope (owners dependencies : List Nat) (r : Nat)
    (h : InScope (r :: owners) dependencies) (no_escape : r ∉ dependencies) :
    InScope owners dependencies := by
  intro x hx
  rcases List.mem_cons.mp (h x hx) with rfl | present
  · exact False.elim (no_escape hx)
  · exact present

theorem borrowed_region_cannot_escape (owners : List Nat) (r : Nat)
    (fresh : r ∉ owners) : ¬ InScope owners [r] := by
  intro h
  exact fresh (h r (by simp))

end BoundaryV2
