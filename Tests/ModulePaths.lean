import LeanEvalGenerator.Core.Generate

open LeanEvalGenerator.Core

private def assertEqual (label actual expected : String) : IO Unit := do
  unless actual == expected do
    throw <| IO.userError s!"{label}: got {actual.quote}, expected {expected.quote}"

def main : IO Unit := do
  let root : System.FilePath := "/tmp/lean-eval-generator-context"
  let quoted := "FormalConjectures.Arxiv.«0912.2382».CurlingNumberConjecture"
  let components := splitNameComponents quoted
  unless components ==
      #["FormalConjectures", "Arxiv", "0912.2382", "CurlingNumberConjecture"] do
    throw <| IO.userError s!"quoted components were split incorrectly: {components}"
  assertEqual "source path" (moduleSourcePath root quoted).toString
    "/tmp/lean-eval-generator-context/FormalConjectures/Arxiv/0912.2382/CurlingNumberConjecture.lean"
  assertEqual "ilean path" (ileanPath root quoted).toString
    "/tmp/lean-eval-generator-context/.lake/build/lib/lean/FormalConjectures/Arxiv/0912.2382/CurlingNumberConjecture.ilean"
  assertEqual "plain path" (moduleSourcePath root "LeanEval.Fixture").toString
    "/tmp/lean-eval-generator-context/LeanEval/Fixture.lean"
  assertEqual "quoted keyword" (moduleSourcePath root "Foo.«match».Bar").toString
    "/tmp/lean-eval-generator-context/Foo/match/Bar.lean"
  assertEqual "inner opening guillemet"
    (moduleSourcePath root "Foo.«a«b.c».Bar").toString
    "/tmp/lean-eval-generator-context/Foo/a«b.c/Bar.lean"
  assertEqual "rendered prefix"
    (renderNameComponents #["Foo", "a.b"]) "Foo.«a.b»"
  assertEqual "last component" (lastComponentStr "Foo.«a.b»") "«a.b»"
