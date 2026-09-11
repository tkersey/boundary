import BoundaryV2.SourceValues
import BoundaryV2.SourceContracts
import BoundaryV2.SourceUsage

namespace BoundaryV2.Profile.Source.Machine

def activeAttachments (frames : List Frame) : List AttachmentId := frames.filterMap fun frame => match frame with
  | .handler activation => some activation.identity | _ => none

def activeRegions (frames : List Frame) : List RegionInstanceId := frames.filterMap fun frame => match frame with
  | .region identity => some identity | _ => none

def bindArguments (context : Context) (vars : List VariableId) (values : List Located) : Bool :=
  vars.length == values.length && decide vars.Nodup &&
  (vars.zip values).all (fun (var, value) => context.source.variables[var.value]? == some value.value.schema)

def createScope (state : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located)
    (environment : Environment) : Except Invalid (State × Environment) := do
  require (bindArguments context vars values) .type
  if parent.isSome && values.all (fun value => (ownedTokens value.value).isEmpty) then
    let bindings := (vars.zip values).map (fun (var, located) => Binding.mk var located)
    return (state, bindings ++ environment.filter (fun binding => !vars.contains binding.var))
  require (state.heap.nextScope == state.heap.scopes.length) .scope
  let scope : LexicalScopeId := ⟨state.heap.nextScope⟩
  let relocated := values.mapIdx (fun index value => retainAt value (.lexical scope index))
  let heap ← fromOption (moveValues state.heap values (Custody.Owner.lexical scope)) .custody
  let record : Scope := ⟨scope, invocation, parent, vars.length, relocated⟩
  let heap := { heap with scopes := heap.scopes ++ [record], nextScope := heap.nextScope + 1 }
  let bindings := (vars.zip relocated).map (fun (var, located) => Binding.mk var located)
  let result := bindings ++ environment.filter (fun binding => !vars.contains binding.var)
  return ({ state with heap := heap, scope := scope }, result)

def invokeFunction (state : State) (context : Context) (function : FunctionId .source)
    (environment : Environment) (arguments : List Located) : Except Invalid Transition := do
  let definition ← fromOption context.source.functions[function.value]? .reference
  let body ← fromOption definition.body .reference
  let captures := Analysis.captures context.captures function
  let captured ← captures.mapM (fun var => fromOption (lookupVariable environment var) .reference)
  require (arguments.length == definition.parameters.length) .operands
  require (state.heap.nextInvocation == state.heap.invocations.length) .scope
  let invocation : InvocationId := ⟨state.heap.nextInvocation⟩
  let (after, enteredEnvironment) ← createScope state context invocation none (captures ++ definition.parameters) (captured ++ arguments) []
  let record : Invocation := ⟨invocation, function, activeAttachments state.stack, activeRegions state.stack⟩
  let heap := { after.heap with
    invocations := after.heap.invocations ++ [record]
    nextInvocation := after.heap.nextInvocation + 1 }
  return ⟨{ after with
    control := .term body enteredEnvironment
    stack := .invocation state.invocation state.scope :: state.stack
    invocation := invocation
    heap := heap }, []⟩

def applyClosure (state : State) (context : Context) (closure : Located)
    (arguments : List Located) : Except Invalid Transition := do
  let (_, .closure _ function environment) ← lookupObject state closure | throw .type
  let heap ← match closure.value with
    | .reference _ _ (some _) => fromOption (retireObject state.heap closure) .custody
    | .reference _ _ none => pure state.heap
    | _ => throw .type
  invokeFunction { state with heap := heap } context function environment arguments

def enterInvocation (state : State) (context : Context) : Except Invalid Transition := do
  let .invoke function environment arguments := state.control | throw .inactive
  invokeFunction state context function environment arguments

def enterBinding (state : State) (context : Context) : Except Invalid Transition := do
  let .delivered value := state.control | throw .inactive
  let .binding var next environment parent :: tail := state.stack | throw .inactive
  let (after, enteredEnvironment) ← createScope state context state.invocation (some parent) [var] [value] environment
  return ⟨{ after with
    control := .term next enteredEnvironment
    stack := if after.scope == parent then tail else .lexical after.scope :: tail }, []⟩

def enterPattern (state : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId)
    (environment : Environment) : Except Invalid Transition := do
  let values := parts.map (fun value => Located.mk value owner)
  let (after, enteredEnvironment) ← createScope state context state.invocation (some state.scope) vars values environment
  return ⟨{ after with control := .term body enteredEnvironment, stack := if after.scope == state.scope then state.stack else .lexical after.scope :: state.stack }, []⟩

/-- These rules only inspect source AST constructors. Calls stay operational
and may recurse indefinitely; no static-analysis bound enters execution. -/
def executeControlTerm (state : State) (context : Context) : Except Invalid Transition := do
  let .execute (.term term) environment operands := state.control | throw .inactive
  require (operands.all (current state.heap)) .custody
  match term with
  | .conditional _ yes no => match operands with
    | [⟨.scalar schema condition, _⟩] =>
      require ((← fromOption context.source.schemas[schema.value]? .type) == .boolean && (condition == 0 || condition == 1)) .type
      return ⟨{ state with control := .term (if condition == 1 then yes else no) environment }, []⟩
    | _ => throw .operands
  | .call function _ => return ⟨{ state with control := .invoke function environment operands }, []⟩
  | .apply _ _ => match operands with
    | closure :: arguments => applyClosure state context closure arguments
    | _ => throw .operands
  | .fail _ => match operands with
    | [value] =>
      require (value.value.schema == context.source.failure) .type
      return ⟨{ state with control := .unwind ⟨.failure value.value, [], none⟩ }, []⟩
    | _ => throw .operands
  | .matchSum _ cases => match operands with
    | [⟨.variant _ tag payload, owner⟩] =>
      let (var, body) ← fromOption cases[tag]? .reference
      enterPattern state context [var] [payload] owner body environment
    | _ => throw .operands
  | .unpackProduct _ vars body => match operands with
    | [⟨.product _ parts, owner⟩] => enterPattern state context vars parts owner body environment
    | _ => throw .operands
  | .value _ | .bind .. | .yieldThen _ => throw .inactive
  | .perform _ | .handle .. | .resumeValue .. | .resumeWith .. | .resumeComputation ..
  | .protect .. | .withRegion .. | .dispose _ => throw .inactive

def liveHoldings (heap : Heap) (scope : Scope) : List (Located × CustodyToken) :=
  scope.holdings.flatMap (fun value =>
    (ownedTokens value.value).filterMap (fun token =>
      if Custody.has heap.custody token value.owner then some (value, token) else none))

/-- A result moves to the caller before its old scope is released. Its former
holding remains as an inactive record, preserving cleanup creation order. -/
def leaveScope (state : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) : Except Invalid Transition := do
  let departed := state.scope
  let (after, owner) ← temporary { state with scope := parent, invocation := invocation, stack := tail }
  let heap ← fromOption (moveValues after.heap [value] (fun _ => owner)) .custody
  let delivered ← finishTemporary { after with heap := heap } (retainAt value owner)
  return ⟨{ delivered.state with control := .release departed (.deliver (retainAt value owner)) }, []⟩

def leaveInvocation (state : State) : Except Invalid Transition := do
  let .delivered value := state.control | throw .inactive
  let .invocation caller parent :: tail := state.stack | throw .inactive
  leaveScope state parent caller tail value

def leaveLexical (state : State) : Except Invalid Transition := do
  let .delivered value := state.control | throw .inactive
  let .lexical scope :: tail := state.stack | throw .inactive
  require (scope == state.scope) .scope
  let record ← fromOption state.heap.scopes[scope.value]? .scope
  let parent ← fromOption record.parent .scope
  let result ← leaveScope state parent state.invocation tail value
  let .release _ (.deliver delivered) := result.state.control | throw .inactive
  let remaining := record.holdings.flatMap (liveOwned result.state.heap)
  let parentRecord ← fromOption result.state.heap.scopes[parent.value]? .scope
  let owner := fun index => Custody.Owner.temporary parent (parentRecord.nextOwner + index)
  let heap ← fromOption (moveValues result.state.heap remaining owner) .custody
  let inherited := remaining.mapIdx (fun index located => retainAt located (owner index))
  let parentRecord := { parentRecord with
    nextOwner := parentRecord.nextOwner + remaining.length
    holdings := inherited ++ parentRecord.holdings }
  return ⟨{ result.state with
    heap := { heap with scopes := heap.scopes.set parent.value parentRecord }
    control := .delivered delivered }, []⟩

def resumeRelease (state : State) (after : AfterRelease) : Transition :=
  ⟨{ state with control := match after with
    | .deliver value => .delivered value
    | .unwind exit => .unwind exit }, []⟩

def finishEmptyRelease (state : State) : Except Invalid Transition := do
  let .release scope after := state.control | throw .inactive
  let record ← fromOption state.heap.scopes[scope.value]? .scope
  require (liveHoldings state.heap record).isEmpty .custody
  return resumeRelease state after

def Context.typingValid (context : Context) : Bool :=
  (Analysis.inferResults context.source).any (fun results =>
    Admission.typed context.source context.captures results context.constants)

def initial (context : Context) (arguments : List SemanticValue) : Except Invalid State := do
  require context.typingValid .type
  require (Usage.check context.source context.captures) .custody
  require (Borrow.check context.source context.captures context.borrows) .scope
  let entry ← fromOption context.source.functions[context.source.entry.value]? .reference
  require (Analysis.captures context.captures context.source.entry).isEmpty .scope
  require (arguments.all (Profile.Value.externalValid context.source.schemas)) .type
  let located := arguments.mapIdx (fun index value => Located.mk value (.receiver 0 index))
  require (bindArguments context entry.parameters located) .type
  let rootScope : Scope := ⟨0, 0, none, 0, []⟩
  let rootInvocation : Invocation := ⟨0, context.source.entry, [], []⟩
  return {
    control := .invoke context.source.entry [] located
    stack := []
    heap := { scopes := [rootScope], invocations := [rootInvocation], nextInvocation := 1, nextScope := 1 }
    scope := 0
    invocation := 0 }

theorem initial_checks_typing (context : Context) (arguments : List SemanticValue) (state : State)
    (accepted : initial context arguments = .ok state) :
    ∃ results, Analysis.inferResults context.source = some results ∧
      Admission.typed context.source context.captures results context.constants = true := by
  have checked : context.typingValid = true := by
    cases valid : context.typingValid with
    | false => simp [initial, valid, require, bind, Except.bind] at accepted
    | true => rfl
  exact (Option.any_eq_true _ _).mp checked

theorem initial_checks_usage (context : Context) (arguments : List SemanticValue) (state : State)
    (accepted : initial context arguments = .ok state) :
    Usage.check context.source context.captures = true := by
  cases used : Usage.check context.source context.captures with
  | true => rfl
  | false =>
    cases typed : context.typingValid <;>
      simp [initial, typed, used, require, bind, Except.bind] at accepted

theorem initial_checks_borrows (context : Context) (arguments : List SemanticValue) (state : State)
    (accepted : initial context arguments = .ok state) :
    Borrow.check context.source context.captures context.borrows = true := by
  cases borrowed : Borrow.check context.source context.captures context.borrows with
  | true => rfl
  | false =>
    cases typed : context.typingValid <;>
      cases used : Usage.check context.source context.captures <;>
      simp [initial, typed, used, borrowed, require, bind, Except.bind] at accepted

theorem empty_release_has_no_event (state : State) (scope : LexicalScopeId) (after : AfterRelease)
    (record : Scope) (control : state.control = .release scope after)
    (lookup : state.heap.scopes[scope.value]? = some record)
    (empty : liveHoldings state.heap record = []) :
    finishEmptyRelease state = .ok (resumeRelease state after) := by
  simp [finishEmptyRelease, control, lookup, fromOption, bind, Except.bind, require, empty]
  rfl

end BoundaryV2.Profile.Source.Machine
