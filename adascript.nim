# AdaScript - Ada/Odin-like syntax extensions for Nim
# Curated collection of Nim macros providing:
#   - Ada-style declare/begin blocks with array/table/set type DSL
#   - Ada-style tick attributes via ^ operator
#   - Ada-style case statements (defCase/when/when others)
#   - Python-style classes (defclass), with statement, context managers
#   - Shell command execution with variable interpolation and piping
import macros, strformat, times, options, tables, sets, strutils
export tables, sets, times, strutils, options

include adascript_declarations
include adascript_attributes
include adascript_case
include adascript_classes
include adascript_shell
