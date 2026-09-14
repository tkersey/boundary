import BoundaryV2.GeneralizedFreshNames

namespace BoundaryV2.Generalized.Scope

/-- Nesting is structural. Reparenting moves a subtree, so it cannot manufacture
a parent cycle; distinct names are checked separately on the finite forest. -/
inductive Tree where
  | node : Id .scope → List Tree → Tree

abbrev Forest := List Tree

mutual
  def Tree.names : Tree → List (Id .scope)
    | .node identity children => identity :: names children
  def names : Forest → List (Id .scope)
    | [] => []
    | tree :: rest => tree.names ++ names rest
end

def Valid (forest : Forest) : Prop := (names forest).Nodup

mutual
  def Tree.path (wanted : Id .scope) : Tree → Option (List (Id .scope))
    | .node identity children =>
      if identity = wanted then some [identity] else (path wanted children).map (identity :: ·)
  def path (wanted : Id .scope) : Forest → Option (List (Id .scope))
    | [] => none
    | tree :: rest => (tree.path wanted).or (path wanted rest)
end

mutual
  def Tree.detach (wanted : Id .scope) : Tree → Option (Tree × Forest)
    | .node identity children =>
      if identity = wanted then some (.node identity children, [])
      else (detach wanted children).map fun (selected, remaining) => (selected, [.node identity remaining])
  def detach (wanted : Id .scope) : Forest → Option (Tree × Forest)
    | [] => none
    | tree :: rest =>
      match tree.detach wanted with
      | some (selected, remaining) => some (selected, remaining ++ rest)
      | none => (detach wanted rest).map fun (selected, remaining) => (selected, tree :: remaining)
end

mutual
  def Tree.attach (parent : Id .scope) (child : Tree) : Tree → Option Tree
    | .node identity children =>
      if identity = parent then some (.node identity (children ++ [child]))
      else (attach parent child children).map (Tree.node identity)
  def attach (parent : Id .scope) (child : Tree) : Forest → Option Forest
    | [] => none
    | tree :: rest =>
      match Tree.attach parent child tree with
      | some updated => some (updated :: rest)
      | none => (attach parent child rest).map (tree :: ·)
end

/-- Moving first removes the source subtree. A destination inside that subtree
therefore cannot be found, and the pure operation rejects without publishing a
partially detached forest. -/
def move (wanted parent : Id .scope) (forest : Forest) : Option Forest :=
  (detach wanted forest).bind fun (selected, remaining) => attach parent selected remaining

def close (wanted : Id .scope) (forest : Forest) : Option (Tree × Forest) := detach wanted forest

def permitsBorrow (forest : Forest) (destination dependency : Id .scope) : Bool :=
  (path destination forest).any (fun ancestors => dependency ∈ ancestors)

def permitsCapture (forest : Forest) (destination : Id .scope) (owned : Forest) (borrowed : List (Id .scope)) : Bool :=
  (path destination forest).isSome && borrowed.all (fun dependency => dependency ∈ names owned || permitsBorrow forest destination dependency)

theorem names_append (first second : Forest) : names (first ++ second) = names first ++ names second := by
  induction first with
  | nil => rfl
  | cons tree rest induction => simp only [List.cons_append, names, induction, List.append_assoc]

mutual
  theorem Tree.detach_names (tree : Tree) (found : tree.detach wanted = some (selected, remaining)) :
      tree.names.Perm (selected.names ++ names remaining) := by
    cases tree with
    | node identity children =>
      simp only [Tree.detach] at found
      split at found
      · cases found
        simp only [names, List.append_nil]
        exact .refl _
      · obtain ⟨⟨taken, rest⟩, takenAt, mapped⟩ := Option.map_eq_some_iff.mp found
        cases mapped
        have moved := (detach_names children takenAt).cons identity
        simp only [Tree.names, names, List.append_nil]
        exact moved.trans List.perm_middle.symm
  termination_by sizeOf tree

  theorem detach_names (forest : Forest) (found : detach wanted forest = some (selected, remaining)) :
      (names forest).Perm (selected.names ++ names remaining) := by
    cases forest with
    | nil => contradiction
    | cons tree rest =>
      simp only [detach] at found
      cases treeAt : tree.detach wanted with
      | some pair =>
        rcases pair with ⟨taken, tail⟩
        simp only [treeAt, Option.some.injEq, Prod.mk.injEq] at found
        rcases found with ⟨rfl, rfl⟩
        simpa only [names, names_append, List.append_assoc] using (Tree.detach_names tree treeAt).append_right (names rest)
      | none =>
        simp only [treeAt] at found
        obtain ⟨⟨taken, tail⟩, takenAt, mapped⟩ := Option.map_eq_some_iff.mp found
        cases mapped
        have moved := (detach_names rest takenAt).append_left tree.names
        exact moved.trans (by simpa only [names, List.append_assoc] using
          (List.perm_append_comm (l₁ := tree.names) (l₂ := taken.names)).append_right (names tail))
  termination_by sizeOf forest
end

mutual
  theorem Tree.attach_names (tree child : Tree) (found : Tree.attach parent child tree = some updated) :
      (tree.names ++ child.names).Perm updated.names := by
    cases tree with
    | node identity children =>
      simp only [Tree.attach] at found
      split at found
      · cases found
        simp only [Tree.names, names_append, names, List.append_nil, List.cons_append]
        exact .refl _
      · obtain ⟨next, attached, rfl⟩ := Option.map_eq_some_iff.mp found
        exact (attach_names children child attached).cons identity
  termination_by sizeOf tree

  theorem attach_names (forest : Forest) (child : Tree) (found : attach parent child forest = some updated) :
      (names forest ++ child.names).Perm (names updated) := by
    cases forest with
    | nil => contradiction
    | cons tree rest =>
      simp only [attach] at found
      cases treeAt : Tree.attach parent child tree with
      | some next =>
        simp only [treeAt, Option.some.injEq] at found
        cases found
        have grouped : (tree.names ++ names rest ++ child.names).Perm (tree.names ++ child.names ++ names rest) := by
          simpa only [List.append_assoc] using (List.perm_append_comm (l₁ := names rest) (l₂ := child.names)).append_left tree.names
        exact grouped.trans ((Tree.attach_names tree child treeAt).append_right (names rest))
      | none =>
        simp only [treeAt] at found
        obtain ⟨next, attached, rfl⟩ := Option.map_eq_some_iff.mp found
        simpa only [names, List.append_assoc] using (attach_names rest child attached).append_left tree.names
  termination_by sizeOf forest
end

theorem move_preserves_names (accepted : move wanted parent forest = some updated) : (names forest).Perm (names updated) := by
  obtain ⟨⟨selected, remaining⟩, detached, attached⟩ := Option.bind_eq_some_iff.mp accepted
  exact (detach_names forest detached).trans (List.perm_append_comm.trans (attach_names remaining selected attached))

theorem move_preserves_validity (valid : Valid forest) (accepted : move wanted parent forest = some updated) : Valid updated :=
  (move_preserves_names accepted).nodup_iff.mp valid

theorem closed_scopes_are_removed (valid : Valid forest) (closed : close wanted forest = some (retired, remaining)) :
    ∀ identity ∈ retired.names, identity ∉ names remaining := by
  have unique := (detach_names forest closed).nodup_iff.mp valid
  have disjoint := (List.nodup_append.mp unique).2.2
  intro identity member repeated
  exact disjoint identity member identity repeated rfl

mutual
  theorem Tree.path_stays_live (tree : Tree) (found : tree.path wanted = some result) :
      ∀ identity ∈ result, identity ∈ tree.names := by
    cases tree with
    | node identity children =>
      simp only [Tree.path] at found
      split at found
      · cases found
        intro name member
        simp only [List.mem_cons, List.not_mem_nil, or_false] at member
        subst name
        exact List.mem_cons_self
      · obtain ⟨tail, innerFound, rfl⟩ := Option.map_eq_some_iff.mp found
        intro name member
        rcases List.mem_cons.mp member with rfl | later
        · exact List.mem_cons_self
        · exact List.mem_cons_of_mem _ (path_stays_live children innerFound name later)
  termination_by sizeOf tree

  theorem path_stays_live (forest : Forest) (found : path wanted forest = some result) :
      ∀ identity ∈ result, identity ∈ names forest := by
    cases forest with
    | nil => contradiction
    | cons tree rest =>
      simp only [path] at found
      cases first : tree.path wanted with
      | none =>
        simp only [first] at found
        exact fun identity member => List.mem_append_right _ (path_stays_live rest found identity member)
      | some route =>
        simp only [first] at found
        cases found
        exact fun identity member => List.mem_append_left _ (Tree.path_stays_live tree first identity member)
  termination_by sizeOf forest
end

theorem permitted_borrow_is_live (allowed : permitsBorrow forest destination dependency = true) : dependency ∈ names forest := by
  unfold permitsBorrow at allowed
  cases found : path destination forest with
  | none => simp [found] at allowed
  | some route =>
    have member : dependency ∈ route := by simpa [found] using allowed
    exact path_stays_live forest found dependency member

theorem closed_scope_cannot_supply_a_borrow (valid : Valid forest)
    (closed : close wanted forest = some (retired, remaining)) (retiredDependency : dependency ∈ retired.names) :
    permitsBorrow remaining destination dependency = false := by
  cases allowed : permitsBorrow remaining destination dependency with
  | false => rfl
  | true => exact False.elim (closed_scopes_are_removed valid closed dependency retiredDependency (permitted_borrow_is_live allowed))

theorem permitted_capture_has_supported_dependencies
    (allowed : permitsCapture forest destination owned borrowed = true) :
    ∀ dependency ∈ borrowed, dependency ∈ names owned ∨ dependency ∈ names forest := by
  have all := (Bool.and_eq_true_iff.mp allowed).2
  intro dependency member
  have one := (List.all_eq_true.mp all) dependency member
  rcases Bool.or_eq_true_iff.mp one with captured | borrowed
  · exact Or.inl (by simpa using captured)
  · exact Or.inr (permitted_borrow_is_live borrowed)

structure Retained where
  scope : Id .scope
  forest : Forest

/-- A retained owner receives the actual detached subtree. External borrows
must outlive its destination; the owned subtree's own dependencies travel with
it. A failed check leaves the original forest as the caller's only state. -/
def retain (wanted destination : Id .scope) (borrowed : List (Id .scope)) (forest : Forest) : Option Retained :=
  (detach wanted forest).bind fun (owned, remaining) =>
    if permitsCapture remaining destination [owned] borrowed then
      let scope : Id .scope := ⟨FreshNames.bound (names forest)⟩
      (attach destination (.node scope [owned]) remaining).map fun updated => ⟨scope, updated⟩
    else none

theorem retain_checks_dependencies (accepted : retain wanted destination borrowed forest = some result) :
    ∃ owned remaining, detach wanted forest = some (owned, remaining) ∧
      permitsCapture remaining destination [owned] borrowed = true ∧
      ∀ dependency ∈ borrowed, dependency ∈ owned.names ∨ permitsBorrow remaining destination dependency = true := by
  obtain ⟨⟨owned, remaining⟩, detached, accepted⟩ := Option.bind_eq_some_iff.mp accepted
  dsimp only at accepted
  split at accepted
  · rename_i checked
    refine ⟨owned, remaining, detached, checked, ?_⟩
    intro dependency member
    have all := (Bool.and_eq_true_iff.mp checked).2
    have one := (List.all_eq_true.mp all) dependency member
    rcases Bool.or_eq_true_iff.mp one with internal | external
    · exact Or.inl (by simpa [names] using internal)
    · exact Or.inr external
  · contradiction

theorem retained_scope_is_fresh (accepted : retain wanted destination borrowed forest = some result) : result.scope ∉ names forest := by
  obtain ⟨⟨owned, remaining⟩, _, accepted⟩ := Option.bind_eq_some_iff.mp accepted
  dsimp only at accepted
  split at accepted
  · obtain ⟨updated, _, rfl⟩ := Option.map_eq_some_iff.mp accepted
    intro member
    have impossible := FreshNames.member_below_bound member
    exact Nat.lt_irrefl _ impossible
  · contradiction

theorem retain_preserves_old_scopes (accepted : retain wanted destination borrowed forest = some result) :
    (result.scope :: names forest).Perm (names result.forest) := by
  obtain ⟨⟨owned, remaining⟩, detached, accepted⟩ := Option.bind_eq_some_iff.mp accepted
  dsimp only at accepted
  split at accepted
  · obtain ⟨updated, attached, rfl⟩ := Option.map_eq_some_iff.mp accepted
    have moved := (detach_names forest detached).cons (Id.mk (FreshNames.bound (names forest)))
    have attachedNames := attach_names remaining (.node ⟨FreshNames.bound (names forest)⟩ [owned]) attached
    simp only [Tree.names, names, List.append_nil] at attachedNames
    apply moved.trans
    exact List.perm_append_comm.trans attachedNames
  · contradiction

theorem retain_preserves_validity (valid : Valid forest) (accepted : retain wanted destination borrowed forest = some result) : Valid result.forest := by
  have prepared := List.nodup_cons.mpr ⟨retained_scope_is_fresh accepted, valid⟩
  exact (retain_preserves_old_scopes accepted).nodup_iff.mp prepared

end BoundaryV2.Generalized.Scope
