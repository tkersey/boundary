import BoundaryV2
import Lean

/-!
Enforce the documented logical trust boundary. Select declarations by their
owning module, not their namespace: this includes private declarations and
helpers written outside `namespace BoundaryV2`. Inspect every declaration, not
only a hand-maintained theorem list, so an unused admitted axiom also rejects.
`check.mjs` imports every source module, including modules not yet in the root.
-/
run_cmd do
  let env ← Lean.getEnv
  let mut declarations := 0
  let mut theorems := 0
  for (name, info) in env.constants.toList do
    let some index := env.getModuleIdxFor? name | continue
    let some owner := env.allImportedModuleNames[index.toNat]? |
      throwError "trust audit: missing owning module for {name}"
    unless (`BoundaryV2).isPrefixOf owner do continue
    declarations := declarations + 1
    if info matches .thmInfo _ then theorems := theorems + 1
    for axiomName in (← Lean.collectAxioms name) do
      unless #[`propext, `Quot.sound, `Classical.choice].contains axiomName do
        throwError "trust audit: unapproved axiom {axiomName} in {name} (module {owner})"
  if theorems == 0 then throwError "trust audit: no BoundaryV2 theorems discovered"
  logInfo m!"trust audit: checked {declarations} declarations ({theorems} theorems); only propext, Quot.sound, Classical.choice permitted"
