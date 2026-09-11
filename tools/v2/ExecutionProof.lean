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

private def stateWithNodes (pools : List Pool) (nodes : String) (state : Machine.State program) : String :=
  let blobs := String.intercalate "," (state.store.blobs.map (fun blob => shared pools (storedLiteral blob)))
  s!"{leftBrace} identity := {render pools state.identity}, store := {leftBrace} nodes := {nodes}, blobs := [{blobs}] {rightBrace}, status := {render pools state.status}, roots := {render pools state.roots}, result := {render pools state.result}, nextOccurrence := {state.nextOccurrence}, pendingOccurrence := {render pools state.pendingOccurrence} {rightBrace}"

private def stateLiteral (pools : List Pool) (state : Machine.State program) : String :=
  stateWithNodes pools (render pools state.store.nodes) state

/-- Fixed emitter separator; the driver inventories every resulting module. -/
def moduleBreak : String := "\n-- boundary-execution-module-break\n"

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

/-- Candidate lookup inventory, bounded by the finite graph. It has no proof
authority: each lookup and the original dispatcher are checked in Lean. -/
private def reachableNodes (state : Machine.State program) : IO (List (NodeId × Graph.Node)) := do
  let mut pending := (Graph.rootEdges state.roots).map Graph.Edge.target
  let mut found : List (NodeId × Graph.Node) := []
  while !pending.isEmpty do
    let some reference := pending.head? | break
    pending := pending.drop 1
    if found.any (fun item => item.1 == reference) then continue
    let node ← required (state.store.lookup reference) "shared lookup candidate"
    found := found ++ [(reference, node)]
    pending := pending ++ (Graph.nodeEdges node).map Graph.Edge.target
  return found

/-- Select sharing only where each fragment reads the most recent append and
the final boundary needs no graph serialization. Other traces retain literal
states. This is a presentation choice, never a semantic acceptance check. -/
private def canShareNodes (entry : ProgramCache) (initial : Machine.State entry.image.context.program)
    (count : Nat) : IO Bool := do
  if count ≤ 128 then return false
  let mut state := initial
  let mut remaining := count
  let mut previousLength := 0
  while remaining > 0 do
    let reachable? ← try pure (some (← reachableNodes state)) catch _ => pure none
    let some reachable := reachable? | return false
    if reachable.any (fun item => item.1.value < previousLength) then return false
    let size := min 8 remaining
    let transition ← semantic (Boundary.internalPrefix entry.image.context size state) "sharing candidate"
    let length := state.store.nodes.length
    if !(decide (transition.state.store.nodes.take length = state.store.nodes)) then return false
    previousLength := length
    state := transition.state
    remaining := remaining - size
  return state.result.isSome

private def sharingRules (index : Nat) : String := String.intercalate "\n" [
  s!"@[cbv_eval] theorem executionGetAppend{index} (left right : List α) (offset : Nat) :
    (List.append left right).get?Internal offset =
      if offset < left.length then left.get?Internal offset else right.get?Internal (offset - left.length) :=
  List.getElem?_append
@[cbv_eval] theorem executionGetNil{index} (offset : Nat) : ([] : List α).get?Internal offset = none := by
  cases offset <;> rfl
@[cbv_eval] theorem executionGetConsZero{index} (head : α) (tail : List α) :
    (head :: tail).get?Internal 0 = some head := rfl
@[cbv_eval] theorem executionGetConsSucc{index} (head : α) (tail : List α) (offset : Nat) :
    (head :: tail).get?Internal (offset + 1) = tail.get?Internal offset := rfl",
  "attribute [cbv_eval] Wire.Evaluation.length_append_eval List.length_nil List.length_cons Wire.Evaluation.append_assoc_eval Wire.Evaluation.append_nil_eval Wire.Evaluation.append_nil_left_eval Wire.Evaluation.append_cons_eval",
  "attribute [cbv_opaque] List.append List.get?Internal List.length"]

/-- Native states are proposals only. Each short fragment is checked against
the original dispatcher, then composed with its mandatory stopping check.
Module boundaries limit elaborator memory; shared appends avoid copying every
historical heap into every proof fragment. -/
private def internalProof (entry : ProgramCache) (prepared : Boundary.Prepared entry.image.context.program)
    (count index : Nat) (shareNodes : Bool) : IO String := do
  let mut state := prepared.state
  let mut remaining := count
  let mut sizes : List Nat := []
  let mut part := 0
  let nodes := s!"execution{index}Nodes"
  let mut declarations := if shareNodes then [sharingRules index,
    s!"def {nodes}0 : List Graph.Node := {render [] state.store.nodes}
attribute [cbv_opaque] {nodes}0
@[cbv_eval] theorem {nodes}0Length : {nodes}0.length = {state.store.nodes.length} := by decide +kernel
def execution{index}State0 : Machine.State image.context.program := {stateWithNodes [] s!"{nodes}0" state}"]
    else [s!"def execution{index}State0 : Machine.State image.context.program := {stateLiteral [] state}"]
  while remaining > 0 do
    let size := min 8 remaining
    if shareNodes then
      for (reference, node) in ← reachableNodes state do
        let proof := if part == 0 then s!"by unfold {nodes}0; decide_cbv"
          else s!"by\n  unfold {nodes}{part}\n  exact (executionGetAppend{index} _ _ _).trans (by rw [{nodes}{part-1}Length]; cbv)"
        declarations := declarations ++ [s!"@[cbv_eval] theorem execution{index}Lookup{part}At{reference.value} : {nodes}{part}.get?Internal {reference.value} = some {render [] node} := {proof}"]
    let transition ← semantic (Boundary.internalPrefix entry.image.context size state) "internal fragment candidate"
    if shareNodes then
      let added := render [] (transition.state.store.nodes.drop state.store.nodes.length)
      declarations := declarations ++ [s!"def {nodes}{part+1} : List Graph.Node := {nodes}{part} ++ {added}
attribute [cbv_opaque] {nodes}{part+1}
@[cbv_eval] theorem {nodes}{part+1}Length : {nodes}{part+1}.length = {transition.state.store.nodes.length} := by
  rw [{nodes}{part+1}, List.length_append, {nodes}{part}Length]
  decide +kernel
@[cbv_eval] theorem {nodes}{part+1}Added : {nodes}{part} ++ {added} = {nodes}{part+1} := rfl"]
    let nextState := if shareNodes then stateWithNodes [] s!"{nodes}{part+1}" transition.state
      else stateLiteral [] transition.state
    declarations := declarations ++ [s!"def execution{index}State{part+1} : Machine.State image.context.program := {nextState}
def execution{index}Part{part} : Machine.Transition image.context.program := ⟨execution{index}State{part+1}, {render [] transition.events}⟩
theorem execution{index}Part{part}Known : Boundary.internalPrefix image.context {size} execution{index}State{part} = .ok execution{index}Part{part} := by cbv"]
    sizes := sizes ++ [size]
    state := transition.state
    remaining := remaining - size
    part := part + 1
    if part % 32 == 0 then declarations := declarations ++ [moduleBreak]
  declarations := declarations ++ [s!"def execution{index}Suffix{part} : Machine.Transition image.context.program := ⟨execution{index}State{part}, []⟩
theorem execution{index}Suffix{part}Known : Boundary.completeInternal image.context 0 execution{index}State{part} = .ok execution{index}Suffix{part} := by cbv"]
  let mut rest := 0
  for (size, ordinal) in sizes.zipIdx.reverse do
    declarations := declarations ++ [s!"def execution{index}Suffix{ordinal} : Machine.Transition image.context.program := ⟨execution{index}Suffix{ordinal+1}.state, execution{index}Part{ordinal}.events ++ execution{index}Suffix{ordinal+1}.events⟩
theorem execution{index}Suffix{ordinal}Known : Boundary.completeInternal image.context {size+rest} execution{index}State{ordinal} = .ok execution{index}Suffix{ordinal} := Boundary.completeInternal_prepend _ {size} {rest} _ _ _ execution{index}Part{ordinal}Known execution{index}Suffix{ordinal+1}Known"]
    rest := rest + size
  return String.intercalate "\n" declarations

private def finishProof (entry : ProgramCache) (state : Machine.State entry.image.context.program)
    (witness : Graph.Admission.Witness) (outcome : Protocol.Outcome) (stateName : String)
    (index : Nat) : IO String := do
  let stem := s!"finish{index}"
  let mut declarations := [s!"theorem {stem}Identity : ({stateName}.identity == image.identity) = true := by cbv
theorem {stem}Clock : (Boundary.clock {stateName}).valid {stateName}.status = true := by decide +kernel"]
  if let some result := state.result then
    declarations := declarations ++ [s!"theorem {stem}Terminal : Boundary.terminal image.context.program {render [] result} = .ok outcome{index} := by cbv
theorem finished{index} : Boundary.finish image execution{index}Suffix0.state witness{index}.outgoing = .ok outcome{index} :=
  Boundary.finish_terminal_of_parts image {stateName} witness{index}.outgoing {render [] result} outcome{index}
    {stem}Identity {stem}Clock rfl {stem}Terminal"]
    return String.intercalate "\n" declarations
  let graph ← required (Graph.Snapshot.canonicalize state.raw) "finish graph candidate"
  let bytes := Images.rawState.encode graph
  declarations := declarations ++ [s!"def {stem}Graph : Graph.State := {render [] graph}
def {stem}Bytes : Bytes := {render [] bytes}
theorem {stem}Canonical : Graph.Snapshot.canonicalize {stateName}.raw = some {stem}Graph := by first | decide +kernel | cbv
theorem {stem}Raw : Images.rawState.valid {stem}Graph = true := by first | decide +kernel | decide_cbv
theorem {stem}Position : Graph.Admission.positionValidWithIdentity image.context.program image.identity {stem}Graph = true := by
  have identity : image.identity = {stem}Graph.programIdentity := by cbv
  rw [identity]
  first | decide +kernel | decide_cbv
theorem {stem}Records : Graph.Admission.recordsValid image.context.program {stem}Graph = true := by first | decide +kernel | decide_cbv
theorem {stem}Captures : Graph.Admission.captureRecordsValid image.context.program {stem}Graph = true := by first | decide +kernel | decide_cbv
theorem {stem}Effects : Graph.Admission.effectsValid image.context.program {stem}Graph = true := by first | decide +kernel | decide_cbv
theorem {stem}Uses : (Graph.Admission.directUses {stem}Graph).any (Graph.Admission.usesValid {stem}Graph) = true := by first | decide +kernel | decide_cbv
theorem {stem}Future : Graph.Admission.futureScopesValid image.context.program {stem}Graph programWitness.borrows witness{index}.outgoing.projections = true := by decide_cbv"]
  let mut blobNames := []
  for ((raw, meaning), ordinal) in (graph.blobs.zip witness.blobs).zipIdx do
    let stored ← required (state.store.blobs.findIdx? (fun blob => blob.raw == raw)) "finish blob candidate"
    let name := s!"{stem}Blob{ordinal}"
    blobNames := blobNames ++ [name]
    declarations := declarations ++ [s!"def {name} : Graph.Blob × Profile.Value .target := ⟨{render [] raw}, {render [] meaning}⟩
theorem {name}Known : Profile.Value.checkExternal image.context.program.schemas {name}.1.schema {name}.1.bytes {name}.2 = true :=
  ({stateName}.store.blobs[{stored}]'(by decide +kernel)).checked"]
  let blobRows := String.intercalate "," blobNames
  let allBlobs := blobNames.foldr (fun name rest => s!"Borrow.all_cons_checked _ _ _ {name}Known ({rest})") "rfl"
  declarations := declarations ++ [s!"theorem {stem}Blobs : Graph.Admission.blobsValid image.context.program {stem}Graph witness{index}.outgoing.blobs = true := by
  unfold Graph.Admission.blobsValid
  simp only [Bool.and_eq_true]
  refine ⟨by decide +kernel, ?_⟩
  exact Borrow.all_of_exact_list _ _ [{blobRows}] rfl ({allBlobs})
theorem {stem}Admitted : Graph.Admission.check image.context.program programWitness.borrows {stem}Graph witness{index}.outgoing = true := by
  unfold Graph.Admission.check Graph.Admission.checkWithFacts
  simp only [Bool.and_eq_true, and_assoc]
  exact ⟨{stem}Position, {stem}Records, {stem}Captures, {stem}Effects, {stem}Blobs, {stem}Uses, {stem}Future⟩
theorem {stem}Encoded : Images.rawState.encode {stem}Graph = {stem}Bytes := by decide +kernel"]
  let common := s!"image {stateName} witness{index}.outgoing {stem}Graph {stem}Bytes"
  let proofs := s!"{stem}Identity {stem}Clock rfl {stem}Canonical {stem}Raw {stem}Admitted"
  let body ← match state.status with
    | .yielded => pure s!"Boundary.finish_yielded_of_parts {common} {proofs} rfl {stem}Encoded"
    | .active | .unwinding =>
      let selected := if state.status == .active then "Or.inl rfl" else "Or.inr rfl"
      pure s!"Boundary.finish_progressed_of_parts {common} {proofs} ({selected}) {stem}Encoded"
    | .parked => do
      let pending ← semantic (Boundary.request entry.image.context.program graph bytes) "finish request candidate"
      let .requested _ requestBytes := outcome | throw (IO.userError "finish request outcome candidate")
      declarations := declarations ++ [s!"def {stem}Request : Protocol.Request := {render [] pending}
theorem {stem}Requested : Boundary.request image.context.program {stem}Graph {stem}Bytes = .ok {stem}Request := by cbv
theorem {stem}RequestValid : (Images.rawRequest.valid {stem}Request && Protocol.requestHeaderValid {stem}Request) = true := by cbv
theorem {stem}RequestEncoded : Images.rawRequest.encode {stem}Request = {render [] requestBytes} := by decide +kernel"]
      pure s!"by
  have checked := Boundary.finish_requested_of_parts {common} {stem}Request {proofs} rfl {stem}Encoded {stem}Requested {stem}RequestValid
  rw [{stem}RequestEncoded] at checked
  exact checked"
  declarations := declarations ++ [s!"theorem finished{index} : Boundary.finish image execution{index}Suffix0.state witness{index}.outgoing = .ok outcome{index} := {body}"]
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
      let shareNodes ← canShareNodes entry prepared.state witness.internalSteps
      let initialUnfold := if shareNodes then s!" execution{index}Nodes0" else ""
      declarations := declarations ++ [s!"def input{index} : Protocol.Input := ⟨{literal input.mode}, imageBytes, {render [] input.instanceData}, {render [] input.control}⟩
theorem input{index}Valid : Protocol.inputCodec.valid input{index} = true := by decide +kernel
theorem input{index}Encoded : Protocol.inputCodec.encode input{index} = input{index}Bytes := by cbv
theorem input{index}Decoded : Protocol.inputCodec.decode input{index}Bytes = some input{index} := by
  rw [← input{index}Encoded]; exact Protocol.inputCodec.decode_encode _ input{index}Valid",
        ← internalProof entry prepared witness.internalSteps index shareNodes,
        s!"def prepared{index}State : Machine.State image.context.program := execution{index}State0
def prepared{index} : Boundary.Prepared image.context.program := ⟨prepared{index}State, {render [] prepared.events}, {literal prepared.parked}⟩
theorem prepared{index}Known : Boundary.prepare image input{index} witness{index}.incoming = .ok prepared{index} := by
  unfold prepared{index} prepared{index}State execution{index}State0{initialUnfold}; cbv
def outcome{index} : Protocol.Outcome := {render [] outcome}",
        ← finishProof entry transition.state witness.outgoing outcome s!"execution{index}State{(witness.internalSteps + 7) / 8}" index,
        s!"
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
    declarations := declarations ++ [moduleBreak]
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
    declarations := declarations ++ [moduleBreak]
  declarations := declarations ++ [proofConclusion pools records.length arguments]
  return String.intercalate "\n" declarations

end BoundaryV2.Tooling.ExecutionProof
