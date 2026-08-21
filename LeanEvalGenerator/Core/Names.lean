import Lean

namespace LeanEvalGenerator.Core

set_option autoImplicit false

/-- Split a rendered Lean hierarchical name into its semantic components.

Dots inside a guillemet-quoted identifier are data, not separators, and the
outer guillemets are not part of the resulting component. Lean permits any
character except `»` inside a quoted component, including another `«` and a
newline, so only the first closing `»` changes the scanner back to the ordinary
state. Callers use module and declaration names already accepted by Lean; this
helper is not a replacement identifier parser. -/
def splitNameComponents (text : String) : Array String := Id.run do
  let mut parts : Array String := #[]
  let mut current := ""
  let mut quoted := false
  for character in text.toList do
    if quoted then
      if character == '»' then
        quoted := false
      else
        current := current.push character
    else if character == '«' then
      quoted := true
    else if character == '.' then
      parts := parts.push current
      current := ""
    else
      current := current.push character
  parts.push current

def nameFromComponents (parts : Array String) : Lean.Name :=
  parts.foldl Lean.Name.str .anonymous

def parseHierarchicalName (text : String) : Lean.Name :=
  nameFromComponents (splitNameComponents text)

/-- Render semantic components back to unambiguous Lean syntax. In particular,
a component containing `.` regains its required guillemets. -/
def renderNameComponents (parts : Array String) : String :=
  (nameFromComponents parts).toString

end LeanEvalGenerator.Core
