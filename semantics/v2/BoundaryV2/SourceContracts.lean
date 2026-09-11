import BoundaryV2.SourceDeclarations
import BoundaryV2.DependencyAdmission
import BoundaryV2.ControlAdmission

namespace BoundaryV2.Profile.Source.Admission

/-- All function bodies are checked, including functions unreachable from entry.
Syntax outside every function body does not introduce an ambient execution. -/
def ambientEffect (source : Module) (effect : EffectId .source) : Bool :=
  let rows := source.terms.foldl (fun earlier term => earlier ++ [
    (match term with | .perform operation => operation.effect == effect && operation.capability.isNone | _ => false) ||
    (Analysis.termChildren term).any (fun (child, _) => earlier[child.value]?.getD false)]) []
  source.functions.any (fun function => (function.body >>= fun body => rows[body.value]?).getD false)

def dependencyContext (source : Module) : DependencyAdmission.Context .source :=
  ⟨source.schemas, source.effects.length, ambientEffect source⟩

def controlContext (source : Module) : ControlAdmission.Context .source :=
  ⟨declarationContext source, source.handlers, source.failure⟩

abbrev EffectFacts := DependencyAdmission.EffectFacts .source

def effectFacts (source : Module) : EffectFacts := DependencyAdmission.effectFacts (dependencyContext source)

def argumentsValid (source : Module) (arguments : List SourceValueId) (expected : List (SchemaId .source)) : Bool :=
  valueTypes source arguments == some expected

def protectionTypes (source : Module) (effects : List (EffectId .source)) (regions : List (RegionId .source))
    (body cleanup : ComputationType .source) (arguments : List SourceValueId) (resource : Option SourceValueId)
    (loanRegion : Option (RegionId .source)) : Bool := ((do
  let context := controlContext source
  let loaned := resource.toList.length
  let info ← cleanup.parameters[0]?
  let general := body.parameters.length ≥ loaned && cleanup.parameters.length == 1 + loaned &&
    shape source cleanup.result == some .unit &&
    argumentsValid source arguments (body.parameters.drop loaned) && ControlAdmission.cleanupInfoValid context info &&
    subset body.effects effects && subset cleanup.effects effects && subset cleanup.regions regions &&
    ControlAdmission.effectsAllowCleanup context body.effects && ControlAdmission.effectsAllowCleanup context cleanup.effects
  match resource with
  | none => return general && loanRegion.isNone && subset body.regions regions
  | some value =>
    let type ← Analysis.valueType source value
    let _ ← resourceDescriptor source type
    let region ← loanRegion
    let borrowed ← body.parameters[0]?
    return general && region.value < source.regionCount && cleanup.parameters[1]? == some type &&
      shape source borrowed == some (.internal (.borrowed type region)) &&
      (body.regions.filter (· != region)).all regions.contains &&
      ControlAdmission.capturedRegion context body.effects region) : Option Bool).getD false

/-- Contracts on source control constructors. The ambient effect and region
allowances are supplied by the actual enclosing source function at each use.
No block, continuation edge or compiler witness participates in this checker. -/
def termValid (source : Module) (facts : EffectFacts) (effects : List (EffectId .source))
    (regions : List (RegionId .source)) (term : Term) : Bool := ((do
  let context := controlContext source
  match term with
  | .value _ | .bind .. | .conditional .. | .yieldThen _ | .matchSum .. | .unpackProduct .. =>
    return true -- Formation and result inference check these structural interfaces.
  | .fail value => return Analysis.valueType source value == some source.failure
  | .call callee arguments =>
    let callee ← source.functions[callee.value]?
    let parameters ← variableTypes source callee.parameters
    return argumentsValid source arguments parameters && subset callee.effects effects
  | .perform operation =>
    let effect ← source.effects[operation.effect.value]?
    let explicit := match operation.capability with
      | none => effect.external
      | some value => (Analysis.valueType source value).any (fun type => capability source type operation.effect)
    let evidence := (valueTypes source operation.useSiteCapabilities).any (fun types =>
      types.length == effect.useSiteEffects.length &&
      (types.zip effect.useSiteEffects).all (fun (type, effect) => capability source type effect))
    return explicit && argumentsValid source operation.bodies effect.bodies && evidence &&
      effects.contains operation.effect && subset effect.useSiteEffects effects &&
      Analysis.valueType source operation.payload == some effect.payload
  | .apply closure arguments =>
    let signature ← Analysis.computationType source closure
    return argumentsValid source arguments signature.parameters && subset signature.effects effects &&
      subset signature.regions regions
  | .handle handler body arguments state =>
    let handler ← source.handlers[handler.value]?
    let body ← Analysis.computationType source body
    return subset body.regions regions && body.result == handler.input &&
      body.parameters.length == handler.clauses.length + arguments.length &&
      ((body.parameters.take handler.clauses.length).zip handler.clauses).all
        (fun (type, clause) => capability source type clause.effect) &&
      argumentsValid source arguments (body.parameters.drop handler.clauses.length) &&
      argumentsValid source state handler.state &&
      body.effects.all (fun effect =>
        let escapes := !DependencyAdmission.discharged facts handler body effect
        (!escapes || effects.contains effect) && ControlAdmission.continuationEffect context handler effect escapes) &&
      subset handler.effects effects && ControlAdmission.deepHandlerEffects context handler
  | .resumeValue token argument =>
    let signature ← Analysis.resumptionType source token
    return Analysis.valueType source argument == some signature.input && subset signature.effects effects
  | .resumeWith token argument handler state =>
    let signature ← Analysis.resumptionType source token
    let successor ← source.handlers[handler.value]?
    return signature.mode == .shallow && Analysis.valueType source argument == some signature.input &&
      successor.input == signature.answer && successor.clauses.map Clause.effect == signature.handled &&
      signature.effects.all (fun effect =>
        let escapes := !ControlAdmission.covers successor effect || signature.escaping.contains effect
        (!escapes || effects.contains effect) && ControlAdmission.continuationEffect context successor effect escapes) &&
      subset successor.effects effects && ControlAdmission.deepHandlerEffects context successor &&
      argumentsValid source state successor.state
  | .resumeComputation token closure =>
    let signature ← Analysis.resumptionType source token
    let thunk ← Analysis.computationType source closure
    let effect ← source.effects[signature.effect.value]?
    return thunk.result == signature.input && thunk.parameters.length == effect.useSiteEffects.length &&
      (thunk.parameters.zip effect.useSiteEffects).all (fun (type, effect) => capability source type effect) &&
      subset thunk.effects effect.useSiteEffects && subset signature.effects effects
  | .dispose token =>
    let signature ← Analysis.resumptionType source token
    return signature.use != .multi && subset signature.effects effects
  | .protect body cleanup arguments resource loanRegion =>
    let body ← Analysis.computationType source body
    let cleanup ← Analysis.computationType source cleanup
    return protectionTypes source effects regions body cleanup arguments resource loanRegion
  | .withRegion region body arguments =>
    let body ← Analysis.computationType source body
    let regionType ← body.parameters[0]?
    return region.value < source.regionCount && body.parameters.length == arguments.length + 1 &&
      shape source regionType == some (.internal (.region region)) &&
      subset (body.regions.filter (· != region)) regions &&
      argumentsValid source arguments (body.parameters.drop 1) && subset body.effects effects &&
      ControlAdmission.capturedRegion context body.effects region) : Option Bool).getD false

def contractRows (source : Module) (facts : EffectFacts) (effects : List (EffectId .source))
    (regions : List (RegionId .source)) : List Bool :=
  EarlierRows.compute (fun index => (source.terms[index]?).any (termValid source facts effects regions))
    (termChildren source) source.terms.length

def contractsValid (source : Module) : Bool :=
  let facts := effectFacts source
  let allEffects := (List.range source.effects.length).map (fun index => (⟨index⟩ : EffectId .source))
  let allRegions := (List.range source.regionCount).map (fun index => (⟨index⟩ : RegionId .source))
  source.terms.all (termValid source facts allEffects allRegions) &&
  source.functions.all (fun function =>
    (function.body >>= fun body => (contractRows source facts function.effects function.regions)[body.value]?).getD false)

def typed (source : Module) (captures : Analysis.Facts) (results : List Analysis.ResultType)
    (constants : List (Profile.Value .source)) : Bool :=
  Analysis.foundationValid source captures results && declarationsValid source constants &&
    primitivesValid source captures && contractsValid source

theorem typed_checks_all_declarations (source : Module) (captures : Analysis.Facts)
    (results : List Analysis.ResultType) (constants : List (Profile.Value .source))
    (accepted : typed source captures results constants = true) :
    declarationsValid source constants = true ∧ primitivesValid source captures = true ∧ contractsValid source = true := by
  simp only [typed, Bool.and_eq_true] at accepted
  exact ⟨accepted.1.1.2, accepted.1.2, accepted.2⟩

theorem call_interface (source : Module) (facts : EffectFacts) (effects : List (EffectId .source))
    (regions : List (RegionId .source)) (function : FunctionId .source) (arguments : List SourceValueId)
    (accepted : termValid source facts effects regions (.call function arguments) = true) :
    ∃ declaration parameters, source.functions[function.value]? = some declaration ∧
      variableTypes source declaration.parameters = some parameters ∧
      valueTypes source arguments = some parameters ∧ subset declaration.effects effects = true := by
  unfold termValid at accepted
  cases declaration : source.functions[function.value]? with
  | none => simp [declaration] at accepted
  | some definition =>
    cases parameters : variableTypes source definition.parameters with
    | none => simp [declaration, parameters] at accepted
    | some types =>
      simp [declaration, parameters, Bool.and_eq_true, argumentsValid] at accepted
      exact ⟨definition, types, rfl, parameters, accepted.1, accepted.2⟩

theorem function_contracts_reach_every_child (source : Module) (function : Function)
    (body term : TermId) (authored : Term) (accepted : contractsValid source = true)
    (member : function ∈ source.functions) (atBody : function.body = some body)
    (reachable : EarlierRows.Reach (termChildren source) body.value term.value)
    (atTerm : source.terms[term.value]? = some authored) :
    termValid source (effectFacts source) function.effects function.regions authored = true := by
  simp only [contractsValid, Bool.and_eq_true] at accepted
  have checked := List.all_eq_true.mp accepted.2 function member
  simp only [atBody, EarlierRows.getD_true] at checked
  have localChecked := EarlierRows.descendants_checked _ _ _ _ checked reachable
  simpa only [atTerm, Option.any_some] using localChecked

end BoundaryV2.Profile.Source.Admission
