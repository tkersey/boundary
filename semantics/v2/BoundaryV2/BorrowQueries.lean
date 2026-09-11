import BoundaryV2.BorrowSources

namespace BoundaryV2.Profile.Target.Borrow

structure Expansion where
  sources : List Source := []
  traces : List Trace := []
  deriving DecidableEq, Repr

def querySeeds (program : Program) (witness : Witness) (query : Query) : Option (List Trace) := do
  let live := reachable program query.start
  match query.kind with
  | .origin trace => if live.contains trace.block then pushTrace program trace else some []
  | .returned path =>
    let parts ← live.mapM fun block => do
      let code ← program.blocks[block.value]?
      match code.terminator with
      | .returnValue slot => push program block slot path
      | _ => some []
    return parts.flatten
  | .writes schema path =>
    let parts ← live.mapM fun block => do
      let code ← program.blocks[block.value]?
      let written ← code.instructions.mapM fun instruction => do
        if instruction.opcode != .cellSet then return []
        let cell ← instruction.operands[0]?
        let type ← slotType program block cell
        if type != schema then return []
        let value ← instruction.operands[1]?
        push program block value path
      let called ← calledWrites program witness block schema path
      return written.flatten ++ called
    return parts.flatten

def incomingTraces (program : Program) (witness : Witness) (slot : Slot) (path : Path) :
    Incoming → Option (List Trace)
  | .edge block edge variant => do
    let argument ← edge.arguments[slot.value]?
    match argument with
    | .slot source => push program block source path
    | .returned => match variant with
      | none => outputSources program witness block path
      | some index =>
        let code ← program.blocks[block.value]?
        let .switchVariant source _ := code.terminator | none
        push program block source (prepend (.field index) path)
  | .product block source arguments => do
    let type ← slotType program block source
    let .product fields ← Admission.shape program type | none
    if slot.value < fields.length then push program block source (prepend (.field slot.value) path)
    else
      let argument ← arguments[slot.value - fields.length]?
      push program block argument path

def traceStep (program : Program) (witness : Witness) (start : BlockId) (live : List BlockId) :
    Trace → Option Expansion
  | .ambient _ component => some ⟨[.ambient component], []⟩
  | .bodyResult block path => do
    let code ← program.blocks[block.value]?
    let .handle handler body arguments _ _ := code.terminator | none
    let handler ← program.handlers[handler.value]?
    let traces ← bodySources program witness block body arguments handler.clauses.length (.returned path)
    return ⟨[], traces⟩
  | .slot block slot path => do
    let code ← program.blocks[block.value]?
    if slot.value ≥ code.parameters.length then
      let instruction ← code.instructions[slot.value - code.parameters.length]?
      let traces ← instructionTraces program block path instruction
      let sources ← if instruction.opcode == .cellGet then do
        let cell ← instruction.operands[0]?
        let type ← slotType program block cell
        sourcesAt program witness ⟨start, .writes type path⟩
      else some []
      return ⟨sources, traces⟩
    else
      let sources := if block == start then [.parameter slot.value path] else []
      let edges := (incoming program block).filter (fun edge => live.contains edge.source)
      let traces ← edges.mapM (incomingTraces program witness slot path)
      return ⟨sources, traces.flatten⟩

def queryRowValid (program : Program) (witness : Witness) (row : QueryRow) : Bool := ((do
  let normalized ← normalizedQuery program row.query
  let seeds ← querySeeds program witness row.query
  let live := reachable program row.query.start
  return normalized == row.query && Admission.subset seeds row.support && row.support.all (fun trace =>
    live.contains trace.block && (traceStep program witness row.query.start live trace).any (fun expansion =>
      Admission.subset expansion.sources row.sources && Admission.subset expansion.traces row.support))) : Option Bool).getD false

/-- Local trace closure relative to the supplied interprocedural summaries.
Global summary soundness is a separate obligation; this relation does not
assume the correctness of the native witness generator. -/
inductive TraceDerives (program : Program) (witness : Witness) (start : BlockId) : Trace → Source → Prop where
  | direct : traceStep program witness start (reachable program start) trace = some expansion →
      source ∈ expansion.sources → TraceDerives program witness start trace source
  | through : traceStep program witness start (reachable program start) trace = some expansion →
      next ∈ expansion.traces → TraceDerives program witness start next source →
      TraceDerives program witness start trace source

theorem row_supported (program : Program) (witness : Witness) (row : QueryRow)
    (accepted : queryRowValid program witness row = true) :
    ∃ seeds, querySeeds program witness row.query = some seeds ∧ seeds ⊆ row.support ∧
      ∀ trace ∈ row.support, ∃ expansion,
        traceStep program witness row.query.start (reachable program row.query.start) trace = some expansion ∧
        expansion.sources ⊆ row.sources ∧ expansion.traces ⊆ row.support := by
  unfold queryRowValid at accepted
  cases normalized : normalizedQuery program row.query with
  | none => simp [normalized] at accepted
  | some checked =>
    cases seeds : querySeeds program witness row.query with
    | none => simp [normalized, seeds] at accepted
    | some initial =>
      simp [normalized, seeds, Bool.and_eq_true] at accepted
      refine ⟨initial, rfl, ?_, ?_⟩
      · intro trace member
        exact List.contains_iff_mem.mp (List.all_eq_true.mp accepted.1.2 trace member)
      · intro trace member
        have checked := accepted.2 trace member
        simp only [Bool.and_eq_true, Option.any_eq_true] at checked
        obtain ⟨expansion, found, closed⟩ := checked.2
        refine ⟨expansion, found, ?_, ?_⟩
        · intro source member
          exact List.contains_iff_mem.mp (List.all_eq_true.mp closed.1 source member)
        · intro next member
          exact List.contains_iff_mem.mp (List.all_eq_true.mp closed.2 next member)

theorem row_covers_local_derivation (program : Program) (witness : Witness) (row : QueryRow)
    (accepted : queryRowValid program witness row = true) (trace : Trace) (source : Source)
    (inside : trace ∈ row.support) (derived : TraceDerives program witness row.query.start trace source) :
    source ∈ row.sources := by
  obtain ⟨_, _, _, supported⟩ := row_supported program witness row accepted
  induction derived with
  | direct found member =>
    obtain ⟨expansion, actual, sources, _⟩ := supported _ inside
    cases found.symm.trans actual
    exact sources member
  | through found next _ ih =>
    obtain ⟨expansion, actual, _, traces⟩ := supported _ inside
    cases found.symm.trans actual
    exact ih (traces next)

end BoundaryV2.Profile.Target.Borrow
