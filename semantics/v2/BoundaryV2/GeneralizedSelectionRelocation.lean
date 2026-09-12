import BoundaryV2.GeneralizedExecutionRelocation

namespace BoundaryV2.Generalized.Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

def Stack.attachments : Stack signature algebra program input result → List (Id .attachment)
  | .done => []
  | .push (.handler _ _ attachment _ _ _) rest => attachment :: rest.attachments
  | .push _ rest => rest.attachments

private theorem attachment_survives_push (frame : Frame signature algebra program input middle)
    (rest : Stack signature algebra program middle result) (member : identity ∈ rest.attachments) :
    identity ∈ (Stack.push frame rest).attachments := by
  cases frame <;> simp only [Stack.attachments]
  all_goals first | exact member | exact List.mem_cons_of_mem _ member

def Selection.relocate (relocation : UseScope.Relocation) (selected : Selection signature algebra program input result) :
    Selection signature algebra program input result :=
  ⟨selected.effect, selected.mode, relocation.name .attachment selected.identity, selected.body, selected.answer,
    selected.captured, selected.returned.relocate relocation, selected.clauses.relocate relocation,
    relocateEnvironment relocation selected.environment, selected.inside.relocate relocation, selected.outside.relocate relocation⟩

/-- Injectivity is needed only on the requested name and the actual delimiter
names in this finite stack. Unused natural numbers are outside the premise. -/
theorem selection_relocation (relocation : UseScope.Relocation) (wanted : Id .attachment)
    (future : Stack signature algebra program input result)
    (injective : ∀ first ∈ wanted :: future.attachments, ∀ second ∈ wanted :: future.attachments,
      relocation.name .attachment first = relocation.name .attachment second → first = second) :
    select (relocation.name .attachment wanted) (future.relocate relocation) =
      (select wanted future).map (Selection.relocate relocation) := by
  induction future with
  | done => rfl
  | @push input middle output frame rest induction =>
    have included : ∀ identity ∈ wanted :: rest.attachments, identity ∈ wanted :: (Stack.push frame rest).attachments := by
      intro identity member
      rcases List.mem_cons.mp member with rfl | tail
      · exact List.mem_cons_self
      · exact List.mem_cons_of_mem _ (attachment_survives_push frame rest tail)
    have tail := induction (fun first firstAt second secondAt same =>
      injective first (included first firstAt) second (included second secondAt) same)
    cases frame with
    | returnTo next bindings values | region identity | protection identity cleanup bindings =>
      simp only [Stack.relocate, Frame.relocate, select, tail, Option.map_map]
      rfl
    | handler effect mode identity returned clauses bindings =>
      by_cases same : wanted = identity
      · subst identity
        simp only [Stack.relocate, Frame.relocate, select, ite_true, Option.map_some]
        rfl
      · have different : relocation.name .attachment wanted ≠ relocation.name .attachment identity := by
          intro equal
          apply same
          exact injective wanted List.mem_cons_self identity (by simp [Stack.attachments]) equal
        simp only [Stack.relocate, Frame.relocate, select, if_neg same, if_neg different, tail, Option.map_map]
        rfl

theorem fresh_selection_relocation (support locals : ∀ domain, List (Id domain)) (owner : Owner → Owner)
    (wanted : Id .attachment) (future : Stack signature algebra program input result)
    (supported : ∀ identity ∈ wanted :: future.attachments, identity ∈ support .attachment) :
    select ((UseScope.freshRelocation support locals owner).name .attachment wanted)
        (future.relocate (UseScope.freshRelocation support locals owner)) =
      (select wanted future).map (Selection.relocate (UseScope.freshRelocation support locals owner)) := by
  apply selection_relocation
  intro first firstAt second secondAt same
  exact FreshNames.injective_on_support (supported first firstAt) (supported second secondAt) same

end BoundaryV2.Generalized.Target
