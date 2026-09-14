import BoundaryV2.GeneralizedRegisteredFreeze
import BoundaryV2.GeneralizedDormantRegistry
import BoundaryV2.GeneralizedStateObservations

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

namespace Source.Multi

/-- The arena owns current cells once. The ordinary state is a projection;
immutable templates and the live branch inventory stay with this runtime. -/
structure Runtime (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  control : ControlState signature algebra program result
  arena : Arena signature algebra program
  regions : List (Id .region)
  registry : Registry signature algebra program

def Runtime.state (runtime : Runtime signature algebra program result) : State signature algebra program result :=
  ⟨runtime.control, runtime.arena.cells, runtime.regions⟩

/-- Registry and suspended roots supplement the current state. Current cells
are owned once by the arena and are reserved by the ordinary state rules. -/
def retainedSupport (registry : Registry signature algebra program) (arena : Arena signature algebra program) : List Reference :=
  registryReferences registry ++ arena.dormant.flatMap Record.references ++
    arena.active.flatMap (fun packed => packed.snd.references)

def Runtime.executionSupport (runtime : Runtime signature algebra program result) : List Reference :=
  retainedSupport runtime.registry runtime.arena

/-- Write back the actual ordinary successor, keeping the registry and other
retained roots. No earlier cell snapshot is restored. -/
def Runtime.withState (runtime : Runtime signature algebra program result)
    (state : Source.State signature algebra program result) : Runtime signature algebra program result :=
  ⟨state.control, { runtime.arena with cells := state.cells }, state.liveRegions, runtime.registry⟩

theorem Runtime.writeback_has_exact_state (runtime : Runtime signature algebra program result)
    (state : Source.State signature algebra program result) : (runtime.withState state).state = state := rfl

theorem Runtime.writeback_keeps_retained_support (runtime : Runtime signature algebra program result)
    (state : Source.State signature algebra program result) : (runtime.withState state).executionSupport = runtime.executionSupport := rfl

structure Activated (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) where
  activation : Activation signature algebra program shape
  regions : List (Id .region)
  registry : Registry signature algebra program

def Runtime.support (runtime : Runtime signature algebra program result) (external : List Reference) : List Reference :=
  registryReferences runtime.registry ++ UseScope.stateReferences runtime.control.store.fields ++ external

/-- `external` supplies the supported caller, code table, and other retained
futures. Registry templates, physical fields, and arena support are included
here, so activation cannot omit another retained template or live branch. -/
def Runtime.activate [DecidableEq (ControlShape signature)] (shape : ControlShape signature) (identity : Id .control)
    (runtime : Runtime signature algebra program result) (external : List Reference) : Option (Activated signature algebra program shape) :=
  (TemplateRegistry.lookup shape identity runtime.registry).bind fun template =>
    let supported := runtime.support external
    let relocation := allocation template.image runtime.arena supported
    (registerRecords (relocateRecords relocation template.image.dormant) runtime.registry).map fun registry =>
      ⟨instantiate template runtime.arena supported,
        template.image.regions.map (relocation.name .region) ++ runtime.regions, registry⟩

def Runtime.afterActivation (runtime : Runtime signature algebra program result)
    (active : Activated signature algebra program shape) (computation : Program signature algebra program result) :
    Runtime signature algebra program result :=
  ⟨⟨runtime.control.store, computation⟩, active.activation.arena, active.regions, active.registry⟩

def Runtime.resume [DecidableEq (ControlShape signature)] (shape : ControlShape signature) (identity : Id .control)
    (runtime : Runtime signature algebra program result) (value : RuntimeValue signature algebra program shape.input)
    (outside : Context signature algebra program shape.answer result) (external : List Reference) : Option (Runtime signature algebra program result) :=
  (runtime.activate shape identity (valueReferences value ++ external)).map fun active =>
    runtime.afterActivation active (outside.plug (reenter active.activation.saved.payload (.returned value)))

def Runtime.inject [DecidableEq (ControlShape signature)] (shape : ControlShape signature) (identity : Id .control)
    (runtime : Runtime signature algebra program result) (body : Computation signature algebra program context shape.input)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Context signature algebra program shape.answer result) (external : List Reference) : Option (Runtime signature algebra program result) :=
  (runtime.activate shape identity (body.references ++ environmentReferences bindings ++ external)).map fun active =>
    runtime.afterActivation active (outside.plug (reenter active.activation.saved.payload (.evaluate body bindings)))

def Runtime.successor [DecidableEq (ControlShape signature)] (identity : Id .control)
    (runtime : Runtime signature algebra program result) (value : RuntimeValue signature algebra program input)
    (returned : Computation signature algebra program (body :: context) answer)
    (clauses : Clauses signature algebra program effect .deep context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Context signature algebra program answer result) (external : List Reference) : Option (Runtime signature algebra program result) :=
  (runtime.activate ⟨.shallow, effect, input, body⟩ identity
    (valueReferences value ++ returned.references ++ clauses.references ++ environmentReferences bindings ++ external)).map fun active =>
    runtime.afterActivation active (reenterWith active.activation.saved.payload value returned clauses bindings outside)

end Source.Multi

namespace Target.Multi

structure Runtime (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  control : ControlState signature algebra program result
  arena : Arena signature algebra program
  regions : List (Id .region)
  registry : Registry signature algebra program

def Runtime.state (runtime : Runtime signature algebra program result) : State signature algebra program result :=
  ⟨runtime.control, runtime.arena.cells, runtime.regions⟩

/-- Registry and suspended roots supplement the current state. Current cells
are owned once by the arena and are reserved by the ordinary state rules. -/
def retainedSupport (registry : Registry signature algebra program) (arena : Arena signature algebra program) : List Reference :=
  registryReferences registry ++ arena.dormant.flatMap Record.references ++
    arena.active.flatMap payloadReferences

def Runtime.executionSupport (runtime : Runtime signature algebra program result) : List Reference :=
  retainedSupport runtime.registry runtime.arena

/-- Write back the actual ordinary successor, keeping the registry and other
retained roots. No earlier cell snapshot is restored. -/
def Runtime.withState (runtime : Runtime signature algebra program result)
    (state : Target.State signature algebra program result) : Runtime signature algebra program result :=
  ⟨state.control, { runtime.arena with cells := state.cells }, state.liveRegions, runtime.registry⟩

theorem Runtime.writeback_has_exact_state (runtime : Runtime signature algebra program result)
    (state : Target.State signature algebra program result) : (runtime.withState state).state = state := rfl

theorem Runtime.writeback_keeps_retained_support (runtime : Runtime signature algebra program result)
    (state : Target.State signature algebra program result) : (runtime.withState state).executionSupport = runtime.executionSupport := rfl

structure Activated (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) where
  activation : Activation signature algebra program shape
  regions : List (Id .region)
  registry : Registry signature algebra program

def Runtime.support (runtime : Runtime signature algebra program result) (external : List Reference) : List Reference :=
  registryReferences runtime.registry ++ UseScope.stateReferences runtime.control.store.fields ++ external

def Runtime.activate [DecidableEq (ControlShape signature)] (shape : ControlShape signature) (identity : Id .control)
    (runtime : Runtime signature algebra program result) (external : List Reference) : Option (Activated signature algebra program shape) :=
  (TemplateRegistry.lookup shape identity runtime.registry).bind fun template =>
    let supported := runtime.support external
    let relocation := allocation template.image runtime.arena supported
    (registerRecords (relocateRecords relocation template.image.dormant) runtime.registry).map fun registry =>
      ⟨instantiate template runtime.arena supported,
        template.image.regions.map (relocation.name .region) ++ runtime.regions, registry⟩

def Runtime.afterActivation (runtime : Runtime signature algebra program result)
    (active : Activated signature algebra program shape) (configuration : Configuration signature algebra program result) :
    Runtime signature algebra program result :=
  ⟨⟨runtime.control.store, configuration⟩, active.activation.arena, active.regions, active.registry⟩

def Runtime.resume [DecidableEq (ControlShape signature)] (shape : ControlShape signature) (identity : Id .control)
    (runtime : Runtime signature algebra program result) (value : RuntimeValue signature algebra program shape.input)
    (outside : Stack signature algebra program shape.answer result) (external : List Reference) : Option (Runtime signature algebra program result) :=
  (runtime.activate shape identity (valueReferences value ++ external)).map fun active =>
    runtime.afterActivation active (reenter active.activation.saved value outside)

def Runtime.inject [DecidableEq (ControlShape signature)] (shape : ControlShape signature) (identity : Id .control)
    (runtime : Runtime signature algebra program result) (body : Entry signature algebra program shape.input)
    (outside : Stack signature algebra program shape.answer result) (external : List Reference) : Option (Runtime signature algebra program result) :=
  (runtime.activate shape identity (body.body.references ++ environmentReferences body.environment ++ external)).map fun active =>
    runtime.afterActivation active (Target.inject active.activation.saved body outside)

def Runtime.successor [DecidableEq (ControlShape signature)] (identity : Id .control)
    (runtime : Runtime signature algebra program result) (value : RuntimeValue signature algebra program input)
    (returned : Code signature algebra program (body :: context) [] answer)
    (clauses : Clauses signature algebra program effect .deep context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Stack signature algebra program answer result) (external : List Reference) : Option (Runtime signature algebra program result) :=
  (runtime.activate ⟨.shallow, effect, input, body⟩ identity
    (valueReferences value ++ returned.references ++ clauses.references ++ environmentReferences bindings ++ external)).map fun active =>
    runtime.afterActivation active (reenterWith active.activation.saved value returned clauses bindings outside)

end Target.Multi

namespace Defunctionalization

structure MultiDataRelated (source : Source.Multi.Runtime signature algebra program result)
    (target : Target.Multi.Runtime signature algebra program result) : Prop where
  store : ControlHeapRelated source.control.store target.control.store
  arena : target.arena = templateArena source.arena
  regions : target.regions = source.regions
  registry : target.registry = templateRegistry source.registry

theorem retained_support_corresponds (registry : Source.Multi.Registry signature algebra program)
    (arena : Source.Multi.Arena signature algebra program) :
    Target.Multi.retainedSupport (templateRegistry registry) (templateArena arena) = Source.Multi.retainedSupport registry arena := by
  simp only [Target.Multi.retainedSupport, Source.Multi.retainedSupport, registry_reference_support,
    templateArena, List.flatMap_map, template_record_references,
    Target.Multi.payloadReferences, templateFuture, capture_references, Source.Multi.Future.references]

theorem execution_support_corresponds (related : MultiDataRelated source target) :
    target.executionSupport = source.executionSupport := by
  simp only [Target.Multi.Runtime.executionSupport, Source.Multi.Runtime.executionSupport,
    related.registry, related.arena, retained_support_corresponds]

structure MultiRuntimeRelated (source : Source.Multi.Runtime signature algebra program result)
    (target : Target.Multi.Runtime signature algebra program result) : Prop extends MultiDataRelated source target where
  computation : ProgramRelated source.control.computation .done target.control.configuration

theorem MultiRuntimeRelated.as_state (related : MultiRuntimeRelated source target) :
    ExecutionStateRelated source.state target.state :=
  ⟨related.store, congrArg Target.Multi.Arena.cells related.arena, related.regions.symm, related.computation⟩

theorem MultiDataRelated.writeback
    {source : Source.Multi.Runtime signature algebra program result}
    {target : Target.Multi.Runtime signature algebra program result}
    (related : MultiDataRelated source target)
    {sourceState : Source.State signature algebra program result}
    {targetState : Target.State signature algebra program result}
    (states : ExecutionStateRelated sourceState targetState) :
    MultiRuntimeRelated (source.withState sourceState) (target.withState targetState) := by
  refine ⟨⟨states.store, ?_, states.regions.symm, related.registry⟩, states.computation⟩
  change { target.arena with cells := targetState.cells } = templateArena { source.arena with cells := sourceState.cells }
  rw [related.arena, states.cells]
  rfl

theorem registered_initialization
    (body : Source.Computation signature algebra program context result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (arena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program) :
    MultiRuntimeRelated
      ⟨⟨sourceStore, .evaluate body bindings⟩, arena, regions, registry⟩
      ⟨⟨targetStore, .code (computation body) (environment bindings) .nil .done⟩,
        templateArena arena, regions, templateRegistry registry⟩ :=
  ⟨⟨stores, rfl, rfl, rfl⟩, .evaluate body bindings .done⟩

theorem registered_response_entry
    {sourceFuture : Source.Context signature algebra program input result}
    {targetFuture : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceFuture targetFuture)
    (response : Source.RuntimeValue signature algebra program input)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (arena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program) :
    MultiRuntimeRelated
      ⟨⟨sourceStore, sourceFuture.plug (.returned response)⟩, arena, regions, registry⟩
      ⟨⟨targetStore, .returned (value response) targetFuture⟩, templateArena arena, regions, templateRegistry registry⟩ :=
  ⟨⟨stores, rfl, rfl, rfl⟩, (EntryRelated.returned response outside).as_program⟩

def registeredActivation (source : Source.Multi.Activated signature algebra program shape) : Target.Multi.Activated signature algebra program shape :=
  ⟨templateActivation source.activation, source.regions, templateRegistry source.registry⟩

theorem runtime_support_corresponds (related : MultiDataRelated source target) (external : List Reference) :
    target.support external = source.support external := by
  simp only [Target.Multi.Runtime.support, Source.Multi.Runtime.support, related.registry,
    registry_reference_support, related.store.fields]

theorem registered_activation_corresponds [DecidableEq (ControlShape signature)]
    (related : MultiDataRelated source target) (shape : ControlShape signature) (identity : Id .control) (external : List Reference) :
    target.activate shape identity external = (source.activate shape identity external).map registeredActivation := by
  unfold Target.Multi.Runtime.activate Source.Multi.Runtime.activate
  rw [related.registry]
  simp only [templateRegistry, TemplateRegistry.lookup_map]
  cases TemplateRegistry.lookup shape identity source.registry with
  | none => rfl
  | some selected =>
    simp only [Option.map_some, Option.bind_some, runtime_support_corresponds related, related.arena]
    change (Target.Multi.registerRecords
      (Target.Multi.relocateRecords (Target.Multi.allocation (templateImage selected.image) (templateArena source.arena) (source.support external))
        ((templateImage selected.image).dormant)) (templateRegistry source.registry)).map _ = _
    rw [template_allocation_corresponds]
    simp only [templateImage, ← template_records_map, template_records_relocation, dormant_registrations_correspond]
    generalize Source.Multi.registerRecords
      (Source.Multi.relocateRecords (Source.Multi.allocation selected.image source.arena (source.support external)) selected.image.dormant)
      source.registry = installed
    cases installed with
    | none => rfl
    | some registry =>
      simp only [Option.map_some, registeredActivation]
      rw [template_instantiation_corresponds]
      simp only [template, template_allocation_corresponds, related.regions]
      rfl

theorem after_activation_corresponds (related : MultiDataRelated source target)
    (active : Source.Multi.Activated signature algebra program shape)
    (entry : EntryRelated sourceEntry targetEntry) :
    MultiRuntimeRelated (source.afterActivation active sourceEntry)
      (target.afterActivation (registeredActivation active) targetEntry) :=
  ⟨⟨related.store, rfl, rfl, rfl⟩, entry.as_program⟩

theorem registered_resume_corresponds [DecidableEq (ControlShape signature)]
    {source : Source.Multi.Runtime signature algebra program result} {target : Target.Multi.Runtime signature algebra program result}
    (related : MultiDataRelated source target) (shape : ControlShape signature) (identity : Id .control)
    (input : Source.RuntimeValue signature algebra program shape.input)
    {sourceOutside : Source.Context signature algebra program shape.answer result}
    {targetOutside : Target.Stack signature algebra program shape.answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) (external : List Reference) :
    Option.Rel MultiRuntimeRelated (source.resume shape identity input sourceOutside external)
      (target.resume shape identity (value input) targetOutside external) := by
  unfold Source.Multi.Runtime.resume Target.Multi.Runtime.resume
  rw [value_reference_support, registered_activation_corresponds related]
  cases source.activate shape identity (Source.valueReferences input ++ external) with
  | none => exact .none
  | some active => exact .some (after_activation_corresponds related active
      (resumption_reentry_corresponds (template_future_correspondence active.activation.saved) input outside))

theorem registered_injection_corresponds [DecidableEq (ControlShape signature)]
    {source : Source.Multi.Runtime signature algebra program result} {target : Target.Multi.Runtime signature algebra program result}
    (related : MultiDataRelated source target) (shape : ControlShape signature) (identity : Id .control)
    (body : Source.Computation signature algebra program context shape.input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceOutside : Source.Context signature algebra program shape.answer result}
    {targetOutside : Target.Stack signature algebra program shape.answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) (external : List Reference) :
    Option.Rel MultiRuntimeRelated (source.inject shape identity body bindings sourceOutside external)
      (target.inject shape identity ⟨context, computation body, environment bindings⟩ targetOutside external) := by
  unfold Source.Multi.Runtime.inject Target.Multi.Runtime.inject
  rw [computation_reference_support, environment_reference_support, registered_activation_corresponds related]
  cases source.activate shape identity (body.references ++ Source.environmentReferences bindings ++ external) with
  | none => exact .none
  | some active => exact .some (after_activation_corresponds related active
      (computation_injection_corresponds (template_future_correspondence active.activation.saved) body bindings outside))

theorem registered_successor_corresponds [DecidableEq (ControlShape signature)]
    (related : MultiDataRelated source target) (identity : Id .control)
    (inputValue : Source.RuntimeValue signature algebra program input)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect .deep context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) (external : List Reference) :
    Option.Rel MultiRuntimeRelated (source.successor identity inputValue returned clauses bindings sourceOutside external)
      (target.successor identity (value inputValue) (computation returned) (Defunctionalization.clauses clauses)
        (environment bindings) targetOutside external) := by
  unfold Source.Multi.Runtime.successor Target.Multi.Runtime.successor
  rw [value_reference_support, computation_reference_support, clauses_reference_support, environment_reference_support,
    registered_activation_corresponds related]
  cases source.activate ⟨.shallow, effect, input, body⟩ identity
      (Source.valueReferences inputValue ++ returned.references ++ clauses.references ++ Source.environmentReferences bindings ++ external) with
  | none => exact .none
  | some active => exact .some (after_activation_corresponds related active
      (successor_handler_reentry_corresponds (template_future_correspondence active.activation.saved)
        inputValue returned clauses bindings outside))

end Defunctionalization
end BoundaryV2.Generalized
