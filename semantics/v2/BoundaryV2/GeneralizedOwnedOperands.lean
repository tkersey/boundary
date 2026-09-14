import BoundaryV2.GeneralizedClosureEvaluation

namespace BoundaryV2.Generalized.Source

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} {Future : Type}

/- Operand views are evaluated left to right. A closure allocation transfers
its selected physical captures at that position. Failure retains the store
reached by the successful prefix; the receiving control operation has not yet
consumed any of the operand values. -/
mutual
  inductive ExpressionEvaluation (bindings : RuntimeEnvironment signature algebra program context)
      (reserved : List (Id .custody)) :
      {type : TypeOf signature} → UseScope.ControlStore Future →
      Expression signature algebra program context type →
      Except algebra.Fault (RuntimeValue signature algebra program type) → UseScope.ControlStore Future → Prop where
    | datum : ExpressionEvaluation bindings reserved store (.datum datum) (.ok (.datum datum)) store
    | reference : ExpressionEvaluation bindings reserved store (.reference reference) (.ok (bindings.lookup reference)) store
    | closure : ClosureEvaluation bindings reserved expression before value after →
        ExpressionEvaluation bindings reserved before expression (.ok value) after
    | pair : ExpressionEvaluation bindings reserved before first (.ok firstValue) middle →
        ExpressionEvaluation bindings reserved middle second (.ok secondValue) after →
        ExpressionEvaluation bindings reserved before (.pair first second) (.ok (.pair firstValue secondValue)) after
    | pairFirstFault : ExpressionEvaluation bindings reserved before first (.error fault) after →
        ExpressionEvaluation bindings reserved before (.pair first second) (.error fault) after
    | pairSecondFault : ExpressionEvaluation bindings reserved before first (.ok firstValue) middle →
        ExpressionEvaluation bindings reserved middle second (.error fault) after →
        ExpressionEvaluation bindings reserved before (.pair first second) (.error fault) after
    | first : ExpressionEvaluation bindings reserved before expression (.ok value) after →
        ExpressionEvaluation bindings reserved before (.first expression) (.ok value.first) after
    | firstFault : ExpressionEvaluation bindings reserved before expression (.error fault) after →
        ExpressionEvaluation bindings reserved before (.first expression) (.error fault) after
    | second : ExpressionEvaluation bindings reserved before expression (.ok value) after →
        ExpressionEvaluation bindings reserved before (.second expression) (.ok value.second) after
    | secondFault : ExpressionEvaluation bindings reserved before expression (.error fault) after →
        ExpressionEvaluation bindings reserved before (.second expression) (.error fault) after
    | left : ExpressionEvaluation bindings reserved before expression (.ok value) after →
        ExpressionEvaluation bindings reserved before (.left expression) (.ok (.left value)) after
    | leftFault : ExpressionEvaluation bindings reserved before expression (.error fault) after →
        ExpressionEvaluation bindings reserved before (.left expression) (.error fault) after
    | right : ExpressionEvaluation bindings reserved before expression (.ok value) after →
        ExpressionEvaluation bindings reserved before (.right expression) (.ok (.right value)) after
    | rightFault : ExpressionEvaluation bindings reserved before expression (.error fault) after →
        ExpressionEvaluation bindings reserved before (.right expression) (.error fault) after
    | primitive {parameters : List signature.Data} {answer : signature.Data}
        {operation : algebra.operation parameters answer}
        {inputs : Arguments signature algebra program context (parameters.map Ty.leaf)}
        {values : RuntimeEnvironment signature algebra program (parameters.map Ty.leaf)}
        {value : algebra.Value answer} :
        ArgumentsEvaluation bindings reserved before inputs (.ok values) after →
        algebra.evaluate operation values.leaves = .ok value →
        ExpressionEvaluation bindings reserved before (.primitive operation inputs) (.ok (.datum (.leaf value))) after
    | primitiveFault {parameters : List signature.Data} {answer : signature.Data}
        {operation : algebra.operation parameters answer}
        {inputs : Arguments signature algebra program context (parameters.map Ty.leaf)}
        {values : RuntimeEnvironment signature algebra program (parameters.map Ty.leaf)} :
        ArgumentsEvaluation bindings reserved before inputs (.ok values) after →
        algebra.evaluate operation values.leaves = .error fault →
        ExpressionEvaluation bindings reserved before (.primitive operation inputs) (.error fault) after
    | primitiveInputFault {parameters : List signature.Data} {answer : signature.Data}
        {operation : algebra.operation parameters answer}
        {inputs : Arguments signature algebra program context (parameters.map Ty.leaf)} :
        ArgumentsEvaluation bindings reserved before inputs (.error fault) after →
        ExpressionEvaluation bindings reserved before (.primitive operation inputs) (.error fault) after

  inductive ArgumentsEvaluation (bindings : RuntimeEnvironment signature algebra program context)
      (reserved : List (Id .custody)) :
      {types : List (TypeOf signature)} → UseScope.ControlStore Future →
      Arguments signature algebra program context types →
      Except algebra.Fault (RuntimeEnvironment signature algebra program types) → UseScope.ControlStore Future → Prop where
    | nil : ArgumentsEvaluation bindings reserved store .nil (.ok .nil) store
    | cons : ExpressionEvaluation bindings reserved before first (.ok firstValue) middle →
        ArgumentsEvaluation bindings reserved middle rest (.ok restValues) after →
        ArgumentsEvaluation bindings reserved before (.cons first rest) (.ok (.cons firstValue restValues)) after
    | firstFault : ExpressionEvaluation bindings reserved before first (.error fault) after →
        ArgumentsEvaluation bindings reserved before (.cons first rest) (.error fault) after
    | restFault : ExpressionEvaluation bindings reserved before first (.ok firstValue) middle →
        ArgumentsEvaluation bindings reserved middle rest (.error fault) after →
        ArgumentsEvaluation bindings reserved before (.cons first rest) (.error fault) after
end

private theorem operand_ownership_bounded
    (bindings : RuntimeEnvironment signature algebra program context) (reserved : List (Id .custody)) (bound : Nat) :
    (∀ {type} (expression : Expression signature algebra program context type), sizeOf expression < bound →
      ∀ (before after : UseScope.ControlStore Future) (outcome : Except algebra.Fault (RuntimeValue signature algebra program type)),
      ExpressionEvaluation bindings reserved before expression outcome after →
      UseScope.ControlStore.Valid before → UseScope.ControlStore.Valid after) ∧
    (∀ {types} (arguments : Arguments signature algebra program context types), sizeOf arguments < bound →
      ∀ (before after : UseScope.ControlStore Future) (outcome : Except algebra.Fault (RuntimeEnvironment signature algebra program types)),
      ArgumentsEvaluation bindings reserved before arguments outcome after →
      UseScope.ControlStore.Valid before → UseScope.ControlStore.Valid after) := by
  cases bound with
  | zero => constructor <;> intro types expression sized <;> omega
  | succ bound =>
    obtain ⟨expressions, arguments⟩ := operand_ownership_bounded bindings reserved bound
    constructor
    · intro type expression sized before after outcome evaluation valid
      cases evaluation with
      | datum | reference => exact valid
      | closure evaluated => exact evaluated.preserves_ownership valid
      | pair first second | pairSecondFault first second =>
        exact expressions _ (by simp_all; omega) _ _ _ second
          (expressions _ (by simp_all; omega) _ _ _ first valid)
      | pairFirstFault evaluated => exact expressions _ (by simp_all; omega) _ _ _ evaluated valid
      | first evaluated => exact expressions _ (by simp_all; omega) _ _ _ evaluated valid
      | firstFault evaluated => exact expressions _ (by simp_all; omega) _ _ _ evaluated valid
      | second evaluated => exact expressions _ (by simp_all; omega) _ _ _ evaluated valid
      | secondFault evaluated => exact expressions _ (by simp_all; omega) _ _ _ evaluated valid
      | left evaluated => exact expressions _ (by simp_all; omega) _ _ _ evaluated valid
      | leftFault evaluated => exact expressions _ (by simp_all; omega) _ _ _ evaluated valid
      | right evaluated => exact expressions _ (by simp_all; omega) _ _ _ evaluated valid
      | rightFault evaluated => exact expressions _ (by simp_all; omega) _ _ _ evaluated valid
      | primitive evaluated _ | primitiveFault evaluated _ | primitiveInputFault evaluated =>
        exact arguments _ (by simp_all; omega) _ _ _ evaluated valid
    · intro types inputs sized before after outcome evaluation valid
      cases evaluation with
      | nil => exact valid
      | cons first rest | restFault first rest =>
        exact arguments _ (by simp_all; omega) _ _ _ rest
          (expressions _ (by simp_all; omega) _ _ _ first valid)
      | firstFault first => exact expressions _ (by simp_all; omega) _ _ _ first valid
  termination_by bound

theorem ExpressionEvaluation.preserves_ownership
    {expression : Expression signature algebra program context type}
    (evaluation : ExpressionEvaluation bindings reserved before expression outcome after)
    (valid : UseScope.ControlStore.Valid before) : UseScope.ControlStore.Valid after :=
  (operand_ownership_bounded bindings reserved (sizeOf expression + 1)).1
    expression (Nat.lt_succ_self _) before after outcome evaluation valid

theorem ArgumentsEvaluation.preserves_ownership
    {arguments : Arguments signature algebra program context types}
    (evaluation : ArgumentsEvaluation bindings reserved before arguments outcome after)
    (valid : UseScope.ControlStore.Valid before) : UseScope.ControlStore.Valid after :=
  (operand_ownership_bounded bindings reserved (sizeOf arguments + 1)).2
    arguments (Nat.lt_succ_self _) before after outcome evaluation valid

end BoundaryV2.Generalized.Source
