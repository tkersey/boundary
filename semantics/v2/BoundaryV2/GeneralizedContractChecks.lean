import BoundaryV2.GeneralizedContracts

/-! Statement checks, not inhabitants of the five contracts. These consumers
keep the stateful observation definitions and the principal contract field types
visible to the trust mutation suite. A `True` declaration or an ordinary-only
observation relation cannot satisfy them. -/
namespace BoundaryV2.Generalized.ContractChecks

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- Check the meaning-bearing definition, including the final resource state. -/
theorem source_observation_definition (table : Source.Definitions signature algebra program)
    (before after : Source.State signature algebra program result) observation :
    Source.StateObserves table before after observation =
      (∃ count, Source.ExecutionSteps table before count after ∧
        Source.HeadObservation after.control.computation observation) := rfl

theorem target_observation_definition (table : Target.Definitions signature algebra program)
    (before after : Target.State signature algebra program result) observation :
    Target.StateObserves table before after observation =
      (∃ count, Target.ExecutionSteps table before count after ∧
        Target.HeadObservation after.control.configuration observation) := rfl

/-- A hypothetical proof of D must provide both stateful directions. No such
proof is constructed here, and ordinary adequacy has a different type. -/
theorem defunctionalization_contract
    (claim : Defunctionalization.adequacy signature algebra program)
    (table : Source.Definitions signature algebra program)
    {source : Source.State signature algebra program result}
    {target : Target.State signature algebra program result}
    (related : Defunctionalization.ExecutionStateRelated source target) :
    (∀ final observation, Source.StateObserves table source final observation →
      ∃ targetFinal targetObservation,
        Target.StateObserves (Defunctionalization.definitions table) target targetFinal targetObservation ∧
        Defunctionalization.StateObservationRelated final targetFinal observation targetObservation) ∧
    (∀ final observation, Target.StateObserves (Defunctionalization.definitions table) target final observation →
      ∃ sourceFinal sourceObservation,
        Source.StateObserves table source sourceFinal sourceObservation ∧
        Defunctionalization.StateObservationRelated sourceFinal final sourceObservation observation) :=
  ⟨fun _ => claim.preservation table related, fun _ => claim.reflection table related⟩

omit [DecidableEq (TypeOf signature)] in
theorem handler_contract (claim : Handlers.interpretation signature algebra program)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : Defunctionalization.ContextRelated signature algebra program sourceOutside targetOutside)
    {source : Source.Program signature algebra program input}
    {target : Target.Configuration signature algebra program result}
    (related : Defunctionalization.ProgramRelated source targetOutside target) :
    Defunctionalization.ProgramRelated (sourceOutside.plug source) .done target :=
  claim.context outside related

theorem use_contract (claim : UseScope.preservation signature algebra program)
    shape view (store : Target.ControlHeap signature algebra program) acquired
    (valid : UseScope.ControlStore.Valid store)
    (accepted : UseScope.acquireAt shape view store = some acquired) :
    UseScope.ControlStore.Valid acquired.store ∧ view.authority ∉ UseScope.inventory acquired.store.fields ∧
      UseScope.acquireAt shape view acquired.store = none := claim.typed_consumption shape view store acquired valid accepted

theorem exit_contract (claim : Exits.composition signature algebra program)
    (table : Target.Definitions signature algebra program)
    (work : ExitComposition.CleanupDisposal signature algebra program result)
    (after : ExitComposition.Resolution signature algebra program result) :
    ¬ ExitComposition.CleanupFrameStep table (.disposing work) (.running after) :=
  claim.value_disposal table work after

theorem nested_exit_contract (claim : Exits.composition signature algebra program)
    (table : Target.Definitions signature algebra program)
    {current : ExitComposition.CleanupInfo algebra.Fault algebra.Reason}
    {parents : List (ExitComposition.CleanupParent signature algebra program)}
    {work : ExitComposition.RegionDisposal signature algebra program .unit}
    {after : ExitComposition.NestedCleanup signature algebra program}
    (step : ExitComposition.NestedProgressStep table (.region current parents work) (.active after) retained) :
    ∃ external, ExitComposition.NestedProgress.finishRegion (retained ++ external)
      (.region current parents work) = some (.active after) :=
  claim.nested_retained_roots table step

theorem nested_disposal_contract (claim : Exits.composition signature algebra program)
    (table : Target.Definitions signature algebra program)
    {before after : ExitComposition.NestedProgress signature algebra program}
    (resume : ExitComposition.ResumePoint signature algebra program answer)
    (outside : Target.Stack signature algebra program .unit result)
    (steps : ExitComposition.NestedProgressSteps table before count after
      (resume.references ++ outside.installationReferences)) :
    Target.DisposalRun table (.nested before resume outside) count (.nested after resume outside) :=
  claim.nested_disposal_embedding table resume outside steps

omit [DecidableEq (TypeOf signature)] in
theorem open_contract (claim : OpenControl.observation_relocation signature algebra program)
    (operation : signature.operation effect) (pending : Target.Pending signature algebra program operation result)
    (sourceFuture : Source.Context signature algebra program (signature.result operation) result)
    (related : Defunctionalization.ContextRelated signature algebra program sourceFuture pending.future)
    (response : Source.RuntimeValue signature algebra program (signature.result operation)) :
    Target.interact (.parked pending)
        (.response ⟨pending.occurrence, pending.attachment, Defunctionalization.value response⟩) =
      .running (.returned (Defunctionalization.value response) pending.future) pending.owners ∧
    Defunctionalization.EntryRelated (sourceFuture.plug (.returned response))
      (.returned (Defunctionalization.value response) pending.future) :=
  claim.response operation pending sourceFuture related response

/-- Registered observations use the actual retained runtime and its admitted
transitions, including clone and multi-use entry. -/
theorem registered_source_observation_definition (table : Source.Definitions signature algebra program)
    (before after : Source.Multi.Runtime signature algebra program result) observation :
    Source.Multi.Observes table before after observation =
      (∃ count, Source.Multi.Steps table before count after ∧
        Source.HeadObservation after.control.computation observation) := rfl

theorem registered_target_observation_definition (table : Target.Definitions signature algebra program)
    (before after : Target.Multi.Runtime signature algebra program result) observation :
    Target.Multi.Observes table before after observation =
      (∃ count, Target.Multi.Steps table before count after ∧
        Target.HeadObservation after.control.configuration observation) := rfl

theorem registered_defunctionalization_contract
    (claim : Defunctionalization.adequacy signature algebra program)
    (table : Source.Definitions signature algebra program)
    {source : Source.Multi.Runtime signature algebra program result}
    {target : Target.Multi.Runtime signature algebra program result}
    (related : Defunctionalization.MultiRuntimeRelated source target) :
    (∀ final observation, Source.Multi.Observes table source final observation →
      ∃ targetFinal targetObservation,
        Target.Multi.Observes (Defunctionalization.definitions table) target targetFinal targetObservation ∧
        Defunctionalization.MultiDataRelated final targetFinal ∧
        Defunctionalization.StateObservationRelated final.state targetFinal.state observation targetObservation) ∧
    (∀ final observation, Target.Multi.Observes (Defunctionalization.definitions table) target final observation →
      ∃ sourceFinal sourceObservation,
        Source.Multi.Observes table source sourceFinal sourceObservation ∧
        Defunctionalization.MultiDataRelated sourceFinal final ∧
        Defunctionalization.StateObservationRelated sourceFinal.state final.state sourceObservation observation) :=
  ⟨fun _ => claim.registered_preservation table related, fun _ => claim.registered_reflection table related⟩

end BoundaryV2.Generalized.ContractChecks
