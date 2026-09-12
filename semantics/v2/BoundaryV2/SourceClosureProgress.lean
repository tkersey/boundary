import BoundaryV2.SourceEntryProgress
import BoundaryV2.SourceCustodyBounds

namespace BoundaryV2.Profile.Source.Machine
namespace ClosureProgress

private theorem no_move (book : Custody.Book) : Custody.commit book [] = some book := by
  have unchanged : Custody.destination [] = id := by funext entry; rfl
  cases book
  simp [Custody.commit, Custody.admissible, Custody.relocate, unchanged]

theorem move_token_free (heap : Heap) (values : List Located) (owner : Nat → Custody.Owner)
    (free : ∀ value ∈ values, ownedTokens value.value = []) : moveValues heap values owner = some heap := by
  have empty : (values.mapIdx fun index value => value.moves (owner index)).flatten = [] := by
    apply List.flatten_eq_nil_iff.mpr
    intro moves member
    obtain ⟨index, found⟩ := List.mem_iff_getElem?.mp member
    rw [List.getElem?_mapIdx] at found
    obtain ⟨value, valueAt, rfl⟩ := Option.map_eq_some_iff.mp found
    simp [Located.moves, free value (List.mem_of_getElem? valueAt)]
  simp [moveValues, empty, no_move, bind, Option.bind, pure]

/-- Mathematical allocation has a fresh token and object on a bounded custody
book. It never needs a semantic execution horizon. -/
theorem allocate_fresh (heap : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (bounded : heap.CustodyBounded) :
    ∃ after value, allocateObject heap schema stored owner exclusive = some (after, value) ∧
      after.scopes = heap.scopes := by
  obtain ⟨⟨after, value⟩, allocated⟩ := Option.isSome_iff_exists.mp
    (bounded_custody_allocation_succeeds heap bounded schema stored owner exclusive)
  refine ⟨after, value, allocated, ?_⟩
  cases exclusive with
  | false => cases allocated; rfl
  | true =>
    obtain ⟨_, _, same⟩ := Option.bind_eq_some_iff.mp allocated
    cases same
    rfl

theorem makeClosureWithValues (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (scope : Scope)
    (scopeAt : machine.heap.scopes[machine.scope.value]? = some scope) (identity : scope.id = machine.scope)
    (bounded : machine.heap.CustodyBounded)
    (count : (Analysis.captures context.captures function).length = values.length)
    (types : ((Analysis.captures context.captures function).zip values).all
      (fun (binder, value) => context.source.variables[binder.value]? == some value.value.schema) = true)
    (free : ∀ value ∈ values, ownedTokens value.value = []) :
    ∃ after, Machine.makeClosureWithValues machine context schema function values = .ok after := by
  have scopeBound := (List.getElem?_eq_some_iff.mp scopeAt).1
  let middle : State := { machine with heap := { machine.heap with
    scopes := machine.heap.scopes.set machine.scope.value { scope with nextOwner := scope.nextOwner + 1 } } }
  let owner := Custody.Owner.temporary machine.scope scope.nextOwner
  have temporaryOk : temporary machine = .ok (middle, owner) := by
    simp [temporary, scopeAt, identity, middle, owner, pure, Except.pure]
  have middleBound : middle.heap.CustodyBounded := bounded
  have moved := move_token_free middle.heap values (Custody.Owner.closure ⟨middle.heap.objects.length⟩) free
  let captured := ((Analysis.captures context.captures function).zip values).mapIdx
    (fun index pair => Binding.mk pair.1 (retainAt pair.2 (.closure ⟨middle.heap.objects.length⟩ index)))
  obtain ⟨heap, result, allocated, scopes⟩ := allocate_fresh middle.heap schema (.closure schema function captured)
    owner (!Traits.check context.source.schemas .copy schema) middleBound
  dsimp only [captured] at allocated
  have finish : ∃ after, finishTemporary { middle with heap := heap } result = .ok after := by
    have scopeAt : heap.scopes[middle.scope.value]? = some { scope with nextOwner := scope.nextOwner + 1 } := by
      rw [scopes]
      exact List.getElem?_set_self scopeBound
    simp [finishTemporary, scopeAt, pure, Except.pure]
  simpa only [Machine.makeClosureWithValues, count, beq_self_eq_true, types, Bool.true_and, require,
    ↓reduceIte, temporaryOk, bind, Except.bind, moved, fromOption, allocated, pure, Except.pure]
    using finish

theorem collect_variables (bindings : Environment) (variables : List VariableId)
    (covered : LexicalCoverage.Covers bindings variables) :
    ∃ values, variables.mapM (fun binder => fromOption (lookupVariable bindings binder) .reference) = .ok values ∧
      variables.length = values.length ∧
      (∀ binder value, (binder, value) ∈ variables.zip values → lookupVariable bindings binder = some value) := by
  induction variables with
  | nil => exact ⟨[], rfl, rfl, by simp⟩
  | cons binder rest induction =>
    obtain ⟨value, valueAt⟩ := covered binder (by simp)
    obtain ⟨values, collected, count, lookups⟩ := induction (fun var member => covered var (by simp [member]))
    refine ⟨value :: values, ?_, by simp [count], ?_⟩
    · rw [List.mapM_cons, collected]
      simp [fromOption, valueAt, bind, Except.bind, pure, Except.pure]
    · intro var located member
      simp only [List.zip_cons_cons, List.mem_cons] at member
      rcases member with same | member
      · cases same; exact valueAt
      · exact lookups _ _ member

private theorem lambda_signature (context : Context) (function : FunctionId .source) (schema : SchemaId .source)
    (accepted : Admission.lambdaValid context.source context.captures function schema = true) :
    ∃ signature, context.source.schemas[schema.value]? = some (.internal (.computation signature)) := by
  cases found : context.source.schemas[schema.value]? with
  | none => simp [Admission.lambdaValid, found] at accepted
  | some shape =>
    cases shape <;> try solve | simp [Admission.lambdaValid, found] at accepted
    rename_i inner
    cases inner <;> first
    | exact ⟨_, rfl⟩
    | simp [Admission.lambdaValid, found] at accepted

/-- All captures of a copyable lambda are themselves copyable, by the checked
source interface. Reachability supplies their bindings and runtime shapes. -/
theorem reachable_copy_lambda (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (reference : SourceValueId) (bindings : Environment)
    (schema : SchemaId .source) (function : FunctionId .source)
    (executing : machine.control = .expression reference bindings)
    (found : context.source.values[reference.value]? = some ⟨schema, .lambda function⟩)
    (copy : Traits.check context.source.schemas .copy schema = true)
    (running : machine.status = .running) : ∃ after, tick machine context = .ok after := by
  have typed : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  have admitted : Admission.lambdaValid context.source context.captures function schema = true := by
    simpa only [Admission.primitiveValid] using checked_context_checks_value context reference _ typed found
  obtain ⟨signature, signatureAt⟩ := lambda_signature _ _ _ admitted
  have allCovered := (LexicalCoverage.initialized_execution_preserves_lexical_coverage _ _ _ _ _ initialized steps).1
  have site : LexicalCoverage.SiteValid context (.value reference) bindings := by
    simpa only [LexicalCoverage.ControlValid, executing] using allCovered
  have covered : LexicalCoverage.Covers bindings (Analysis.captures context.captures function) := by
    intro var member
    apply site.2 var
    exact LexicalCoverage.dependency_variables context.source context.captures
      (LexicalCoverage.checked_capture_analysis _ typed) (.value reference) ⟨.function function, []⟩
      (by simp [Analysis.dependencies, found]) var member (by simp)
  obtain ⟨values, collected, count, lookups⟩ := collect_variables bindings _ covered
  have envTypes : Environment.Types context.source bindings := by
    simpa only [EnvironmentInventory.control, executing] using EnvironmentInventory.control_types _ _
      (EnvironmentInventory.initialized_execution_preserves_environment_types _ _ _ _ _ initialized steps)
  have valuesTyped := initialized_execution_preserves_value_shapes _ _ _ _ _ initialized steps
  have captureTypes : ((Analysis.captures context.captures function).zip values).all
      (fun (binder, value) => context.source.variables[binder.value]? == some value.value.schema) = true := by
    apply List.all_eq_true.mpr
    rintro ⟨binder, value⟩ member
    exact beq_iff_eq.mpr (envTypes.lookup _ _ (lookups _ _ member))
  have free : ∀ value ∈ values, ownedTokens value.value = [] := by
    intro value member
    obtain ⟨index, valueAt⟩ := List.mem_iff_getElem?.mp member
    have bounded : index < (Analysis.captures context.captures function).length :=
      count ▸ (List.getElem?_eq_some_iff.mp valueAt).1
    let binder := (Analysis.captures context.captures function)[index]
    have binderAt : (Analysis.captures context.captures function)[index]? = some binder :=
      List.getElem?_eq_getElem bounded
    have pairMember : (binder, value) ∈ (Analysis.captures context.captures function).zip values :=
      List.mem_iff_getElem?.mpr ⟨index, List.getElem?_zip_eq_some.mpr ⟨binderAt, valueAt⟩⟩
    have lookup := lookups binder value pairMember
    have safe := Admission.lambda_capture_trait_safe context.source context.captures function schema signature
      binder value.value.schema .copy admitted signatureAt (Traits.check_sound _ _ _ copy)
      (List.mem_of_getElem? binderAt) (envTypes.lookup _ _ lookup)
    apply copy_value_has_no_tokens _ _ ?_ safe
    apply lookupVariable_preserves_all bindings binder value lookup
    intro binding bindingMember
    apply valuesTyped
    simp only [ValueInventory.state, executing, ValueInventory.control, ValueInventory.environment,
      List.mem_append, List.mem_map]
    exact Or.inl (Or.inl (Or.inl ⟨binding, bindingMember, rfl⟩))
  obtain ⟨scope, scopeAt, identity⟩ :=
    (IdentitySupport.initialized_execution_has_current_records _ _ _ _ _ initialized steps).1
  have constructed := makeClosureWithValues machine context schema function values scope scopeAt identity
    (source_trajectory_custody_bounds _ _ _ _ initialized steps) count captureTypes free
  simp only [tick, running, tickRunning, executing, enterExpression, found]
  change ∃ after, Machine.makeClosure machine context schema function bindings = .ok after
  simpa only [Machine.makeClosure, collected, bind, Except.bind] using constructed

end ClosureProgress
end BoundaryV2.Profile.Source.Machine
