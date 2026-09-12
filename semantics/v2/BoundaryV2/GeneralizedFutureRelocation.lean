import BoundaryV2.GeneralizedValueRelocation
import BoundaryV2.GeneralizedControlExecution

namespace BoundaryV2.Generalized.Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

def relocateValue (relocation : UseScope.Relocation) (value : RuntimeValue signature algebra program type) :
    RuntimeValue signature algebra program type := value.relocate relocation (fun _ _ body => body.relocate relocation)

def relocateEnvironment (relocation : UseScope.Relocation) (values : RuntimeEnvironment signature algebra program types) :
    RuntimeEnvironment signature algebra program types := values.relocate relocation (fun _ _ body => body.relocate relocation)

def Frame.relocate (relocation : UseScope.Relocation) : Frame signature algebra program input result → Frame signature algebra program input result
  | .returnTo next bindings operands => .returnTo (next.relocate relocation)
      (relocateEnvironment relocation bindings) (relocateEnvironment relocation operands)
  | .handler effect mode attachment returned clauses bindings =>
    .handler effect mode (relocation.name .attachment attachment) (returned.relocate relocation)
      (clauses.relocate relocation) (relocateEnvironment relocation bindings)
  | .region identity => .region (relocation.name .region identity)
  | .protection identity cleanup bindings =>
    .protection (relocation.name .obligation identity) (cleanup.relocate relocation) (relocateEnvironment relocation bindings)

def Stack.relocate (relocation : UseScope.Relocation) : Stack signature algebra program input result → Stack signature algebra program input result
  | .done => .done
  | .push frame rest => .push (frame.relocate relocation) (rest.relocate relocation)

theorem Stack.relocate_append (relocation : UseScope.Relocation) (first : Stack signature algebra program a b)
    (second : Stack signature algebra program b c) :
    (first.append second).relocate relocation = (first.relocate relocation).append (second.relocate relocation) := by
  induction first with
  | done => rfl
  | push frame rest induction => simp only [Stack.relocate, Stack.append, induction]

def Configuration.relocate (relocation : UseScope.Relocation) :
    Configuration signature algebra program result → Configuration signature algebra program result
  | .code body bindings operands future =>
    .code (body.relocate relocation) (relocateEnvironment relocation bindings)
      (relocateEnvironment relocation operands) (future.relocate relocation)
  | .returned value future => .returned (relocateValue relocation value) (future.relocate relocation)
  | .requested operation attachment payload bodies future =>
    .requested operation (relocation.name .attachment attachment) (relocateValue relocation payload)
      (relocateEnvironment relocation bodies) (future.relocate relocation)
  | .failed fault future => .failed fault (future.relocate relocation)
  | .yielded next => .yielded (next.relocate relocation)

def Entry.relocate (relocation : UseScope.Relocation) (entry : Entry signature algebra program result) : Entry signature algebra program result :=
  ⟨entry.context, entry.body.relocate relocation, relocateEnvironment relocation entry.environment⟩

def Resumption.relocate (relocation : UseScope.Relocation)
    (saved : Resumption signature algebra program mode effect input answer) : Resumption signature algebra program mode effect input answer :=
  ⟨relocation.name .attachment saved.attachment, saved.future.relocate relocation⟩

def relocateControlPayload (relocation : UseScope.Relocation) (packed : Sigma (ControlPayload signature algebra program)) :
    Sigma (ControlPayload signature algebra program) := ⟨packed.fst, packed.snd.relocate relocation⟩

def relocateControlInfo (relocation : UseScope.Relocation) (record : UseScope.ControlInfo (Sigma (ControlPayload signature algebra program))) :
    UseScope.ControlInfo (Sigma (ControlPayload signature algebra program)) :=
  ⟨relocation.name .control record.identity, relocation.name .custody record.authority, record.use,
    relocateControlPayload relocation record.future⟩

/-- The registry, disposal work, executable futures, and physical fields all
receive the same maps. A dormant reference is not dropped because it is inactive. -/
def relocateControlHeap (relocation : UseScope.Relocation) (store : ControlHeap signature algebra program) : ControlHeap signature algebra program :=
  ⟨store.fields.relocate relocation, store.controls.map (relocateControlInfo relocation),
    store.disposing.map (relocateControlInfo relocation)⟩

def ControlState.relocate (relocation : UseScope.Relocation) (state : ControlState signature algebra program result) :
    ControlState signature algebra program result := ⟨relocateControlHeap relocation state.store, state.configuration.relocate relocation⟩

theorem relocation_commutes_with_deep_and_shallow_capture (relocation : UseScope.Relocation)
    (mode : Mode) (effect : signature.Effect) (attachment : Id .attachment)
    (returned : Code signature algebra program (body :: context) [] answer)
    (clauses : Clauses signature algebra program effect mode context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (inside : Stack signature algebra program input body) :
    (captureResumption mode effect attachment returned clauses bindings inside).relocate relocation =
      captureResumption mode effect (relocation.name .attachment attachment) (returned.relocate relocation)
        (clauses.relocate relocation) (relocateEnvironment relocation bindings) (inside.relocate relocation) := by
  cases mode <;> simp only [captureResumption, Resumption.relocate, Stack.relocate_append, Stack.relocate, Frame.relocate] <;> rfl

theorem relocation_commutes_with_reentry (relocation : UseScope.Relocation)
    (saved : Resumption signature algebra program mode effect input answer) (value : RuntimeValue signature algebra program input)
    (outside : Stack signature algebra program answer result) :
    (reenter saved value outside).relocate relocation =
      reenter (saved.relocate relocation) (relocateValue relocation value) (outside.relocate relocation) := by
  simp only [reenter, Configuration.relocate, Resumption.relocate, Stack.relocate_append]

theorem relocation_commutes_with_injection (relocation : UseScope.Relocation)
    (saved : Resumption signature algebra program mode effect input answer) (entry : Entry signature algebra program input)
    (outside : Stack signature algebra program answer result) :
    (inject saved entry outside).relocate relocation =
      inject (saved.relocate relocation) (entry.relocate relocation) (outside.relocate relocation) := by
  simp only [inject, Configuration.relocate, Resumption.relocate, Entry.relocate, Stack.relocate_append]
  rfl

theorem relocation_commutes_with_successor (relocation : UseScope.Relocation)
    (saved : Resumption signature algebra program .shallow effect input body) (value : RuntimeValue signature algebra program input)
    (returned : Code signature algebra program (body :: context) [] answer)
    (clauses : Clauses signature algebra program effect .deep context body answer)
    (bindings : RuntimeEnvironment signature algebra program context) (outside : Stack signature algebra program answer result) :
    (reenterWith saved value returned clauses bindings outside).relocate relocation =
      reenterWith (saved.relocate relocation) (relocateValue relocation value) (returned.relocate relocation)
        (clauses.relocate relocation) (relocateEnvironment relocation bindings) (outside.relocate relocation) := by
  simp only [reenterWith, Configuration.relocate, Resumption.relocate, Stack.relocate_append, Stack.relocate, Frame.relocate]

theorem relocation_preserves_physical_environment (relocation : UseScope.Relocation)
    (bindings : RuntimeEnvironment signature algebra program context) :
    (relocateEnvironment relocation bindings).owningFields = UseScope.relocateFields relocation bindings.owningFields :=
  Environment.relocate_owning_fields relocation _ bindings

end BoundaryV2.Generalized.Target
