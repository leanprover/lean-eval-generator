import LeanEvalGenerator.Contract

namespace LeanEvalGenerator

set_option autoImplicit false

private def readRequest : List String → IO String
  | [] => do
      let stdin ← IO.getStdin
      stdin.readToEnd
  | [path] => IO.FS.readFile path
  | _ => throw <| IO.userError "usage: lean-eval-generator [request.json]"

def run (args : List String) : IO UInt32 := do
  try
    let payload ← readRequest args
    let request ← match parseRequest payload with
      | .ok request => pure request
      | .error error => throw <| IO.userError s!"Invalid generator request: {error}"
    let response ← render request
    IO.print response
    return 0
  catch error =>
    IO.eprintln s!"lean-eval-generator: {error}"
    return 1

end LeanEvalGenerator

def main (args : List String) : IO UInt32 :=
  LeanEvalGenerator.run args
