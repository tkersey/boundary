import BoundaryV2.GeneralizedResumptions

namespace BoundaryV2.Generalized.Source

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {definitions : List (BodyType signature.Data signature.Effect)}

/-- Source control reduces authored syntax and applies genuine continuation
functions. This relation currently covers ordinary computation/context reductions;
the remaining store-dependent control, use, and scope rules are not yet included. -/
inductive Step (table : Definitions signature algebra definitions) :
    Program signature algebra definitions result → Program signature algebra definitions result → Prop where
  | operandFault {context : List (TypeOf signature)} {result : TypeOf signature}
      {body : Computation signature algebra definitions context result}
      {environment : RuntimeEnvironment signature algebra definitions context} :
      body.operandPrefix.arguments.evaluate environment = .error fault →
      Step table (.evaluate body environment) (.failed fault)
  | returnValue : expression.evaluate environment = .ok value →
      Step table (.evaluate (.returnValue expression) environment) (.returned value)
  | bind : Step table (.evaluate (.bind first rest) environment)
      (.bindAuthored (.evaluate first environment) rest environment)
  | call : arguments.evaluate environment = .ok values →
      Step table (.evaluate (.call reference arguments) environment) (unfoldCall table reference values)
  | apply : function.evaluate environment = .ok (.closure body captured authority) →
      arguments.evaluate environment = .ok values →
      Step table (.evaluate (.apply function arguments) environment) (enterClosure body values captured)
  | primitive : (Expression.primitive operation arguments).evaluate environment = .ok value →
      Step table (.evaluate (.primitive operation arguments) environment) (.returned value)
  | matchLeft : expression.evaluate environment = .ok value → value.asSum = .inl payload →
      Step table (.evaluate (.matchSum expression left right) environment) (.evaluate left (.cons payload environment))
  | matchRight : expression.evaluate environment = .ok value → value.asSum = .inr payload →
      Step table (.evaluate (.matchSum expression left right) environment) (.evaluate right (.cons payload environment))
  | perform : capability.evaluate environment = .ok (.datum (.capability attachment)) →
      payload.evaluate environment = .ok payloadValue → bodies.evaluate environment = .ok bodyValues →
      Step table (.evaluate (.perform operation capability payload bodies) environment)
        (.request operation attachment payloadValue bodyValues .done)
  | handle : Step table (.evaluate (.handle effect mode returned clauses body) environment)
      (.handler effect mode attachment returned clauses environment
        (.evaluate body (.cons (.datum (.capability attachment)) environment)))
  | fail : Step table (.evaluate (.fail fault) environment) (.failed fault)
  | yield : Step table (.evaluate (.yieldThen body) environment) (.yielded (.evaluate body environment))
  | bindValue : Step table (.bind (.returned value) next description) (next value)
  | bindFault : Step table (.bind (.failed fault) next description) (.failed fault)
  | bindYield : Step table (.bind (.yielded body) next description) (.yielded (.bind body next description))
  | bindRequest : Step table (.bind (.request operation attachment payload bodies saved) next description)
      (.request operation attachment payload bodies (saved.append (.push (.bind next description) .done)))
  | bindStep : Step table before after → Step table (.bind before next description) (.bind after next description)
  | handlerValue : Step table (.handler effect mode attachment returned clauses environment (.returned value))
      (.evaluate returned (.cons value environment))
  | handlerFault : Step table (.handler effect mode attachment returned clauses environment (.failed fault)) (.failed fault)
  | handlerYield : Step table (.handler effect mode attachment returned clauses environment (.yielded body))
      (.yielded (.handler effect mode attachment returned clauses environment body))
  | handlerForward : requested ≠ attachment →
      Step table (.handler effect mode attachment returned clauses environment (.request operation requested payload bodies saved))
        (.request operation requested payload bodies
          (saved.append (.push (.handler effect mode attachment returned clauses environment) .done)))
  | handlerUnhandled {effect : signature.Effect} {operation : signature.operation effect}
      [DecidableEq (signature.operation effect)]
      {mode : Mode} {context : List (TypeOf signature)} {body answer : TypeOf signature}
      {clauses : Clauses signature algebra definitions effect mode context body answer}
      {returned : Computation signature algebra definitions (body :: context) answer}
      {environment : RuntimeEnvironment signature algebra definitions context}
      {payload : RuntimeValue signature algebra definitions (signature.payload operation)}
      {bodies : RuntimeEnvironment signature algebra definitions ((signature.bodies operation).map BodyType.type)}
      {saved : Context signature algebra definitions (signature.result operation) body} :
      clauses.lookup operation = none →
      Step table (.handler effect mode attachment returned clauses environment (.request operation attachment payload bodies saved))
        (.request operation attachment payload bodies
          (saved.append (.push (.handler effect mode attachment returned clauses environment) .done)))
  | handlerStep : Step table before after →
      Step table (.handler effect mode attachment returned clauses environment before)
        (.handler effect mode attachment returned clauses environment after)
  | regionStep : Step table before after → Step table (.region identity before) (.region identity after)
  | regionYield : Step table (.region identity (.yielded body)) (.yielded (.region identity body))
  | regionRequest : Step table (.region identity (.request operation attachment payload bodies saved))
      (.request operation attachment payload bodies (saved.append (.push (.region identity) .done)))
  | protectionStep : Step table before after →
      Step table (.protection identity cleanup environment before) (.protection identity cleanup environment after)
  | protectionYield : Step table (.protection identity cleanup environment (.yielded body))
      (.yielded (.protection identity cleanup environment body))
  | protectionRequest : Step table (.protection identity cleanup environment (.request operation attachment payload bodies saved))
      (.request operation attachment payload bodies (saved.append (.push (.protection identity cleanup environment) .done)))

/- Compatibility names are derived from the single ordered operand-failure
rule. They do not add alternative failure semantics to the transition datatype. -/
section OperandFaultAliases

variable {context : List (TypeOf signature)} {environment : RuntimeEnvironment signature algebra definitions context}

theorem Step.returnFault {expression : Expression signature algebra definitions context result}
    (failed : expression.evaluate environment = .error fault) :
    Step table (.evaluate (.returnValue expression) environment) (.failed fault) :=
  .operandFault (by simp only [Computation.operandPrefix, Arguments.evaluate, failed])

theorem Step.primitiveFault {operation : algebra.operation parameters result}
    {arguments : Arguments signature algebra definitions context (parameters.map Ty.leaf)}
    (failed : (Expression.primitive operation arguments).evaluate environment = .error fault) :
    Step table (.evaluate (.primitive operation arguments) environment) (.failed fault) :=
  .operandFault (by simp only [Computation.operandPrefix, Arguments.evaluate, failed])

theorem Step.matchFault {expression : Expression signature algebra definitions context (.sum leftType rightType)}
    {left : Computation signature algebra definitions (leftType :: context) result}
    {right : Computation signature algebra definitions (rightType :: context) result}
    (failed : expression.evaluate environment = .error fault) :
    Step table (.evaluate (.matchSum expression left right) environment) (.failed fault) :=
  .operandFault (by simp only [Computation.operandPrefix, Arguments.evaluate, failed])

theorem Step.callFault {reference : Variable definitions body}
    {arguments : Arguments signature algebra definitions context body.parameters}
    (failed : arguments.evaluate environment = .error fault) :
    Step table (.evaluate (.call reference arguments) environment) (.failed fault) := .operandFault failed

theorem Step.applyFunctionFault {function : Expression signature algebra definitions context (.computation use parameters result)}
    {arguments : Arguments signature algebra definitions context parameters}
    (failed : function.evaluate environment = .error fault) :
    Step table (.evaluate (.apply function arguments) environment) (.failed fault) :=
  .operandFault (by simp only [Computation.operandPrefix, Arguments.evaluate, failed])

theorem Step.applyArgumentFault {function : Expression signature algebra definitions context (.computation use parameters result)}
    {arguments : Arguments signature algebra definitions context parameters}
    (evaluated : function.evaluate environment = .ok functionValue)
    (failed : arguments.evaluate environment = .error fault) :
    Step table (.evaluate (.apply function arguments) environment) (.failed fault) :=
  .operandFault (by simp only [Computation.operandPrefix, Arguments.evaluate, evaluated, failed])

section Perform
variable {effect : signature.Effect} {operation : signature.operation effect}
  {capability : Expression signature algebra definitions context (.capability effect)}
  {payload : Expression signature algebra definitions context (signature.payload operation)}
  {bodies : Arguments signature algebra definitions context ((signature.bodies operation).map BodyType.type)}

theorem Step.performCapabilityFault (failed : capability.evaluate environment = .error fault) :
    Step table (.evaluate (.perform operation capability payload bodies) environment) (.failed fault) :=
  .operandFault (by simp only [Computation.operandPrefix, Arguments.evaluate, failed])

theorem Step.performPayloadFault (evaluated : capability.evaluate environment = .ok capabilityValue)
    (failed : payload.evaluate environment = .error fault) :
    Step table (.evaluate (.perform operation capability payload bodies) environment) (.failed fault) :=
  .operandFault (by simp only [Computation.operandPrefix, Arguments.evaluate, evaluated, failed])

theorem Step.performBodyFault (capabilityAt : capability.evaluate environment = .ok capabilityValue)
    (payloadAt : payload.evaluate environment = .ok payloadValue) (failed : bodies.evaluate environment = .error fault) :
    Step table (.evaluate (.perform operation capability payload bodies) environment) (.failed fault) :=
  .operandFault (by simp only [Computation.operandPrefix, Arguments.evaluate, capabilityAt, payloadAt, failed])

end Perform
end OperandFaultAliases

inductive Steps (table : Definitions signature algebra definitions) :
    Program signature algebra definitions result → Nat → Program signature algebra definitions result → Prop where
  | refl : Steps table program 0 program
  | cons : Step table first middle → Steps table middle count last → Steps table first (count + 1) last

theorem Steps.single (step : Step table before after) : Steps table before 1 after := .cons step .refl

theorem Steps.trans (first : Steps table before count middle) (second : Steps table middle rest after) :
    Steps table before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using Steps.cons step (induction second)

theorem Steps.under_bind {input result : TypeOf signature}
    {before after : Program signature algebra definitions input} (steps : Steps table before count after)
    (next : RuntimeValue signature algebra definitions input → Program signature algebra definitions result)
    (description : BindDescription signature algebra definitions input result) :
    Steps table (.bind before next description) count (.bind after next description) := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.bindStep step) induction

theorem Steps.under_handler {body answer : TypeOf signature} {context : List (TypeOf signature)}
    {before after : Program signature algebra definitions body} (steps : Steps table before count after)
    (effect : signature.Effect) (mode : Mode) (attachment : Id .attachment)
    (returned : Computation signature algebra definitions (body :: context) answer)
    (clauses : Clauses signature algebra definitions effect mode context body answer)
    (environment : RuntimeEnvironment signature algebra definitions context) :
    Steps table (.handler effect mode attachment returned clauses environment before) count
      (.handler effect mode attachment returned clauses environment after) := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.handlerStep step) induction

end BoundaryV2.Generalized.Source
