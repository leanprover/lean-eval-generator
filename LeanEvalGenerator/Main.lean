import LeanEvalGenerator.Structured

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
    let value ← IO.ofExcept <| (Lean.Json.parse payload).mapError ("Invalid generator request: " ++ ·)
    let version ← IO.ofExcept <| (value.getObjValAs? Nat "schemaVersion").mapError ("Invalid generator request: " ++ ·)
    let response ← if version == 3 then do
      let request ← IO.ofExcept <| (Structured.parse value).mapError ("Invalid generator request: " ++ ·)
      Structured.render request
    else do
      let request ← IO.ofExcept <| (parseRequest payload).mapError ("Invalid generator request: " ++ ·)
      render request
    IO.print response
    return 0
  catch error =>
    IO.eprintln s!"lean-eval-generator: {error}"
    return 1

end LeanEvalGenerator

def main (args : List String) : IO UInt32 :=
  LeanEvalGenerator.run args
