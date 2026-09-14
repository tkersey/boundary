import BoundaryV2.GeneralizedFiniteReflection
import BoundaryV2.GeneralizedRegisteredSimulation

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

namespace Target.Multi

theorem Step.core_of_noncode
    {table : Target.Definitions signature algebra program}
    {before after : Runtime signature algebra program result}
    (step : Step table before after) (noncode : before.control.configuration.codeConstructor = none) :
    ∃ state, Target.ExecutionStep table before.state state before.executionSupport ∧ after = before.withState state := by
  cases step with
  | core actual => exact ⟨_, actual, rfl⟩
  | resume entry => cases entry <;> cases noncode
  | clone atCode accepted => rw [atCode] at noncode; cases noncode

/-- Registered control receivers cannot replace an ordinary operand or caller
instruction. The actual successor stays in this runtime with current storage. -/
theorem Step.ordinary_result
    {table : Target.Definitions signature algebra program}
    {before after : Runtime signature algebra program result}
    (step : Step table before after)
    (expected : Target.CallStep table before.control.configuration next)
    (neutral : before.control.configuration.needsOwnershipStep = false) :
    after = before.withState ⟨⟨before.control.store, next⟩, before.arena.cells, before.regions⟩ := by
  cases step with
  | core actual => rw [actual.ordinary_result expected neutral]; rfl
  | resume actual =>
    obtain ⟨attachment, computed⟩ := expected.computes_next
    cases actual <;> cases computed
  | clone atCode accepted =>
    obtain ⟨attachment, computed⟩ := expected.computes_next
    rw [atCode] at computed
    cases computed

theorem Step.core_of_close_view
    {table : Target.Definitions signature algebra program}
    {before after : Runtime signature algebra program result}
    (step : Step table before after)
    (viewed : before.control.configuration.closeView = some view) :
    ∃ state, Target.ExecutionStep table before.state state before.executionSupport ∧ after = before.withState state := by
  cases step with
  | core actual => exact ⟨_, actual, rfl⟩
  | resume actual => cases actual <;> cases viewed
  | clone atCode accepted => rw [atCode] at viewed; cases viewed

/-- Instantiate the shared prefix proof from actual registered transitions.
Registry and dormant/active roots remain fixed during these operand steps. -/
theorem operand_trace_laws (table : Target.Definitions signature algebra program)
    (runtime final : Runtime signature algebra program result)
    (observation : Target.Observation signature algebra program result) :
    Target.OperandTraceLaws table runtime.executionSupport (fun before count =>
      Steps table (runtime.withState before) count final ∧ Target.HeadObservation final.control.configuration observation) := by
  constructor
  · intro before count next expected neutral observed
    obtain ⟨run, head⟩ := observed
    cases run with
    | refl => exact False.elim (head.no_step table expected)
    | cons step tail =>
      rw [step.ordinary_result expected neutral] at tail
      exact ⟨_, rfl, tail, head⟩
  · intro before count view viewed observed
    obtain ⟨run, head⟩ := observed
    cases run with
    | refl =>
      change Target.HeadObservation before.control.configuration observation at head
      rw [head.close_view_none] at viewed
      cases viewed
    | cons step tail =>
      obtain ⟨state, actual, afterAt⟩ := step.core_of_close_view viewed
      rw [afterAt] at tail
      exact ⟨_, state, rfl, actual, tail, head⟩

theorem ordinary_cancel_observed
    {table : Target.Definitions signature algebra program}
    {before final : Runtime signature algebra program result}
    (expected : Target.CallStep table before.control.configuration next)
    (neutral : before.control.configuration.needsOwnershipStep = false)
    (run : Steps table before count final) (head : Target.HeadObservation final.control.configuration observation) :
    ∃ remaining, count = remaining + 1 ∧
      Steps table (before.withState ⟨⟨before.control.store, next⟩, before.arena.cells, before.regions⟩) remaining final := by
  cases run with
  | refl => exact False.elim (head.no_step table expected)
  | cons actual tail =>
    rw [actual.ordinary_result expected neutral] at tail
    exact ⟨_, rfl, tail⟩

theorem Steps.returned_done
    {table : Target.Definitions signature algebra program}
    (value : Target.RuntimeValue signature algebra program result)
    (store : Target.ControlHeap signature algebra program) (arena : Arena signature algebra program)
    (regions : List (Id .region)) (registry : Registry signature algebra program)
    (run : Steps table ⟨⟨store, .returned value .done⟩, arena, regions, registry⟩ count final) :
    final = ⟨⟨store, .returned value .done⟩, arena, regions, registry⟩ := by
  cases run with
  | refl => rfl
  | cons step tail =>
    obtain ⟨after, actual, _⟩ := step.core_of_noncode rfl
    have ordinary := (actual.returned_is_ordinary _ _ _ _ _).2.2.2
    cases ordinary

theorem Steps.failed_done
    {table : Target.Definitions signature algebra program}
    (fault : algebra.Fault) (result : TypeOf signature)
    (store : Target.ControlHeap signature algebra program) (arena : Arena signature algebra program)
    (regions : List (Id .region)) (registry : Registry signature algebra program)
    {final : Runtime signature algebra program result}
    (run : Steps table ⟨⟨store, .failed fault .done⟩, arena, regions, registry⟩ count final) :
    final = ⟨⟨store, .failed fault .done⟩, arena, regions, registry⟩ := by
  cases run with
  | refl => rfl
  | cons step tail =>
    obtain ⟨after, actual, _⟩ := step.core_of_noncode rfl
    have ordinary := (actual.failed_is_ordinary _ _ _ _ _).2.2.2
    cases ordinary

omit [DecidableEq (TypeOf signature)] in
theorem resume_entry_inverts
    {table : Target.Definitions signature algebra program}
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (values : Target.RuntimeEnvironment signature algebra program operands)
    (next : Target.Code signature algebra program context (answer :: operands) input)
    (outside : Target.Stack signature algebra program input result)
    (store : Target.ControlHeap signature algebra program) (arena : Arena signature algebra program)
    (regions : List (Id .region)) (registry : Registry signature algebra program)
    (mode : Mode) (effect : signature.Effect) (use : Use) (identity : Id .control)
    (authority : Option (Id .custody × Owner)) (response : Target.RuntimeValue signature algebra program responseType)
    (entry : ResumeEntry table
      ⟨⟨store, .code (.resume (mode := mode) (effect := effect) (use := use) next) bindings
        (.cons response (.cons (.continuation identity authority) values)) outside⟩, arena, regions, registry⟩ after) :
    use = .multi ∧ authority = none ∧
      Runtime.resume ⟨mode, effect, responseType, answer⟩ identity
        ⟨⟨store, .code (.resume (mode := mode) (effect := effect) (use := use) next) bindings
          (.cons response (.cons (.continuation identity authority) values)) outside⟩, arena, regions, registry⟩ response
        (.push (.returnTo next bindings values) outside) (callSupport table bindings values next outside store) = some after := by
  generalize atCode : Target.Configuration.code (.resume (mode := mode) (effect := effect) (use := use) next) bindings
    (.cons response (.cons (.continuation identity authority) values)) outside = initial at entry
  have tag := congrArg Target.Configuration.codeConstructor atCode
  cases entry with
  | enter accepted => cases atCode; exact ⟨rfl, rfl, accepted⟩
  | injection | successor => cases tag

omit [DecidableEq (TypeOf signature)] in
theorem ResumeEntry.has_nonowning_view
    {table : Target.Definitions signature algebra program}
    {before after : Runtime signature algebra program result}
    (entry : ResumeEntry table before after) : before.control.configuration.missingControlGrant = true := by
  cases entry <;> rfl

omit [DecidableEq (TypeOf signature)] in
theorem injection_entry_inverts
    {table : Target.Definitions signature algebra program}
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (values : Target.RuntimeEnvironment signature algebra program operands)
    (next : Target.Code signature algebra program context (answer :: operands) input)
    (outside : Target.Stack signature algebra program input result)
    (store : Target.ControlHeap signature algebra program) (arena : Arena signature algebra program)
    (regions : List (Id .region)) (registry : Registry signature algebra program)
    (mode : Mode) (effect : signature.Effect) (use bodyUse : Use) (identity : Id .control)
    (authority : Option (Id .custody × Owner))
    (body : Target.Code signature algebra program capturedTypes [] responseType)
    (captured : Target.RuntimeEnvironment signature algebra program capturedTypes)
    (bodyAuthority : Option (Id .custody × Owner))
    (entry : ResumeEntry table
      ⟨⟨store, .code (.inject (mode := mode) (effect := effect) (use := use) (useBody := bodyUse) next) bindings
        (.cons (.closure body captured bodyAuthority) (.cons (.continuation identity authority) values)) outside⟩,
        arena, regions, registry⟩ after) :
    use = .multi ∧ authority = none ∧ ∃ fields,
      ComputationHandoff captured bodyUse bodyAuthority store.fields fields ∧
      Runtime.inject ⟨mode, effect, responseType, answer⟩ identity
        ⟨⟨{ store with fields := fields }, .code (.inject (mode := mode) (effect := effect) (use := use) (useBody := bodyUse) next)
          bindings (.cons (.closure body captured bodyAuthority) (.cons (.continuation identity authority) values)) outside⟩,
          arena, regions, registry⟩ ⟨capturedTypes, body, captured⟩ (.push (.returnTo next bindings values) outside)
        (callSupport table bindings values next outside { store with fields := fields }) = some after := by
  generalize atCode : Target.Configuration.code (.inject (mode := mode) (effect := effect) (use := use) (useBody := bodyUse) next)
    bindings (.cons (.closure body captured bodyAuthority) (.cons (.continuation identity authority) values)) outside = initial at entry
  have tag := congrArg Target.Configuration.codeConstructor atCode
  cases entry with
  | injection handoff accepted => cases atCode; exact ⟨rfl, rfl, _, handoff, accepted⟩
  | enter | successor => cases tag

omit [DecidableEq (TypeOf signature)] in
theorem successor_entry_inverts
    {table : Target.Definitions signature algebra program}
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (values : Target.RuntimeEnvironment signature algebra program operands)
    (next : Target.Code signature algebra program context (answer :: operands) input)
    (outside : Target.Stack signature algebra program input result)
    (store : Target.ControlHeap signature algebra program) (arena : Arena signature algebra program)
    (regions : List (Id .region)) (registry : Registry signature algebra program)
    (effect : signature.Effect) (use : Use) (identity : Id .control)
    (authority : Option (Id .custody × Owner)) (response : Target.RuntimeValue signature algebra program responseType)
    (returned : Target.Code signature algebra program (body :: context) [] answer)
    (clauses : Target.Clauses signature algebra program effect .deep context body answer)
    (entry : ResumeEntry table
      ⟨⟨store, .code (.replaceHandler (use := use) effect returned clauses next) bindings
        (.cons response (.cons (.continuation identity authority) values)) outside⟩, arena, regions, registry⟩ after) :
    use = .multi ∧ authority = none ∧
      Runtime.successor identity
        ⟨⟨store, .code (.replaceHandler (use := use) effect returned clauses next) bindings
          (.cons response (.cons (.continuation identity authority) values)) outside⟩, arena, regions, registry⟩ response
        returned clauses bindings (.push (.returnTo next bindings values) outside)
        (callSupport table bindings values next outside store) = some after := by
  generalize atCode : Target.Configuration.code (.replaceHandler (use := use) effect returned clauses next) bindings
    (.cons response (.cons (.continuation identity authority) values)) outside = initial at entry
  have tag := congrArg Target.Configuration.codeConstructor atCode
  cases entry with
  | successor accepted => cases atCode; exact ⟨rfl, rfl, accepted⟩
  | enter | injection => cases tag

theorem clone_step_inverts
    {table : Target.Definitions signature algebra program}
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (values : Target.RuntimeEnvironment signature algebra program operands)
    (next : Target.Code signature algebra program context (.continuation mode .multi effect input answer :: operands) valueType)
    (outside : Target.Stack signature algebra program valueType result)
    (store : Target.ControlHeap signature algebra program) (arena : Arena signature algebra program)
    (regions : List (Id .region)) (registry : Registry signature algebra program)
    (use : Use) (identity : Id .control) (authority : Option (Id .custody × Owner))
    (step : Step table
      ⟨⟨store, .code (.clone (mode := mode) (effect := effect) (use := use) next) bindings
        (.cons (.continuation identity authority) values) outside⟩, arena, regions, registry⟩ after) :
    ∃ (oneShot : UseScope.OneShotUse), ∃ token owner partition frozen registered,
      use = oneShot.type ∧ authority = some (token, owner) ∧
      freezeInto ⟨mode, effect, input, answer⟩ ⟨identity, token, owner⟩ store arena partition registry = some (frozen, registered) ∧
      after = ⟨⟨frozen.store, .code next bindings (.cons frozen.value values) outside⟩, frozen.arena,
        regions.filter (fun region => !partition.regions.contains region), registered⟩ := by
  generalize atCode : Target.Configuration.code (.clone (mode := mode) (effect := effect) (use := use) next) bindings
    (.cons (.continuation identity authority) values) outside = initial at step
  have tag := congrArg Target.Configuration.codeConstructor atCode
  cases step with
  | core actual =>
    have unavailable := actual.uses_current_driver.1
    change initial.separateDriver = false at unavailable
    rw [← atCode] at unavailable
    cases unavailable
  | resume entry => cases entry <;> cases tag
  | @clone context mode effect input answer operands valueType result view partition registered use next bindings values outside before frozen actual accepted =>
    dsimp only at actual accepted
    rw [actual] at atCode
    cases view
    cases atCode
    exact ⟨use, _, _, partition, frozen, registered, rfl, rfl, accepted, rfl⟩

end Target.Multi

namespace Defunctionalization

theorem registered_requested_step_reflected
    (table : Source.Definitions signature algebra program)
    (operation : signature.operation effect) (attachment : Id .attachment)
    (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (saved : Source.Context signature algebra program (signature.result operation) input)
    (around : Source.Context signature algebra program input result)
    (targetFuture : Target.Stack signature algebra program (signature.result operation) result)
    (future : ContextRelated signature algebra program (saved.append around) targetFuture)
    (arena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (step : Target.Multi.Step (definitions table)
      ⟨⟨targetStore, .requested operation attachment (value payload) (environment bodies) targetFuture⟩,
        templateArena arena, regions, templateRegistry registry⟩ after) :
    ∃ sourceAfter, Source.Multi.Step table
      ⟨⟨sourceStore, around.plug (.request operation attachment payload bodies saved)⟩, arena, regions, registry⟩ sourceAfter ∧
      MultiRuntimeRelated sourceAfter after := by
  obtain ⟨targetState, actual, afterAt⟩ := step.core_of_noncode rfl
  change Target.ExecutionStep (retained := Target.Multi.retainedSupport (templateRegistry registry) (templateArena arena))
    (definitions table) _ _ at actual
  rw [retained_support_corresponds] at actual
  obtain ⟨sourceState, sourceStep, matching⟩ := requested_state_step_reflected table operation attachment payload bodies
    saved around targetFuture future arena.cells regions stores actual
  have joined : MultiDataRelated
      (⟨⟨sourceStore, around.plug (.request operation attachment payload bodies saved)⟩, arena, regions, registry⟩ :
        Source.Multi.Runtime signature algebra program result)
      (⟨⟨targetStore, .requested operation attachment (value payload) (environment bodies) targetFuture⟩,
        templateArena arena, regions, templateRegistry registry⟩ : Target.Multi.Runtime signature algebra program result) :=
    ⟨stores, rfl, rfl, rfl⟩
  rw [afterAt]
  exact ⟨_, .core sourceStep, joined.writeback matching⟩

omit [DecidableEq (TypeOf signature)] in
theorem registered_resumption_receiver_reflected
    (table : Source.Definitions signature algebra program)
    (continuation : Source.Expression signature algebra program context (.continuation mode use effect input answer))
    (response : Source.Expression signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (identity : Id .control) (authority : Option (Id .custody × Owner))
    (inputValue : Source.RuntimeValue signature algebra program input)
    (arena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program)
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings
      (arena.cells.reservations.withSupport (Source.Multi.retainedSupport registry arena)).custody sourceStore
      (.cons continuation (.cons response .nil)) (.ok (.cons (.continuation identity authority) (.cons inputValue .nil))) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (entry : Target.Multi.ResumeEntry (definitions table)
      ⟨⟨targetStore, .code (.resume (mode := mode) (effect := effect) (use := use) .ret) (environment bindings)
        (.cons (value inputValue) (.cons (.continuation identity authority) .nil)) targetOutside⟩,
        templateArena arena, regions, templateRegistry registry⟩ targetAfter) :
    ∃ sourceAfter, Source.Multi.ResumeEntry table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.resume continuation response) bindings)⟩, arena, regions, registry⟩ sourceAfter ∧
      MultiRuntimeRelated sourceAfter targetAfter := by
  obtain ⟨rfl, rfl, accepted⟩ := Target.Multi.resume_entry_inverts (environment bindings) .nil .ret targetOutside
    targetStore (templateArena arena) regions (templateRegistry registry) mode effect use identity authority (value inputValue) entry
  let sourceReady : Source.Multi.Runtime signature algebra program result :=
    ⟨⟨evaluated, sourceOutside.plug (.evaluate (.resume continuation response) bindings)⟩, arena, regions, registry⟩
  let targetReady : Target.Multi.Runtime signature algebra program result :=
    ⟨⟨targetStore, .code (.resume (mode := mode) (effect := effect) (use := Use.multi) .ret) (environment bindings)
      (.cons (value inputValue) (.cons (.continuation identity none) .nil)) targetOutside⟩,
      templateArena arena, regions, templateRegistry registry⟩
  have related : MultiDataRelated sourceReady targetReady := ⟨stores, rfl, rfl, rfl⟩
  rw [multi_call_support_corresponds table bindings outside stores] at accepted
  obtain ⟨sourceAfter, resumed, matching⟩ := corresponding_target_acceptance
    (registered_resume_corresponds related ⟨mode, effect, input, answer⟩ identity inputValue
      (.passthrough bindings outside) (Source.Multi.callSupport table bindings sourceOutside evaluated)) accepted
  exact ⟨sourceAfter, .enter operands resumed, matching⟩

omit [DecidableEq (TypeOf signature)] in
theorem registered_injection_receiver_reflected
    (table : Source.Definitions signature algebra program)
    (continuation : Source.Expression signature algebra program context (.continuation mode use effect input answer))
    (injected : Source.Expression signature algebra program context (.computation bodyUse [] input))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (identity : Id .control) (authority : Option (Id .custody × Owner))
    (body : Source.Computation signature algebra program capturedTypes input)
    (captured : Source.RuntimeEnvironment signature algebra program capturedTypes)
    (bodyAuthority : Option (Id .custody × Owner))
    (arena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program)
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings
      (arena.cells.reservations.withSupport (Source.Multi.retainedSupport registry arena)).custody sourceStore
      (.cons continuation (.cons injected .nil))
      (.ok (.cons (.continuation identity authority) (.cons (.closure body captured bodyAuthority) .nil))) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (entry : Target.Multi.ResumeEntry (definitions table)
      ⟨⟨targetStore, .code (.inject (mode := mode) (effect := effect) (use := use) (useBody := bodyUse) .ret) (environment bindings)
        (.cons (.closure (computation body) (environment captured) bodyAuthority) (.cons (.continuation identity authority) .nil)) targetOutside⟩,
        templateArena arena, regions, templateRegistry registry⟩ targetAfter) :
    ∃ sourceAfter, Source.Multi.ResumeEntry table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.inject continuation injected) bindings)⟩, arena, regions, registry⟩ sourceAfter ∧
      MultiRuntimeRelated sourceAfter targetAfter := by
  obtain ⟨rfl, rfl, fields, handoff, accepted⟩ := Target.Multi.injection_entry_inverts (environment bindings) .nil .ret targetOutside
    targetStore (templateArena arena) regions (templateRegistry registry) mode effect use bodyUse identity authority
    (computation body) (environment captured) bodyAuthority entry
  have sourceHandoff := handoff.of_map (fun _ _ body => computation body) captured
  rw [← stores.fields] at sourceHandoff
  have updated : ControlHeapRelated { evaluated with fields := fields } { targetStore with fields := fields } :=
    ⟨rfl, stores.controls, stores.disposing⟩
  let sourceReady : Source.Multi.Runtime signature algebra program result :=
    ⟨⟨{ evaluated with fields := fields }, sourceOutside.plug (.evaluate (.inject continuation injected) bindings)⟩, arena, regions, registry⟩
  let targetReady : Target.Multi.Runtime signature algebra program result :=
    ⟨⟨{ targetStore with fields := fields }, .code (.inject (mode := mode) (effect := effect) (use := Use.multi) (useBody := bodyUse) .ret)
      (environment bindings) (.cons (.closure (computation body) (environment captured) bodyAuthority)
        (.cons (.continuation identity none) .nil)) targetOutside⟩, templateArena arena, regions, templateRegistry registry⟩
  have related : MultiDataRelated sourceReady targetReady := ⟨updated, rfl, rfl, rfl⟩
  rw [multi_call_support_corresponds table bindings outside updated] at accepted
  obtain ⟨sourceAfter, entered, matching⟩ := corresponding_target_acceptance
    (registered_injection_corresponds related ⟨mode, effect, input, answer⟩ identity body captured
      (.passthrough bindings outside) (Source.Multi.callSupport table bindings sourceOutside { evaluated with fields := fields })) accepted
  exact ⟨sourceAfter, .injection operands sourceHandoff entered, matching⟩

omit [DecidableEq (TypeOf signature)] in
theorem registered_successor_receiver_reflected
    (table : Source.Definitions signature algebra program)
    (continuation : Source.Expression signature algebra program context (.continuation .shallow use effect input bodyType))
    (response : Source.Expression signature algebra program context input)
    (returned : Source.Computation signature algebra program (bodyType :: context) answer)
    (clauses : Source.Clauses signature algebra program effect .deep context bodyType answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (identity : Id .control) (authority : Option (Id .custody × Owner))
    (inputValue : Source.RuntimeValue signature algebra program input)
    (arena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program)
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings
      (arena.cells.reservations.withSupport (Source.Multi.retainedSupport registry arena)).custody sourceStore
      (.cons continuation (.cons response .nil)) (.ok (.cons (.continuation identity authority) (.cons inputValue .nil))) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (entry : Target.Multi.ResumeEntry (definitions table)
      ⟨⟨targetStore, .code (.replaceHandler (use := use) effect (computation returned) (Defunctionalization.clauses clauses) .ret) (environment bindings)
        (.cons (value inputValue) (.cons (.continuation identity authority) .nil)) targetOutside⟩,
        templateArena arena, regions, templateRegistry registry⟩ targetAfter) :
    ∃ sourceAfter, Source.Multi.ResumeEntry table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩,
        arena, regions, registry⟩ sourceAfter ∧ MultiRuntimeRelated sourceAfter targetAfter := by
  obtain ⟨rfl, rfl, accepted⟩ := Target.Multi.successor_entry_inverts (environment bindings) .nil .ret targetOutside
    targetStore (templateArena arena) regions (templateRegistry registry) effect use identity authority (value inputValue)
    (computation returned) (Defunctionalization.clauses clauses) entry
  let sourceReady : Source.Multi.Runtime signature algebra program result :=
    ⟨⟨evaluated, sourceOutside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩,
      arena, regions, registry⟩
  let targetReady : Target.Multi.Runtime signature algebra program result :=
    ⟨⟨targetStore, .code (.replaceHandler (use := Use.multi) effect (computation returned) (Defunctionalization.clauses clauses) .ret)
      (environment bindings) (.cons (value inputValue) (.cons (.continuation identity none) .nil)) targetOutside⟩,
      templateArena arena, regions, templateRegistry registry⟩
  have related : MultiDataRelated sourceReady targetReady := ⟨stores, rfl, rfl, rfl⟩
  rw [multi_call_support_corresponds table bindings outside stores] at accepted
  obtain ⟨sourceAfter, entered, matching⟩ := corresponding_target_acceptance
    (registered_successor_corresponds related identity inputValue returned clauses bindings
      (.passthrough bindings outside) (Source.Multi.callSupport table bindings sourceOutside evaluated)) accepted
  exact ⟨sourceAfter, .successor operands entered, matching⟩

theorem registered_resume_computation_receiver_reflected
    (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (values : Source.RuntimeEnvironment signature algebra program body.operandPrefix.types)
    (arena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program)
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings
      (arena.cells.reservations.withSupport (Source.Multi.retainedSupport registry arena)).custody
      sourceStore body.operandPrefix.arguments (.ok values) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (entry : Target.Multi.ResumeEntry (definitions table)
      ⟨⟨targetStore, .code (operandTail body) (environment bindings) ((environment values).pushReverse .nil) targetOutside⟩,
        templateArena arena, regions, templateRegistry registry⟩ targetAfter) :
    ∃ sourceAfter, Source.Multi.Step table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate body bindings)⟩, arena, regions, registry⟩ sourceAfter ∧
      MultiRuntimeRelated sourceAfter targetAfter := by
  cases body with
  | resume continuation response =>
    cases values with
    | cons control rest => cases rest with
      | cons responseValue rest =>
        cases rest
        cases control with
        | datum datum => cases datum
        | continuation identity authority =>
          obtain ⟨sourceAfter, step, matching⟩ := registered_resumption_receiver_reflected table continuation response bindings
            identity authority responseValue arena regions registry operands stores outside entry
          exact ⟨sourceAfter, .resume step, matching⟩
  | inject continuation injected =>
    cases values with
    | cons control rest => cases rest with
      | cons bodyValue rest =>
        cases rest
        cases control with
        | datum datum => cases datum
        | continuation identity authority =>
          cases bodyValue with
          | datum datum => cases datum
          | closure body captured bodyAuthority =>
            obtain ⟨sourceAfter, step, matching⟩ := registered_injection_receiver_reflected table continuation injected bindings
              identity authority body captured bodyAuthority arena regions registry operands stores outside entry
            exact ⟨sourceAfter, .resume step, matching⟩
  | resumeWith effect continuation response returned clauses =>
    cases values with
    | cons control rest => cases rest with
      | cons responseValue rest =>
        cases rest
        cases control with
        | datum datum => cases datum
        | continuation identity authority =>
          obtain ⟨sourceAfter, step, matching⟩ := registered_successor_receiver_reflected table continuation response returned clauses bindings
            identity authority responseValue arena regions registry operands stores outside entry
          exact ⟨sourceAfter, .resume step, matching⟩
  | apply function arguments =>
    cases values with
    | cons functionValue argumentsValues =>
      have impossible := entry.has_nonowning_view
      dsimp only at impossible
      rw [application_operand_configuration function arguments bindings functionValue argumentsValues targetOutside] at impossible
      cases impossible
  | perform operation capability payload bodies =>
    cases values with
    | cons capabilityValue rest => cases rest with
      | cons payloadValue bodyValues =>
        have impossible := entry.has_nonowning_view
        dsimp only at impossible
        rw [operation_operand_configuration operation capability payload bodies bindings capabilityValue payloadValue bodyValues targetOutside] at impossible
        cases impossible
  | call =>
    have impossible := entry.has_nonowning_view
    change false = true at impossible
    cases impossible
  | returnValue | bind | fail | yieldThen | primitive | matchSum | handle |
      withRegion | cellNew | cellRead | cellWrite | protect | dispose | clone | package | unpackage => cases entry

/-- Invert the one shared operand prefix inside a registered execution. The
saved-future relation may use ordinary payloads or their authored descriptions;
the target always takes its actual registered steps and permission gates. -/
theorem registered_computation_operands_reflected
    {SourceFuture : Type}
    (table : Source.Definitions signature algebra program)
    (futureRelation : SourceFuture → Sigma (Target.ControlPayload signature algebra program) → Prop)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    (ambient : Target.Multi.Runtime signature algebra program result)
    {sourceStore : UseScope.ControlStore SourceFuture} {targetStore : Target.ControlHeap signature algebra program}
    (stores : UseScope.ControlStore.Related futureRelation sourceStore targetStore)
    (outside : Target.Stack signature algebra program input result)
    {final : Target.Multi.Runtime signature algebra program result}
    (run : Target.Multi.Steps (definitions table)
      (ambient.withState ⟨⟨targetStore, .code (computation body) (environment bindings) .nil outside⟩,
        cells storage, regions⟩) count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ outcome sourceAfter changed remaining,
      Source.ArgumentsEvaluation bindings (storage.reservations.withSupport ambient.executionSupport).custody
        sourceStore body.operandPrefix.arguments outcome sourceAfter ∧
      UseScope.ControlStore.Related futureRelation sourceAfter changed ∧ remaining ≤ count ∧
      (∀ fault, outcome = .error fault → remaining < count) ∧
      Target.Multi.Steps (definitions table)
        (ambient.withState ⟨⟨changed,
          Target.argumentsOutcome (operandTail body) (environment bindings) .nil outside (outcome.map environment)⟩,
          cells storage, regions⟩) remaining final := by
  rw [computation_operand_prefix] at run
  obtain ⟨outcome, sourceAfter, changed, remaining, evaluated, matching, bounded, faultBounded, following⟩ :=
    arguments_trace_reflected table futureRelation bindings storage regions body.operandPrefix.arguments stores
      (operandTail body) .nil outside (Target.Multi.operand_trace_laws (definitions table) ambient final observation) ⟨run, head⟩
  exact ⟨outcome, sourceAfter, changed, remaining, evaluated, matching, bounded, faultBounded, following.1⟩

/-- Reverse clone through its actual registered receiver and the finite return
drain. The source description is an input view of the actual source heap. -/
theorem registered_clone_receiver_reflected
    (table : Source.Definitions signature algebra program)
    (expression : Source.Expression signature algebra program context (.continuation mode use effect input answer))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (identity : Id .control) (authority : Option (Id .custody × Owner))
    (store evaluated : Source.Multi.DescribedHeap signature algebra program)
    (arena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program)
    {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ExpressionEvaluation bindings
      (arena.cells.reservations.withSupport (Source.Multi.retainedSupport registry arena)).custody
      store expression (.ok (.continuation identity authority)) evaluated)
    (stores : DescribedHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program (.continuation mode .multi effect input answer) result}
    {targetOutside : Target.Stack signature algebra program (.continuation mode .multi effect input answer) result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {after final : Target.Multi.Runtime signature algebra program result}
    (step : Target.Multi.Step (definitions table)
      ⟨⟨targetStore, .code (.clone (mode := mode) (effect := effect) (use := use) .ret) (environment bindings)
        (.cons (.continuation identity authority) .nil) targetOutside⟩, templateArena arena, regions, templateRegistry registry⟩ after)
    (tail : Target.Multi.Steps (definitions table) after rest final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < rest + 1 ∧
      Source.Multi.Step table
        ⟨⟨Source.Multi.sourceHeap store, sourceOutside.plug (.evaluate (.clone expression) bindings)⟩, arena, regions, registry⟩ sourceAfter ∧
      MultiRuntimeRelated sourceAfter targetAfter ∧ Target.Multi.Steps (definitions table) targetAfter remaining final := by
  obtain ⟨oneShot, token, owner, partition, frozen, registered, rfl, rfl, accepted, atAfter⟩ :=
    Target.Multi.clone_step_inverts (environment bindings) .nil .ret targetOutside targetStore (templateArena arena)
      regions (templateRegistry registry) use identity authority step
  obtain ⟨⟨sourceFrozen, sourceRegistry⟩, sourceAccepted, matching, registries⟩ := corresponding_target_acceptance
    (registered_freeze_related ⟨mode, effect, input, answer⟩ ⟨identity, token, owner⟩ stores arena partition registry) accepted
  change FrozenRelated sourceFrozen frozen at matching
  change registered = templateRegistry sourceRegistry at registries
  rw [atAfter] at tail
  let ready : Target.Multi.Runtime signature algebra program result :=
    ⟨⟨frozen.store, .code .ret (environment bindings) (.cons frozen.value .nil) targetOutside⟩,
      frozen.arena, regions.filter (fun region => !partition.regions.contains region), registered⟩
  obtain ⟨remaining, counted, following, _⟩ :=
    (Target.Multi.operand_trace_laws (definitions table) ready final observation).ordinary
      (before := ready.state) Target.CallStep.returned rfl ⟨tail, head⟩
  refine ⟨_, _, remaining, by omega,
    Source.Multi.Step.clone (use := oneShot) (view := ⟨identity, token, owner⟩) rfl rfl operands sourceAccepted,
    frozen_runtime_related matching _ sourceRegistry registries outside, following⟩

theorem registered_receiver_reflected
    (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (values : Source.RuntimeEnvironment signature algebra program body.operandPrefix.types)
    (store evaluated : Source.Multi.DescribedHeap signature algebra program)
    (arena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program)
    {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings
      (arena.cells.reservations.withSupport (Source.Multi.retainedSupport registry arena)).custody
      store body.operandPrefix.arguments (.ok values) evaluated)
    (stores : DescribedHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {after final : Target.Multi.Runtime signature algebra program result}
    (step : Target.Multi.Step (definitions table)
      ⟨⟨targetStore, .code (operandTail body) (environment bindings) ((environment values).pushReverse .nil) targetOutside⟩,
        templateArena arena, regions, templateRegistry registry⟩ after)
    (tail : Target.Multi.Steps (definitions table) after rest final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < rest + 1 ∧
      Source.Multi.Step table
        ⟨⟨Source.Multi.sourceHeap store, sourceOutside.plug (.evaluate body bindings)⟩, arena, regions, registry⟩ sourceAfter ∧
      MultiRuntimeRelated sourceAfter targetAfter ∧ Target.Multi.Steps (definitions table) targetAfter remaining final := by
  have normalOperands := operands.mapFuture (UseScope.mapPacked (fun _ => Source.Multi.Future.payload))
  have normalStores := (described_heap_related_iff _ _).mp stores
  cases step with
  | core actual =>
    let ready : Target.Multi.Runtime signature algebra program result :=
      ⟨⟨targetStore, .code (operandTail body) (environment bindings) ((environment values).pushReverse .nil) targetOutside⟩,
        templateArena arena, regions, templateRegistry registry⟩
    have laws := Target.Multi.operand_trace_laws (definitions table) ready final observation
    change Target.OperandTraceLaws (definitions table)
      (Target.Multi.retainedSupport (templateRegistry registry) (templateArena arena)) _ at laws
    rw [retained_support_corresponds] at laws
    change Target.ExecutionStep (retained := Target.Multi.retainedSupport (templateRegistry registry) (templateArena arena))
      (definitions table) _ _ at actual
    rw [retained_support_corresponds] at actual
    obtain ⟨sourceAfter, targetAfter, remaining, smaller, sourceStep, matching, following⟩ :=
      evaluated_core_receiver_reflected table body bindings values arena.cells regions normalOperands normalStores outside laws actual ⟨tail, head⟩
    have joined : MultiDataRelated
        (⟨⟨Source.Multi.sourceHeap evaluated, sourceOutside.plug (.evaluate body bindings)⟩, arena, regions, registry⟩ :
          Source.Multi.Runtime signature algebra program result) ready := ⟨normalStores, rfl, rfl, rfl⟩
    exact ⟨_, _, remaining, smaller, .core sourceStep, joined.writeback matching, following.1⟩
  | resume actual =>
    obtain ⟨sourceAfter, sourceStep, matching⟩ := registered_resume_computation_receiver_reflected
      table body bindings values arena regions registry normalOperands normalStores outside actual
    exact ⟨sourceAfter, _, rest, by omega, sourceStep, matching, tail⟩
  | clone atCode accepted =>
    have separate := congrArg Target.Configuration.separateDriver atCode
    dsimp only at atCode separate accepted
    cases body with
    | clone expression =>
      cases values with
      | cons control remaining =>
        cases remaining
        cases control with
        | datum datum => cases datum
        | continuation identity authority =>
          exact registered_clone_receiver_reflected table expression bindings identity authority store evaluated arena regions registry
            operands.singleton stores outside (.clone atCode accepted) tail head
    | dispose =>
      have impossible := congrArg Target.Configuration.codeConstructor atCode
      cases impossible
    | apply function arguments =>
      cases values with
      | cons functionValue argumentValues =>
        rw [application_operand_configuration function arguments bindings functionValue argumentValues targetOutside] at separate
        cases separate
    | perform operation capability payload bodies =>
      cases values with
      | cons capabilityValue rest => cases rest with
        | cons payloadValue bodyValues =>
          rw [operation_operand_configuration operation capability payload bodies bindings capabilityValue payloadValue bodyValues targetOutside] at separate
          cases separate
    | returnValue | bind | fail | yieldThen | call | primitive | matchSum | handle |
        withRegion | cellNew | cellRead | cellWrite | protect | resume | resumeWith | inject | package | unpackage =>
      cases separate

theorem registered_computation_step_reflected
    (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (arena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.Multi.Runtime signature algebra program result}
    (run : Target.Multi.Steps (definitions table)
      ⟨⟨targetStore, .code (computation body) (environment bindings) .nil targetOutside⟩,
        templateArena arena, regions, templateRegistry registry⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.Multi.Step table
        ⟨⟨sourceStore, sourceOutside.plug (.evaluate body bindings)⟩, arena, regions, registry⟩ sourceAfter ∧
      MultiRuntimeRelated sourceAfter targetAfter ∧ Target.Multi.Steps (definitions table) targetAfter remaining final := by
  let described := Source.Multi.describeHeap sourceStore
  have projected : Source.Multi.sourceHeap described = sourceStore := described_heap_projects stores
  have describedRelated : DescribedHeapRelated described targetStore := by
    apply (described_heap_related_iff _ _).mpr
    rw [projected]
    exact stores
  let ambient : Target.Multi.Runtime signature algebra program result :=
    ⟨⟨targetStore, .code (computation body) (environment bindings) .nil targetOutside⟩,
      templateArena arena, regions, templateRegistry registry⟩
  have roots : ambient.executionSupport = Source.Multi.retainedSupport registry arena :=
    retained_support_corresponds registry arena
  obtain ⟨outcome, sourceEvaluated, targetEvaluated, remaining, operands, evaluatedRelated, bounded, faultLess, following⟩ :=
    registered_computation_operands_reflected table (UseScope.PackedControlRelated describedPayloadRelated)
      body bindings arena.cells regions ambient describedRelated targetOutside run head
  rw [roots] at operands
  cases outcome with
  | error fault =>
    have normal := operands.mapFuture (UseScope.mapPacked (fun _ => Source.Multi.Future.payload))
    change Source.ArgumentsEvaluation bindings
      (arena.cells.reservations.withSupport (Source.Multi.retainedSupport registry arena)).custody
      (Source.Multi.sourceHeap described) body.operandPrefix.arguments (.error fault) (Source.Multi.sourceHeap sourceEvaluated) at normal
    rw [projected] at normal
    have normalStores := (described_heap_related_iff _ _).mp evaluatedRelated
    let sourceAfter : Source.Multi.Runtime signature algebra program result :=
      ⟨⟨Source.Multi.sourceHeap sourceEvaluated, sourceOutside.plug (.failed fault)⟩, arena, regions, registry⟩
    let targetAfter : Target.Multi.Runtime signature algebra program result :=
      ⟨⟨targetEvaluated, .failed fault targetOutside⟩, templateArena arena, regions, templateRegistry registry⟩
    refine ⟨sourceAfter, targetAfter, remaining, faultLess fault rfl,
      Source.Multi.Step.core
        (before := ⟨⟨sourceStore, sourceOutside.plug (.evaluate body bindings)⟩, arena, regions, registry⟩)
        (state := sourceAfter.state)
        (Source.ExecutionStep.operandFault (body := body) (bindings := bindings) (outside := sourceOutside)
        (cells := arena.cells) (regions := regions) (retained := Source.Multi.retainedSupport registry arena) normal),
      ⟨⟨normalStores, rfl, rfl, rfl⟩, (EntryRelated.failed fault outside).as_program⟩, following⟩
  | ok values =>
    change Target.Multi.Steps (definitions table)
      ⟨⟨targetEvaluated, .code (operandTail body) (environment bindings) ((environment values).pushReverse .nil) targetOutside⟩,
        templateArena arena, regions, templateRegistry registry⟩ remaining final at following
    cases following with
    | refl => cases head
    | cons step tail =>
      obtain ⟨sourceAfter, targetAfter, rest, smaller, sourceStep, matching, remainingRun⟩ :=
        registered_receiver_reflected table body bindings values described sourceEvaluated arena regions registry
          operands evaluatedRelated outside step tail head
      rw [projected] at sourceStep
      exact ⟨sourceAfter, targetAfter, rest, by omega, sourceStep, matching, remainingRun⟩

theorem registered_head_observation_reflected
    (table : Source.Definitions signature algebra program)
    {source : Source.Multi.Runtime signature algebra program result}
    {target : Target.Multi.Runtime signature algebra program result}
    (related : MultiRuntimeRelated source target)
    (head : Target.HeadObservation target.control.configuration observation) :
    ∃ sourceAfter sourceObservation,
      Source.Multi.Observes table source sourceAfter sourceObservation ∧
      MultiDataRelated sourceAfter target ∧
      StateObservationRelated sourceAfter.state target.state sourceObservation observation := by
  obtain ⟨after, sourceObservation, ⟨count, steps, observed⟩, matching⟩ :=
    stateful_head_observation_reflected (retained := source.executionSupport) table related.as_state head
  refine ⟨source.withState after, sourceObservation,
    ⟨count, Source.Multi.Steps.from_core source steps, observed⟩,
    ⟨matching.store, ?_, matching.regions.symm, related.registry⟩, matching⟩
  have sameCells := matching.cells
  change target.arena.cells = cells after.cells at sameCells
  rw [related.arena] at sameCells
  change cells source.arena.cells = cells after.cells at sameCells
  change target.arena = templateArena { source.arena with cells := after.cells }
  rw [related.arena]
  simp only [templateArena]
  rw [sameCells]

private theorem registered_reflection_bounded (table : Source.Definitions signature algebra program) (bound : Nat) :
    ∀ {input result} {source : Source.Program signature algebra program input}
      {sourceOutside : Source.Context signature algebra program input result}
      {targetOutside : Target.Stack signature algebra program input result}
      {target : Target.Configuration signature algebra program result}
      {count} {final : Target.Multi.Runtime signature algebra program result} {observation},
      count < bound → ProgramRelated source targetOutside target →
      ContextRelated signature algebra program sourceOutside targetOutside →
      ∀ {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program},
      ControlHeapRelated sourceStore targetStore →
      ∀ (arena : Source.Multi.Arena signature algebra program) regions registry,
      Target.Multi.Steps (definitions table) ⟨⟨targetStore, target⟩, templateArena arena, regions, templateRegistry registry⟩ count final →
      Target.HeadObservation final.control.configuration observation →
      ∃ sourceFinal sourceObservation,
        Source.Multi.Observes table ⟨⟨sourceStore, sourceOutside.plug source⟩, arena, regions, registry⟩ sourceFinal sourceObservation ∧
        MultiDataRelated sourceFinal final ∧ StateObservationRelated sourceFinal.state final.state sourceObservation observation := by
  induction bound with
  | zero => intros; omega
  | succ bound smaller =>
    intro input result source sourceOutside targetOutside target count final observation counted related outside sourceStore targetStore stores arena regions registry run head
    have reflectTail {remaining} (sourceAfter : Source.Multi.Runtime signature algebra program result)
        (targetAfter : Target.Multi.Runtime signature algebra program result)
        (decreased : remaining < bound) (matched : MultiRuntimeRelated sourceAfter targetAfter)
        (tail : Target.Multi.Steps (definitions table) targetAfter remaining final) :
        ∃ sourceFinal sourceObservation, Source.Multi.Observes table sourceAfter sourceFinal sourceObservation ∧
          MultiDataRelated sourceFinal final ∧ StateObservationRelated sourceFinal.state final.state sourceObservation observation := by
      rcases sourceAfter with ⟨⟨sourceHeap, sourceProgram⟩, sourceArena, sourceRegions, sourceRegistry⟩
      rcases targetAfter with ⟨⟨targetHeap, targetProgram⟩, targetArena, targetRegions, targetRegistry⟩
      rcases matched with ⟨⟨heaps, sameArena, sameRegions, sameRegistry⟩, programs⟩
      dsimp only at sameArena sameRegions sameRegistry programs
      subst targetArena
      subst targetRegions
      subst targetRegistry
      exact smaller decreased programs .done heaps sourceArena sourceRegions sourceRegistry tail head
    induction related with
    | evaluate body bindings future =>
      obtain ⟨sourceAfter, targetAfter, remaining, decreased, sourceStep, matched, tail⟩ :=
        registered_computation_step_reflected table body bindings arena regions registry stores outside run head
      obtain ⟨sourceFinal, sourceObservation, observed, data, same⟩ := reflectTail sourceAfter targetAfter (by omega) matched tail
      exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons sourceStep .refl), data, same⟩
    | bind body bindings inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug, Source.Frame.bindAuthored, Source.Program.bindAuthored] using
        induction (.push (.bind body bindings) outside) run head reflectTail
    | handler effect mode attachment returned clauses bindings inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug] using
        induction (.push (.handler effect mode attachment returned clauses bindings) outside) run head reflectTail
    | region identity inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug] using induction (.push (.region identity) outside) run head reflectTail
    | protection identity cleanup bindings inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug] using induction (.push (.protection identity cleanup bindings) outside) run head reflectTail
    | cleaning identity original exit inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug] using induction (.push (.cleanupReturn identity original exit) outside) run head reflectTail
    | passthrough bindings inner induction => exact induction (.passthrough bindings outside) run head reflectTail
    | yielded inner induction =>
      cases run with
      | refl =>
        exact registered_head_observation_reflected table
          ⟨⟨stores, rfl, rfl, rfl⟩, outside.close_program (.yielded inner)⟩ head
      | cons step tail =>
        obtain ⟨state, actual, _⟩ := step.core_of_noncode rfl
        exact False.elim (Target.ExecutionStep.no_yielded_step _ targetStore (cells arena.cells) regions actual)
    | requested operation attachment payload bodies saved future =>
      cases run with
      | refl =>
        exact registered_head_observation_reflected table
          ⟨⟨stores, rfl, rfl, rfl⟩, outside.close_program (.requested operation attachment payload bodies saved _)⟩ head
      | cons step tail =>
        obtain ⟨sourceAfter, sourceStep, matched⟩ := registered_requested_step_reflected table operation attachment payload bodies _ sourceOutside
          _ (context_composition saved outside) arena regions registry stores step
        obtain ⟨sourceFinal, sourceObservation, observed, data, same⟩ := reflectTail sourceAfter _ (by omega) matched tail
        exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons sourceStep .refl), data, same⟩
    | returned value future =>
      cases outside with
      | done =>
        have finalAt := Target.Multi.Steps.returned_done (Defunctionalization.value value) targetStore (templateArena arena) regions (templateRegistry registry) run
        subst final
        cases head
        exact ⟨_, _, ⟨0, .refl, .returned⟩, ⟨stores, rfl, rfl, rfl⟩, ⟨stores, rfl, rfl, .returned value⟩⟩
      | passthrough bindings rest =>
        obtain ⟨firstCount, firstEq, firstRun⟩ := Target.Multi.ordinary_cancel_observed Target.CallStep.caller rfl run head
        obtain ⟨remaining, secondEq, tail⟩ := Target.Multi.ordinary_cancel_observed Target.CallStep.returned rfl firstRun head
        exact smaller (by omega) (.returned value _) rest stores arena regions registry tail head
      | push frame rest =>
        cases frame with
        | bind body bindings =>
          obtain ⟨firstCount, firstEq, firstRun⟩ := Target.Multi.ordinary_cancel_observed Target.CallStep.caller rfl run head
          obtain ⟨remaining, secondEq, tail⟩ := Target.Multi.ordinary_cancel_observed Target.CallStep.enter rfl firstRun head
          obtain ⟨sourceFinal, sourceObservation, observed, data, same⟩ := smaller (by omega) (.evaluate body (.cons value bindings) _) rest stores arena regions registry tail head
          exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons (Source.Step.in_registered_context .bindValue rfl _ sourceStore arena regions registry) .refl), data, same⟩
        | handler effect mode identity returned clauses bindings =>
          obtain ⟨remaining, decreased, tail⟩ := Target.Multi.ordinary_cancel_observed Target.CallStep.handlerReturned rfl run head
          obtain ⟨sourceFinal, sourceObservation, observed, data, same⟩ := smaller (by omega) (.evaluate returned (.cons value bindings) _) rest stores arena regions registry tail head
          exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons (Source.Step.in_registered_context .handlerValue rfl _ sourceStore arena regions registry) .refl), data, same⟩
        | protection identity cleanup bindings =>
          obtain ⟨remaining, decreased, tail⟩ := Target.Multi.ordinary_cancel_observed Target.CallStep.protectionReturn rfl run head
          obtain ⟨sourceFinal, sourceObservation, observed, data, same⟩ := smaller (by omega)
            (.cleaning identity (some value) ⟨.normal, [], none⟩ (.evaluate cleanup (.cons (.exit ⟨.normal, [], none⟩) bindings) _)) rest stores arena regions registry tail head
          exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons (Source.Step.in_registered_context .protectionReturn rfl _ sourceStore arena regions registry) .refl), data, same⟩
        | cleanupReturn identity original exit =>
          cases original with
          | none =>
            cases run with
            | refl => cases head
            | cons step tail =>
              obtain ⟨state, actual, _⟩ := step.core_of_noncode rfl
              have ordinary := (actual.returned_is_ordinary _ _ _ _ _).2.2.2
              cases ordinary
          | some original =>
            cases run with
            | refl => cases head
            | cons step tail =>
              obtain ⟨state, actual, afterAt⟩ := step.core_of_noncode rfl
              rw [afterAt] at tail
              rcases state with ⟨⟨heap, configuration⟩, targetCells, targetRegions⟩
              obtain ⟨stored, sameCells, sameRegions, ordinary⟩ := actual.returned_is_ordinary _ _ _ _ _
              dsimp only at stored sameCells sameRegions ordinary
              subst heap
              subst targetCells
              subst targetRegions
              cases ordinary with
              | cleanupReturn normal =>
                obtain ⟨sourceFinal, sourceObservation, observed, data, same⟩ := smaller (by omega) (.returned original _) rest stores arena regions registry tail head
                exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons
                  (Source.Step.in_registered_context (.cleaningReturn normal) rfl _ sourceStore arena regions registry) .refl), data, same⟩
        | region identity =>
          cases run with
          | refl => cases head
          | cons step tail =>
            obtain ⟨state, actual, _⟩ := step.core_of_noncode rfl
            have ordinary := (actual.returned_is_ordinary _ _ _ _ _).2.2.2
            cases ordinary
    | failed fault future =>
      cases outside with
      | done =>
        have finalAt := Target.Multi.Steps.failed_done fault _ targetStore (templateArena arena) regions (templateRegistry registry) run
        subst final
        cases head
        exact ⟨_, _, ⟨0, .refl, .failed⟩, ⟨stores, rfl, rfl, rfl⟩, ⟨stores, rfl, rfl, .failed fault⟩⟩
      | passthrough bindings rest =>
        obtain ⟨remaining, decreased, tail⟩ := Target.Multi.ordinary_cancel_observed Target.CallStep.callerFault rfl run head
        exact smaller (by omega) (.failed fault _) rest stores arena regions registry tail head
      | push frame rest =>
        cases frame with
        | bind body bindings =>
          obtain ⟨remaining, decreased, tail⟩ := Target.Multi.ordinary_cancel_observed Target.CallStep.callerFault rfl run head
          obtain ⟨sourceFinal, sourceObservation, observed, data, same⟩ := smaller (by omega) (.failed fault _) rest stores arena regions registry tail head
          exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons (Source.Step.in_registered_context .bindFault rfl _ sourceStore arena regions registry) .refl), data, same⟩
        | handler effect mode identity returned clauses bindings =>
          obtain ⟨remaining, decreased, tail⟩ := Target.Multi.ordinary_cancel_observed Target.CallStep.handlerFault rfl run head
          obtain ⟨sourceFinal, sourceObservation, observed, data, same⟩ := smaller (by omega) (.failed fault _) rest stores arena regions registry tail head
          exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons (Source.Step.in_registered_context .handlerFault rfl _ sourceStore arena regions registry) .refl), data, same⟩
        | region identity | protection identity cleanup bindings | cleanupReturn identity original exit =>
          cases run with
          | refl => cases head
          | cons step tail =>
            obtain ⟨state, actual, _⟩ := step.core_of_noncode rfl
            have ordinary := (actual.failed_is_ordinary _ _ _ _ _).2.2.2
            cases ordinary


/-- D's registered reflection direction. No source execution or desired
correspondence is a premise: the finite target derivation determines it. -/
theorem registered_observation_reflected
    (table : Source.Definitions signature algebra program)
    {source : Source.Multi.Runtime signature algebra program result}
    {target : Target.Multi.Runtime signature algebra program result}
    (related : MultiRuntimeRelated source target)
    (observed : Target.Multi.Observes (definitions table) target targetFinal observation) :
    ∃ sourceFinal sourceObservation,
      Source.Multi.Observes table source sourceFinal sourceObservation ∧
      MultiDataRelated sourceFinal targetFinal ∧
      StateObservationRelated sourceFinal.state targetFinal.state sourceObservation observation := by
  rcases source with ⟨⟨sourceStore, sourceProgram⟩, sourceArena, sourceRegions, sourceRegistry⟩
  rcases target with ⟨⟨targetStore, targetProgram⟩, targetArena, targetRegions, targetRegistry⟩
  rcases related with ⟨⟨stores, arenaAt, regionsAt, registryAt⟩, programs⟩
  dsimp only at arenaAt regionsAt registryAt programs
  subst targetArena
  subst targetRegions
  subst targetRegistry
  obtain ⟨count, run, head⟩ := observed
  exact registered_reflection_bounded table (count + 1) (by omega) programs .done stores sourceArena sourceRegions sourceRegistry run head

end Defunctionalization
end BoundaryV2.Generalized
