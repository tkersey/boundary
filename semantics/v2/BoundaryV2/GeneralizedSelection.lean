import BoundaryV2.GeneralizedContinuations

namespace BoundaryV2.Generalized.Source

structure Selection (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) (input output : TypeOf signature) where
  effect : signature.Effect
  mode : Mode
  identity : Id .attachment
  body : TypeOf signature
  answer : TypeOf signature
  captured : List (TypeOf signature)
  returned : Computation signature algebra definitions (body :: captured) answer
  clauses : Clauses signature algebra definitions effect mode captured body answer
  environment : RuntimeEnvironment signature algebra definitions captured
  inside : Context signature algebra definitions input body
  outside : Context signature algebra definitions answer output

def Selection.whole (selected : Selection signature algebra definitions input output) : Context signature algebra definitions input output :=
  selected.inside.append (.push (.handler selected.effect selected.mode selected.identity selected.returned selected.clauses selected.environment) selected.outside)

def Selection.prepend (frame : Frame signature algebra definitions first middle)
    (selected : Selection signature algebra definitions middle last) : Selection signature algebra definitions first last :=
  { selected with inside := .push frame selected.inside }

def select (wanted : Id .attachment) : Context signature algebra definitions input output → Option (Selection signature algebra definitions input output)
  | .done => none
  | .push (.handler effect mode identity returned clauses environment) rest =>
    if wanted = identity then some ⟨effect, mode, identity, _, _, _, returned, clauses, environment, .done, rest⟩
    else (select wanted rest).map (Selection.prepend (.handler effect mode identity returned clauses environment))
  | .push frame rest => (select wanted rest).map (Selection.prepend frame)

def Context.attachments : Context signature algebra definitions input output → List (Id .attachment)
  | .done => []
  | .push (.handler _ _ identity _ _ _) rest => identity :: rest.attachments
  | .push _ rest => rest.attachments

theorem selection_reconstructs (context : Context signature algebra definitions input output) (wanted : Id .attachment)
    (selected : Selection signature algebra definitions input output) (found : select wanted context = some selected) : selected.whole = context := by
  suffices ∀ (n : Nat) {input output} (context : Context signature algebra definitions input output)
      (selected : Selection signature algebra definitions input output), context.length ≤ n →
      select wanted context = some selected → selected.whole = context from
    this context.length context selected (Nat.le_refl _) found
  intro n
  induction n with
  | zero =>
    intro input output context selected bounded found
    cases context with
    | done => contradiction
    | push frame rest => simp [Context.length] at bounded
  | succ n induction =>
    intro input output context selected bounded found
    cases context with
    | done => contradiction
    | push frame rest =>
      have smaller : rest.length ≤ n := by simpa [Context.length] using bounded
      cases frame <;> simp only [select] at found
      all_goals first
        | (split at found
           · cases found; rfl
           · obtain ⟨next, innerAt, rfl⟩ := Option.map_eq_some_iff.mp found
             exact congrArg (Context.push _) (induction rest next smaller innerAt))
        | (obtain ⟨next, innerAt, rfl⟩ := Option.map_eq_some_iff.mp found
           exact congrArg (Context.push _) (induction rest next smaller innerAt))

theorem selection_uses_identity (context : Context signature algebra definitions input output) (wanted : Id .attachment)
    (selected : Selection signature algebra definitions input output) (found : select wanted context = some selected) : selected.identity = wanted := by
  suffices ∀ (n : Nat) {input output} (context : Context signature algebra definitions input output)
      (selected : Selection signature algebra definitions input output), context.length ≤ n →
      select wanted context = some selected → selected.identity = wanted from
    this context.length context selected (Nat.le_refl _) found
  intro n
  induction n with
  | zero =>
    intro input output context selected bounded found
    cases context with
    | done => contradiction
    | push frame rest => simp [Context.length] at bounded
  | succ n induction =>
    intro input output context selected bounded found
    cases context with
    | done => contradiction
    | push frame rest =>
      have smaller : rest.length ≤ n := by simpa [Context.length] using bounded
      cases frame <;> simp only [select] at found
      all_goals first
        | (split at found
           · rename_i same; cases found; exact same.symm
           · obtain ⟨next, innerAt, rfl⟩ := Option.map_eq_some_iff.mp found
             exact induction rest next smaller innerAt)
        | (obtain ⟨next, innerAt, rfl⟩ := Option.map_eq_some_iff.mp found
           exact induction rest next smaller innerAt)

theorem selection_is_nearest (context : Context signature algebra definitions input output) (wanted : Id .attachment)
    (selected : Selection signature algebra definitions input output) (found : select wanted context = some selected) :
    wanted ∉ selected.inside.attachments := by
  suffices ∀ (n : Nat) {input output} (context : Context signature algebra definitions input output)
      (selected : Selection signature algebra definitions input output), context.length ≤ n →
      select wanted context = some selected → wanted ∉ selected.inside.attachments from
    this context.length context selected (Nat.le_refl _) found
  intro n
  induction n with
  | zero =>
    intro input output context selected bounded found
    cases context with
    | done => contradiction
    | push frame rest => simp [Context.length] at bounded
  | succ n induction =>
    intro input output context selected bounded found
    cases context with
    | done => contradiction
    | push frame rest =>
      have smaller : rest.length ≤ n := by simpa [Context.length] using bounded
      cases frame <;> simp only [select] at found
      all_goals first
        | (split at found
           · cases found; simp [Context.attachments]
           · rename_i different
             obtain ⟨next, innerAt, rfl⟩ := Option.map_eq_some_iff.mp found
             simp only [Selection.prepend, Context.attachments, List.mem_cons, not_or]
             exact ⟨different, induction rest next smaller innerAt⟩)
        | (obtain ⟨next, innerAt, rfl⟩ := Option.map_eq_some_iff.mp found
           exact induction rest next smaller innerAt)

/-- Inject the whole computation into its saved context. Binding an injected
computation outside this context would lose handlers crossed during capture. -/
def inject (saved : Context signature algebra definitions input result) (computation : Program signature algebra definitions input) :
    Program signature algebra definitions result := saved.plug computation

theorem injection_respects_context_composition (inside : Context signature algebra definitions input middle)
    (outside : Context signature algebra definitions middle result) (computation : Program signature algebra definitions input) :
    inject (inside.append outside) computation = outside.plug (inject inside computation) :=
  Context.append_plug inside outside computation

end BoundaryV2.Generalized.Source

namespace BoundaryV2.Generalized.Target

structure Selection (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) (input output : TypeOf signature) where
  effect : signature.Effect
  mode : Mode
  identity : Id .attachment
  body : TypeOf signature
  answer : TypeOf signature
  captured : List (TypeOf signature)
  returned : Code signature algebra definitions (body :: captured) [] answer
  clauses : Clauses signature algebra definitions effect mode captured body answer
  environment : RuntimeEnvironment signature algebra definitions captured
  inside : Stack signature algebra definitions input body
  outside : Stack signature algebra definitions answer output

def Selection.whole (selected : Selection signature algebra definitions input output) : Stack signature algebra definitions input output :=
  selected.inside.append (.push (.handler selected.effect selected.mode selected.identity selected.returned selected.clauses selected.environment) selected.outside)

def Selection.prepend (frame : Frame signature algebra definitions first middle)
    (selected : Selection signature algebra definitions middle last) : Selection signature algebra definitions first last :=
  { selected with inside := .push frame selected.inside }

/-- Target selection inspects its own data frames. It does not call the source
selector or interpret a source context. -/
def select (wanted : Id .attachment) : Stack signature algebra definitions input output → Option (Selection signature algebra definitions input output)
  | .done => none
  | .push (.handler effect mode identity returned clauses environment) rest =>
    if wanted = identity then some ⟨effect, mode, identity, _, _, _, returned, clauses, environment, .done, rest⟩
    else (select wanted rest).map (Selection.prepend (.handler effect mode identity returned clauses environment))
  | .push frame rest => (select wanted rest).map (Selection.prepend frame)

end BoundaryV2.Generalized.Target
