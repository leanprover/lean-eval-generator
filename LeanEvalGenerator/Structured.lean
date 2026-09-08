import LeanEvalGenerator.Contract

/-! A source-free renderer for closed declaration signatures. No source slices,
`.ilean` files, dependency discovery, or namespace reconstruction are used. -/
namespace LeanEvalGenerator.Structured
open Lean

structure Declaration where
  name : String
  kind : String
  type : String
  levels : Array String
  deriving FromJson, ToJson

structure Problem where
  id : String
  title : String
  imports : Array String
  declarations : Array Declaration
  deriving FromJson

structure Request where
  schemaVersion : Nat
  leanToolchain : String
  dependencies : Array DependencyPin
  templates : TemplateInputs
  problems : Array Problem
  deriving FromJson

private def exactFields (value : Json) (fields : List String) : Except String Unit := do
  let object ← value.getObj?
  unless object.size == fields.length && object.all (fun k _ => fields.contains k) do
    throw "Unexpected or missing structured request fields"

def parse (value : Json) : Except String Request := do
  exactFields value ["schemaVersion", "leanToolchain", "dependencies", "templates", "problems"]
  exactFields (← value.getObjVal? "templates") ["workspaceTest"]
  for d in (← value.getObjValAs? (Array Json) "dependencies") do
    exactFields d ["name", "git", "rev"]
  for p in (← value.getObjValAs? (Array Json) "problems") do
    exactFields p ["id", "title", "imports", "declarations"]
    for d in (← p.getObjValAs? (Array Json) "declarations") do
      exactFields d ["name", "kind", "type", "levels"]
  fromJson? value

private def identifier (s : String) : Bool :=
  !s.isEmpty && (s.toList.head!.isAlpha || s.startsWith "_") &&
    s.toList.all (fun c => c.toNat < 128 && (c.isAlphanum || c == '_'))

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def validate (r : Request) : IO Unit := do
  require (r.schemaVersion == 3) "Expected schemaVersion 3"
  require (!r.leanToolchain.trimAscii.isEmpty && !r.problems.isEmpty) "Empty toolchain or problems"
  let mut packages := #[]
  for d in r.dependencies do
    require (identifier (d.name.replace "-" "_") && !packages.contains d.name)
      "Invalid or duplicate package name"
    require (!d.git.isEmpty && d.rev.length == 40 && d.rev.toList.all
      (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f'))) "Expected package URL and full lowercase commit SHA"
    packages := packages.push d.name
  let mut ids := #[]
  for p in r.problems do
    require (identifier p.id && !ids.contains p.id && !p.title.isEmpty) "Invalid or duplicate problem id"
    ids := ids.push p.id
    require (!p.imports.isEmpty && !p.declarations.isEmpty) "Empty imports or declarations"
    -- Use Lean's parser to validate syntax boundaries, never an approximate lexer.
    for name in p.imports do
      let ctx := Parser.mkInputContext s!"import {name}\n" "<structured import>"
      let (header, state, messages) ← Parser.parseHeader ctx
      let imports := Elab.HeaderSyntax.imports header (includeInit := false)
      require (!messages.hasErrors && ctx.atEnd state.pos && imports.size == 1 &&
        imports[0]!.module.toString == name.toName.toString) "Invalid module import"
    let mut names := #[]
    for d in p.declarations do
      require (identifier d.name && !names.contains d.name) "Invalid or duplicate declaration name"
      names := names.push d.name
      require (d.kind == "def" || d.kind == "theorem") "Expected def or theorem"
      require (d.levels.all identifier && d.levels.toList.eraseDups.length == d.levels.size)
        "Invalid universe parameters"
      -- Type syntax belongs to the producer's Lean environment (which may
      -- provide notation unknown to this renderer). It is trusted input,
      -- just like v1 moduleContent, and must be validated by the consumer.
      require (!d.type.trimAscii.isEmpty) "Empty declaration type"

private def levelSuffix (d : Declaration) : String :=
  if d.levels.isEmpty then "" else ".{" ++ String.intercalate ", " d.levels.toList ++ "}"

private def declaration (d : Declaration) (solution : Bool := false) : String :=
  let command := if d.kind == "def" then
    (if solution then "@[reducible] " else "") ++ "noncomputable def" else "theorem"
  let body := if solution then "@Submission." ++ d.name ++ levelSuffix d else "by\n  sorry"
  s!"{command} {d.name}{levelSuffix d} : {d.type} := {body}\n\n"

private def workspace (r : Request) (p : Problem) : Array (String × String) := Id.run do
  let imports := String.join (p.imports.toList.map (fun n => s!"import {n}\n")) ++ "\n"
  let holes := String.join (p.declarations.toList.map (declaration ·))
  let challenge := imports ++ holes
  let submission := imports ++ "import Submission.Helpers\n\nnamespace Submission\n\n" ++
    holes ++ "end Submission\n"
  let solution := imports ++ "import Submission\n\n" ++
    String.join (p.declarations.toList.map (declaration · true))
  let deps := String.join <| r.dependencies.toList.map fun d =>
    s!"[[require]]\nname = {d.name.quote}\ngit = {d.git.quote}\nrev = {d.rev.quote}\n\n"
  let lakefile := s!"name = {p.id.quote}\nversion = \"0.1.0\"\ndefaultTargets = [\"Challenge\", \"Solution\"]\ntestDriver = \"workspace_test\"\n\n" ++
    deps ++ "[[lean_lib]]\nname = \"Challenge\"\n\n[[lean_lib]]\nname = \"Solution\"\n\n[[lean_lib]]\nname = \"Submission\"\n\n[[lean_exe]]\nname = \"workspace_test\"\nroot = \"WorkspaceTest\"\n"
  let config := Json.mkObj [
    ("challenge_module", toJson "Challenge"), ("solution_module", toJson "Solution"),
    ("theorem_names", toJson (p.declarations.filter (·.kind == "theorem") |>.map (·.name))),
    ("definition_names", toJson (p.declarations.filter (·.kind == "def") |>.map (·.name))),
    ("permitted_axioms", toJson #["propext", "Quot.sound", "Classical.choice"])]
  return #[("Challenge.lean", challenge), ("Submission.lean", submission),
    ("Submission/Helpers.lean", imports), ("Solution.lean", solution),
    ("lakefile.toml", lakefile), ("lean-toolchain", r.leanToolchain.trimAscii.toString ++ "\n"),
    ("WorkspaceTest.lean", r.templates.workspaceTest), ("config.json", config.pretty ++ "\n"),
    ("holes.json", (Json.mkObj [("id", toJson p.id),
      ("declarations", toJson p.declarations)]).pretty ++ "\n"),
    ("README.md", s!"# {p.title}\n\nFill the holes in Submission.lean. Keep Challenge.lean and Solution.lean unchanged.\nRun `lake test` with the configured Comparator and sandbox.\n")]

/-- Render only the supplied signatures; the consumer must compile the result
under its pinned imports before publishing it as a challenge. -/
def render (r : Request) : IO String := do
  validate r
  let mut files := #[]
  for p in r.problems do
    for (path, content) in workspace r p do
      files := files.push <| Json.mkObj [("problemId", toJson p.id), ("path", toJson path),
        ("content", toJson content), ("sha256", toJson (← LeanEvalGenerator.sha256 content))]
  return (Json.mkObj [("schemaVersion", toJson (3 : Nat)), ("files", toJson files)]).pretty ++ "\n"

end LeanEvalGenerator.Structured
