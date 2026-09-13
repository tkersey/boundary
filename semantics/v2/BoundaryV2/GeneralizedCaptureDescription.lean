import BoundaryV2.GeneralizedFreeze

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

namespace Source

/-- Authored provenance for a captured higher-order context. `future` builds
the source callbacks; this description never executes target code. -/
inductive Capture (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) : TypeOf signature → TypeOf signature → Type where
  | done : Capture signature algebra program result result
  | bind (body : Computation signature algebra program (input :: context) middle)
      (bindings : RuntimeEnvironment signature algebra program context)
      (rest : Capture signature algebra program middle result) : Capture signature algebra program input result
  | handler (effect : signature.Effect) (mode : Mode) (identity : Id .attachment)
      (returned : Computation signature algebra program (input :: context) middle)
      (clauses : Clauses signature algebra program effect mode context input middle)
      (bindings : RuntimeEnvironment signature algebra program context)
      (rest : Capture signature algebra program middle result) : Capture signature algebra program input result
  | region (identity : Id .region) (rest : Capture signature algebra program input result) :
      Capture signature algebra program input result
  | protection (identity : Id .obligation)
      (cleanup : Computation signature algebra program (.exit :: context) .unit)
      (bindings : RuntimeEnvironment signature algebra program context)
      (rest : Capture signature algebra program input result) : Capture signature algebra program input result

def Capture.future : Capture signature algebra program input result → Context signature algebra program input result
  | .done => .done
  | .bind body bindings rest => .push (.bind (fun value => .evaluate body (.cons value bindings))) rest.future
  | .handler effect mode identity returned clauses bindings rest =>
      .push (.handler effect mode identity returned clauses bindings) rest.future
  | .region identity rest => .push (.region identity) rest.future
  | .protection identity cleanup bindings rest => .push (.protection identity cleanup bindings) rest.future

def Capture.references : Capture signature algebra program input result → List Reference
  | .done => []
  | .bind body bindings rest => (body.references ++ environmentReferences bindings) ++ rest.references
  | .handler _ _ identity returned clauses bindings rest =>
      (.name .attachment identity :: (returned.references ++ clauses.references ++ environmentReferences bindings)) ++ rest.references
  | .region identity rest => .name .region identity :: rest.references
  | .protection identity cleanup bindings rest =>
      (.name .obligation identity :: (cleanup.references ++ environmentReferences bindings)) ++ rest.references

def Capture.copyable : Capture signature algebra program input result → Bool
  | .done => true
  | .bind _ bindings rest | .handler _ _ _ _ _ bindings rest => bindings.copyable && rest.copyable
  | .region _ rest => rest.copyable
  | .protection _ _ _ _ => false

theorem Capture.supported (capture : Capture signature algebra program input result) :
    ContextSupported capture.future capture.references := by
  induction capture with
  | done => exact .done
  | bind body bindings rest induction => exact .push (.bind body bindings) induction
  | handler effect mode identity returned clauses bindings rest induction =>
      exact .push (.handler effect mode identity returned clauses bindings) induction
  | region identity rest induction => exact .push (.region identity) induction
  | protection identity cleanup bindings rest induction => exact .push (.protection identity cleanup bindings) induction

end Source

namespace Defunctionalization

def capture : Source.Capture signature algebra program input result → Target.Stack signature algebra program input result
  | .done => .done
  | .bind body bindings rest => .push (.returnTo (.enter (computation body)) (environment bindings) .nil) (capture rest)
  | .handler effect mode identity returned clauses bindings rest =>
      .push (.handler effect mode identity (computation returned) (Defunctionalization.clauses clauses) (environment bindings)) (capture rest)
  | .region identity rest => .push (.region identity) (capture rest)
  | .protection identity cleanup bindings rest => .push (.protection identity (computation cleanup) (environment bindings)) (capture rest)

theorem capture_correspondence (source : Source.Capture signature algebra program input result) :
    ContextRelated signature algebra program source.future (capture source) := by
  induction source with
  | done => exact .done
  | bind body bindings rest induction => exact .push (.bind body bindings) induction
  | handler effect mode identity returned clauses bindings rest induction =>
      exact .push (.handler effect mode identity returned clauses bindings) induction
  | region identity rest induction => exact .push (.region identity) induction
  | protection identity cleanup bindings rest induction => exact .push (.protection identity cleanup bindings) induction

/-- Every context already related by the core has authored provenance. Only
the target's silent identity frames disappear; no source frame is discarded. -/
theorem related_context_has_capture
    {source : Source.Context signature algebra program input result}
    {target : Target.Stack signature algebra program input result}
    (related : ContextRelated signature algebra program source target) :
    ∃ description : Source.Capture signature algebra program input result,
      description.future = source ∧ capture description = target.cloneView := by
  induction related with
  | done => exact ⟨.done, rfl, rfl⟩
  | passthrough bindings rest induction => exact induction
  | push frame rest induction =>
    obtain ⟨description, original, compiled⟩ := induction
    cases frame with
    | bind body bindings => exact ⟨.bind body bindings description, congrArg _ original, congrArg _ compiled⟩
    | handler effect mode identity returned clauses bindings =>
        exact ⟨.handler effect mode identity returned clauses bindings description, congrArg _ original, congrArg _ compiled⟩
    | region identity => exact ⟨.region identity description, congrArg _ original, congrArg _ compiled⟩
    | protection identity cleanup bindings =>
        exact ⟨.protection identity cleanup bindings description, congrArg _ original, congrArg _ compiled⟩

theorem capture_copyability (source : Source.Capture signature algebra program input result) :
    (capture source).copyable = source.copyable := by
  induction source with
  | done => rfl
  | bind body bindings rest induction =>
      simp only [capture, Target.Stack.copyable, Target.Frame.copyable, environment,
        Environment.copyable_map, Environment.copyable, Bool.and_true, Source.Capture.copyable, induction]
  | handler effect mode identity returned clauses bindings rest induction =>
      simp only [capture, Target.Stack.copyable, Target.Frame.copyable, environment,
        Environment.copyable_map, Source.Capture.copyable, induction]
  | region identity rest induction => exact induction
  | protection identity cleanup bindings rest induction => rfl

theorem capture_references (source : Source.Capture signature algebra program input result) :
    (capture source).references = source.references := by
  induction source with
  | done => rfl
  | bind body bindings rest induction =>
      simp only [capture, Target.Stack.references, Target.Frame.references, Target.Code.references,
        computation_reference_support, environment_reference_support, Target.environmentReferences,
        List.append_nil, Source.Capture.references, induction]
  | handler effect mode identity returned clauses bindings rest induction =>
      simp only [capture, Target.Stack.references, Target.Frame.references, computation_reference_support,
        clauses_reference_support, environment_reference_support, Source.Capture.references, induction]
  | region identity rest induction => exact congrArg (Reference.name .region identity :: ·) induction
  | protection identity cleanup bindings rest induction =>
      simp only [capture, Target.Stack.references, Target.Frame.references, computation_reference_support,
        environment_reference_support, Source.Capture.references, induction]

end Defunctionalization
end BoundaryV2.Generalized
