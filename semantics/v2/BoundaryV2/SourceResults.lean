import BoundaryV2.SourceAnalysis
import BoundaryV2.SchemaAdmission

namespace BoundaryV2.Profile.Source.Analysis

/-- none is an authored abrupt term, while the outer Option of inference is
static rejection. An abrupt branch may coexist with a normally returning one. -/
abbrev ResultType := Option (SchemaId .source)

def compatible (left right : ResultType) : Option ResultType :=
  match left, right with
  | some left, some right => if left == right then some (some left) else none
  | some left, none => some (some left)
  | none, right => some right

def valueType (source : Module) (id : SourceValueId) : Option (SchemaId .source) :=
  (source.values[id.value]?).map Source.Value.schema

def valueShape (source : Module) (id : SourceValueId) : Option (Schema .source) := do
  let type ← valueType source id
  source.schemas[type.value]?

def computationType (source : Module) (id : SourceValueId) : Option (ComputationType .source) := do
  let .internal (.computation signature) ← valueShape source id | none
  return signature

def resumptionType (source : Module) (id : SourceValueId) : Option (ResumptionType .source) := do
  let .internal (.resumption signature) ← valueShape source id | none
  return signature

def firstUnit (source : Module) : Option (SchemaId .source) :=
  (source.schemas.findIdx? (· == .unit)).map Ref.mk

def resultType (source : Module) (earlier : List ResultType) : Term → Option ResultType
  | .value value => some <$> valueType source value
  | .bind binder value next => do
    let value ← earlier[value.value]?
    let binder ← source.variables[binder.value]?
    let _ ← compatible value (some binder)
    let next ← earlier[next.value]?
    return if value.isNone then none else next
  | .conditional condition yes no => do
    if (← valueShape source condition) != .boolean then none else do
      compatible (← earlier[yes.value]?) (← earlier[no.value]?)
  | .call function _ => some <$> (source.functions[function.value]?).map Function.result
  | .apply closure _ => some <$> (computationType source closure).map ComputationType.result
  | .perform operation => some <$> (source.effects[operation.effect.value]?).map Effect.result
  | .handle handler .. | .resumeWith _ _ handler _ =>
    some <$> (source.handlers[handler.value]?).map Handler.answer
  | .resumeValue token _ | .resumeComputation token _ =>
    some <$> (resumptionType source token).map ResumptionType.answer
  | .protect body .. | .withRegion _ body _ =>
    some <$> (computationType source body).map ComputationType.result
  | .dispose _ => some <$> firstUnit source
  | .fail value => do
    if (← valueType source value) == source.failure then some none else none
  | .yieldThen next => earlier[next.value]?
  | .matchSum value cases => do
    let .sum fields ← valueShape source value | none
    if fields.length != cases.length then none else
      (cases.zip fields).foldlM (fun prior ((binder, body), type) => do
        if source.variables[binder.value]? != some type then none else
          compatible prior (← earlier[body.value]?)) none
  | .unpackProduct value variables body => do
    let .product fields ← valueShape source value | none
    if variables.length != fields.length || !(decide variables.Nodup) ||
        !(variables.zip fields).all (fun (binder, type) => source.variables[binder.value]? == some type)
    then none else earlier[body.value]?

/-- A structurally terminating static scan. Recursion here consumes declarations,
not execution steps. Calls use the declared function result and do not recurse
through function bodies. -/
def extendResults (source : Module) : List ResultType → List Term → Option (List ResultType)
  | earlier, [] => some earlier
  | earlier, term :: rest => do
    let result ← resultType source earlier term
    extendResults source (earlier ++ [result]) rest

def inferResults (source : Module) : Option (List ResultType) := extendResults source [] source.terms

/-- The checker can accept an untrusted finite table instead of trusting the
inference algorithm. Every row is rederived from exactly its earlier prefix. -/
def resultsValid (source : Module) (results : List ResultType) : Bool :=
  results.length == source.terms.length &&
  source.terms.zipIdx.all (fun (term, index) =>
    (results[index]?).any (fun type => resultType source (results.take index) term == some type))

def declarationSchemasValid (source : Module) : Bool :=
  let existsType := fun (type : SchemaId .source) => type.value < source.schemas.length
  existsType source.failure && source.variables.all existsType &&
  source.constants.all (fun literal => existsType literal.schema) &&
  source.resources.all (fun resource => existsType resource.representation) &&
  source.effects.all (fun effect => existsType effect.payload && existsType effect.result && effect.bodies.all existsType) &&
  source.handlers.all (fun handler => existsType handler.input && existsType handler.answer && handler.state.all existsType &&
    handler.clauses.all (fun clause => existsType clause.resumption)) &&
  source.functions.all (fun function => existsType function.result)

def functionResultsValid (source : Module) (results : List ResultType) : Bool :=
  source.functions.all (fun function =>
    (function.body >>= fun body => results[body.value]?).any
      (fun result => (compatible result (some function.result)).isSome))

def closureRootsValid (source : Module) (facts : Facts) : Bool :=
  let closed := fun (function : FunctionId .source) =>
    function.value < source.functions.length && (captures facts function).isEmpty
  closed source.entry && source.handlers.all (fun handler =>
    closed handler.returnFunction && handler.clauses.all (fun clause => closed clause.function))

/-- The production frontend's declaration, formation, result-inference and
lexical-capture obligations. Primitive typing and higher-order use/effect
contracts are subsequent source-admission obligations. -/
def foundationValid (source : Module) (facts : Facts) (results : List ResultType) : Bool :=
  formation source && SchemaAdmission.valid source.schemas && declarationSchemasValid source &&
  source.values.zipIdx.all (fun (value, index) => match value.expression with
    | .lambda _ => (computationType source ⟨index⟩).isSome
    | _ => true) && resultsValid source results && functionResultsValid source results &&
  check source facts && closureRootsValid source facts

theorem compatible_exact (left right result : ResultType) :
    compatible left right = some result ↔
      (∀ l r, left = some l → right = some r → l = r) ∧ left.or right = result := by
  cases left <;> cases right <;> simp [compatible, Option.or, beq_iff_eq]

theorem resultsValid_row (source : Module) (results : List ResultType)
    (accepted : resultsValid source results = true) (index : Nat) (term : Term) (type : ResultType)
    (atTerm : source.terms[index]? = some term) (atResult : results[index]? = some type) :
    resultType source (results.take index) term = some type := by
  have rows : source.terms.zipIdx.all (fun (term, index) =>
      (results[index]?).any (fun type => resultType source (results.take index) term == some type)) = true := by
    simp only [resultsValid, Bool.and_eq_true] at accepted
    exact accepted.2
  have member : (term, index) ∈ source.terms.zipIdx := List.mem_iff_getElem?.mpr ⟨index, by simp [atTerm]⟩
  simpa only [atResult, Option.any_some, beq_iff_eq] using List.all_eq_true.mp rows _ member

theorem extendResults_prefix (source : Module) (earlier : List ResultType) (terms : List Term)
    (result : List ResultType) (accepted : extendResults source earlier terms = some result) :
    ∃ extra, result = earlier ++ extra ∧ extra.length = terms.length := by
  induction terms generalizing earlier with
  | nil =>
    simp only [extendResults, Option.some.injEq] at accepted
    subst result
    exact ⟨[], by simp, rfl⟩
  | cons term terms ih =>
    cases first : resultType source earlier term with
    | none => simp [extendResults, first] at accepted
    | some type =>
      have rest : extendResults source (earlier ++ [type]) terms = some result := by
        simpa [extendResults, first] using accepted
      obtain ⟨extra, equal, size⟩ := ih (earlier ++ [type]) rest
      refine ⟨type :: extra, ?_, by simp [size]⟩
      simpa only [List.append_assoc, List.singleton_append] using equal

def ResultRows (source : Module) (earlier : List ResultType) (terms : List Term) (results : List ResultType) : Prop :=
  results.length = terms.length ∧
  ∀ index term type, terms[index]? = some term → results[index]? = some type →
    resultType source (earlier ++ results.take index) term = some type

theorem extendResults_sound (source : Module) (earlier : List ResultType) (terms : List Term)
    (result : List ResultType) (accepted : extendResults source earlier terms = some result) :
    ∃ extra, result = earlier ++ extra ∧ ResultRows source earlier terms extra := by
  induction terms generalizing earlier with
  | nil =>
    simp only [extendResults, Option.some.injEq] at accepted
    subst result
    exact ⟨[], by simp, rfl, by intro index term type absent; simp at absent⟩
  | cons head tail ih =>
    cases first : resultType source earlier head with
    | none => simp [extendResults, first] at accepted
    | some headType =>
      have rest : extendResults source (earlier ++ [headType]) tail = some result := by
        simpa [extendResults, first] using accepted
      obtain ⟨extra, equal, length, rows⟩ := ih (earlier ++ [headType]) rest
      refine ⟨headType :: extra, by simpa only [List.append_assoc, List.singleton_append] using equal,
        by simp [length], ?_⟩
      intro index term type atTerm atResult
      cases index with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at atTerm atResult
        subst term
        subst type
        simpa using first
      | succ index =>
        simp only [List.getElem?_cons_succ] at atTerm atResult
        simpa only [List.take_succ_cons, List.append_assoc, List.singleton_append] using
          rows index term type atTerm atResult

theorem inferResults_sound (source : Module) (results : List ResultType)
    (accepted : inferResults source = some results) : resultsValid source results = true := by
  obtain ⟨extra, equal, length, rows⟩ := extendResults_sound source [] source.terms results accepted
  simp only [List.nil_append] at equal
  subst extra
  simp only [resultsValid, length, beq_self_eq_true, Bool.true_and, List.all_eq_true]
  intro pair member
  obtain ⟨index, found⟩ := List.mem_iff_getElem?.mp member
  cases atTerm : source.terms[index]? with
  | none => simp [atTerm] at found
  | some term =>
    have pairEqual : (term, index) = pair := by simpa [atTerm] using found
    subst pair
    have bounded : index < results.length := by
      rw [length]
      exact (List.getElem?_eq_some_iff.mp atTerm).1
    have atResult := List.getElem?_eq_getElem bounded
    have checked := rows index term results[index] atTerm atResult
    simpa only [List.nil_append, atResult, Option.any_some, beq_iff_eq] using checked

theorem resultRows_complete (source : Module) (earlier : List ResultType) (terms : List Term)
    (results : List ResultType) (valid : ResultRows source earlier terms results) :
    extendResults source earlier terms = some (earlier ++ results) := by
  induction terms generalizing earlier results with
  | nil =>
    have empty : results = [] := List.length_eq_zero_iff.mp valid.1
    simp [empty, extendResults]
  | cons head tail ih =>
    cases results with
    | nil => simp [ResultRows] at valid
    | cons headType rest =>
      have first : resultType source earlier head = some headType := by
        simpa using valid.2 0 head headType rfl rfl
      have remainder : ResultRows source (earlier ++ [headType]) tail rest := by
        refine ⟨by simpa using valid.1, ?_⟩
        intro index term type atTerm atResult
        simpa only [List.take_succ_cons, List.append_assoc, List.singleton_append] using
          valid.2 (index + 1) term type atTerm atResult
      have inferred := ih (earlier ++ [headType]) rest remainder
      simpa [extendResults, first, List.append_assoc] using inferred

theorem resultsValid_iff_inference (source : Module) (results : List ResultType) :
    resultsValid source results = true ↔ inferResults source = some results := by
  constructor
  · intro checked
    have size : results.length = source.terms.length := by
      simp only [resultsValid, Bool.and_eq_true, beq_iff_eq] at checked
      exact checked.1
    have rows : ResultRows source [] source.terms results := by
      refine ⟨size, ?_⟩
      intro index term type atTerm atResult
      simpa using resultsValid_row source results checked index term type atTerm atResult
    simpa [inferResults] using resultRows_complete source [] source.terms results rows
  · exact inferResults_sound source results

theorem result_table_unique (source : Module) (left right : List ResultType)
    (leftValid : resultsValid source left = true) (rightValid : resultsValid source right = true) : left = right :=
  Option.some.inj (((resultsValid_iff_inference source left).mp leftValid).symm.trans
    ((resultsValid_iff_inference source right).mp rightValid))

theorem foundation_entry_closed (source : Module) (facts : Facts) (results : List ResultType)
    (accepted : foundationValid source facts results = true) (var : VariableId) :
    ¬ Free source (.function source.entry) var := by
  simp only [foundationValid, Bool.and_eq_true] at accepted
  have capturesChecked := accepted.1.2
  have roots := accepted.2
  simp only [closureRootsValid, Bool.and_eq_true] at roots
  have empty : facts.row (.function source.entry) = [] := by
    simpa [captures] using roots.1.2
  intro free
  obtain ⟨rank, found⟩ := free_complete source facts capturesChecked free
  simp [Facts.rank, empty] at found

theorem foundation_checks_unreachable_term (source : Module) (facts : Facts) (results : List ResultType)
    (accepted : foundationValid source facts results = true) (index : Nat) (term : Term) (type : ResultType)
    (atTerm : source.terms[index]? = some term) (atResult : results[index]? = some type) :
    resultType source (results.take index) term = some type := by
  simp only [foundationValid, Bool.and_eq_true] at accepted
  exact resultsValid_row source results accepted.1.1.1.2 index term type atTerm atResult

theorem source_call_recursion_does_not_consume_inference_steps (source : Module)
    (earlier : List ResultType) (function : FunctionId .source) (arguments : List SourceValueId)
    (declaration : Function) (found : source.functions[function.value]? = some declaration) :
    resultType source earlier (.call function arguments) = some (some declaration.result) := by
  simp [resultType, found]

theorem abrupt_value_stops_binding (source : Module) (earlier : List ResultType)
    (binder : VariableId) (value next : TermId) (type : SchemaId .source) (nextType : ResultType)
    (variableFound : source.variables[binder.value]? = some type)
    (valueAbrupt : earlier[value.value]? = some none) (nextFound : earlier[next.value]? = some nextType) :
    resultType source earlier (.bind binder value next) = some none := by
  simp [resultType, variableFound, valueAbrupt, nextFound, compatible]

end BoundaryV2.Profile.Source.Analysis
