import Lean
import BoundaryV2

/- Verification tooling only. No semantic module may depend on this module.
   Read private declaration bodies, not printed names or cached axiom reports. -/
open Lean

namespace BoundaryTrust

structure ModuleEntry where
  name : String
  kind : String
  sha256 : String
  deriving FromJson, ToJson

structure InvocationClaim where
  input : Array Nat
  output : Array Nat
  deriving FromJson, ToJson

structure RefusalClaim where
  backend : String
  input : Array Nat
  output : Array Nat
  diagnostic : Array Nat
  inputAfter : Array Nat
  status : Nat
  deriving FromJson, ToJson

structure CapacityFollowupClaim where
  invocation : InvocationClaim
  inputAfter : Array Nat
  prepareStatus : Nat
  executeStatus : Nat
  deriving FromJson, ToJson

structure CapacityClaim where
  input : Array Nat
  output : Array Nat
  callerInputAfter : Array Nat
  guestInputAfter : Option (Array Nat)
  prepareStatus : Nat
  executeStatus : Option Nat
  retry : InvocationClaim
  retryInputAfter : Array Nat
  retryPrepareStatus : Nat
  retryExecuteStatus : Nat
  followups : Array CapacityFollowupClaim
  deriving FromJson, ToJson

structure Claim where
  name : String
  kind : String
  source : Array Nat := #[]
  image : Array Nat
  records : Array InvocationClaim := #[]
  record : Option RefusalClaim := none
  capacity : Option CapacityClaim := none
  deriving ToJson

instance : FromJson Claim where
  fromJson? json := do
    let name ← json.getObjValAs? String "name"
    let kind ← json.getObjValAs? String "kind"
    let image ← json.getObjValAs? (Array Nat) "image"
    let source ← match json.getObjVal? "source" with
      | .ok value => fromJson? value
      | .error _ => pure #[]
    let records ← match json.getObjVal? "records" with
      | .ok value => fromJson? value
      | .error _ => pure #[]
    let record ← match json.getObjVal? "record" with
      | .ok value => fromJson? value
      | .error _ => pure none
    let capacity ← match json.getObjVal? "capacity" with
      | .ok value => fromJson? value
      | .error _ => pure none
    pure ⟨name, kind, source, image, records, record, capacity⟩

structure Inventory where
  format : String
  modules : Array ModuleEntry
  roots : Array String
  claims : Array Claim := #[]
  deriving FromJson

def allowedAxioms : List Name :=
  ["propext", "Quot.sound", "Classical.choice"].map String.toName

def reject (code detail : String) : IO α :=
  throw <| IO.userError (code ++ ": " ++ detail)

def moduleOf (env : Environment) (name : Name) : IO String := do
  let some index := env.getModuleIdxFor? name
    | reject "trust.unknown_provenance" name.toString
  -- moduleNames maps this whole array; dependency walks need one entry.
  let some imported := env.header.modules[index.toNat]?
    | reject "trust.unknown_provenance" name.toString
  return imported.module.toString

theorem module_name_lookup_exact (header : EnvironmentHeader) (index : Nat) :
    header.moduleNames[index]? = (header.modules[index]?).map (·.module) := by
  simp [EnvironmentHeader.moduleNames]

def dependencies (ci : ConstantInfo) : Array Name := Id.run do
  let mut result := ci.type.getUsedConstants
  if let some value := ci.value? (allowOpaque := true) then
    result := result ++ value.getUsedConstants
  if let .inductInfo value := ci then
    result := result ++ value.ctors.toArray
  return result

def isProof (env : Environment) (ci : ConstantInfo) : IO Bool :=
  PPContext.runMetaM { env := env, mctx := {}, lctx := {}, opts := {} }
    (Meta.isProp ci.type)

/-- The pinned compiler gives recursive definitions an executable companion.
It is never a logical definition: its safe parent supplies the meaning, and
every logical dependency closure below rejects an edge into unsafe code. -/
def executableHelper (env : Environment) (ci : ConstantInfo) : IO (Option Name) := do
  -- addAndCompilePartialRec in the pinned elaborator marks these companions
  -- partial. A handwritten unsafe declaration may copy the suffix and type.
  if !ci.isPartial then return none
  let some parent := Compiler.isUnsafeRecName? ci.name | return none
  let some (.defnInfo original) := env.find? parent | return none
  if original.safety != .safe then return none
  let sameType ← PPContext.runMetaM { env := env, mctx := {}, lctx := {}, opts := {} }
    (Meta.isDefEq ci.type original.type)
  return if sameType then some parent else none

/-- Each traversal has its own visited set: cycles cannot hide an axiom through
an incomplete memoized dependency summary. Missing constants are hard errors. -/
def axiomClosure (env : Environment) (root : Name)
    (edges : IO.Ref (NameMap (Array Name))) (toolModules : Array String) (logical := true) : IO (Array String) := do
  let mut pending := #[root]
  let mut visited : NameSet := {}
  let mut axioms : NameSet := {}
  while !pending.isEmpty do
    let name := pending.back!
    pending := pending.pop
    if visited.contains name then continue
    visited := visited.insert name
    let some ci := env.find? name
      | reject "trust.missing_dependency" s!"{root}: {name}"
    if logical && (ci.isUnsafe || ci.isPartial) then
      reject "trust.unsafe_dependency" s!"{root}: {name}"
    let owner ← moduleOf env name
    if toolModules.contains owner then
      reject "trust.semantic_tool_dependency" s!"{root}: {name} ({owner})"
    if let .axiomInfo _ := ci then
      if !allowedAxioms.contains name then
        reject "trust.forbidden_axiom" s!"{root}: {name}"
      axioms := axioms.insert name
    -- Cache only direct edges extracted from this immutable environment. Every
    -- root still has its own visited set and checks each reachable declaration.
    let direct ← match (← edges.get).find? name with
      | some direct => pure direct
      | none => do
        let direct := dependencies ci
        edges.modify (·.insert name direct)
        pure direct
    pending := pending ++ direct
  return (axioms.toArray.qsort Name.lt).map Name.toString

def inspectDeclaration (env : Environment) (entry : ModuleEntry)
    (ci : ConstantInfo) (tools : Array String) (edges : IO.Ref (NameMap (Array Name))) : IO Json := do
  if ci.type.hasSorry || (ci.value? (allowOpaque := true)).any Expr.hasSorry then
    reject "trust.placeholder" s!"{entry.name}: {ci.name}"
  if let .axiomInfo _ := ci then
    reject "trust.project_axiom" s!"{entry.name}: {ci.name}"
  let proof ← isProof env ci
  let helper ← executableHelper env ci
  if entry.kind != "tooling" then
    if (ci.isUnsafe || ci.isPartial) && helper.isNone then
      reject "trust.unsafe_semantics" s!"{entry.name}: {ci.name}"
    if let .opaqueInfo _ := ci then
      if !proof then reject "trust.opaque_semantics" s!"{entry.name}: {ci.name}"
  let axioms ← if entry.kind != "tooling" || proof then
      axiomClosure env ci.name edges (if entry.kind == "tooling" then #[] else tools) helper.isNone
    else pure #[]
  return Json.mkObj [
    ("name", toJson ci.name.toString), ("module", toJson entry.name),
    ("proof", toJson proof), ("axioms", toJson axioms),
    ("executable_helper_for", toJson (helper.map Name.toString))]

def byteExpression (bytes : Array Nat) : IO Expr := do
  if bytes.any (· ≥ 256) then reject "trust.claim_bytes" "non-byte subject"
  let values := bytes.map fun value => mkApp (mkConst ``UInt8.ofNat) (mkNatLit value)
  return values.toList.foldr
    (fun head tail => mkApp3 (mkConst ``List.cons [.zero]) (mkConst ``UInt8) head tail)
    (mkApp (mkConst ``List.nil [.zero]) (mkConst ``UInt8))

def refusalExpression (record : RefusalClaim) : IO Expr := do
  let backend ← match record.backend with
    | "native" => pure (mkConst ``BoundaryV2.Profile.Target.Boundary.Backend.native)
    | "wasm" => pure (mkConst ``BoundaryV2.Profile.Target.Boundary.Backend.wasm)
    | _ => reject "trust.claim_fields" "unknown refusal backend"
  return mkAppN (mkConst ``BoundaryV2.Profile.Target.Boundary.RefusalRecord.mk) #[
    backend, ← byteExpression record.input, ← byteExpression record.output,
    ← byteExpression record.diagnostic, ← byteExpression record.inputAfter, mkNatLit record.status]

def optionExpression (type : Expr) (value : Option Expr) : Expr :=
  match value with
  | none => mkApp (mkConst ``Option.none [.zero]) type
  | some value => mkApp2 (mkConst ``Option.some [.zero]) type value

def capacityExpression (record : CapacityClaim) : IO Expr := do
  let byteList := mkApp (mkConst ``List [.zero]) (mkConst ``UInt8)
  let guest ← record.guestInputAfter.mapM byteExpression
  let retry := mkApp2 (mkConst ``BoundaryV2.Profile.Target.Boundary.PublicInvocation.mk)
    (← byteExpression record.retry.input) (← byteExpression record.retry.output)
  let followups ← record.followups.mapM fun next => do
    let invocation := mkApp2 (mkConst ``BoundaryV2.Profile.Target.Boundary.PublicInvocation.mk)
      (← byteExpression next.invocation.input) (← byteExpression next.invocation.output)
    pure (mkAppN (mkConst ``BoundaryV2.Profile.Target.Boundary.CapacityFollowup.mk) #[
      invocation, ← byteExpression next.inputAfter, mkNatLit next.prepareStatus, mkNatLit next.executeStatus])
  let followupType := mkConst ``BoundaryV2.Profile.Target.Boundary.CapacityFollowup
  let followups := followups.toList.foldr (fun head tail =>
    mkApp3 (mkConst ``List.cons [.zero]) followupType head tail)
    (mkApp (mkConst ``List.nil [.zero]) followupType)
  return mkAppN (mkConst ``BoundaryV2.Profile.Target.Boundary.CapacityRecord.mk) #[
    ← byteExpression record.input, ← byteExpression record.output, ← byteExpression record.callerInputAfter,
    optionExpression byteList guest, mkNatLit record.prepareStatus,
    optionExpression (mkConst ``Nat) (record.executeStatus.map mkNatLit), retry,
    ← byteExpression record.retryInputAfter, mkNatLit record.retryPrepareStatus, mkNatLit record.retryExecuteStatus,
    followups]

/-- Compare the captured data constructors without backtracking through an
entire list when its last byte differs. This is an early rejection check only;
success still requires the complete kernel type comparison below. -/
def capturedSubjectsMatch (env : Environment) (actual expected : Expr) : IO Bool := do
  if actual.getAppFn != expected.getAppFn || actual.getAppNumArgs != expected.getAppNumArgs then return true
  let mut pending := actual.getAppArgs.zip expected.getAppArgs
  let constructors := [``List.nil, ``List.cons, ``Option.none, ``Option.some,
    ``BoundaryV2.Profile.Target.Boundary.PublicInvocation.mk,
    ``BoundaryV2.Profile.Target.Boundary.RefusalRecord.mk,
    ``BoundaryV2.Profile.Target.Boundary.CapacityRecord.mk,
    ``BoundaryV2.Profile.Target.Boundary.CapacityFollowup.mk]
  while !pending.isEmpty do
    let (actual, expected) := pending.back!
    pending := pending.pop
    if (match expected.getAppFn with | .const name _ => constructors.contains name | _ => false) then
      let actual ← match Kernel.whnf env {} actual with
        | .ok actual => pure actual
        | .error _ => reject "trust.claim_kernel" "subject normalization"
      if actual.getAppFn != expected.getAppFn || actual.getAppNumArgs != expected.getAppNumArgs then return false
      pending := pending ++ actual.getAppArgs.zip expected.getAppArgs
    else
      match Kernel.isDefEq env {} actual expected with
      | .ok true => pure ()
      | .ok false => return false
      | .error _ => reject "trust.claim_kernel" "subject comparison"
  return true

def inspectClaim (env : Environment) (claim : Claim) : IO Json := do
  let some ci := env.find? claim.name.toName
    | reject "trust.missing_claim" claim.name
  let expected ← match claim.kind with
    | "projection-artifact" | "lexical-artifact" => do
      if !claim.records.isEmpty || claim.record.isSome || claim.capacity.isSome then reject "trust.claim_fields" "unexpected execution records"
      let predicate := if claim.kind == "projection-artifact" then
        ``BoundaryV2.ProjectionArtifact.Certified else ``BoundaryV2.LexicalArtifact.Certified
      pure (mkApp2 (mkConst predicate) (← byteExpression claim.source) (← byteExpression claim.image))
    | "initial-execution" => do
      if !claim.source.isEmpty || claim.records.isEmpty || claim.record.isSome || claim.capacity.isSome then reject "trust.claim_fields" "expected nonempty initial execution"
      let records ← claim.records.mapM fun record => do
        pure (mkApp2 (mkConst ``BoundaryV2.Profile.Target.Boundary.PublicInvocation.mk)
          (← byteExpression record.input) (← byteExpression record.output))
      let type := mkConst ``BoundaryV2.Profile.Target.Boundary.PublicInvocation
      let records := records.toList.foldr (fun head tail => mkApp3 (mkConst ``List.cons [.zero]) type head tail)
        (mkApp (mkConst ``List.nil [.zero]) type)
      pure (mkApp2 (mkConst ``BoundaryV2.Profile.Target.Boundary.CertifiedInitialExecution)
        (← byteExpression claim.image) records)
    | "refusal" => do
      if !claim.source.isEmpty || !claim.records.isEmpty || claim.capacity.isSome then reject "trust.claim_fields" "unexpected refusal fields"
      let some record := claim.record | reject "trust.claim_fields" "missing refusal record"
      pure (mkApp2 (mkConst ``BoundaryV2.Profile.Target.Boundary.CertifiedRefusal)
        (← byteExpression claim.image) (← refusalExpression record))
    | "capacity-execution" => do
      if !claim.source.isEmpty || !claim.records.isEmpty || claim.record.isSome then
        reject "trust.claim_fields" "unexpected capacity fields"
      let some capacity := claim.capacity | reject "trust.claim_fields" "missing capacity record"
      pure (mkApp2 (mkConst ``BoundaryV2.Profile.Target.Boundary.CertifiedCapacityExecution)
        (← byteExpression claim.image) (← capacityExpression capacity))
    | _ => reject "trust.unsupported_claim" claim.kind
  -- Both types are closed. Use the kernel's definitional equality directly;
  -- standalone imports omit the elaborator extensions used by smart unfolding.
  -- The independently captured subjects above retain every byte and record field.
  if !(← capturedSubjectsMatch env ci.type expected) then reject "trust.claim_type" claim.name
  let typeMatches ← match Kernel.isDefEq env {} ci.type expected with
    | .ok equalTypes => pure equalTypes
    | .error _ => reject "trust.claim_kernel" claim.name
  if !typeMatches then reject "trust.claim_type" claim.name
  let fields := [("name", toJson claim.name), ("kind", toJson claim.kind), ("image", toJson claim.image)]
  let subject := match claim.kind with
    | "initial-execution" => [("records", toJson claim.records)]
    | "refusal" => [("record", toJson claim.record)]
    | "capacity-execution" => [("capacity", toJson claim.capacity)]
    | _ => [("source", toJson claim.source)]
  return Json.mkObj (fields ++ subject)

def audit (env : Environment) (inventory : Inventory) : IO Json := do
  if inventory.format != "boundary.formal-inventory/v1" then
    reject "trust.inventory_format" inventory.format
  if inventory.modules.isEmpty || inventory.roots.isEmpty then
    reject "trust.empty_inventory" "modules and roots must be nonempty"
  if !(inventory.modules.any fun m => m.name == "BoundaryV2" && m.kind == "semantic") then
    reject "trust.missing_root" "BoundaryV2"
  let names := inventory.modules.map (·.name)
  if names.toList.eraseDups.length != names.size then
    reject "trust.duplicate_module" "duplicate module entries"
  let tools := (inventory.modules.filter fun m => m.kind == "tooling").map (·.name)
  let sysroot ← IO.FS.realPath (← findSysroot)
  let buildRoot ← IO.FS.realPath ".lake/build/lib/lean"
  for moduleName in env.header.moduleNames do
    if names.contains moduleName.toString then continue
    let objectPath ← IO.FS.realPath (← findOLean moduleName)
    if !objectPath.toString.startsWith (sysroot.toString ++ "/") then
      reject "trust.unlisted_module" s!"{moduleName}: {objectPath}"
  for entry in inventory.modules do
    if !["semantic", "tooling", "certificate"].contains entry.kind then
      reject "trust.module_kind" entry.kind
    if entry.kind == "tooling" && entry.name != "Trust" then
      reject "trust.tooling_module" entry.name
    if !(env.header.moduleNames.any fun m => m.toString == entry.name) then
      reject "trust.module_not_built" entry.name
    let objectPath ← IO.FS.realPath (← findOLean entry.name.toName)
    let expected ← IO.FS.realPath (buildRoot / (entry.name.replace "." "/" ++ ".olean"))
    if !expected.toString.startsWith (buildRoot.toString ++ "/") || objectPath != expected then
      reject "trust.module_artifact" s!"{entry.name}: {objectPath}"
  let claims ← inventory.claims.mapM (inspectClaim env)
  let constants := env.constants.toList.toArray.qsort fun a b => Name.lt a.1 b.1
  let edges ← IO.mkRef ({} : NameMap (Array Name))
  let mut reports := #[]
  let mut semanticDeclarations := 0
  for (name, ci) in constants do
    let owner ← moduleOf env name
    if let some entry := inventory.modules.find? (·.name == owner) then
      reports := reports.push (← inspectDeclaration env entry ci tools edges)
      if entry.kind != "tooling" then semanticDeclarations := semanticDeclarations + 1
  if reports.isEmpty then reject "trust.empty_declarations" "no project declarations"
  if semanticDeclarations == 0 then reject "trust.empty_semantics" "no semantic declarations"
  return Json.mkObj [
    ("format", toJson "boundary.trust-audit/v1"), ("status", toJson "passed"),
    ("modules", toJson inventory.modules), ("declarations", toJson reports),
    ("declaration_count", toJson reports.size),
    ("semantic_declaration_count", toJson semanticDeclarations),
    ("claims", toJson claims),
    ("allowed_axioms", toJson (allowedAxioms.map Name.toString))]

unsafe def run (input output : System.FilePath) : IO UInt32 := do
  let parsed := (Json.parse (← IO.FS.readFile input)) >>= fromJson? (α := Inventory)
  let inventory ← match parsed with
    | .ok inventory => pure inventory
    | .error error => reject "trust.invalid_inventory" error
  initSearchPath (← findSysroot)
  let imports := inventory.roots.map fun name => { module := name.toName : Import }
  withImportModules imports {} fun env => do
    let report ← audit env inventory
    -- Names and strings may borrow the imported compacted regions. Serialize
    -- before withImportModules frees them; no imported object may escape.
    IO.FS.writeFile output (report.compress ++ "\n")
    IO.println s!"formal trust: {inventory.modules.size} modules passed"
    return 0

end BoundaryTrust

unsafe def main (args : List String) : IO UInt32 := do
  match args with
  | [input, output] =>
    try BoundaryTrust.run input output catch error =>
      IO.eprintln error.toString
      return 1
  | _ =>
    IO.eprintln "usage: boundary-trust <discovered-inventory.json> <audit.json>"
    return 64
