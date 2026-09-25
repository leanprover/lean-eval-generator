import LeanEvalGenerator.Core.Generate

open LeanEvalGenerator.Core

private def expectEq (label actual expected : String) : IO Unit := do
  unless actual == expected do
    throw <| IO.userError
      s!"{label} mismatch\nexpected:\n{repr expected}\nactual:\n{repr actual}"

private def mathlibRev := "d13f23b723b8a846827a245b89c10fc7d3f11612"
private def tauCetiRev := "7cfdfef3ac31cce91302b926ac2f49525eed6fbc"

private def rootLakefile : String :=
  "name = \"fixture\"\n\n" ++
  "[[require]]\nname = \"mathlib\"\n" ++
  "git = \"https://github.com/leanprover-community/mathlib4.git\"\n" ++
  s!"rev = \"{mathlibRev}\"\n\n" ++
  "[[require]]\nname = \"TauCeti\"\n" ++
  "git = \"https://github.com/TauCetiProject/TauCeti\"\n" ++
  s!"rev = \"{tauCetiRev}\"\n\n" ++
  "[[require]]\nname = \"Cli\"\n" ++
  "git = \"https://github.com/leanprover/lean4-cli\"\n" ++
  "rev = \"e92c9f15fdfacc8536f31cfb3b7ad26c3c8cd204\"\n\n" ++
  "[[require]]\nname = \"LocalTool\"\npath = \"tools/local\"\n"

private def requireBlock (name git rev : String) : String :=
  s!"[[require]]\nname = \"{name}\"\ngit = \"{git}\"\nrev = \"{rev}\"\n\n"

private def mathlibBlock : String :=
  requireBlock "mathlib" "https://github.com/leanprover-community/mathlib4.git" mathlibRev

/-- The lakefile every Mathlib-only workspace had before extra requires
existed, spelled out literally so any drift in its bytes is caught. -/
private def mathlibOnlyLakefile (problemId : String) : String :=
  s!"name = \"{problemId}\"\n" ++
  "testDriver = \"workspace_test\"\n" ++
  "defaultTargets = [\"Challenge\", \"Solution\", \"Submission\"]\n\n" ++
  "[leanOptions]\nautoImplicit = false\n\n" ++
  mathlibBlock ++
  "[[lean_lib]]\nname = \"Challenge\"\n\n" ++
  "[[lean_lib]]\nname = \"Solution\"\n\n" ++
  "[[lean_lib]]\nname = \"Submission\"\n\n" ++
  "[[lean_exe]]\nname = \"workspace_test\"\nroot = \"WorkspaceTest\"\n"

private def writeModule (root : System.FilePath) (moduleName source : String) : IO Unit := do
  let path := moduleSourcePath root moduleName
  if let some dir := path.parent then IO.FS.createDirAll dir
  IO.FS.writeFile path source

private def requiresFor (root : System.FilePath) (deps : RootDependencies)
    (moduleName : String) : IO (Array DependencySpec) :=
  return workspaceRequires deps (← problemWorkspaceImports root moduleName)

private def names (specs : Array DependencySpec) : String :=
  toString (specs.map (·.name))

def main : IO Unit := do
  let root ← IO.FS.createTempDir
  try
    IO.FS.writeFile (root / "lakefile.toml") rootLakefile
    -- The TauCeti import is reached only through a repo-local helper module.
    writeModule root "LeanEval.Cfsg"
      "import Mathlib.GroupTheory.Perm.Basic\nimport LeanEval.CfsgHelper\n"
    writeModule root "LeanEval.CfsgHelper"
      "import TauCeti.GroupTheory.SpecificGroups.CFSG.Classification\n"
    writeModule root "LeanEval.Plain" "import Mathlib.Data.Nat.Basic\n"

    let deps ← loadRootDependencies root
    expectEq "mathlib pin" deps.mathlib.rev mathlibRev
    expectEq "extra requires" (names deps.extras) "#[TauCeti, Cli]"
    expectEq "legacy loader" (← loadRootMathlibDependency root).rev mathlibRev

    let cfsg ← requiresFor root deps "LeanEval.Cfsg"
    expectEq "imported extra require precedes mathlib; Cli is not required"
      (names cfsg) "#[TauCeti, mathlib]"
    let cfsgLakefile := lakefileToml "cfsg" cfsg (withChallengeDeps := false)
    unless (cfsgLakefile.splitOn
        (requireBlock "TauCeti" "https://github.com/TauCetiProject/TauCeti" tauCetiRev ++
          mathlibBlock)).length == 2 do
      throw <| IO.userError
        s!"TauCeti require is not immediately before mathlib:\n{cfsgLakefile}"
    if (cfsgLakefile.splitOn "Cli").length > 1 then
      throw <| IO.userError s!"unimported Cli require was emitted:\n{cfsgLakefile}"

    let plain ← requiresFor root deps "LeanEval.Plain"
    expectEq "mathlib-only requires" (names plain) "#[mathlib]"
    expectEq "mathlib-only lakefile"
      (lakefileToml "plain" plain (withChallengeDeps := false))
      (mathlibOnlyLakefile "plain")
    -- A bare mathlib pin (the pre-existing API) coerces to the same result.
    expectEq "coerced mathlib pin"
      (lakefileToml "plain" (workspaceRequires deps.mathlib #["TauCeti.X"])
        (withChallengeDeps := false))
      (mathlibOnlyLakefile "plain")
  finally
    IO.FS.removeDirAll root
  IO.println "dependency tests passed"
