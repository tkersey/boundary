import BoundaryV2.GeneralizedCode

namespace BoundaryV2.Generalized.Defunctionalization

open Target

def selection (source : Selection (context : List (TypeOf signature)) captured)
    (next : Code signature algebra definitions context (captured.reverse ++ stack) result) :
    Code signature algebra definitions context stack result :=
  match source with
  | .nil => next
  | .cons reference rest => .load reference (selection rest (by
    simpa only [List.reverse_cons, List.append_assoc, List.singleton_append] using next))

/- Compilation is total on the typed source syntax. Authored bodies, clauses,
and lexical continuations all become target instruction data. -/
mutual
  def expression (source : Source.Expression signature algebra definitions context type)
      (next : Code signature algebra definitions context (type :: stack) result) :
      Code signature algebra definitions context stack result :=
    match source with
    | .datum value => .push value next
    | .reference reference => .load reference next
    | .pair first second => expression first (expression second (.pair next))
    | .first pair => expression pair (.first next)
    | .second pair => expression pair (.second next)
    | .left value => expression value (.left next)
    | .right value => expression value (.right next)
    | .primitive operation inputs => arguments inputs (.primitive operation next)
    | .lambda captures body => selection captures (.close (computation body) next)

  def arguments (source : Source.Arguments signature algebra definitions context types)
      (next : Code signature algebra definitions context (types.reverse ++ stack) result) :
      Code signature algebra definitions context stack result :=
    match source with
    | .nil => next
    | .cons first rest => expression first (arguments rest (by
      simpa only [List.reverse_cons, List.append_assoc, List.singleton_append] using next))

  def computation (source : Source.Computation signature algebra definitions context result) :
      Code signature algebra definitions context [] result :=
    match source with
    | .returnValue value => expression value .ret
    | .bind first rest => .callBlock (computation first) (.enter (computation rest))
    | .apply function inputs => expression function (arguments inputs (.callClosure .ret))
    | .call reference inputs => arguments inputs (.callNamed reference .ret)
    | .primitive operation inputs => arguments inputs (.primitive operation .ret)
    | .matchSum value left right => expression value (.branch (computation left) (computation right))
    | .perform operation capability payload bodies => expression capability (expression payload (arguments bodies (.dispatch operation .ret)))
    | .handle effect mode returned handlers body => .attach effect mode (computation returned) (clauses handlers) (computation body) .ret
    | .resume continuation value => expression continuation (expression value (.resume .ret))
    | .resumeWith effect continuation value returned handlers =>
      expression continuation (expression value (.replaceHandler effect (computation returned) (clauses handlers) .ret))
    | .inject continuation body => expression continuation (expression body (.inject .ret))
    | .withRegion body => .enterRegion (computation body) .ret
    | .cellNew region value => expression region (expression value (.cellNew .ret))
    | .cellRead cell => expression cell (.cellRead .ret)
    | .cellWrite cell value => expression cell (expression value (.cellWrite .ret))
    | .protect cleanup body => .protect (computation cleanup) (computation body) .ret
    | .dispose continuation => expression continuation (.dispose .ret)
    | .clone continuation => expression continuation (.clone .ret)
    | .package value => expression value (.package .ret)
    | .unpackage value => expression value (.unpackage .ret)
    | .fail failure => .fault failure
    | .yieldThen rest => .yieldThen (computation rest)

  def clauses (source : Source.Clauses signature algebra definitions effect mode context body answer) :
      Target.Clauses signature algebra definitions effect mode context body answer :=
    match source with
    | .nil => .nil
    | .cons operation use body rest => .cons operation use (computation body) (clauses rest)
end

def definitions (source : Source.Definitions signature algebra signatures) : Target.Definitions signature algebra signatures :=
  source.map (fun _ body => computation body)

end BoundaryV2.Generalized.Defunctionalization
