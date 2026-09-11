import BoundaryV2.GraphPosition
import BoundaryV2.TerminatorAdmission

namespace BoundaryV2.Profile.Graph.Admission

def block (program : Target.Program) (reference : BlockId) : Option Target.Block := program.blocks[reference.value]?
def slotType (source : Target.Block) (slot : Target.Slot) : Option (SchemaId .target) :=
  (Target.Admission.blockSlots source)[slot.value]?

def expectedResult (program : Target.Program) (source : Target.Block) : Option (SchemaId .target) :=
  match source.terminator with
  | .call function _ _ => (program.functions[function.value]?).map (·.result)
  | .perform operation => (program.effects[operation.effect.value]?).map (·.result)
  | .apply closure _ _ | .withRegion _ closure _ _ | .protect closure _ _ _ _ _ => do
    return (← Target.Admission.computation program (← slotType source closure)).result
  | .handle handler _ _ _ _ | .resumeWith _ _ handler _ _ =>
    (program.handlers[handler.value]?).map (·.answer)
  | .resumeValue token _ _ | .resumeComputation token _ _ | .dispose token _ => do
    return (← Target.Admission.resumption program (← slotType source token)).answer
  | _ => none

def nextEdge : Target.Terminator → Option Target.Edge
  | .call _ _ next | .apply _ _ next | .handle _ _ _ _ next
  | .resumeValue _ _ next | .resumeWith _ _ _ _ next | .resumeComputation _ _ next
  | .dispose _ next | .protect _ _ _ _ _ next | .withRegion _ _ _ next => some next
  | .perform operation | .forward operation => some operation.next
  | _ => none

def parentType (program : Target.Program) (state : State) (reference : Option NodeId) : Option (SchemaId .target) :=
  match reference with
  | none => some program.roots.result
  | some reference => do
    match ← node state reference with
    | .continuation saved => expectedResult program (← block program saved.sourceBlock)
    | .attachment activation _ _ _ _ => return (← handler program state activation).input
    | .regionScope source _ _ | .protection source _ _ _ _ _ => expectedResult program (← block program source)
    | .injection continuation =>
      let .continuation saved ← node state continuation | none
      expectedResult program (← block program saved.sourceBlock)
    | .cleanupReturn obligation _ _ =>
      let .obligation source _ _ _ ← node state obligation.node | none
      let source ← block program source
      let .protect _ cleanup _ _ _ _ := source.terminator | none
      return (← Target.Admission.computation program (← slotType source cleanup)).result
    | .disposalReturn schema _ _ => return (← Target.Admission.resumption program schema).answer
    | _ => none

def evidenceValid (state : State) (reference : Option NodeId) : Bool := reference.all fun reference =>
  match node state reference with | some (.attachment ..) => true | _ => false
def regionValid (state : State) (reference : Option NodeId) : Bool := reference.all fun reference =>
  match node state reference with | some (.region ..) => true | _ => false

def frameRegion (state : State) (record : Node) : Option (Option NodeId) := match record with
  | .control control => some control.region
  | .continuation saved => some saved.region
  | .attachment _ _ _ _ region => some region
  | .regionScope _ region _ => some (some region)
  | .protection _ _ _ _ region loan => some (loan.or region)
  | .injection continuation => match node state continuation with
    | some (.continuation saved) => some saved.region
    | _ => none
  | _ => none

def availableRegion (state : State) (parent : Option NodeId) : Option NodeId :=
  ((chain state frameParent isFrame (inventory state) parent).bind fun path =>
    path.findSome? (fun reference => (node state reference).bind (frameRegion state))).getD none

def regionContextValid (state : State) (required parent : Option NodeId) : Bool :=
  required.all (containsScope state (availableRegion state parent))

def valueRegionValid (program : Target.Program) (state : State) (value : Value) (context : Option NodeId) : Bool :=
  ((do
    let shape ← program.schemas[value.schema.value]?
    let required : Option NodeId ← match shape with
      | .internal (.region _) => match value.body with | .reference reference => some (some reference) | _ => none
      | .internal (.cell _ _) => do
        let .reference reference := value.body | none
        let .cell _ region _ ← node state reference | none
        pure (some region)
      | .internal (.borrowed _ _) => do
        let .reference reference := value.body | none
        let .borrow _ _ region ← node state reference | none
        pure (some region)
      | _ => some none
    return required.all (containsScope state context)) : Option Bool).getD false

def valueScopeValid (program : Target.Program) (state : State) (value : Value)
    (parent region : Option NodeId) : Bool :=
  valueRegionValid program state value region &&
  (match program.schemas[value.schema.value]? with
  | some (.internal (.capability _)) => match value.body with
    | .reference attachment => containsScope state parent attachment | _ => false
  | some _ => true
  | none => false)

def scopeValid (state : State) (parent evidence region : Option NodeId) : Bool :=
  evidenceValid state evidence && evidence.all (containsScope state parent) &&
    regionValid state region && regionContextValid state region parent

def loanResources (state : State) (region : NodeId) : List NodeId := state.nodes.filterMap fun record => do
  let .protection _ obligation _ _ _ (some loan) := record | none
  if loan != region then none else do
    let .obligation _ _ (some resource) _ ← node state obligation.node | none
    let .owned resource := resource.body | none
    return resource.node

def ownedValuesValid (program : Target.Program) (state : State) (values : List Value) : Bool :=
  values.all fun value => (match value.body with | .owned _ => true | _ => false) && valueValid program state value value.schema

def aggregateValid (program : Target.Program) (state : State) (schema : SchemaId .target)
    (tag : Nat) (fields : List Value) : Bool := !Traits.check program.schemas .external schema &&
  program.schemas[schema.value]?.any fun shape => match shape with
    | .product types => tag == 0 && valuesValid program state fields types
    | .sum types => types[tag]?.any (fun type => valuesValid program state fields [type])
    | .seq element => tag == 0 && fields.all (valueValid program state · element)
    | .vector element maximum => tag == 0 && fields.length ≤ maximum && fields.all (valueValid program state · element)
    | .array element length => tag == 0 && fields.length == length && fields.all (valueValid program state · element)
    | _ => false

/-- Intrinsic record interfaces and their direct lexical references. Capture
bounds, transitive value support, and effect obligations are checked separately;
this predicate alone does not admit a saved machine. -/
def recordValid (program : Target.Program) (state : State) (index : Nat) (record : Node) : Bool := ((do
  match record with
  | .control control =>
    let source ← block program control.block
    let function ← program.functions[source.function.value]?
    return valuesValid program state control.arguments source.parameters &&
      parentType program state control.parent == some function.result &&
      scopeValid state control.parent control.evidence control.region &&
      control.arguments.all (valueScopeValid program state · control.parent control.region)
  | .continuation saved =>
    let source ← block program saved.sourceBlock
    let edge ← nextEdge source.terminator
    let target ← block program edge.block
    let function ← program.functions[source.function.value]?
    return saved.arguments.length == edge.arguments.length && edge.arguments.length == target.parameters.length &&
      ((saved.arguments.zip edge.arguments).zip target.parameters).all (fun ((argument, spec), schema) =>
        match argument, spec with
        | none, .returned => true
        | some value, .slot _ => valueValid program state value schema && valueScopeValid program state value saved.parent saved.region
        | _, _ => false) && parentType program state saved.parent == some function.result &&
      scopeValid state saved.parent saved.evidence saved.region
  | .handler definition values evidence region =>
    let definition ← program.handlers[definition.value]?
    return valuesValid program state values definition.state && evidenceValid state evidence && regionValid state region &&
      values.all (valueRegionValid program state · region)
  | .attachment activation outer parent phase region =>
    let .handler definition _ evidence actualRegion ← node state activation | none
    let definition ← program.handlers[definition.value]?
    return outer == evidence && region == actualRegion && evidenceValid state outer &&
      (match phase with
      | .active => parentType program state parent == some definition.answer &&
          outer.all (containsScope state parent) && regionContextValid state region parent
      | .suspended => parent.isNone)
  | .environment values tail => return tail.isNone && values.all (fun value => valueValid program state value value.schema)
  | .aggregate schema tag fields => return aggregateValid program state schema tag fields
  | .region descriptor outer obligations =>
    return descriptor.value < program.scopes.regionCount && obligations.isEmpty && regionValid state outer
  | .regionScope source region parent =>
    let .region descriptor outer _ ← node state region | none
    let sourceBlock ← block program source
    let .withRegion actual _ _ _ := sourceBlock.terminator | none
    let after ← parent
    let .continuation saved ← node state after | none
    return actual == descriptor && parentType program state parent == expectedResult program sourceBlock &&
      saved.sourceBlock == source && saved.region == outer
  | .cell schema region content =>
    let .internal (.cell element descriptor) ← program.schemas[schema.value]? | none
    let .region actual _ _ ← node state region | none
    let content ← content
    return descriptor == actual && valueValid program state content element && valueRegionValid program state content (some region)
  | .injection continuation =>
    let .continuation saved ← node state continuation | none
    let source ← block program saved.sourceBlock
    return match source.terminator with | .perform _ => true | _ => false
  | .computation constructor environment =>
    let constructor ← program.constructors[constructor.value]?
    let .environment values _ ← node state environment | none
    let capture ← program.scopes.captures[constructor.capture.value]?
    return values.map Value.schema == capture.fields
  | .oneShot capture => return (← Target.Admission.resumption program capture.schema).use != .multi
  | .multiTemplate capture => return (← Target.Admission.resumption program capture.schema).use == .multi
  | .package schema continuation =>
    let .internal (.suspensionPackage token) ← program.schemas[schema.value]? | none
    return valueValid program state continuation token
  | .resource schema value =>
    let descriptor ← Target.Admission.resourceDescriptor program schema
    return valueValid program state value descriptor.representation
  | .borrow schema resource region =>
    let .internal (.borrowed expected descriptor) ← program.schemas[schema.value]? | none
    let .resource actual _ ← node state resource | none
    let .region actualRegion _ _ ← node state region | none
    return actual == expected && actualRegion == descriptor && loanResources state region == [resource]
  | .pending effect payload continuation source =>
    let definition ← program.effects[effect.value]?
    let .continuation saved ← node state continuation | none
    let sourceBlock ← block program source
    let .perform operation := sourceBlock.terminator | none
    return definition.external && valueValid program state payload definition.payload && saved.sourceBlock == source &&
      operation.effect == effect && operation.capability.isNone && parentType program state (some continuation) == some definition.result
  | .protection source obligation parent evidence region loan =>
    let sourceBlock ← block program source
    let .protect _ _ _ _ loanRegion _ := sourceBlock.terminator | none
    let .obligation actualSource _ _ .pending ← node state obligation.node | none
    let after ← parent
    let .continuation saved ← node state after | none
    let loanValid ← match loanRegion, loan with
      | none, none => some true
      | some descriptor, some loan => do
        let .region actual outer _ ← node state loan | none
        pure (descriptor == actual && outer == region)
      | _, _ => some false
    return actualSource == source && saved.sourceBlock == source && saved.evidence == evidence && saved.region == region && loanValid
  | .cleanupReturn obligation parent _ =>
    let .obligation source _ _ (.running current) ← node state obligation.node | none
    let after ← parent
    let .continuation saved ← node state after | none
    return current.value == index && saved.sourceBlock == source
  | .disposalReturn schema _ values =>
    return (← Target.Admission.resumption program schema).use != .multi && state.roots.exit.isSome && ownedValuesValid program state values
  | .unwind _ values =>
    return state.status == .unwinding && state.roots.current == some ⟨index⟩ && ownedValuesValid program state values
  | .obligation source cleanup resource status =>
    let sourceBlock ← block program source
    let .protect _ cleanupSlot _ resourceSlot _ _ := sourceBlock.terminator | none
    match status with
    | .pending =>
      let cleanup ← cleanup
      let cleanupType ← slotType sourceBlock cleanupSlot
      let resourceValid ← match resourceSlot, resource with
        | none, none => some true
        | some slot, some resource => pure (valueValid program state resource (← slotType sourceBlock slot))
        | _, _ => some false
      return valueValid program state cleanup cleanupType && resourceValid
    | .running current =>
      let .cleanupReturn obligation _ _ ← node state current | none
      return cleanup.isNone && resource.isNone && obligation.node.value == index
    | _ => return false
  | .exit exit =>
    let reasonValid ← match exit.reason with
      | .normal value => do
        let stop ← exit.stop
        let .continuation saved ← node state stop | none
        let source ← block program saved.sourceBlock
        let .protect .. := source.terminator | none
        pure (valueValid program state value value.schema && normalReturning state stop &&
          parentType program state exit.stop == some value.schema)
      | .abandoned => do
        let stop ← exit.stop
        let .continuation saved ← node state stop | none
        let source ← block program saved.sourceBlock
        let .dispose .. := source.terminator | none
        pure (normalReturning state stop)
      | .failure value => pure (valueValid program state value program.roots.failure && exit.stop.isNone)
      | .cancellation => pure (exit.cancellation.isSome && exit.stop.isNone)
    return reasonValid && exit.cleanupFailures.all (valueValid program state · program.roots.failure) &&
      ownedValuesValid program state exit.discarded &&
      (exit.outer.isNone || (exit.cancellation.isNone && exit.cleanupFailures.isEmpty)) &&
      exit.cancellation.all (fun reason => match reason with | .text text => UTF8.valid text | .bytes _ => true)
  | .branch .. => return false) : Option Bool).getD false

def recordsValid (program : Target.Program) (state : State) : Bool :=
  state.nodes.zipIdx.all (fun (record, index) => recordValid program state index record)

theorem every_record_checked (program : Target.Program) (state : State) (index : Nat) (record : Node)
    (accepted : recordsValid program state = true) (actual : state.nodes[index]? = some record) :
    recordValid program state index record = true :=
  List.all_eq_true.mp accepted (record, index) (List.mem_zipIdx_iff_getElem?.mpr actual)

end BoundaryV2.Profile.Graph.Admission
