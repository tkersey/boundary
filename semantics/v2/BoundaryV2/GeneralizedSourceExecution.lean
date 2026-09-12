import BoundaryV2.GeneralizedResumptions

namespace BoundaryV2.Generalized.Source

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {definitions : List (BodyType signature.Data signature.Effect)}

/-- Source control reduces authored syntax and applies genuine continuation
functions. This relation currently covers ordinary computation/context reductions;
the remaining store-dependent control, use, and scope rules are not yet included. -/
inductive Step (table : Definitions signature algebra definitions) :
    Program signature algebra definitions result → Program signature algebra definitions result → Prop where
  | returnValue : expression.evaluate environment = .ok value →
      Step table (.evaluate (.returnValue expression) environment) (.returned value)
  | returnFault : expression.evaluate environment = .error fault →
      Step table (.evaluate (.returnValue expression) environment) (.failed fault)
  | bind : Step table (.evaluate (.bind first rest) environment)
      (.bind (.evaluate first environment) (fun value => .evaluate rest (.cons value environment)))
  | call : arguments.evaluate environment = .ok values →
      Step table (.evaluate (.call reference arguments) environment) (unfoldCall table reference values)
  | callFault : arguments.evaluate environment = .error fault →
      Step table (.evaluate (.call reference arguments) environment) (.failed fault)
  | apply : function.evaluate environment = .ok (.closure body captured authority) →
      arguments.evaluate environment = .ok values →
      Step table (.evaluate (.apply function arguments) environment) (enterClosure body values captured)
  | applyFunctionFault : function.evaluate environment = .error fault →
      Step table (.evaluate (.apply function arguments) environment) (.failed fault)
  | applyArgumentFault : function.evaluate environment = .ok functionValue →
      arguments.evaluate environment = .error fault →
      Step table (.evaluate (.apply function arguments) environment) (.failed fault)
  | primitive : (Expression.primitive operation arguments).evaluate environment = .ok value →
      Step table (.evaluate (.primitive operation arguments) environment) (.returned value)
  | primitiveFault : (Expression.primitive operation arguments).evaluate environment = .error fault →
      Step table (.evaluate (.primitive operation arguments) environment) (.failed fault)
  | perform : capability.evaluate environment = .ok (.datum (.capability attachment)) →
      payload.evaluate environment = .ok payloadValue → bodies.evaluate environment = .ok bodyValues →
      Step table (.evaluate (.perform operation capability payload bodies) environment)
        (.request operation attachment payloadValue bodyValues .done)
  | performCapabilityFault : capability.evaluate environment = .error fault →
      Step table (.evaluate (.perform operation capability payload bodies) environment) (.failed fault)
  | performPayloadFault : capability.evaluate environment = .ok capabilityValue →
      payload.evaluate environment = .error fault →
      Step table (.evaluate (.perform operation capability payload bodies) environment) (.failed fault)
  | performBodyFault : capability.evaluate environment = .ok capabilityValue →
      payload.evaluate environment = .ok payloadValue → bodies.evaluate environment = .error fault →
      Step table (.evaluate (.perform operation capability payload bodies) environment) (.failed fault)
  | handle : Step table (.evaluate (.handle effect mode returned clauses body) environment)
      (.handler effect mode attachment returned clauses environment
        (.evaluate body (.cons (.datum (.capability attachment)) environment)))
  | fail : Step table (.evaluate (.fail fault) environment) (.failed fault)
  | yield : Step table (.evaluate (.yieldThen body) environment) (.yielded (.evaluate body environment))
  | bindValue : Step table (.bind (.returned value) next) (next value)
  | bindFault : Step table (.bind (.failed fault) next) (.failed fault)
  | bindYield : Step table (.bind (.yielded body) next) (.yielded (.bind body next))
  | bindRequest : Step table (.bind (.request operation attachment payload bodies saved) next)
      (.request operation attachment payload bodies (saved.append (.push (.bind next) .done)))
  | bindStep : Step table before after → Step table (.bind before next) (.bind after next)
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
    (next : RuntimeValue signature algebra definitions input → Program signature algebra definitions result) :
    Steps table (.bind before next) count (.bind after next) := by
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
