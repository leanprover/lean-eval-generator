import LeanEvalGenerator.Core.Generate

open Lean

namespace LeanEvalGenerator

set_option autoImplicit false

/-- The first public wire format. Changes to its meaning require a new version. -/
def contractVersion : Nat := 1

structure DependencyPin where
  name : String
  git : String
  rev : String
  deriving FromJson, Inhabited

structure TemplateInputs where
  workspaceTest : String
  deriving FromJson

structure ResolvedHole where
  declarationName : String
  module : String
  startLine : Nat
  startColumn : Nat
  endLine : Nat
  endColumn : Nat
  explicitParameters : Option (Array String) := none
  sameModuleDependencies : Array String := #[]
  holeDependentDependencies : Array String := #[]
  kind : String
  deriving FromJson, Inhabited

/-- All problem-specific data supplied to the renderer. `contextRoot` remains
necessary in v1 for trusted helper modules and `.ilean` declaration spans. -/
structure ProblemInput where
  id : String
  title : String
  group : String
  status : String
  visible : Bool
  statementRevision : Nat
  tags : Array String
  moduleName : String
  holes : Array String
  submitter : String
  notes : Option String := none
  source : Option String := none
  informalSolution : Option String := none
  moduleContent : String
  resolvedHoles : Array ResolvedHole
  deriving FromJson

structure GenerateRequest where
  schemaVersion : Nat
  contextRoot : String
  leanToolchain : String
  mathlib : DependencyPin
  templates : TemplateInputs
  problems : Array ProblemInput
  deriving FromJson

private def validateRequest (request : GenerateRequest) : IO Unit := do
  if request.schemaVersion != contractVersion then
    throw <| IO.userError
      s!"Unsupported schemaVersion {request.schemaVersion}; expected {contractVersion}."
  if request.problems.isEmpty then
    throw <| IO.userError "The request must contain at least one problem."
  if request.contextRoot.isEmpty then
    throw <| IO.userError "contextRoot must be non-empty."
  if request.leanToolchain.isEmpty then
    throw <| IO.userError "leanToolchain must be non-empty."
  if request.mathlib.name != "mathlib" then
    throw <| IO.userError "The dependency pin must be named `mathlib`."
  if request.mathlib.git.isEmpty || request.mathlib.rev.isEmpty then
    throw <| IO.userError "The mathlib git and rev pins must be non-empty."
  let mut problemIds : Array String := #[]
  for problem in request.problems do
    if problemIds.contains problem.id then
      throw <| IO.userError s!"Duplicate problem id `{problem.id}`."
    problemIds := problemIds.push problem.id

private def sha256 (content : String) : IO String := do
  let out ← IO.Process.output {
    cmd := "sha256sum"
    args := #["-"]
  } (some content)
  if out.exitCode != 0 then
    throw <| IO.userError s!"sha256sum failed: {out.stderr.trimAscii.toString}"
  let digest := (out.stdout.splitOn " ").head!.trimAscii.toString
  if digest.length != 64 then
    throw <| IO.userError "sha256sum returned an invalid digest."
  return digest

private def metadata (problem : ProblemInput) : LeanEvalGenerator.Core.EvalProblemMetadata := {
  id := problem.id
  title := problem.title
  group := problem.group
  status := problem.status
  visible := problem.visible
  statementRevision := problem.statementRevision
  tags := problem.tags
  moduleName := problem.moduleName
  holes := problem.holes
  submitter := problem.submitter
  notes := problem.notes
  source := problem.source
  informalSolution := problem.informalSolution
}

private def extracted (hole : ResolvedHole) : LeanEvalGenerator.Core.ExtractedTheorem := {
  declarationName := hole.declarationName
  module := hole.module
  startLine := hole.startLine
  startColumn := hole.startColumn
  endLine := hole.endLine
  endColumn := hole.endColumn
  explicitParameters := hole.explicitParameters
  sameModuleDependencies := hole.sameModuleDependencies
  holeDependentDependencies := hole.holeDependentDependencies
  kind := hole.kind
}

private def validateProblem (root : System.FilePath) (problem : ProblemInput) : IO Unit := do
  if problem.id.isEmpty then
    throw <| IO.userError "Problem id must be non-empty."
  if problem.title.isEmpty then
    throw <| IO.userError s!"Problem `{problem.id}` title must be non-empty."
  if problem.moduleName.isEmpty then
    throw <| IO.userError s!"Problem `{problem.id}` moduleName must be non-empty."
  if problem.submitter.isEmpty then
    throw <| IO.userError s!"Problem `{problem.id}` submitter must be non-empty."
  unless LeanEvalGenerator.Core.allowedProblemGroups.contains problem.group do
    throw <| IO.userError s!"Problem `{problem.id}` has an unsupported group."
  unless LeanEvalGenerator.Core.allowedProblemStatuses.contains problem.status do
    throw <| IO.userError s!"Problem `{problem.id}` has an unsupported status."
  if problem.statementRevision == 0 then
    throw <| IO.userError s!"Problem `{problem.id}` statementRevision must be positive."
  if problem.tags.any String.isEmpty then
    throw <| IO.userError s!"Problem `{problem.id}` tags must be non-empty strings."
  let mut seenTags : Array String := #[]
  for tag in problem.tags do
    if seenTags.contains tag then
      throw <| IO.userError s!"Problem `{problem.id}` has duplicate tag `{tag}`."
    seenTags := seenTags.push tag
  if problem.holes.isEmpty then
    throw <| IO.userError s!"Problem `{problem.id}` must contain at least one hole."
  if problem.holes.any String.isEmpty then
    throw <| IO.userError s!"Problem `{problem.id}` holes must be non-empty strings."
  if problem.holes.size != problem.resolvedHoles.size then
    throw <| IO.userError <|
      s!"Problem `{problem.id}` has {problem.holes.size} manifest holes but " ++
        s!"{problem.resolvedHoles.size} resolved holes."
  let sourcePath := LeanEvalGenerator.Core.moduleSourcePath root problem.moduleName
  let actual ← IO.FS.readFile sourcePath
  if actual != problem.moduleContent then
    throw <| IO.userError
      s!"Problem `{problem.id}` moduleContent does not match {sourcePath}."
  for hole in problem.resolvedHoles do
    if hole.declarationName.isEmpty || hole.module.isEmpty then
      throw <| IO.userError s!"Problem `{problem.id}` has empty resolved-hole metadata."
    if hole.startLine == 0 || hole.endLine == 0 then
      throw <| IO.userError s!"Problem `{problem.id}` resolved-hole lines must be positive."
    unless #["theorem", "def", "instance"].contains hole.kind do
      throw <| IO.userError s!"Problem `{problem.id}` has an unsupported resolved-hole kind."
    if hole.module != problem.moduleName then
      throw <| IO.userError <|
        s!"Resolved hole `{hole.declarationName}` belongs to module `{hole.module}`, " ++
          s!"not `{problem.moduleName}`."
  for index in [0:problem.holes.size] do
    let manifestHole := problem.holes[index]!
    let resolvedHole := problem.resolvedHoles[index]!
    let basename := LeanEvalGenerator.Core.lastComponentStr resolvedHole.declarationName
    if manifestHole != resolvedHole.declarationName && manifestHole != basename then
      throw <| IO.userError <|
        s!"Problem `{problem.id}` manifest hole `{manifestHole}` does not match " ++
          s!"resolved declaration `{resolvedHole.declarationName}` at index {index}."

private def fileJson (problemId : String) (path content digest : String) : LeanEvalGenerator.Core.OJson :=
  LeanEvalGenerator.Core.ojObj #[
    ("problemId", LeanEvalGenerator.Core.ojStr problemId),
    ("path", LeanEvalGenerator.Core.ojStr path),
    ("sha256", LeanEvalGenerator.Core.ojStr digest),
    ("content", LeanEvalGenerator.Core.ojStr content)
  ]

/-- Render a request without mutating the benchmark repository. The response is
ordered and byte-stable, including complete file contents and SHA-256 digests. -/
def render (request : GenerateRequest) : IO String := do
  validateRequest request
  let root : System.FilePath := request.contextRoot
  let mathlib : LeanEvalGenerator.Core.DependencySpec := {
    name := request.mathlib.name
    git := request.mathlib.git
    rev := request.mathlib.rev
  }
  let mut files : Array LeanEvalGenerator.Core.OJson := #[]
  for problem in request.problems do
    validateProblem root problem
    let rendered ← LeanEvalGenerator.Core.renderWorkspace root (metadata problem)
      (problem.resolvedHoles.map extracted) request.leanToolchain mathlib
      request.templates.workspaceTest
    for (path, content) in rendered do
      files := files.push <| fileJson problem.id path content (← sha256 content)
  let response := LeanEvalGenerator.Core.ojObj #[
    ("schemaVersion", LeanEvalGenerator.Core.ojNat contractVersion),
    ("files", LeanEvalGenerator.Core.ojArr files)
  ]
  return LeanEvalGenerator.Core.OJson.pretty response ++ "\n"

def parseRequest (payload : String) : Except String GenerateRequest :=
  Json.parse payload >>= fromJson?

end LeanEvalGenerator
