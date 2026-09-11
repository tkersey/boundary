/- CLI transport only. Proof generation, kernel checking, trust audit and fresh
replay are mandatory in the fixed driver; this entry point grants no proof. -/
def main (arguments : List String) : IO UInt32 := do
  try
    let child ← IO.Process.spawn {
      cmd := "node"
      args := #["../../tools/v2/certify.mjs"] ++ arguments.toArray
      stdin := .inherit
      stdout := .inherit
      stderr := .inherit }
    child.wait
  catch error =>
    IO.eprintln s!"tool.unavailable: {error}"
    return 2
