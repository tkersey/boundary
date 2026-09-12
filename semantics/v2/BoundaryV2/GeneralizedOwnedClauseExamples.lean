import BoundaryV2.GeneralizedOwnedClause
import BoundaryV2.GeneralizedObservationExamples

namespace BoundaryV2.Generalized.Examples

local instance : DecidableEq (signature.operation .choose) := fun first second => by
  cases first
  cases second
  exact isTrue rfl

def effectfulOwnedClause : Source.SelectedClause signature algebra [] Operation.choice .shallow
    [.capability .text, .leaf .boolean] (.leaf .boolean) (.leaf .text) :=
  ⟨.affine, Source.Computation.perform (signature := signature) (algebra := algebra)
    Operation.text (.reference (.there (.there .here)))
    (.reference (.there (.there (.there .here)))) .nil⟩

def effectfulOwnedClauses : Source.Clauses signature algebra [] .choose .shallow
    [.capability .text, .leaf .boolean] (.leaf .boolean) (.leaf .text) :=
  .cons Operation.choice .affine effectfulOwnedClause.code .nil

def distinctNormalReturn : Source.Computation signature algebra []
    [.leaf .boolean, .capability .text, .leaf .boolean] (.leaf .text) :=
  .returnValue (.datum (.leaf "normal-return-only"))

def capturedOwners : List UseScope.Field :=
  [.owned ⟨10⟩ (.lexical ⟨1⟩ 0), .owned ⟨11⟩ (.lexical ⟨1⟩ 1)]

def beforeOwnedDispatch : UseScope.State := ⟨capturedOwners ++ [.alias ⟨50⟩], [], []⟩

def sourceBeforeOwnedDispatch : UseScope.ControlStore
    (Source.Resumption signature algebra [] .shallow .choose (.leaf .boolean) (.leaf .boolean)) :=
  ⟨beforeOwnedDispatch, [], []⟩

def targetBeforeOwnedDispatch : UseScope.ControlStore
    (Target.Resumption signature algebra [] .shallow .choose (.leaf .boolean) (.leaf .boolean)) :=
  ⟨beforeOwnedDispatch, [], []⟩

def sourceOwnedDispatch := Source.dispatchOwnedClause (signature := signature) (algebra := algebra)
  Operation.choice ⟨8⟩ distinctNormalReturn effectfulOwnedClauses textBindings .done (.datum .unit) .nil .done
  (.lexical ⟨2⟩ 0) [] capturedOwners [.alias ⟨50⟩] sourceBeforeOwnedDispatch rfl

def targetOwnedDispatch := Target.dispatchOwnedClause (signature := signature) (algebra := algebra)
  Operation.choice ⟨8⟩ (Defunctionalization.computation distinctNormalReturn)
  (Defunctionalization.clauses effectfulOwnedClauses) (Defunctionalization.environment textBindings)
  .done (.datum .unit) .nil .done (.lexical ⟨2⟩ 0) [] capturedOwners [.alias ⟨50⟩] targetBeforeOwnedDispatch rfl

def ownedClauseBindings : Source.RuntimeEnvironment signature algebra []
    [.continuation .shallow .affine .choose (.leaf .boolean) (.leaf .boolean), .unit, .capability .text, .leaf .boolean] :=
  .cons (.continuation ⟨0⟩ (some (⟨51⟩, .lexical ⟨2⟩ 0))) (.cons (.datum .unit) textBindings)

theorem owned_dispatch_preserves_source_and_target_entry :
    Option.Rel Defunctionalization.OwnedClauseRelated sourceOwnedDispatch targetOwnedDispatch := by
  exact Defunctionalization.owned_clause_dispatch_corresponds (signature := signature) (algebra := algebra)
    Operation.choice ⟨8⟩ distinctNormalReturn
    effectfulOwnedClauses textBindings .done (.datum .unit) .nil .done (.lexical ⟨2⟩ 0) [] capturedOwners [.alias ⟨50⟩]
    (sourceStore := sourceBeforeOwnedDispatch) (targetStore := targetBeforeOwnedDispatch) ⟨rfl, .nil, .nil⟩ rfl rfl

theorem owned_dispatch_moves_two_owners_and_avoids_old_alias :
    (targetOwnedDispatch.map fun selected =>
      (selected.view, selected.store.fields.active, selected.store.fields.retained)) =
      some (⟨⟨0⟩, ⟨51⟩, .lexical ⟨2⟩ 0⟩,
        [.owned ⟨51⟩ (.lexical ⟨2⟩ 0), .alias ⟨50⟩], [.continuation ⟨0⟩ capturedOwners]) := rfl

theorem source_dispatched_clause_performs_its_own_effect :
    ∃ selected, sourceOwnedDispatch = some selected ∧
      Source.Steps .nil selected.computation 1 (.request Operation.text ⟨4⟩ (.datum (.leaf true)) .nil .done) := by
  refine ⟨_, rfl, ?_⟩
  exact .single (.perform rfl rfl rfl)

/-- The selected operation clause executes its ordinary compiled code. It opens
the captured text effect; it does not run the unrelated normal-return clause. -/
theorem target_dispatched_clause_performs_its_own_effect :
    ∃ selected count, targetOwnedDispatch = some selected ∧ Target.CallSteps .nil selected.configuration count
      (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil
        (.push (.returnTo .ret (Defunctionalization.environment ownedClauseBindings) .nil) .done)) := by
  obtain ⟨count, _, steps⟩ := Defunctionalization.compiled_operation_opens_typed_future
    (signature := signature) (algebra := algebra) .nil Operation.text
    (.reference (.there (.there .here))) (.reference (.there (.there (.there .here)))) .nil
    ownedClauseBindings ⟨4⟩ (.datum (.leaf true)) .nil rfl rfl rfl .done
  exact ⟨_, count, rfl, steps⟩

theorem freshly_created_owned_future_is_resumable_once :
    ∃ selected acquired, targetOwnedDispatch = some selected ∧
      UseScope.acquire selected.view selected.store = some acquired ∧
      acquired.future.future = (.done : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .boolean)) ∧
      acquired.store.fields.active = capturedOwners ++ [.alias ⟨50⟩] ∧
      UseScope.acquire selected.view acquired.store = none := by
  exact ⟨_, _, rfl, rfl, rfl, rfl, rfl⟩

end BoundaryV2.Generalized.Examples
