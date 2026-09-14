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

theorem select_after_no_match (wanted : Id .attachment)
    (before : Context signature algebra definitions input middle) (after : Context signature algebra definitions middle output)
    (absent : select wanted before = none) :
    select wanted (before.append after) =
      (select wanted after).map (fun selected => { selected with inside := before.append selected.inside }) := by
  suffices ∀ bound {input middle} (before : Context signature algebra definitions input middle), before.length ≤ bound →
      ∀ (after : Context signature algebra definitions middle output), select wanted before = none →
      select wanted (before.append after) =
        (select wanted after).map (fun selected => { selected with inside := before.append selected.inside }) from
    this before.length before (Nat.le_refl _) after absent
  intro bound
  induction bound with
  | zero =>
    intro input middle before bounded after absent
    cases before with
    | done => simp only [Context.append]; cases select wanted after <;> rfl
    | push frame rest => simp [Context.length] at bounded
  | succ bound induction =>
    intro input middle before bounded after absent
    cases before with
    | done => simp only [Context.append]; cases select wanted after <;> rfl
    | push frame rest =>
      have smaller : rest.length ≤ bound := by simpa [Context.length] using bounded
      cases frame <;> simp only [select] at absent
      all_goals first
        | (split at absent
           · contradiction
           · rename_i different
             have tail := Option.map_eq_none_iff.mp absent
             simp only [Context.append, select, if_neg different, induction rest smaller after tail, Option.map_map]
             rfl)
        | (have tail := Option.map_eq_none_iff.mp absent
           simp only [Context.append, select, induction rest smaller after tail, Option.map_map]
           rfl)

/-- The source prefix guard selects this delimiter with its complete captured
context, whether that prefix was saved with a request or surrounds its syntax. -/
theorem matching_delimiter_after_prefix (attachment : Id .attachment)
    (inside : Context signature algebra definitions input body)
    (effect : signature.Effect) (mode : Mode)
    (returned : Computation signature algebra definitions (body :: context) answer)
    (clauses : Clauses signature algebra definitions effect mode context body answer)
    (bindings : RuntimeEnvironment signature algebra definitions context)
    (outside : Context signature algebra definitions answer output)
    (absent : select attachment inside = none) :
    select attachment (inside.append (.push (.handler effect mode attachment returned clauses bindings) outside)) =
      some ⟨effect, mode, attachment, body, answer, context, returned, clauses, bindings, inside, outside⟩ := by
  rw [select_after_no_match _ _ _ absent]
  simp [select, Context.append_done]

theorem select_none_of_absent (future : Context signature algebra definitions input result)
    (absent : wanted ∉ future.attachments) : select wanted future = none := by
  suffices ∀ bound {input result} (future : Context signature algebra definitions input result),
      future.length ≤ bound → wanted ∉ future.attachments → select wanted future = none from
    this future.length future (Nat.le_refl _) absent
  intro bound
  induction bound with
  | zero =>
    intro input result future bounded absent
    cases future with
    | done => rfl
    | push frame rest => simp [Context.length] at bounded
  | succ bound induction =>
    intro input result future bounded absent
    cases future with
    | done => rfl
    | push frame rest =>
      have smaller : rest.length ≤ bound := by simpa [Context.length] using bounded
      cases frame <;> simp only [Context.attachments, List.mem_cons, not_or] at absent
      all_goals first
        | (simp only [select, if_neg absent.1, induction rest smaller absent.2, Option.map_none])
        | (simp only [select, induction rest smaller absent, Option.map_none])

theorem selection_inside_has_no_match
    (future : Context signature algebra definitions input result) (wanted : Id .attachment)
    (selected : Selection signature algebra definitions input result)
    (found : select wanted future = some selected) : select wanted selected.inside = none :=
  select_none_of_absent selected.inside (selection_is_nearest future wanted selected found)

end BoundaryV2.Generalized.Source

namespace BoundaryV2.Generalized.Target

def Stack.length : Stack signature algebra definitions input output → Nat
  | .done => 0
  | .push _ rest => rest.length + 1

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

theorem select_after_no_match (wanted : Id .attachment)
    (before : Stack signature algebra definitions input middle) (after : Stack signature algebra definitions middle output)
    (absent : select wanted before = none) :
    select wanted (before.append after) =
      (select wanted after).map (fun selected => { selected with inside := before.append selected.inside }) := by
  induction before with
  | done =>
    simp only [Stack.append]
    cases select wanted after <;> rfl
  | push frame rest induction =>
    cases frame <;> simp only [select] at absent
    all_goals first
      | (split at absent
         · contradiction
         · rename_i different
           have tail := Option.map_eq_none_iff.mp absent
           simp only [Stack.append, select, if_neg different, induction after tail, Option.map_map]
           rfl)
      | (have tail := Option.map_eq_none_iff.mp absent
         simp only [Stack.append, select, induction after tail, Option.map_map]
         rfl)

/-- The operational prefix guard implies that the actual target selector picks
this delimiter and retains the entire prefix as its captured inside context. -/
theorem matching_delimiter_after_prefix (attachment : Id .attachment)
    (inside : Stack signature algebra definitions input body)
    (effect : signature.Effect) (mode : Mode)
    (returned : Code signature algebra definitions (body :: context) [] answer)
    (clauses : Clauses signature algebra definitions effect mode context body answer)
    (bindings : RuntimeEnvironment signature algebra definitions context)
    (outside : Stack signature algebra definitions answer output)
    (absent : select attachment inside = none) :
    select attachment (inside.append (.push (.handler effect mode attachment returned clauses bindings) outside)) =
      some ⟨effect, mode, attachment, body, answer, context, returned, clauses, bindings, inside, outside⟩ := by
  rw [select_after_no_match _ _ _ absent]
  simp [select, Stack.append_done]

theorem selection_reconstructs (context : Stack signature algebra definitions input output) (wanted : Id .attachment)
    (selected : Selection signature algebra definitions input output) (found : select wanted context = some selected) : selected.whole = context := by
  suffices ∀ (n : Nat) {input output} (context : Stack signature algebra definitions input output)
      (selected : Selection signature algebra definitions input output), context.length ≤ n →
      select wanted context = some selected → selected.whole = context from
    this context.length context selected (Nat.le_refl _) found
  intro n
  induction n with
  | zero =>
    intro input output context selected bounded found
    cases context with
    | done => contradiction
    | push frame rest => simp [Stack.length] at bounded
  | succ n induction =>
    intro input output context selected bounded found
    cases context with
    | done => contradiction
    | push frame rest =>
      have smaller : rest.length ≤ n := by simpa [Stack.length] using bounded
      cases frame <;> simp only [select] at found
      all_goals first
        | (split at found
           · cases found; rfl
           · obtain ⟨next, innerAt, rfl⟩ := Option.map_eq_some_iff.mp found
             exact congrArg (Stack.push _) (induction rest next smaller innerAt))
        | (obtain ⟨next, innerAt, rfl⟩ := Option.map_eq_some_iff.mp found
           exact congrArg (Stack.push _) (induction rest next smaller innerAt))

end BoundaryV2.Generalized.Target
