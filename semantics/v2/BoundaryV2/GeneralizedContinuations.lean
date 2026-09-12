import BoundaryV2.GeneralizedValues

namespace BoundaryV2.Generalized

namespace Source

abbrev RuntimeValue (signature : Signature) (algebra : LeafAlgebra signature.Data) (program) :=
  Value signature algebra (Computation signature algebra program)
abbrev RuntimeEnvironment (signature : Signature) (algebra : LeafAlgebra signature.Data) (program) :=
  Environment signature algebra (Computation signature algebra program)

/- The source uses ordinary higher-order continuation functions. Recursive
calls still refer to the finite authored code table, rather than unfolding an
infinite computation into this datatype. -/
mutual
  inductive Program (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (definitions : List (BodyType signature.Data signature.Effect)) : TypeOf signature → Type where
    | evaluate : Computation signature algebra definitions context result → RuntimeEnvironment signature algebra definitions context →
      Program signature algebra definitions result
    | returned : RuntimeValue signature algebra definitions result → Program signature algebra definitions result
    | bind : Program signature algebra definitions input →
      (RuntimeValue signature algebra definitions input → Program signature algebra definitions result) →
      Program signature algebra definitions result
    | request : (operation : signature.operation effect) → Id .attachment →
      RuntimeValue signature algebra definitions (signature.payload operation) →
      RuntimeEnvironment signature algebra definitions ((signature.bodies operation).map BodyType.type) →
      Context signature algebra definitions (signature.result operation) result →
      Program signature algebra definitions result
    | handler : (effect : signature.Effect) → (mode : Mode) → Id .attachment →
      Computation signature algebra definitions (body :: context) answer →
      Clauses signature algebra definitions effect mode context body answer → RuntimeEnvironment signature algebra definitions context →
      Program signature algebra definitions body → Program signature algebra definitions answer
    | yielded : Program signature algebra definitions result → Program signature algebra definitions result
    | failed : algebra.Fault → Program signature algebra definitions result
    | region : Id .region → Program signature algebra definitions result → Program signature algebra definitions result
    | protection : Id .obligation → Computation signature algebra definitions (.exit :: context) .unit →
      RuntimeEnvironment signature algebra definitions context → Program signature algebra definitions result →
      Program signature algebra definitions result

  inductive Frame (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (definitions : List (BodyType signature.Data signature.Effect)) : TypeOf signature → TypeOf signature → Type where
    | bind : (RuntimeValue signature algebra definitions input → Program signature algebra definitions result) →
      Frame signature algebra definitions input result
    | handler : (effect : signature.Effect) → (mode : Mode) → Id .attachment →
      Computation signature algebra definitions (body :: context) answer →
      Clauses signature algebra definitions effect mode context body answer → RuntimeEnvironment signature algebra definitions context →
      Frame signature algebra definitions body answer
    | region : Id .region → Frame signature algebra definitions result result
    | protection : Id .obligation → Computation signature algebra definitions (.exit :: context) .unit →
      RuntimeEnvironment signature algebra definitions context → Frame signature algebra definitions result result

  inductive Context (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (definitions : List (BodyType signature.Data signature.Effect)) : TypeOf signature → TypeOf signature → Type where
    | done : Context signature algebra definitions result result
    | push : Frame signature algebra definitions input middle → Context signature algebra definitions middle result →
      Context signature algebra definitions input result
end

def Frame.plug : Frame signature algebra definitions input result → Program signature algebra definitions input →
    Program signature algebra definitions result
  | .bind next, computation => .bind computation next
  | .handler effect mode id returned clauses environment, computation => .handler effect mode id returned clauses environment computation
  | .region id, computation => .region id computation
  | .protection id cleanup environment, computation => .protection id cleanup environment computation

def Context.plug : Context signature algebra definitions input result → Program signature algebra definitions input →
    Program signature algebra definitions result
  | .done, computation => computation
  | .push frame rest, computation => rest.plug (frame.plug computation)

def Context.append : Context signature algebra definitions first middle → Context signature algebra definitions middle last →
    Context signature algebra definitions first last
  | .done, last => last
  | .push frame rest, last => .push frame (rest.append last)

def Context.length : Context signature algebra definitions input result → Nat
  | .done => 0
  | .push _ rest => rest.length + 1

theorem Context.append_plug (before : Context signature algebra definitions a b) (after : Context signature algebra definitions b c)
    (computation : Program signature algebra definitions a) :
    (before.append after).plug computation = after.plug (before.plug computation) := by
  cases before with
  | done => rfl
  | push frame rest => exact Context.append_plug rest after (frame.plug computation)
termination_by before.length
decreasing_by all_goals simp_all [Context.length]

theorem Context.append_done (before : Context signature algebra definitions a b) : before.append .done = before := by
  suffices ∀ (n : Nat) {a b} (before : Context signature algebra definitions a b), before.length ≤ n → before.append .done = before from
    this before.length before (Nat.le_refl _)
  intro n
  induction n with
  | zero =>
    intro a b before bounded
    cases before with
    | done => rfl
    | push frame rest => simp [Context.length] at bounded
  | succ n induction =>
    intro a b before bounded
    cases before with
    | done => rfl
    | push frame rest =>
      exact congrArg (Context.push frame) (induction rest (by simpa [Context.length] using bounded))

theorem Context.append_associative (before : Context signature algebra definitions a b) (middle : Context signature algebra definitions b c)
    (after : Context signature algebra definitions c d) :
    (before.append middle).append after = before.append (middle.append after) := by
  suffices ∀ (n : Nat) {a b c d} (before : Context signature algebra definitions a b)
      (middle : Context signature algebra definitions b c) (after : Context signature algebra definitions c d), before.length ≤ n →
      (before.append middle).append after = before.append (middle.append after) from
    this before.length before middle after (Nat.le_refl _)
  intro n
  induction n with
  | zero =>
    intro a b c d before middle after bounded
    cases before with
    | done => rfl
    | push frame rest => simp [Context.length] at bounded
  | succ n induction =>
    intro a b c d before middle after bounded
    cases before with
    | done => rfl
    | push frame rest =>
      exact congrArg (Context.push frame) (induction rest middle after (by simpa [Context.length] using bounded))

end Source

namespace Target

abbrev RuntimeValue (signature : Signature) (algebra : LeafAlgebra signature.Data) (program) :=
  Value signature algebra (fun context result => Code signature algebra program context [] result)
abbrev RuntimeEnvironment (signature : Signature) (algebra : LeafAlgebra signature.Data) (program) :=
  Environment signature algebra (fun context result => Code signature algebra program context [] result)

/-- Return and handler frames contain code and saved environments, never source
programs or executable continuation callbacks. -/
inductive Frame (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) : TypeOf signature → TypeOf signature → Type where
  | returnTo : Code signature algebra definitions context (input :: stack) result →
    RuntimeEnvironment signature algebra definitions context → RuntimeEnvironment signature algebra definitions stack →
    Frame signature algebra definitions input result
  | handler : (effect : signature.Effect) → (mode : Mode) → Id .attachment →
    Code signature algebra definitions (body :: context) [] answer → Clauses signature algebra definitions effect mode context body answer →
    RuntimeEnvironment signature algebra definitions context → Frame signature algebra definitions body answer
  | region : Id .region → Frame signature algebra definitions result result
  | protection : Id .obligation → Code signature algebra definitions (.exit :: context) [] .unit →
    RuntimeEnvironment signature algebra definitions context → Frame signature algebra definitions result result

inductive Stack (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) : TypeOf signature → TypeOf signature → Type where
  | done : Stack signature algebra definitions result result
  | push : Frame signature algebra definitions input middle → Stack signature algebra definitions middle result →
    Stack signature algebra definitions input result

def Stack.append : Stack signature algebra definitions first middle → Stack signature algebra definitions middle last →
    Stack signature algebra definitions first last
  | .done, last => last
  | .push frame rest, last => .push frame (rest.append last)

theorem Stack.append_done (stack : Stack signature algebra definitions input result) : stack.append .done = stack := by
  induction stack with
  | done => rfl
  | push frame rest induction => simp only [Stack.append, induction]

theorem Stack.append_associative (first : Stack signature algebra definitions a b) (second : Stack signature algebra definitions b c)
    (third : Stack signature algebra definitions c d) : (first.append second).append third = first.append (second.append third) := by
  induction first with
  | done => rfl
  | push frame rest induction => simp only [Stack.append, induction]

structure Entry (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  context : List (TypeOf signature)
  body : Code signature algebra definitions context [] result
  environment : RuntimeEnvironment signature algebra definitions context

end Target

namespace Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  {parameters captured : List (TypeOf signature)} {result : TypeOf signature}

/-- This code-entry construction is used after the local call has acquired its
use permission. Its only job is the exact argument/captured-environment binding. -/
def closureEntry (body : Source.Computation signature algebra program (parameters ++ captured) result)
    (arguments : Source.RuntimeEnvironment signature algebra program parameters)
    (environment : Source.RuntimeEnvironment signature algebra program captured) : Target.Entry signature algebra program result :=
  ⟨parameters ++ captured, computation body,
    (Defunctionalization.environment arguments).append (Defunctionalization.environment environment)⟩

theorem closure_entry_has_exact_environment (body : Source.Computation signature algebra program (parameters ++ captured) result)
    (arguments : Source.RuntimeEnvironment signature algebra program parameters)
    (capturedValues : Source.RuntimeEnvironment signature algebra program captured) :
    (closureEntry body arguments capturedValues).environment =
      Defunctionalization.environment (arguments.append capturedValues) :=
  (captured_arguments_keep_order arguments capturedValues).symm

theorem closure_entry_preserves_body_identity (body : Source.Computation signature algebra program (parameters ++ captured) result)
    (arguments : Source.RuntimeEnvironment signature algebra program parameters)
    (capturedValues : Source.RuntimeEnvironment signature algebra program captured) :
    (closureEntry body arguments capturedValues).body = computation body := rfl

end Defunctionalization
end BoundaryV2.Generalized
