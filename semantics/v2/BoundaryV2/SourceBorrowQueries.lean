import BoundaryV2.SourceBorrowSources

namespace BoundaryV2.Profile.Source.Borrow

structure Expansion where
  origins : List Origin := []
  traces : List Trace := []
  deriving DecidableEq, Repr

def querySeeds (context : Context) (witness : Witness) (kind : QueryKind) : Evaluation (List Trace) := do
  let function ← require context.graph[context.current.value]?
  match kind with
  | .origin trace => require (pushTrace context trace)
  | .returned path => require (pushValues context function.returned.toList path)
  | .writes schema path =>
    let parts ← function.nodes.toList.zipIdx.mapM fun (code, node) => do
      match code.expression with
      | .primitive .cellSet operands _ =>
        let cell ← require operands[0]?
        let type ← require (valueType context cell)
        if type != schema then return []
        let value ← require operands[1]?
        require (push context value path)
      | .invocation invocation => calledWrites context witness node invocation schema path
      | _ => return []
    return parts.flatten

def traceStep (context : Context) (witness : Witness) : Trace → Evaluation Expansion
  | .ambient component => pure ⟨[.ambient component], []⟩
  | .bodyResult node path => do
    let code ← require (nodeAt context node)
    let .invocation (.handle handler _ body arguments _) := code.expression | throw ()
    let handler ← require context.source.handlers[handler.value]?
    let traces ← bodyOrigins context witness node body arguments handler.clauses.length (.returned path)
    return ⟨[], traces⟩
  | .value node path => do
    let code ← require (nodeAt context node)
    match code.expression with
    | .parameter index => return ⟨[.parameter index path], []⟩
    | .captured var => return ⟨[.captured var path], []⟩
    | .literal _ => return ⟨[], []⟩
    | .primitive opcode operands immediate =>
      let traces ← require (primitiveTraces context path opcode operands immediate)
      let origins ← if opcode == .cellGet then do
        let cell ← require operands[0]?
        let type ← require (valueType context cell)
        originsAt context.source witness ⟨context.current, .writes type path⟩
      else pure []
      return ⟨origins, traces⟩
    | .closure function environment =>
      let traces ← require (match path with
        | [] => pushValues context (environment.map Prod.snd) []
        | .environment selected var :: rest =>
          if selected != function then some [] else do
            let reference ← (environment.find? (fun entry => entry.1 == var)).map Prod.snd
            push context reference rest
        | _ => some [])
      return ⟨[], traces⟩
    | .invocation invocation => return ⟨[], ← outputOrigins context witness node invocation path⟩
    | .project value field => return ⟨[], ← require (push context value (prepend (.field field) path))⟩
    | .alternative branches => return ⟨[], ← require (pushValues context branches path)⟩
    | .failure value => return ⟨[], ← require (push context value path)⟩

def evaluated (witness : Witness) (action : Evaluation α) (predicate : α → Bool) : Bool :=
  match action.run [] with
  | .error _ => false
  | .ok (result, requests) => requests.all (requestPresent witness) && predicate result

def queryRowValid (context : Context) (witness : Witness) (row : QueryRow) : Bool :=
  context.current == row.query.function && normalizedQuery context.source row.query == some row.query &&
    evaluated witness (querySeeds context witness row.query.kind) (fun seeds => Admission.subset seeds row.support) &&
    row.support.all (fun trace => evaluated witness (traceStep context witness trace) (fun expansion =>
      Admission.subset expansion.origins row.origins && Admission.subset expansion.traces row.support))

/-- Local dependency derivations, relative to the candidate summaries. Closure
of every requested summary is checked separately by the complete checker. -/
inductive TraceDerives (context : Context) (witness : Witness) : Trace → Origin → Prop where
  | direct : (traceStep context witness trace).run [] = .ok (expansion, requests) →
      origin ∈ expansion.origins → TraceDerives context witness trace origin
  | through : (traceStep context witness trace).run [] = .ok (expansion, requests) →
      next ∈ expansion.traces → TraceDerives context witness next origin →
      TraceDerives context witness trace origin

theorem evaluated_sound (witness : Witness) (action : Evaluation α) (predicate : α → Bool)
    (accepted : evaluated witness action predicate = true) :
    ∃ result requests, action.run [] = .ok (result, requests) ∧
      requests.all (requestPresent witness) = true ∧ predicate result = true := by
  unfold evaluated at accepted
  cases run : action.run [] with
  | error error => simp [run] at accepted
  | ok pair =>
    obtain ⟨result, requests⟩ := pair
    simp only [run, Bool.and_eq_true] at accepted
    exact ⟨result, requests, rfl, accepted⟩

theorem row_covers_local_derivation (context : Context) (witness : Witness) (row : QueryRow)
    (accepted : queryRowValid context witness row = true) (trace : Trace) (origin : Origin)
    (inside : trace ∈ row.support) (derived : TraceDerives context witness trace origin) :
    origin ∈ row.origins := by
  simp only [queryRowValid, Bool.and_eq_true] at accepted
  have support := List.all_eq_true.mp accepted.2
  induction derived with
  | direct found member =>
    obtain ⟨expansion, requests, actual, _, closed⟩ := evaluated_sound _ _ _ (support _ inside)
    cases found.symm.trans actual
    simp only [Bool.and_eq_true] at closed
    exact List.contains_iff_mem.mp (List.all_eq_true.mp closed.1 _ member)
  | through found next _ ih =>
    obtain ⟨expansion, requests, actual, _, closed⟩ := evaluated_sound _ _ _ (support _ inside)
    cases found.symm.trans actual
    simp only [Bool.and_eq_true] at closed
    exact ih (List.contains_iff_mem.mp (List.all_eq_true.mp closed.2 _ next))

end BoundaryV2.Profile.Source.Borrow
