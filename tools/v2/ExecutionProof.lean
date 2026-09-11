import InvocationWitness
import BoundaryV2.ExecutionEvaluation

namespace BoundaryV2.Tooling

def compactNumeralList (body : String) : Option String := do
  if body.length < 1024 then none else do
    let values ← (body.splitOn ",").mapM (fun token => token.trimAscii.toString.toNat?)
    let values := values.toArray
    let mut parts : List String := []
    let mut pending : List String := []
    let mut index := 0
    let mut changed := false
    while index < values.size do
      let value := values[index]!
      let mut stop := index + 1
      while stop < values.size && values[stop]! == value do stop := stop + 1
      if stop - index ≥ 16 then
        if !pending.isEmpty then
          parts := parts ++ ["[" ++ String.intercalate "," pending ++ "]"]
          pending := []
        parts := parts ++ [s!"List.replicate {stop - index} {value}"]
        changed := true
      else
        pending := pending ++ List.replicate (stop - index) (toString value)
      index := stop
    if !changed then none else do
      if !pending.isEmpty then parts := parts ++ ["[" ++ String.intercalate "," pending ++ "]"]
      return "(" ++ String.intercalate " ++ " parts ++ ")"

/-- Presentation only: compress long runs in decimal list literals emitted by
Lean's data repr. Skip quoted text and array literals. Every resulting term is
still checked against the independently captured full byte subject. -/
def compactLiteral (value : String) : String := Id.run do
  if value.contains '"' then return value
  let mut result := ""
  let mut first := true
  for part in value.splitOn "[" do
    if first then
      result := part
      first := false
    else
      match part.splitOn "]" with
      | body :: rest =>
        if !result.endsWith "#" && !rest.isEmpty then
          if let some compact := compactNumeralList body then
            result := result ++ compact ++ String.intercalate "]" rest
          else result := result ++ "[" ++ part
        else result := result ++ "[" ++ part
      | [] => result := result ++ "[" ++ part
  return result

end BoundaryV2.Tooling


open Lean BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Target
open BoundaryV2.Tooling.InvocationWitness

deriving instance Repr for BoundaryV2.Profile.Value
deriving instance Repr for Machine.Result
deriving instance Repr for Machine.Event

namespace BoundaryV2.Tooling.ExecutionProof

def literal [Repr α] (value : α) : String :=
  Tooling.compactLiteral ((repr value).pretty 1000000000)

def leftBrace : String := "{"
def rightBrace : String := "}"

def graphLiteral (witness : Graph.Admission.Witness) : String :=
  s!"{leftBrace} blobs := {literal witness.blobs}, projections := {literal witness.projections} {rightBrace}"

def responseLiteral : Option Boundary.ResponseWitness → String
  | none => "none"
  | some witness => s!"(some {leftBrace} value := {literal witness.value}, descriptorPayload := {literal witness.descriptorPayload}, descriptorResponse := {literal witness.descriptorResponse} {rightBrace})"

def witnessLiteral (witness : Boundary.InvocationWitness) : String :=
  s!"{leftBrace} incoming := {leftBrace} arguments := {literal witness.incoming.arguments}, graph := {graphLiteral witness.incoming.graph}, clock := {literal witness.incoming.clock}, response := {responseLiteral witness.incoming.response} {rightBrace}, outgoing := {graphLiteral witness.outgoing}, internalSteps := {witness.internalSteps} {rightBrace}"

def storedLiteral (blob : Machine.StoredBlob schemas) : String :=
  s!"{leftBrace} raw := {literal blob.raw}, meaning := {literal blob.meaning}, checked := by decide_cbv {rightBrace}"

/-- Literal sharing changes presentation only; the final claim still binds every byte. -/
structure Pool where
  count : Nat
  byte : UInt8
  deriving BEq

private def poolsIn (bytes : Bytes) : List Pool := Id.run do
  let values := bytes.toArray
  let mut result := []
  let mut index := 0
  while index < values.size do
    let byte := values[index]!
    let mut stop := index + 1
    while stop < values.size && values[stop]! == byte do stop := stop + 1
    if stop - index ≥ 1024 then result := result ++ [⟨stop - index, byte⟩]
    index := stop
  return result

private def replacePool (source target replacement : String) : String :=
  match source.splitOn target with
  | [] => source
  | first :: rest => first ++ String.join (rest.map fun suffix =>
      -- A byte numeral must end here: pool byte 9 cannot rewrite byte 90.
      (if suffix.toList.head?.any Char.isDigit then target else replacement) ++ suffix)

private def shared (pools : List Pool) (source : String) : String :=
  (pools.zipIdx.foldl (fun value (pool, index) =>
    replacePool value s!"List.replicate {pool.count} {pool.byte.toNat}" s!"pool{index}") source).replace
      "size_toArray := _" "size_toArray := by decide"

private def render [Repr α] (pools : List Pool) (value : α) : String := "(" ++ shared pools (literal value) ++ ")"

/-- Keys use the constructor spine reached after byte mapping, not prefix append. -/
private def numeralKey (pools : List Pool) (bytes : Bytes) : String := Id.run do
  let values := bytes.toArray
  let mut parts : List (Bool × String) := []
  let mut index := 0
  while index < values.size do
    let byte := values[index]!
    let mut stop := index + 1
    while stop < values.size && values[stop]! == byte do stop := stop + 1
    match pools.zipIdx.find? (fun (pool, _) => pool.count == stop - index && pool.byte == byte) with
    | some (_, number) =>
      parts := parts ++ [(true, s!"pool{number}Nat")]
      index := stop
    | none =>
      parts := parts ++ [(false, toString byte.toNat)]
      index := index + 1
  return parts.foldr (fun (isPool, part) rest =>
    if isPool then (if rest == "[]" then part else s!"(List.append {part} {rest})")
    else s!"({part} :: {rest})") "[]"

private def stateLiteral (pools : List Pool) (state : Machine.State program) : String :=
  let blobs := String.intercalate "," (state.store.blobs.map (fun blob => shared pools (storedLiteral blob)))
  s!"{leftBrace} identity := {render pools state.identity}, store := {leftBrace} nodes := {render pools state.store.nodes}, blobs := [{blobs}] {rightBrace}, status := {render pools state.status}, roots := {render pools state.roots}, result := {render pools state.result}, nextOccurrence := {state.nextOccurrence}, pendingOccurrence := {render pools state.pendingOccurrence} {rightBrace}"

private def resultLiteral (pools : List Pool) (result : Boundary.InvocationResult) : String :=
  s!"{leftBrace} instanceData := {render pools result.instanceData}, next := {render pools result.next}, clock := {literal result.clock}, events := {render pools result.events}, terminal := {literal result.terminal} {rightBrace}"

private def responseData (pools : List Pool) (response : Boundary.ResponseWitness) : String :=
  s!"⟨{render pools response.value}, {render pools response.descriptorPayload}, {render pools response.descriptorResponse}⟩"

private def evaluationRules : String := String.intercalate "\n" [
  "attribute [cbv_eval] Wire.Codec.sizedBytes_encode Wire.Codec.sizedBytes_valid Wire.Codec.sizedBytes_direct",
  "attribute [cbv_opaque] Wire.Codec.sizedBytes List.append List.beq List.map",
  "attribute [cbv_eval] Wire.Evaluation.bytes_beq_self Wire.Evaluation.bytes_beq_prefix",
  "attribute [cbv_eval] Wire.Evaluation.append_nil_eval Wire.Evaluation.append_nil_left_eval Wire.Evaluation.append_cons_eval Wire.Evaluation.append_assoc_eval Wire.Evaluation.length_append_eval",
  "attribute [cbv_eval] Wire.Evaluation.map_nil_eval Wire.Evaluation.map_cons_eval Wire.Evaluation.map_append_eval",
  "attribute [cbv_eval] List.beq_cons_cons List.beq_nil_cons List.beq_cons_nil List.beq_nil_nil",
  "set_option linter.unusedSimpArgs false"]

private def poolNames (pools : List Pool) (suffix : String := "") : String :=
  String.intercalate " " ((List.range pools.length).map fun index => s!"pool{index}{suffix}")

private def generalizePools (pools : List Pool) : String :=
  String.intercalate "\n" ((List.range pools.length).map fun index => s!"  generalize pool{index} = data{index}")

private def poolLemmas (pools : List Pool) (suffix : String) : String :=
  String.join ((List.range pools.length).map fun index => s!", pool{index}{suffix}")

private def snapshotProof (pools : List Pool) (bytes : Bytes) (graph : Graph.State) (index : Nat) : String :=
  s!"def snapshot{index} : Bytes := {render pools bytes}
def normalized{index} : Graph.State := {render pools graph}
theorem snapshot{index}Encoded : Images.rawState.encode normalized{index} = snapshot{index} := by
  simp only [Images.rawState, Images.framed, Wire.Codec.enclosed,
    Images.frameBytes_encode, Codecs.rawState_encode, Codecs.graphBlob_encode,
    normalized{index}, snapshot{index}, Wire.NonemptyCodec.list, Wire.Codec.list,
    Wire.Codec.encodeMany, List.flatMap_cons, List.flatMap_nil,
    Wire.Codec.blob, Wire.Codec.sizedBytes_encode,
    List.append_nil, List.append_assoc, List.length_append, List.length_cons,
    List.length_nil{poolLemmas pools "Length"}]
{generalizePools pools}
  cbv
theorem snapshot{index}Valid : Images.rawState.valid normalized{index} = true := by decide_cbv
theorem snapshot{index}Read : Images.rawState.read snapshot{index} = some (normalized{index}, []) := by
  have exactRead := Images.rawState.readComplete normalized{index} [] snapshot{index}Valid
  simpa only [snapshot{index}Encoded, List.append_nil] using exactRead
@[cbv_eval] theorem snapshot{index}Decoded : Graph.Snapshot.decode snapshot{index} = some normalized{index} := by
  unfold Graph.Snapshot.decode
  rw [snapshot{index}Read]
  decide_cbv
@[cbv_eval] theorem snapshot{index}Map : List.map UInt8.toNat snapshot{index} = {numeralKey pools bytes} := by
  unfold snapshot{index}
  simp only [List.map_append, List.map_cons, List.map_nil{poolLemmas pools "Map"}]
  rfl
"

private def inputProof (pools : List Pool) (input : Protocol.Input) (bytes : Bytes) (index : Nat) : String :=
  let instanceData := match input.instanceData with
    | .initialArgs arguments => s!"(.initialArgs {render pools arguments})"
    | .state _ => s!"(.state snapshot{index})"
  let snapshot := match input.instanceData with | .state _ => s!" snapshot{index}" | _ => ""
  s!"def input{index} : Protocol.Input := ⟨{literal input.mode}, {literal input.image}, {instanceData}, {render pools input.control}⟩
def input{index}Bytes : Bytes := {render pools bytes}
theorem input{index}Valid : Protocol.inputCodec.valid input{index} = true := by
  unfold input{index}{snapshot} {poolNames pools}; decide +kernel
theorem input{index}Encoded : Protocol.inputCodec.encode input{index} = input{index}Bytes := by
  simp only [Protocol.inputCodec, Wire.Codec.checked, Images.rawInput, Images.framed,
    Wire.Codec.enclosed, Images.frameBytes_encode, Codecs.rawInput_encode, input{index}, input{index}Bytes{snapshot.replace " " ", "},
    Codecs.initialArgs_encode, Codecs.state_encode, Codecs.run_encode, Codecs.continueNone_encode,
    Codecs.continueSome_encode, Wire.Codec.blob, Wire.Codec.sizedBytes_encode,
    List.length_append, List.length_cons, List.length_nil, List.append_assoc{poolLemmas pools "Length"}]
{generalizePools pools}
  cbv
@[cbv_eval] theorem input{index}Decoded : Protocol.inputCodec.decode input{index}Bytes = some input{index} := by
  rw [← input{index}Encoded]
  exact Protocol.inputCodec.decode_encode _ input{index}Valid
attribute [cbv_opaque] input{index}Bytes Protocol.inputCodec
"

private def responseProof (entry : ProgramCache) (pools : List Pool) (input : Protocol.Input)
    (witness : Boundary.InvocationWitness) (index : Nat) : IO String := do
  let .state snapshot := input.instanceData | throw (IO.userError "expected saved state")
  let .continueValue (some bytes) := input.control | throw (IO.userError "expected response")
  let response ← required witness.incoming.response "missing response witness"
  let graph ← required (Graph.Snapshot.decode snapshot) "saved state candidate"
  let restored ← semantic (Boundary.restore entry.image graph witness.incoming.graph witness.incoming.clock) "restore candidate"
  let request ← semantic (Boundary.request entry.image.context.program graph snapshot) "request candidate"
  let result ← required (Images.rawResult.decode bytes) "result candidate"
  let (payloadType, resumeType) ← required (Protocol.requestDescriptors request) "descriptor candidate"
  let pending ← required graph.roots.pending "pending candidate"
  let some (.pending effect payload resume source) := graph.nodes[pending.value]? | throw (IO.userError "pending node candidate")
  let contract ← required entry.image.context.program.effects[effect.value]? "effect candidate"
  let occurrence ← required restored.pendingOccurrence "occurrence candidate"
  let prepared ← semantic (Boundary.prepare entry.image input witness.incoming) "prepared candidate"
  pure s!"def response{index}Bytes : Bytes := {render pools bytes}
def response{index}Value : Protocol.Result := {render pools result}
@[cbv_eval] theorem response{index}Decoded : Images.rawResult.decode {render pools bytes} = some response{index}Value := by decide +kernel
attribute [cbv_opaque] Images.rawResult
def restored{index} : Machine.State image.context.program := {stateLiteral pools restored}
theorem restored{index}Known : Boundary.restore image normalized{index} witness{index}.incoming.graph witness{index}.incoming.clock = .ok restored{index} := by cbv
def request{index} : Protocol.Request := {render pools request}
theorem request{index}Known : Boundary.request image.context.program normalized{index} snapshot{index} = .ok request{index} := by cbv
theorem descriptors{index}Known : Protocol.requestDescriptors request{index} = some ({render pools payloadType}, {render pools resumeType}) := by cbv
theorem payload{index}Accepted : Value.checkExternal (space := .target) {render pools payloadType.types} {literal payloadType.root} {render pools request.payload} {render pools response.descriptorPayload} = true := by decide_cbv
theorem request{index}Accepted : Protocol.checkRequest request{index} {render pools response.descriptorPayload} = true :=
  Protocol.checkRequest_of_descriptors _ _ _ _ descriptors{index}Known payload{index}Accepted
theorem result{index}Accepted : Protocol.checkResult request{index} response{index}Value {render pools response.descriptorPayload} {render pools response.descriptorResponse} = true :=
  Protocol.checkResult_of_parts _ _ _ _ _ _ request{index}Accepted (by decide_cbv) descriptors{index}Known (by decide_cbv)
def prepared{index}State : Machine.State image.context.program := {stateLiteral pools prepared.state}
theorem response{index}Step : Boundary.acceptResponse image normalized{index} snapshot{index} response{index}Bytes restored{index}
    {responseData pools response} = .ok ⟨prepared{index}State, {render pools prepared.events}⟩ := by
  apply Boundary.acceptResponse_of_parts (requestValue := request{index}) (resultValue := response{index}Value)
    (pending := {literal pending}) (resume := {literal resume}) (effect := {literal effect}) (payload := {render pools payload}) (source := {literal source})
    (contract := {render pools contract}) (occurrence := {literal occurrence})
  · exact request{index}Known
  · exact response{index}Decoded
  · exact result{index}Accepted
  all_goals cbv
def prepared{index} : Boundary.Prepared image.context.program := ⟨prepared{index}State, {render pools prepared.events}, false⟩
theorem state{index}Decoded : CertifiedState.decode image snapshot{index} witness{index}.incoming.graph = some normalized{index} :=
  CertifiedState.decode_complete _ _ _ _ snapshot{index}Decoded
    ((Graph.Admission.check_exact _ _ _ _).mp (by decide_cbv))
theorem prepared{index}Known : Boundary.prepare image input{index} witness{index}.incoming = .ok prepared{index} := by
  apply Boundary.prepare_state_response_of_parts (snapshot := snapshot{index}) (bytes := response{index}Bytes)
    (graph := normalized{index}) (state := restored{index})
    (response := {responseData pools response})
    (transition := ⟨prepared{index}State, {render pools prepared.events}⟩)
  · decide_cbv
  · rfl
  · rfl
  · rfl
  · exact state{index}Decoded
  · exact restored{index}Known
  · rfl
  · exact response{index}Step
"

private def proofConclusion (pools : List Pool) (count : Nat) (arguments : Bytes) : String := Id.run do
  let names := List.range count
  let aliases := String.intercalate "," (names.map fun i => s!"record{i}")
  let unfolds := String.intercalate " " (names.map fun i => s!"record{i} input{i}Bytes output{i}Bytes")
  let events := names.foldr (fun i rest => s!"(result{i}.events ++ {rest})") "[]"
  let meaning := names.foldr (fun i rest => s!"(.invocation rfl (Boundary.checkInvocation_sound _ _ _ _ _ checked{i}) {rest})") ".empty"
  return s!"def evaluationRecords : List Boundary.PublicInvocation := [{aliases}]
theorem exactRecords : [{aliases}] = records := by
  unfold {unfolds} {poolNames pools}; rfl
theorem evaluationRecords_exact : evaluationRecords = records := exactRecords
theorem certificate : Boundary.CertifiedInitialExecution imageBytes records := by
  rw [← exactRecords]
  refine ⟨_, image, {render pools arguments}, ⟨result{count - 1}.continuation, {events}⟩, by simp, ?_, rfl⟩
  exact {meaning}"

private def leafRules (entry : ProgramCache) : String := Id.run do
  let program := entry.image.context.program
  let schemas := (program.effects.flatMap (fun effect => [effect.payload, effect.result])).foldl
    (fun found schema => if found.contains schema then found else found ++ [schema]) []
  let mut declarations := []
  for schema in schemas do
    if let some shape := program.schemas[schema.value]? then
      if (SchemaAdmission.structuralChildren shape).isEmpty && (match shape with | .internal _ => false | _ => true) then
        declarations := declarations ++ [s!"@[cbv_eval] theorem leafDescriptor{schema.value} : SchemaDescriptor.canonicalize ⟨{literal schema}, {literal program.schemas}⟩ = some ⟨0, [{literal shape}]⟩ :=
  SchemaDescriptor.canonicalize_leaf _ _ (by decide_cbv) (by decide_cbv) (by decide) (by intro internal; intro impossible; cases impossible)"]
  return String.intercalate "\n" declarations

/-- Native states are proposals only. Each short fragment is checked against
the original dispatcher, then composed with its mandatory stopping check. -/
private def internalProof (entry : ProgramCache) (prepared : Boundary.Prepared entry.image.context.program)
    (count index : Nat) : IO String := do
  let mut state := prepared.state
  let mut remaining := count
  let mut sizes : List Nat := []
  let mut part := 0
  let mut declarations := [s!"def execution{index}State0 : Machine.State image.context.program := prepared{index}State"]
  while remaining > 0 do
    let size := min 8 remaining
    let transition ← semantic (Boundary.internalPrefix entry.image.context size state) "internal fragment candidate"
    declarations := declarations ++ [s!"def execution{index}State{part+1} : Machine.State image.context.program := {stateLiteral [] transition.state}
def execution{index}Part{part} : Machine.Transition image.context.program := ⟨execution{index}State{part+1}, {render [] transition.events}⟩
theorem execution{index}Part{part}Known : Boundary.internalPrefix image.context {size} execution{index}State{part} = .ok execution{index}Part{part} := by cbv"]
    sizes := sizes ++ [size]
    state := transition.state
    remaining := remaining - size
    part := part + 1
  declarations := declarations ++ [s!"def execution{index}Suffix{part} : Machine.Transition image.context.program := ⟨execution{index}State{part}, []⟩
theorem execution{index}Suffix{part}Known : Boundary.completeInternal image.context 0 execution{index}State{part} = .ok execution{index}Suffix{part} := by cbv"]
  let mut rest := 0
  for (size, ordinal) in sizes.zipIdx.reverse do
    declarations := declarations ++ [s!"def execution{index}Suffix{ordinal} : Machine.Transition image.context.program := ⟨execution{index}Suffix{ordinal+1}.state, execution{index}Part{ordinal}.events ++ execution{index}Suffix{ordinal+1}.events⟩
theorem execution{index}Suffix{ordinal}Known : Boundary.completeInternal image.context {size+rest} execution{index}State{ordinal} = .ok execution{index}Suffix{ordinal} := Boundary.completeInternal_prepend _ {size} {rest} _ _ _ execution{index}Part{ordinal}Known execution{index}Suffix{ordinal+1}Known"]
    rest := rest + size
  return String.intercalate "\n" declarations

private def plainProof (entry : ProgramCache) (records : List Boundary.PublicInvocation)
    (witnesses : List Boundary.InvocationWitness) (arguments : Bytes) : IO String := do
  let mut declarations := [leafRules entry]
  let mut before : Boundary.Clock := ⟨0, none⟩
  for ((record, witness), index) in (records.zip witnesses).zipIdx do
    let input ← required (Protocol.inputCodec.decode record.input) "composed input"
    let result ← required (Boundary.checkInvocation entry.image record before witness) "composed record"
    declarations := declarations ++ [s!"def input{index}Bytes : Bytes := {literal record.input}
def output{index}Bytes : Bytes := {literal record.output}
def record{index} : Boundary.PublicInvocation := ⟨input{index}Bytes, output{index}Bytes⟩
def witness{index} : Boundary.InvocationWitness := {witnessLiteral witness}
def result{index} : Boundary.InvocationResult := {resultLiteral [] result}"]
    if input.mode == .run then
      let prepared ← semantic (Boundary.prepare entry.image input witness.incoming) "composed preparation"
      let transition ← semantic (Boundary.completeInternal entry.image.context witness.internalSteps prepared.state) "composed run"
      let outcome ← semantic (Boundary.finish entry.image transition.state witness.outgoing) "composed finish"
      declarations := declarations ++ [s!"def input{index} : Protocol.Input := ⟨{literal input.mode}, imageBytes, {render [] input.instanceData}, {render [] input.control}⟩
theorem input{index}Valid : Protocol.inputCodec.valid input{index} = true := by decide +kernel
theorem input{index}Encoded : Protocol.inputCodec.encode input{index} = input{index}Bytes := by cbv
theorem input{index}Decoded : Protocol.inputCodec.decode input{index}Bytes = some input{index} := by
  rw [← input{index}Encoded]; exact Protocol.inputCodec.decode_encode _ input{index}Valid
def prepared{index}State : Machine.State image.context.program := {stateLiteral [] prepared.state}
def prepared{index} : Boundary.Prepared image.context.program := ⟨prepared{index}State, {render [] prepared.events}, {literal prepared.parked}⟩
theorem prepared{index}Known : Boundary.prepare image input{index} witness{index}.incoming = .ok prepared{index} := by cbv",
        ← internalProof entry prepared witness.internalSteps index,
        s!"def outcome{index} : Protocol.Outcome := {render [] outcome}
theorem finished{index} : Boundary.finish image execution{index}Suffix0.state witness{index}.outgoing = .ok outcome{index} := by cbv
theorem valid{index} : Protocol.outcomeCodec.valid outcome{index} = true := by decide_cbv
def observation{index} : Boundary.Observation image.context.program := ⟨execution{index}Suffix0.state, prepared{index}.events ++ execution{index}Suffix0.events, outcome{index}⟩
theorem observed{index} : Boundary.observe image input{index} witness{index} = .ok observation{index} :=
  Boundary.run_of_parts _ _ _ _ _ _ _ _ rfl prepared{index}Known execution{index}Suffix0Known finished{index} valid{index}
theorem encoded{index} : Protocol.outcomeCodec.encode outcome{index} = output{index}Bytes := by cbv
theorem checked{index} : Boundary.checkInvocation image record{index} {literal before} witness{index} = some result{index} :=
  Boundary.checkInvocation_of_parts _ _ _ _ _ _ rfl input{index}Decoded observed{index} encoded{index}"]
    else
      declarations := declarations ++ [s!"theorem checked{index} : Boundary.checkInvocation image record{index} {literal before} witness{index} = some result{index} := by cbv"]
    before := result.clock
  return String.intercalate "\n" (declarations ++ [proofConclusion [] records.length arguments])

/-- Emit ordinary compositional proofs of the original checker, using only
native candidate data. Every computation and the complete subject are checked. -/
def composedProof (entry : ProgramCache) (records : List Boundary.PublicInvocation)
    (witnesses : List Boundary.InvocationWitness) (hashInputs : List Bytes) (arguments : Bytes) : IO String := do
  let pools := (records.flatMap fun record => poolsIn record.input ++ poolsIn record.output).foldl
    (fun found pool => if found.contains pool then found else found ++ [pool]) []
  if pools.isEmpty then return ← plainProof entry records witnesses arguments
  let mut declarations := [evaluationRules, leafRules entry]
  for (pool, index) in pools.zipIdx do
    declarations := declarations ++ [s!"def pool{index} : Bytes := List.replicate {pool.count} {pool.byte.toNat}
def pool{index}Nat : List Nat := List.replicate {pool.count} {pool.byte.toNat}
@[cbv_eval] theorem pool{index}Length : pool{index}.length = {pool.count} := List.length_replicate
@[cbv_eval] theorem pool{index}Map : List.map UInt8.toNat pool{index} = pool{index}Nat := by
  unfold pool{index} pool{index}Nat; rw [List.map_replicate]; rfl
attribute [irreducible] pool{index}
attribute [cbv_opaque] pool{index} pool{index}Nat"]
  for (bytes, index) in hashInputs.zipIdx do
    if !(poolsIn bytes).isEmpty then
      declarations := declarations ++ [s!"@[cbv_eval] theorem sharedHash{index} : SHA256.hashNumerals {numeralKey pools bytes} = ({literal (SHA256.hash bytes).toList.toArray}).toVector := by
  unfold {poolNames pools "Nat"}; exact hash{index}"]
  let mut before : Boundary.Clock := ⟨0, none⟩
  for ((record, witness), index) in (records.zip witnesses).zipIdx do
    let input ← required (Protocol.inputCodec.decode record.input) "composed input"
    let result ← required (Boundary.checkInvocation entry.image record before witness) "composed result"
    match input.instanceData with
    | .state snapshot =>
      let graph ← required (Graph.Snapshot.decode snapshot) "composed snapshot"
      declarations := declarations ++ [snapshotProof pools snapshot graph index]
    | _ => pure ()
    declarations := declarations ++ [inputProof pools input record.input index,
      s!"def output{index}Bytes : Bytes := {render pools record.output}",
      s!"def record{index} : Boundary.PublicInvocation := ⟨input{index}Bytes, output{index}Bytes⟩",
      s!"def witness{index} : Boundary.InvocationWitness := {shared pools (witnessLiteral witness)}"]
    match input.instanceData with
    | .state _ => declarations := declarations ++ [s!"attribute [cbv_opaque] snapshot{index} Graph.Snapshot.decode"]
    | _ => pure ()
    if input.mode == .run && (match input.instanceData, input.control with | .state _, .continueValue (some _) => true | _, _ => false) then
      declarations := declarations ++ [← responseProof entry pools input witness index]
      let prepared ← semantic (Boundary.prepare entry.image input witness.incoming) "composed preparation"
      let transition ← semantic (Boundary.completeInternal entry.image.context witness.internalSteps prepared.state) "composed run"
      let outcome ← semantic (Boundary.finish entry.image transition.state witness.outgoing) "composed finish"
      declarations := declarations ++ [s!"def final{index}State : Machine.State image.context.program := {stateLiteral pools transition.state}
def transition{index} : Machine.Transition image.context.program := ⟨final{index}State, {render pools transition.events}⟩
def outcome{index} : Protocol.Outcome := {render pools outcome}
theorem ran{index} : Boundary.completeInternal image.context witness{index}.internalSteps prepared{index}State = .ok transition{index} := by cbv
theorem finished{index} : Boundary.finish image final{index}State witness{index}.outgoing = .ok outcome{index} := by cbv
theorem valid{index} : Protocol.outcomeCodec.valid outcome{index} = true := by decide_cbv
def observation{index} : Boundary.Observation image.context.program := ⟨final{index}State, prepared{index}.events ++ transition{index}.events, outcome{index}⟩
theorem observed{index} : Boundary.observe image input{index} witness{index} = .ok observation{index} :=
  Boundary.run_of_parts _ _ _ _ _ _ _ _ rfl prepared{index}Known ran{index} finished{index} valid{index}
theorem encoded{index} : Protocol.outcomeCodec.encode outcome{index} = output{index}Bytes := by cbv
def result{index} : Boundary.InvocationResult := ⟨input{index}.instanceData, Boundary.nextInstance outcome{index}, Boundary.clock final{index}State, observation{index}.events, Boundary.terminalOutcome outcome{index}⟩
theorem checked{index} : Boundary.checkInvocation image record{index} {literal before} witness{index} = some result{index} :=
  Boundary.checkInvocation_of_parts _ _ _ _ _ _ rfl input{index}Decoded observed{index} encoded{index}"]
    else
      declarations := declarations ++ [s!"def result{index} : Boundary.InvocationResult := {resultLiteral pools result}
theorem checked{index} : Boundary.checkInvocation image record{index} {literal before} witness{index} = some result{index} := by cbv"]
    before := result.clock
  declarations := declarations ++ [proofConclusion pools records.length arguments]
  return String.intercalate "\n" declarations

end BoundaryV2.Tooling.ExecutionProof
