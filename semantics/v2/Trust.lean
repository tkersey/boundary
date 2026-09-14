import Lean
import Lean.Replay

/-! Verification tooling only. The runner supplies every discovered project
module. Declaration ownership comes from Lean, including private helpers and
names outside the project's namespace. No semantic module imports this tool. -/
namespace BoundaryTrust
open Lean

def dependencies (info : ConstantInfo) : Array Name := Id.run do
  let mut result := info.type.getUsedConstants
  if let some body := info.value? (allowOpaque := true) then
    result := result ++ body.getUsedConstants
  if let .inductInfo value := info then result := result ++ value.ctors.toArray
  return result

/-- Lean generates partial executable companions for safe recursive definitions.
Only their safe parent contributes logical meaning; a logical edge to an unsafe
companion still rejects. A copied suffix alone cannot obtain this exception. -/
def executableHelper (env : Environment) (info : ConstantInfo) : CoreM Bool := do
  if !info.isPartial then return false
  let some parent := Compiler.isUnsafeRecName? info.name | return false
  let some (.defnInfo original) := env.find? parent | return false
  if original.safety != .safe then return false
  return (← Meta.MetaM.run' (Meta.isDefEq info.type original.type))

def audit (modules : Array Name) : CoreM Unit := do
  let env ← getEnv
  for moduleName in modules do
    unless env.header.moduleNames.contains moduleName do
      throwError "trust audit: missing discovered module {moduleName}"
  let mut pending := #[]
  let mut declarations := 0
  let mut theorems := 0
  let mut helpers := 0
  for (name, info) in env.constants.toList do
    let some index := env.getModuleIdxFor? name | continue
    let some owner := env.header.moduleNames[index.toNat]? |
      throwError "trust audit: missing module provenance for {name}"
    unless modules.contains owner do continue
    declarations := declarations + 1
    if info matches .thmInfo _ then theorems := theorems + 1
    if owner == `Trust then
      -- Tooling may call unsafe kernel/runtime APIs, but every declaration,
      -- including its private helpers, still obeys the positive axiom policy.
      for axiomName in (← collectAxioms name) do
        unless #[`propext, `Quot.sound, `Classical.choice].contains axiomName do
          throwError "trust audit: unapproved axiom {axiomName} in tooling {name}"
    else if ← executableHelper env info then helpers := helpers + 1
    else pending := pending.push name
  if theorems == 0 then throwError "trust audit: no project theorems discovered"
  let mut visited : NameSet := {}
  while !pending.isEmpty do
    let name := pending.back!
    pending := pending.pop
    if visited.contains name then continue
    visited := visited.insert name
    let some info := env.find? name | throwError "trust audit: missing declaration {name}"
    if info.isUnsafe || info.isPartial then
      throwError "trust audit: unsafe logical dependency {name}"
    if let some index := env.getModuleIdxFor? name then
      if env.header.moduleNames[index.toNat]? == some `Trust then
        throwError "trust audit: semantic dependency on verification tooling {name}"
    if info matches .axiomInfo _ then
      unless #[`propext, `Quot.sound, `Classical.choice].contains name do
        throwError "trust audit: unapproved axiom {name}"
    pending := pending ++ dependencies info
  logInfo m!"trust audit: {modules.size} modules, {declarations} declarations, {theorems} theorems, {helpers} generated executable companions; positive axiom policy passed"

/-- Use the pinned toolchain's replay API to kernel-check imported declarations
in a fresh empty environment, including private theorem bodies. -/
def freshReplay : CoreM Unit := do
  let env ← getEnv
  let constants := Std.HashMap.ofList env.constants.toList
  let _ ← Lean.Environment.replay constants (← mkEmptyEnvironment 0)
  logInfo "trust replay: imported declarations checked in a fresh kernel environment"

end BoundaryTrust
