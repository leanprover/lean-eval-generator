import LeanEvalGenerator.Core.Generate

open LeanEvalGenerator.Core

private def targetAt (line : Nat) : ExtractedTheorem := {
  declarationName := "Fixture.target"
  module := "Fixture"
  startLine := line
  startColumn := 0
  endLine := line
  endColumn := 1
  sameModuleDependencies := #[]
  kind := "theorem"
}

private def expectEq (label actual expected : String) : IO Unit := do
  unless actual == expected do
    throw <| IO.userError
      s!"{label} mismatch\nexpected:\n{repr expected}\nactual:\n{repr actual}"

def main : IO Unit := do
  let erdosStyle :=
    "namespace Fixture\nset_option quotPrecheck false\n\n" ++
    "local notation \"A\" => { x : Nat | x = 0 }\nvariable (n : Nat)\n" ++
    "theorem target : True := by sorry\nend Fixture\n"
  expectEq "active set_option order"
    (extractContextVariablesAndSyntax erdosStyle (some (targetAt 6)) #[]
      isLocalSyntaxContextDeclaration)
    ("set_option quotPrecheck false\n" ++
      "local notation \"A\" => { x : Nat | x = 0 }\n" ++
      "variable (n : Nat)\n\n")

  let endedSection :=
    "section Gone\nset_option quotPrecheck false\nlocal notation \"A\" => Nat\n" ++
    "end Gone\nlocal notation \"B\" => Nat\n" ++
    "theorem target : True := by sorry\n"
  expectEq "ended section context"
    (extractContextVariablesAndSyntax endedSection (some (targetAt 6)) #[]
      isLocalSyntaxContextDeclaration)
    "local notation \"B\" => Nat\n\n"

  let declarationScoped :=
    "set_option pp.universes true in\ndef helper : Nat := 0\n" ++
    "local notation \"A\" => Nat\ntheorem target : True := by sorry\n"
  expectEq "declaration-scoped option does not leak"
    (extractContextVariablesAndSyntax declarationScoped (some (targetAt 4)) #[]
      isLocalSyntaxContextDeclaration)
    "local notation \"A\" => Nat\n\n"

  IO.println "PASS active set_option context is preserved without scoped-option leakage"
