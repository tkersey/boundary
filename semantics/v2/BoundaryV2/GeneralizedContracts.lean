import BoundaryV2.GeneralizedStateObservations
import BoundaryV2.GeneralizedMultiEntry
import BoundaryV2.GeneralizedDisposalExecution
import BoundaryV2.GeneralizedCleanupCompletion
import BoundaryV2.GeneralizedInteraction
import BoundaryV2.GeneralizedOwnedRelocation
import BoundaryV2.GeneralizedExitRelocation

/-!
Required propositions, not assumed or manufactured proofs. The five structures
below have no exported inhabitants. Their fields name the obligations used by
the proof inventory; the existing ordinary adequacy theorem is a component and
cannot inhabit the stateful adequacy fields. All operational premises below are
local typing, ownership, support, or actual transition/admission premises.
-/
namespace BoundaryV2.Generalized

variable (signature : Signature) (algebra : LeafAlgebra signature.Data)
  (program : List (BodyType signature.Data signature.Effect))
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

namespace Defunctionalization

/-- D: finite observations of related executing core states in both directions.
The relations expose values, scoped computation arguments, suspended futures,
and the current store/cell/region state. No premise assumes a simulation or an
observation correspondence. Registry and exit drivers must be connected to this
execution relation before this is the complete core contract (see CONTRACT.md). -/
structure adequacy : Prop where
  preservation : ∀ (table : Source.Definitions signature algebra program) {result}
    {source final : Source.State signature algebra program result}
    {target : Target.State signature algebra program result},
    ExecutionStateRelated source target →
    ∀ observation, Source.StateObserves table source final observation →
      ∃ targetFinal targetObservation,
        Target.StateObserves (definitions table) target targetFinal targetObservation ∧
        StateObservationRelated final targetFinal observation targetObservation
  reflection : ∀ (table : Source.Definitions signature algebra program) {result}
    {source : Source.State signature algebra program result}
    {target final : Target.State signature algebra program result},
    ExecutionStateRelated source target →
    ∀ observation, Target.StateObserves (definitions table) target final observation →
      ∃ sourceFinal sourceObservation,
        Source.StateObserves table source sourceFinal sourceObservation ∧
        StateObservationRelated sourceFinal final sourceObservation observation
  initialization : ∀ {context result}
    (body : Source.Computation signature algebra program context result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program},
    ControlHeapRelated sourceStore targetStore →
    ∀ (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) regions,
      ExecutionStateRelated
        ⟨⟨sourceStore, .evaluate body bindings⟩, sourceCells, regions⟩
        ⟨⟨targetStore, .code (computation body) (environment bindings) .nil .done⟩,
          cells sourceCells, regions⟩
  responses : ∀ {input result}
    {sourceFuture : Source.Context signature algebra program input result}
    {targetFuture : Target.Stack signature algebra program input result},
    ContextRelated signature algebra program sourceFuture targetFuture →
    ∀ (response : Source.RuntimeValue signature algebra program input)
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program},
    ControlHeapRelated sourceStore targetStore →
    ∀ (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) regions,
      ExecutionStateRelated
        ⟨⟨sourceStore, sourceFuture.plug (.returned response)⟩, sourceCells, regions⟩
        ⟨⟨targetStore, .returned (value response) targetFuture⟩, cells sourceCells, regions⟩

end Defunctionalization

namespace Handlers

/-- H: selection, interpretation, and contextual composition. The source
clauses and injected bodies are arbitrary typed computations. All continuation
operations use the actual permission-sensitive heap acquisition. -/
structure interpretation : Prop where
  fresh_installation : ∀ (table : Target.Definitions signature algebra program) {context operands input result}
    (code : Target.Code signature algebra program context operands input)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (values : Target.RuntimeEnvironment signature algebra program operands)
    (outside : Target.Stack signature algebra program input result) store cells extra,
    Target.freshAttachment table code bindings values outside store cells extra ∉
      referenceNames (Target.installationSupport table code bindings values outside store cells extra) .attachment
  nearest : ∀ {input result} (context : Source.Context signature algebra program input result)
    wanted selected, Source.select wanted context = some selected →
      selected.whole = context ∧ selected.identity = wanted ∧ wanted ∉ selected.inside.attachments
  forwarding : ∀ {effect} (operation : signature.operation effect) attachment {result}
    {source : Source.Context signature algebra program (signature.result operation) result}
    {target : Target.Stack signature algebra program (signature.result operation) result},
    Defunctionalization.ContextRelated signature algebra program source target →
      (Source.Forwards operation attachment source ↔ Target.Forwards operation attachment target)
  context : ∀ {input result} {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result},
    Defunctionalization.ContextRelated signature algebra program sourceOutside targetOutside →
    ∀ {source : Source.Program signature algebra program input}
      {target : Target.Configuration signature algebra program result},
      Defunctionalization.ProgramRelated source targetOutside target →
        Defunctionalization.ProgramRelated (sourceOutside.plug source) .done target
  resume : ∀ {result} {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program},
    Defunctionalization.ControlHeapRelated sourceStore targetStore →
    ∀ shape view (response : Source.RuntimeValue signature algebra program shape.input)
      {sourceOutside : Source.Context signature algebra program shape.answer result}
      {targetOutside : Target.Stack signature algebra program shape.answer result},
      Defunctionalization.ContextRelated signature algebra program sourceOutside targetOutside →
        Option.Rel Defunctionalization.ControlStateRelated
          (Source.resumeControl shape view sourceStore response sourceOutside)
          (Target.resumeControl shape view targetStore (Defunctionalization.value response) targetOutside)
  injection : ∀ {context result} {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program},
    Defunctionalization.ControlHeapRelated sourceStore targetStore →
    ∀ shape view (body : Source.Computation signature algebra program context shape.input)
      (bindings : Source.RuntimeEnvironment signature algebra program context)
      {sourceOutside : Source.Context signature algebra program shape.answer result}
      {targetOutside : Target.Stack signature algebra program shape.answer result},
      Defunctionalization.ContextRelated signature algebra program sourceOutside targetOutside →
        Option.Rel Defunctionalization.ControlStateRelated
          (Source.injectControl shape view sourceStore body bindings sourceOutside)
          (Target.injectControl shape view targetStore
            ⟨context, Defunctionalization.computation body, Defunctionalization.environment bindings⟩ targetOutside)
  successor : ∀ {input body answer context effect result}
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program},
    Defunctionalization.ControlHeapRelated sourceStore targetStore →
    ∀ view (response : Source.RuntimeValue signature algebra program input)
      (returned : Source.Computation signature algebra program (body :: context) answer)
      (clauses : Source.Clauses signature algebra program effect .deep context body answer)
      (bindings : Source.RuntimeEnvironment signature algebra program context)
      {sourceOutside : Source.Context signature algebra program answer result}
      {targetOutside : Target.Stack signature algebra program answer result},
      Defunctionalization.ContextRelated signature algebra program sourceOutside targetOutside →
        Option.Rel Defunctionalization.ControlStateRelated
          (Source.resumeControlWith view sourceStore response returned clauses bindings sourceOutside)
          (Target.resumeControlWith view targetStore (Defunctionalization.value response)
            (Defunctionalization.computation returned) (Defunctionalization.clauses clauses)
            (Defunctionalization.environment bindings) targetOutside)

end Handlers

namespace UseScope

/-- U: actual permission-sensitive operations, physical multiplicity, and
scope admission. These are local transition obligations, not a production heap
manager or a premise that a compiler inferred all permissions correctly. -/
structure preservation : Prop where
  control_execution : ∀ (table : Target.Definitions signature algebra program) reserved {result}
    {before after : Target.ControlState signature algebra program result} {count},
    Target.OwnedSteps table reserved before count after →
      ControlStore.Valid before.store → ControlStore.Valid after.store
  cell_occurrences : ∀ (table : Target.Definitions signature algebra program) {result}
    {before after : Target.State signature algebra program result} {count},
    Target.CellSteps table before count after →
      before.physicalInventory.Perm after.physicalInventory
  capture_occurrences : ∀ before selected after retained spent identity,
    (inventory ⟨before ++ selected ++ after, retained, spent⟩).Perm
      (inventory (capture before selected after retained spent identity))
  scoped_package : ∀ ownedScope destination forest before selected after retained spent result,
    Valid ⟨before ++ selected ++ after, retained, spent⟩ → Scope.Valid forest →
    packageScoped ownedScope destination forest before selected after retained spent = some result →
      Valid result.fields ∧ Scope.Valid result.lifetime.forest ∧
      ∃ owned remaining, Scope.detach ownedScope forest = some (owned, remaining) ∧
        ∀ dependency ∈ borrowedScopes selected,
          dependency ∈ owned.names ∨ Scope.permitsBorrow remaining destination dependency = true
  typed_consumption : ∀ shape view (store : Target.ControlHeap signature algebra program) acquired,
    ControlStore.Valid store → acquireAt shape view store = some acquired →
      ControlStore.Valid acquired.store ∧ view.authority ∉ inventory acquired.store.fields ∧
        acquireAt shape view acquired.store = none
  registry_identity : ∀ {shape} identity (payload : Target.Multi.Template signature algebra program shape)
    registry after,
    (TemplateRegistry.identities registry).Nodup →
    TemplateRegistry.insert identity payload registry = some after →
      (TemplateRegistry.identities after).Nodup ∧
      TemplateRegistry.lookup shape identity after = some payload
  activation_correspondence : ∀ {result}
    {source : Source.Multi.Runtime signature algebra program result}
    {target : Target.Multi.Runtime signature algebra program result},
    Defunctionalization.MultiDataRelated source target → ∀ shape identity external,
      target.activate shape identity external =
        (source.activate shape identity external).map Defunctionalization.registeredActivation
  activation_freshness : ∀ {shape}
    (image : Target.Multi.Image signature algebra program shape) arena external domain name old,
    name ∈ image.locals domain →
    old ∈ referenceNames (Target.Multi.support image arena external) domain →
      (Target.Multi.allocation image arena external).name domain name ≠ old
  activation_aliases : ∀ {shape}
    (template : Target.Multi.Template signature algebra program shape) arena external,
    (Target.Multi.instantiate template arena external).arena.dormant.flatMap Target.Multi.Record.references =
      (template.image.dormant.flatMap Target.Multi.Record.references).map
        (Reference.relocate (Target.Multi.allocation template.image arena external)) ++
      arena.dormant.flatMap Target.Multi.Record.references
  current_shared_cells : ∀ {shape}
    (template : Target.Multi.Template signature algebra program shape) arena external name,
    name ∈ Cells.identities arena.cells →
      Cells.lookup name (Target.Multi.instantiate template arena external).arena.cells = Cells.lookup name arena.cells
  lifetime : ∀ wanted forest fields extra retired remaining,
    closeScoped wanted forest fields extra = some (retired, remaining) →
      (∀ dependency ∈ borrowedScopes fields, dependency ∈ Scope.names remaining) ∧
      (∀ dependency ∈ referenceNames extra .scope, dependency ∈ Scope.names remaining)

end UseScope

namespace Exits

/-- X: finite initiation and ordered exit information, retained running cleanup,
and actual returned-value disposal. Finishing the registry/region embedding is
required in addition to the local fields below; see the existing inventory. -/
structure composition : Prop where
  unfinished_boundary : ∀ {result} (resolution : ExitComposition.Resolution signature algebra program result),
    resolution.cleanupFinished = false →
      ExitComposition.finishCleanupFrame resolution = none ∧
      ExitComposition.beginAbruptCleanup resolution = none ∧
      ExitComposition.RegionDisposal.begin resolution = none ∧
      ExitComposition.followUnwindResolution resolution = none
  initiation : ∀ (table : Target.Definitions signature algebra program)
    {before after : ExitComposition.Runtime signature algebra program} {count},
    ExitComposition.RuntimeSteps table before count after →
      count + after.phase.right = before.phase.right
  first_cancellation : ∀ {input result} (first later : algebra.Reason)
    (future : Target.Stack signature algebra program input result),
    (future.cancelRunning first).isSome = (future.cancelRunning later).isSome ∧
      ∀ after, future.cancelRunning first = some after → after.cancelRunning later = some after
  failure_precedence : ∀ (first second : algebra.Fault) (exit : ExitInfo algebra.Fault algebra.Reason),
    (exit.cleanupFailure first).cleanupFailure second =
      { (exit.cleanupFailure first) with failures := (exit.cleanupFailure first).failures ++ [second] }
  operand_order : ∀ (scope : ExitComposition.OperandScope),
    ExitComposition.operandFailure scope = scope.collected ++ scope.outer.flatten
  owned_result : ∀ {type} (original : Target.RuntimeValue signature algebra program type)
    (exit : ExitInfo algebra.Fault algebra.Reason),
    exit.primary ≠ .normal → original.owningField.tokens ≠ [] →
      ExitComposition.finalizeCleanup (some original) exit = some (.disposing original exit)
  value_disposal : ∀ (table : Target.Definitions signature algebra program) {result}
    (work : ExitComposition.CleanupDisposal signature algebra program result)
    (after : ExitComposition.Resolution signature algebra program result),
    ¬ ExitComposition.CleanupFrameStep table (.disposing work) (.running after)
  nested_completion : ∀ (before after : ExitComposition.NestedCleanup signature algebra program),
    before.join = some after → after.memory = before.memory ∧ after.focus.right = 0
  region_completion : ∀ {result} external
    (handoff : ExitComposition.RegionHandoff signature algebra program input result)
    (after : ExitComposition.Resolution signature algebra program result),
    ExitComposition.RegionDisposal.finish external (.offering handoff) = some after →
      after.store = handoff.runtime.store ∧ after.exitInfo = handoff.runtime.exit ∧
      UseScope.tokens after.cells.fields = UseScope.tokens handoff.runtime.cells.fields
  region_embedding : ∀ (table : Target.Definitions signature algebra program) {result count}
    {before after : ExitComposition.RegionDisposal signature algebra program result},
    ExitComposition.RegionDisposalSteps table before count after →
      ExitComposition.CleanupFrameSteps table (.region before) count (.region after)

end Exits

namespace OpenControl

/-- O: logical interaction and relocation. `LookupRelocation` is the local
finite-support injectivity/owner-separation premise for the actual lookup; it
is not an assumption that execution or compilation commutes. -/
structure observation_relocation : Prop where
  polling : ∀ {effect} (operation : signature.operation effect) {result}
    (state : Target.InteractionState signature algebra program operation result),
    Target.interact state .poll = state ∧ Target.interact state .invalid = state
  rejection : ∀ {effect} (operation : signature.operation effect) {result}
    (pending : Target.Pending signature algebra program operation result) response,
    ¬ Target.matchingResponse pending response →
      Target.interact (.parked pending) (.response response) = .parked pending
  response : ∀ {effect} (operation : signature.operation effect) {result}
    (pending : Target.Pending signature algebra program operation result)
    (sourceFuture : Source.Context signature algebra program (signature.result operation) result),
    Defunctionalization.ContextRelated signature algebra program sourceFuture pending.future →
    ∀ (response : Source.RuntimeValue signature algebra program (signature.result operation)),
      Target.interact (.parked pending)
          (.response ⟨pending.occurrence, pending.attachment, Defunctionalization.value response⟩) =
        .running (.returned (Defunctionalization.value response) pending.future) pending.owners ∧
      Defunctionalization.EntryRelated (sourceFuture.plug (.returned response))
        (.returned (Defunctionalization.value response) pending.future)
  occurrences : ∀ {effect} (operation : signature.operation effect) {result} supply attachment payload bodies
    (future : Target.Stack signature algebra program (signature.result operation) result) owners
    (external : Target.Forwards operation attachment future),
    (Target.openRequest operation supply attachment payload bodies future owners external).pending.occurrence ≠
      (Target.openRequest operation
        (Target.openRequest operation supply attachment payload bodies future owners external).supply
        attachment payload bodies future owners external).pending.occurrence
  authority : ∀ {effect} (operation : signature.operation effect) {result}
    (state : Target.InteractionState signature algebra program operation result) input,
    (Target.interact state input).owners = state.owners
  resumption_relocation : ∀ {result} relocation shape view (store : Target.ControlHeap signature algebra program)
    (value : Target.RuntimeValue signature algebra program shape.input)
    (outside : Target.Stack signature algebra program shape.answer result),
    UseScope.LookupRelocation relocation view store →
      Target.resumeControl shape (view.relocate relocation) (Target.relocateControlHeap relocation store)
          (Target.relocateValue relocation value) (outside.relocate relocation) =
        (Target.resumeControl shape view store value outside).map (Target.ControlState.relocate relocation)
  cleanup_relocation : ∀ relocation reason (obligation : ExitComposition.Obligation signature algebra program),
    (ExitComposition.cancel reason obligation).relocate relocation =
      ExitComposition.cancel reason (obligation.relocate relocation)
  future_support : ∀ {input result} relocation
    (future : Target.Stack signature algebra program input result),
    (future.relocate relocation).references = future.references.map (Reference.relocate relocation)
  dormant_support : ∀ {type} relocation (value : Target.RuntimeValue signature algebra program type),
    Target.valueReferences (Target.relocateValue relocation value) =
      (Target.valueReferences value).map (Reference.relocate relocation)

end OpenControl
end BoundaryV2.Generalized
