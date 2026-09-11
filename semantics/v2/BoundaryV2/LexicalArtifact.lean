import BoundaryV2.ProjectionArtifact
import BoundaryV2.Lowering

namespace BoundaryV2.LexicalArtifact
open ProjectionArtifact (Bytes limit text fixed natural vector blob ids jsonArray jsonIds)

/-- This fragment has an authored unit failure for unsigned addition overflow. -/
inductive Outcome where
  | returned : Nat → Outcome
  | overflow : Outcome

def add (left right : Nat) : Outcome :=
  if left + right < limit then .returned (left + right) else .overflow

namespace Source
/-- The source tree is lexical: lambda retains its environment and application
extends that environment with its argument. There are no target slots here. -/
inductive Expr where
  | variable : Nat → Expr
  | literal : Nat → Expr
  | add : Expr → Expr → Expr
  | lambda : Expr → Expr
  | apply : Expr → Expr → Expr
  | bind : Expr → Expr → Expr

inductive Value where
  | number : Nat → Value
  | closure : Expr → List Value → Value

inductive Result where
  | value : Value → Result
  | overflow : Result

/-- Inductive evaluation has no execution fuel. Stuck ill-typed expressions have
no derivation; authored arithmetic overflow has its own derivation. -/
inductive Eval : List Value → Expr → Result → Prop where
  | variable : env[index]? = some value → Eval env (.variable index) (.value value)
  | literal : Eval env (.literal value) (.value (.number value))
  | lambda : Eval env (.lambda body) (.value (.closure body env))
  | add : Eval env left (.value (.number x)) → Eval env right (.value (.number y)) →
      x + y < limit → Eval env (.add left right) (.value (.number (x + y)))
  | addOverflow : Eval env left (.value (.number x)) → Eval env right (.value (.number y)) →
      ¬ x + y < limit → Eval env (.add left right) .overflow
  | addLeftFailure : Eval env left .overflow → Eval env (.add left right) .overflow
  | addRightFailure : Eval env left (.value (.number x)) → Eval env right .overflow →
      Eval env (.add left right) .overflow
  | apply : Eval env computation (.value (.closure body captured)) →
      Eval env argument (.value value) → Eval (value :: captured) body result →
      Eval env (.apply computation argument) result
  | applyLeftFailure : Eval env computation .overflow → Eval env (.apply computation argument) .overflow
  | applyRightFailure : Eval env computation (.value (.closure body captured)) →
      Eval env argument .overflow → Eval env (.apply computation argument) .overflow
  | bind : Eval env value (.value evaluated) → Eval (evaluated :: env) body result →
      Eval env (.bind value body) result
  | bindFailure : Eval env value .overflow → Eval env (.bind value body) .overflow

theorem evaluation_deterministic (first : Eval env expression one)
    (second : Eval env expression two) : one = two := by
  induction first generalizing two <;> cases second <;>
    try rfl
  all_goals grind

def expression (offset : Nat) : Expr :=
  .bind (.lambda (.add (.variable 1) (.variable 0)))
    (.apply (.variable 0) (.literal offset))

def result : Outcome → Result
  | .returned value => .value (.number value)
  | .overflow => .overflow

theorem lexical_evaluates (offset input : Nat) :
    Eval [.number input] (expression offset) (result (LexicalArtifact.add input offset)) := by
  apply Eval.bind Eval.lambda
  apply Eval.apply (Eval.variable rfl) Eval.literal
  unfold LexicalArtifact.add
  split
  · exact Eval.add (Eval.variable rfl) (Eval.variable rfl) ‹_›
  · exact Eval.addOverflow (Eval.variable rfl) (Eval.variable rfl) ‹_›

/-- The original natural-number expression is retained as a checked local
projection precisely when this fixed-width computation succeeds. -/
theorem natural_fragment (offset input : Nat) (bounded : input + offset < limit) :
    result (LexicalArtifact.add input offset) =
      .value (.number (match Core.Expr.eval
        (.add (.ref .here) (.literal (.number offset))) (.cons (.number input) .nil) with
          | .number value => value)) := by
  simp [LexicalArtifact.add, bounded, result, Core.Expr.eval, Core.Variable.lookup]
end Source

namespace Target
inductive Value where
  | number : Nat → Value
  | closure : Nat → List Value → Value

inductive Instruction where
  | constant : Nat → Instruction
  | computation : Nat → List Nat → Instruction
  | add : Nat → Nat → Instruction

inductive Argument where
  | slot : Nat → Argument
  | returned : Argument

structure Edge where
  block : Nat
  arguments : List Argument

inductive Terminator where
  | returnValue : Nat → Terminator
  | jump : Edge → Terminator
  | apply : Nat → List Nat → Edge → Terminator

structure Block where
  function : Nat
  parameters : List Nat
  instructions : List Instruction
  terminator : Terminator

structure Program where
  offset : Nat
  blocks : List Block

structure Continuation where
  edge : Edge
  slots : List Value

inductive State where
  | running : Nat → Nat → List Value → List Continuation → State
  | returned : Nat → State
  | overflow : State

def arguments (slots : List Value) (returned : Option Value) (args : List Argument) : Option (List Value) :=
  args.mapM fun arg => match arg with
    | .slot index => slots[index]?
    | .returned => returned

def enter (edge : Edge) (slots : List Value) (returned : Option Value)
    (continuations : List Continuation) : Option State := do
  return .running edge.block 0 (← arguments slots returned edge.arguments) continuations

/-- One BPI2-shaped transition. Slots, constructor capture fields, block edges,
result holes and the call return stack determine target control independently. -/
def step (program : Program) : State → Option State
  | .returned _ | .overflow => none
  | .running blockIndex pc slots continuations => do
    let block ← program.blocks[blockIndex]?
    if pc < block.instructions.length then
      match ← block.instructions[pc]? with
      | .constant index =>
        if index = 1 then return .running blockIndex (pc + 1) (slots ++ [.number program.offset]) continuations
        else none
      | .computation constructor captures =>
        if constructor = 0 then
          let captured ← captures.mapM fun index => slots[index]?
          return .running blockIndex (pc + 1) (slots ++ [.closure 1 captured]) continuations
        else none
      | .add left right =>
        let .number x ← slots[left]? | none
        let .number y ← slots[right]? | none
        if x + y < limit then
          return .running blockIndex (pc + 1) (slots ++ [.number (x + y)]) continuations
        else return .overflow
    else if pc = block.instructions.length then
      match block.terminator with
      | .jump edge => enter edge slots none continuations
      | .returnValue index =>
        let value ← slots[index]?
        match continuations with
        | [] => match value with | .number value => some (.returned value) | _ => none
        | continuation :: rest => enter continuation.edge continuation.slots (some value) rest
      | .apply computation operands next =>
        let .closure function captured ← slots[computation]? | none
        if function = 1 then
          let values ← operands.mapM fun index => slots[index]?
          return .running 1 0 (captured ++ values) (⟨next, slots⟩ :: continuations)
        else none
    else none

inductive Steps (program : Program) : State → State → Prop where
  | refl : Steps program state state
  | next : step program before = some middle → Steps program middle after → Steps program before after

def terminal : Outcome → State
  | .returned value => .returned value
  | .overflow => .overflow

def program (offset : Nat) : Program := ⟨offset, [
  ⟨0, [0], [.computation 0 [0]], .jump ⟨2, [.slot 1]⟩⟩,
  ⟨1, [0, 0], [.add 0 1], .returnValue 2⟩,
  ⟨0, [1], [.constant 1], .apply 0 [1] ⟨3, [.returned]⟩⟩,
  ⟨0, [0], [], .returnValue 0⟩]⟩

def initial (input : Nat) : State := .running 0 0 [.number input] []

theorem lexical_reduces (offset input : Nat) :
    Steps (program offset) (initial input) (terminal (LexicalArtifact.add input offset)) := by
  apply Steps.next (by rfl)
  apply Steps.next (by rfl)
  apply Steps.next (by rfl)
  apply Steps.next (by rfl)
  by_cases bounded : input + offset < limit
  · apply Steps.next (middle := .running 1 1 [.number input, .number offset, .number (input + offset)]
        [⟨⟨3, [.returned]⟩, [.closure 1 [.number input], .number offset]⟩])
        (by simp [step, program, bounded])
    apply Steps.next (by rfl)
    apply Steps.next (by rfl)
    simpa [LexicalArtifact.add, bounded, terminal] using
      (Steps.refl : Steps (program offset) (.returned (input + offset)) (.returned (input + offset)))
  · apply Steps.next (middle := .overflow) (by simp [step, program, bounded])
    simpa [LexicalArtifact.add, bounded, terminal] using
      (Steps.refl : Steps (program offset) .overflow .overflow)
end Target

/-- Full source-file subject for the lexical closure family. The source term
catalog denotes Source.expression; no target code defines this meaning. -/
def encodeSource (offset : Nat) : Bytes := text <|
  "{\"entry\":0,\"failure\":1,\"schemas\":[{\"u64\":{}},{\"unit\":{}},{\"internal\":{\"computation\":{\"parameters\":[0],\"result\":0,\"effects\":[],\"capture_bound\":[0],\"use\":\"reusable\",\"regions\":[]}}}],\"constants\":[{\"schema\":1,\"bytes\":[]},{\"schema\":0,\"bytes\":" ++ jsonIds ((fixed 8 offset).map UInt8.toNat) ++ "}],\"effects\":[],\"handlers\":[],\"region_count\":0,\"resources\":[],\"variables\":[0,0,2],\"values\":[{\"schema\":1,\"expression\":{\"literal\":0}},{\"schema\":0,\"expression\":{\"variable\":0}},{\"schema\":0,\"expression\":{\"variable\":1}},{\"schema\":0,\"expression\":{\"primitive\":{\"opcode\":\"integer_add\",\"operands\":[1,2],\"immediate\":0,\"failures\":[{\"kind\":\"arithmetic_overflow\",\"value\":0}]}}},{\"schema\":2,\"expression\":{\"lambda\":1}},{\"schema\":2,\"expression\":{\"variable\":2}},{\"schema\":0,\"expression\":{\"literal\":1}}],\"terms\":[{\"value\":3},{\"apply\":{\"computation\":5,\"arguments\":[6]}},{\"value\":4},{\"bind\":{\"variable\":2,\"value\":2,\"next\":1}}],\"functions\":[{\"parameters\":[0],\"result\":0,\"effects\":[],\"regions\":[],\"body\":3},{\"parameters\":[1],\"result\":0,\"effects\":[],\"regions\":[],\"body\":0}]}\n"

namespace Target
def encodeArgument : Argument → Bytes
  | .slot index => natural 0 ++ natural index
  | .returned => natural 1

def encodeEdge (edge : Edge) : Bytes :=
  natural edge.block ++ vector (edge.arguments.map encodeArgument)

def encodeInstruction : Instruction → Bytes
  | .constant index => natural 0 ++ natural 0 ++ ids [] ++ natural index ++ vector []
  | .computation constructor captures =>
    natural 20 ++ natural 1 ++ ids captures ++ natural constructor ++ vector []
  | .add left right => natural 2 ++ natural 0 ++ ids [left, right] ++ natural 0 ++
    vector [natural 0 ++ natural 0]

def encodeTerminator : Terminator → Bytes
  | .returnValue index => natural 0 ++ natural index
  | .jump edge => natural 1 ++ encodeEdge edge
  | .apply computation arguments next =>
    natural 9 ++ natural computation ++ ids arguments ++ encodeEdge next

def encodeBlock (block : Block) : Bytes :=
  natural block.function ++ ids block.parameters ++
    vector (block.instructions.map encodeInstruction) ++ encodeTerminator block.terminator

/-- The fixed catalogs of this family are explicit, including the reusable
capture's field order, internal computation contract, unit failure literal,
constructor and every otherwise empty BPI2 section. -/
def sections (program : Program) : List Bytes := [
  natural 1 ++ natural 0 ++ natural 0 ++ natural 2,
  vector [natural 9,
    natural 16 ++ natural 0 ++ ids [0] ++ natural 0 ++ ids [] ++ ids [0] ++ natural 0 ++ ids [],
    natural 0],
  vector [natural 2 ++ blob [], natural 0 ++ blob (fixed 8 program.offset)],
  vector [],
  vector [natural 0 ++ ids [0] ++ natural 0 ++ ids [] ++ ids [],
    natural 1 ++ ids [0, 0] ++ natural 0 ++ ids [] ++ ids []],
  vector (program.blocks.map encodeBlock),
  vector [],
  vector [ids [0] ++ ids [] ++ ids [] ++ natural 0] ++ natural 0 ++ vector [],
  vector [natural 1 ++ natural 0 ++ natural 1]]

def body (program : Program) : Bytes :=
  natural 9 ++ ProjectionArtifact.directory (sections program) 1 0 ++ (sections program).flatten

def encodeImage (program : Program) : Bytes :=
  let bytes := body program
  text "ABL_BPI2" ++ fixed 2 2 ++ fixed 2 0 ++ fixed 8 bytes.length ++ bytes

/-- A terminal state has no successor; stuttering is not a target rule. -/
theorem terminal_stops (program : Program) (outcome : Outcome) :
    step program (terminal outcome) = none := by cases outcome <;> rfl

theorem terminal_path_unique {program : Program} (path : Steps program before after)
    (other : Steps program before terminalState)
    (done : step program after = none) (terminalDone : step program terminalState = none) :
    after = terminalState := by
  induction path with
  | refl =>
    cases other with
    | refl => rfl
    | next next _ => simp [done] at next
  | next next path ih =>
    cases other with
    | refl => simp [terminalDone] at next
    | next otherNext otherRest =>
      have same := Option.some.inj (next.symm.trans otherNext)
      subst same
      exact ih otherRest done

/-- Every step prefix from an input can be extended to the proved terminal
state. In particular, there is no infinite target-only administrative branch. -/
theorem path_prefix_extends {program : Program} (complete : Steps program start finish)
    (segment : Steps program start middle) (done : step program finish = none) :
    Steps program middle finish := by
  induction segment generalizing finish with
  | refl => exact complete
  | next first rest ih =>
    cases complete with
    | refl => simp [done] at first
    | next next tail =>
      have same := Option.some.inj (first.symm.trans next)
      subst same
      exact ih tail done
/-- A completed deterministic path excludes every infinite successor stream;
there is no appeal to an observation horizon or an identity transition. -/
theorem no_infinite_execution {program : Program} (complete : Steps program start finish)
    (done : step program finish = none) :
    ¬ ∃ stream : Nat → State, stream 0 = start ∧
      ∀ index, step program (stream index) = some (stream (index + 1)) := by
  intro ⟨stream, begins, advances⟩
  induction complete generalizing stream with
  | refl => simpa [begins, done] using advances 0
  | next first rest ih =>
    apply ih done (fun index => stream (index + 1))
    · have equal := Option.some.inj ((advances 0).symm.trans (begins ▸ first))
      exact equal
    · intro index
      exact advances (index + 1)
end Target

/-- All admitted u64 inputs, including those causing the authored failure.
Existence and uniqueness are proved for both independent semantics. -/
def Correspondence (offset : Nat) : Prop := ∀ input, input < limit →
  Source.Eval [.number input] (Source.expression offset) (Source.result (add input offset)) ∧
  Target.Steps (Target.program offset) (Target.initial input) (Target.terminal (add input offset)) ∧
  (∀ result, Source.Eval [.number input] (Source.expression offset) result →
    result = Source.result (add input offset)) ∧
  (∀ state, Target.Steps (Target.program offset) (Target.initial input) state →
    Target.step (Target.program offset) state = none → state = Target.terminal (add input offset))

theorem all_input_correspondence (offset : Nat) : Correspondence offset := by
  intro input _
  have source := Source.lexical_evaluates offset input
  have target := Target.lexical_reduces offset input
  refine ⟨source, target, ?_, ?_⟩
  · intro result evaluated
    exact Source.evaluation_deterministic evaluated source
  · intro state evaluated stopped
    exact Target.terminal_path_unique evaluated target stopped (Target.terminal_stops _ _)

/-- This claim covers a generic closure-and-addition family, including the
baseline lexical artifact. It is not the complete Boundary profile guarantee. -/
def Certified (sourceBytes imageBytes : Bytes) : Prop :=
  ∃ offset, offset < limit ∧ (Target.body (Target.program offset)).length < limit ∧
    encodeSource offset = sourceBytes ∧ Target.encodeImage (Target.program offset) = imageBytes ∧
    Correspondence offset

def check (sourceBytes imageBytes : Bytes) (offset : Nat) : Bool :=
  decide (offset < limit) && decide ((Target.body (Target.program offset)).length < limit) &&
    decide (encodeSource offset = sourceBytes) && decide (Target.encodeImage (Target.program offset) = imageBytes)

theorem check_sound (sourceBytes imageBytes : Bytes) (offset : Nat)
    (accepted : check sourceBytes imageBytes offset = true) : Certified sourceBytes imageBytes := by
  simp only [check, Bool.and_eq_true, decide_eq_true_eq] at accepted
  exact ⟨offset, accepted.1.1.1, accepted.1.1.2, accepted.1.2, accepted.2, all_input_correspondence offset⟩

theorem admitted_input_exists : ∃ input : Nat, input < limit := ⟨0, by decide⟩

end BoundaryV2.LexicalArtifact
