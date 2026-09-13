import BoundaryV2.GeneralizedObservations

namespace BoundaryV2.Generalized.Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

def Code.installsHandler : Code signature algebra program context operands result → Bool
  | .attach _ _ _ _ _ _ => true
  | _ => false

def Configuration.installsHandler : Configuration signature algebra program result → Bool
  | .code body _ _ _ => body.installsHandler
  | _ => false

/-- Characterize ordinary code steps. Attachment choice is explicit because
the enclosing allocation/ownership rules supply its freshness policy. Store
operations and scope exit remain with their own transition owners. -/
def codeNext (table : Definitions signature algebra program) (attachment : Id .attachment)
    (body : Code signature algebra program context operands input)
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (outside : Stack signature algebra program input result) : Option (Configuration signature algebra program result) :=
  match operandNextCode bindings body values with
  | some next => some (.code next.code bindings next.values outside)
  | none =>
    match body with
    | .ret => match values with
      | .cons value _ => some (.returned value outside)
    | .enter body => match values with
      | .cons value rest => some (.code body (.cons value bindings) rest outside)
    | .callBlock body next => some (.code body bindings .nil (.push (.returnTo next bindings values) outside))
    | .callNamed reference next =>
      let (arguments, rest) := Environment.popReverse _ values
      some (.code (reference.lookup table) arguments .nil (.push (.returnTo next bindings rest) outside))
    | .callClosure next =>
      let (arguments, tail) := Environment.popReverse _ values
      match tail with
      | .cons closure rest => match closure with
        | .closure body captured _ => some (.code body (arguments.append captured) .nil (.push (.returnTo next bindings rest) outside))
    | .branch left right => match values with
      | .cons value rest => match value.asSum with
        | .inl payload => some (.code left (.cons payload bindings) rest outside)
        | .inr payload => some (.code right (.cons payload bindings) rest outside)
    | .dispatch operation next =>
      let (bodies, tail) := Environment.popReverse ((signature.bodies operation).map BodyType.type) values
      match tail with
      | .cons payload tail => match tail with
        | .cons capability rest => match capability with
          | .datum (.capability identity) => some (.requested operation identity payload bodies (.push (.returnTo next bindings rest) outside))
    | .attach effect mode returned clauses body next =>
      some (.code body (.cons (.datum (.capability attachment)) bindings) .nil
        (.push (.handler effect mode attachment returned clauses bindings) (.push (.returnTo next bindings values) outside)))
    | .fault fault => some (.failed fault outside)
    | .yieldThen next => some (.yielded (.code next bindings values outside))
    | _ => none

def returnedNext (value : RuntimeValue signature algebra program input)
    (outside : Stack signature algebra program input result) : Option (Configuration signature algebra program result) :=
  match outside with
  | .done => none
  | .push frame rest => match frame with
    | .returnTo next bindings operands => some (.code next bindings (.cons value operands) rest)
    | .handler _ _ _ returned _ bindings => some (.code returned (.cons value bindings) .nil rest)
    | .region _ | .protection _ _ _ => none

def failedNext (fault : algebra.Fault) (outside : Stack signature algebra program input result) :
    Option (Configuration signature algebra program result) :=
  match outside with
  | .done => none
  | .push frame rest => match frame with
    | .returnTo _ _ _ | .handler _ _ _ _ _ _ => some (.failed fault rest)
    | .region _ | .protection _ _ _ => none

def nextWithAttachment (table : Definitions signature algebra program) (attachment : Id .attachment) :
    Configuration signature algebra program result → Option (Configuration signature algebra program result)
  | .code body bindings operands outside => codeNext table attachment body bindings operands outside
  | .returned value outside => returnedNext value outside
  | .failed fault outside => failedNext fault outside
  | .requested _ _ _ _ _ | .yielded _ => none

theorem OperandStep.code_next
    {bindings : RuntimeEnvironment signature algebra program context}
    {before after : Operands signature algebra program context input}
    (step : OperandStep bindings before after)
    (table : Definitions signature algebra program) (attachment : Id .attachment)
    (outside : Stack signature algebra program input result) :
    codeNext table attachment before.code bindings before.values outside = some (.code after.code bindings after.values outside) := by
  have next : operandNextCode bindings before.code before.values = some after := step.computes_next
  simp only [codeNext, next]

theorem CallStep.computes_next (step : CallStep (table : Definitions signature algebra program) before after) :
    ∃ attachment, nextWithAttachment table attachment before = some after := by
  cases step with
  | operand step => exact ⟨⟨0⟩, step.code_next table ⟨0⟩ _⟩
  | attach => exact ⟨_, rfl⟩
  | branchLeft selected | branchRight selected => exact ⟨⟨0⟩, by simp only [nextWithAttachment, codeNext, operandNextCode, selected]⟩
  | returned | enter | block | handlerReturned | caller | callerFault | handlerFault | fault | yield => exact ⟨⟨0⟩, rfl⟩
  | named | closure | dispatch =>
    exact ⟨⟨0⟩, by simp only [nextWithAttachment, codeNext, operandNextCode, Environment.popReverse_pushReverse]⟩

theorem code_next_choice_irrelevant (table : Definitions signature algebra program) (first second : Id .attachment)
    (body : Code signature algebra program context operands input)
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (outside : Stack signature algebra program input result) (ordinary : body.installsHandler = false) :
    codeNext table first body bindings values outside = codeNext table second body bindings values outside := by
  cases body <;> first | rfl | contradiction

theorem next_choice_irrelevant (table : Definitions signature algebra program) (first second : Id .attachment)
    (configuration : Configuration signature algebra program result) (ordinary : configuration.installsHandler = false) :
    nextWithAttachment table first configuration = nextWithAttachment table second configuration := by
  cases configuration with
  | code body bindings operands outside => exact code_next_choice_irrelevant table first second body bindings operands outside ordinary
  | returned | failed | requested | yielded => rfl

theorem CallStep.deterministic {before after other : Configuration signature algebra program result} (ordinary : before.installsHandler = false)
    (first : CallStep (table : Definitions signature algebra program) before after)
    (second : CallStep table before other) : after = other := by
  obtain ⟨firstChoice, firstAt⟩ := first.computes_next
  obtain ⟨secondChoice, secondAt⟩ := second.computes_next
  exact Option.some.inj (firstAt.symm.trans ((next_choice_irrelevant table firstChoice secondChoice before ordinary).trans secondAt))

theorem HeadObservation.no_step {configuration after : Configuration signature algebra program result}
    (observed : HeadObservation configuration observation) (table : Definitions signature algebra program) :
    ¬ CallStep table configuration after := by
  cases observed <;> intro step <;> cases step

theorem HeadObservation.unique {configuration : Configuration signature algebra program result}
    (first : HeadObservation configuration observation) (second : HeadObservation configuration other) : observation = other := by
  cases first <;> cases second <;> rfl

theorem HeadObservation.after_steps {before after : Configuration signature algebra program result}
    (head : HeadObservation before observation) (steps : CallSteps table before count after)
    (final : HeadObservation after other) : observation = other := by
  cases steps with
  | refl => exact head.unique final
  | cons step tail => exact False.elim (head.no_step table step)

theorem HeadObservation.observes_iff {configuration : Configuration signature algebra program result}
    (head : HeadObservation configuration observation) (table : Definitions signature algebra program) :
    Observes table configuration other ↔ other = observation := by
  constructor
  · rintro ⟨count, final, steps, observed⟩
    exact (head.after_steps steps observed).symm
  · rintro rfl
    exact ⟨0, configuration, .refl, head⟩

theorem CallStep.cancel_observed
    {before after final : Configuration signature algebra program result}
    (step : CallStep table before after) (ordinary : before.installsHandler = false)
    (run : CallSteps table before count final) (observed : HeadObservation final observation) :
    ∃ rest, count = 1 + rest ∧ CallSteps table after rest final := by
  cases run with
  | refl => exact False.elim (observed.no_step table step)
  | cons actual tail =>
    have same := CallStep.deterministic ordinary step actual
    cases same
    exact ⟨_, by omega, tail⟩

theorem CallStep.observes_iff
    {before after : Configuration signature algebra program result}
    (step : CallStep table before after) (ordinary : before.installsHandler = false) :
    Observes table before observation ↔ Observes table after observation := by
  constructor
  · rintro ⟨count, final, run, observed⟩
    obtain ⟨rest, _, tail⟩ := step.cancel_observed ordinary run observed
    exact ⟨rest, final, tail, observed⟩
  · exact Observes.prepend (.single step)

/-- Inverting an actual installation recovers the name that execution chose;
reflection must use that name rather than assume one fixed allocator output. -/
theorem CallStep.installed_attachment
    {effect : signature.Effect} {mode : Mode} {context operands : List (TypeOf signature)}
    {bodyType answer result : TypeOf signature}
    {returned : Code signature algebra program (bodyType :: context) [] answer}
    {clauses : Clauses signature algebra program effect mode context bodyType answer}
    {body : Code signature algebra program (.capability effect :: context) [] bodyType}
    {next : Code signature algebra program context (answer :: operands) result}
    {bindings : RuntimeEnvironment signature algebra program context}
    {values : RuntimeEnvironment signature algebra program operands}
    {outside : Stack signature algebra program result finalType}
    {after : Configuration signature algebra program finalType}
    (step : CallStep table (.code (.attach effect mode returned clauses body next) bindings values outside) after) :
    ∃ attachment, after = .code body (.cons (.datum (.capability attachment)) bindings) .nil
      (.push (.handler effect mode attachment returned clauses bindings) (.push (.returnTo next bindings values) outside)) := by
  obtain ⟨attachment, computed⟩ := step.computes_next
  simp only [nextWithAttachment, codeNext, operandNextCode, Option.some.injEq] at computed
  exact ⟨attachment, computed.symm⟩

theorem OperandStep.does_not_install_handler
    {bindings : RuntimeEnvironment signature algebra program context}
    {before after : Operands signature algebra program context input}
    (step : OperandStep bindings before after) (outside : Stack signature algebra program input result) :
    (Configuration.code before.code bindings before.values outside).installsHandler = false := by
  cases step <;> rfl

/-- An observation cannot occur partway through an operand drain. Every actual
observing run contains this same finite prefix, with its exact step count. -/
theorem OperandSteps.cancel_observed_prefix
    {bindings : RuntimeEnvironment signature algebra program context}
    {before after : Operands signature algebra program context input}
    (drain : OperandSteps bindings before drainCount after)
    (outside : Stack signature algebra program input result)
    {final : Configuration signature algebra program result}
    (run : CallSteps table (.code before.code bindings before.values outside) count final)
    (observed : HeadObservation final observation) :
    ∃ rest, count = drainCount + rest ∧ CallSteps table (.code after.code bindings after.values outside) rest final := by
  induction drain generalizing count with
  | refl => exact ⟨count, by omega, run⟩
  | cons step tail induction =>
    cases run with
    | refl => cases observed
    | cons actual rest =>
      have same := CallStep.deterministic (step.does_not_install_handler outside) (.operand step) actual
      cases same
      obtain ⟨remaining, counted, following⟩ := induction rest
      exact ⟨remaining, by omega, following⟩

theorem OperandSteps.observes_iff
    {bindings : RuntimeEnvironment signature algebra program context}
    {before after : Operands signature algebra program context input}
    (drain : OperandSteps bindings before drainCount after)
    (outside : Stack signature algebra program input result) :
    Observes table (.code before.code bindings before.values outside) observation ↔
      Observes table (.code after.code bindings after.values outside) observation := by
  constructor
  · rintro ⟨count, final, run, observed⟩
    obtain ⟨rest, _, tail⟩ := drain.cancel_observed_prefix outside run observed
    exact ⟨rest, final, tail, observed⟩
  · exact Observes.prepend (drain.in_context table outside)

end BoundaryV2.Generalized.Target
