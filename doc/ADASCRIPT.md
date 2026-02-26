# AdaScript -- Ada/Odin-inspired syntax extensions for Nim

AdaScript is a collection of Nim compile-time macros and templates that
reshape Nim's syntax, borrowing the best ideas from three languages:

- **Odin** -- left-to-right type declarations: `[8]int`, `[]string`, `{string}int`
- **Ada** -- tick attributes (`^`), `declare`/`begin` blocks, `switch`/`when others`
- **Python** -- `class` definitions, `def` functions, `with` statement, context managers
- **Shell** -- command execution with variable interpolation and piping

No external tools or code generation -- everything happens inside
Nim's macro system, so you keep full type-checking, IDE support and
native error messages.

```nim
import adascript     # one import gets everything
```

---

## Table of contents

1. [Type declarations (Odin)](#1-type-declarations-odin-inspired)
2. [Declare / Begin blocks (Ada)](#2-declare--begin-blocks-ada-inspired)
3. [Loop statement (Ada)](#5-loop-statement-ada-inspired)
4. [Tick attributes (Ada)](#4-tick-attributes-ada-inspired)
4. [Case statements (Ada)](#4-case-statements-ada-inspired)
6. [Functions with def (Python)](#6-functions-with-def-python-inspired)
6. [Classes (Python)](#7-classes-python-inspired)
7. [Context managers and with (Python)](#8-context-managers-and-with-python-inspired)
8. [Shell command execution](#9-shell-command-execution)
9. [Utility extras](#9-utility-extras)
10. [Template Method Pattern](#10-template-method-pattern)
11. [Design rationale](#11-design-rationale)
12. [Quick reference](#12-quick-reference)
13. [Testing](#13-testing)

---

## 1. Type declarations (Odin-inspired)

Odin writes types left-to-right: *"an array of 8 ints"* is `[8]int`.
AdaScript brings the same convention into Nim `declare` blocks using
compile-time macros that rewrite the syntax into native Nim types.

### Arrays

| AdaScript | Nim equivalent | Read as |
|------|----------------|---------|
| `[8]int` | `array[8, int]` | 8 ints |
| `[1..10]float` | `array[1..10, float]` | floats indexed 1 to 10 |
| `[Color]string` | `array[Color, string]` | a string per Color |

### Sequences (dynamic arrays)

| AdaScript | Nim equivalent | Read as |
|------|----------------|---------|
| `[]int` | `seq[int]` | dynamic list of ints |
| `[]string` | `seq[string]` | dynamic list of strings |

### Nested types

The real payoff -- Odin-style nesting stays flat and readable where
Nim's native syntax becomes deeply nested:

| AdaScript | Nim equivalent |
|------|----------------|
| `[3][4]int` | `array[3, array[4, int]]` |
| `[][]int` | `seq[seq[int]]` |
| `[][5]int` | `seq[array[5, int]]` |
| `[3][]char` | `array[3, seq[char]]` |
| `[][1..5][]char` | `seq[array[1..5, seq[char]]]` |

Compare at depth 3:

```
Nim:   array[3, array[4, seq[int]]]
AdaScript:  [3][4][]int
```

### Hash tables

Curly braces denote the key type, following Odin's map syntax:

| AdaScript | Nim equivalent |
|------|----------------|
| `{string}int` | `Table[string, int]` |
| `{int}string` | `Table[int, string]` |

### Sets

Empty braces denote sets.  The macro automatically picks `set` for
small ordinal types or `HashSet` for larger ones:

| AdaScript | Nim equivalent | Why |
|------|----------------|-----|
| `{}char` | `set[char]` | char is a small ordinal |
| `{}Direction` | `set[Direction]` | enum is a small ordinal |
| `{}int` | `HashSet[int]` | int range is too large for built-in set |
| `{}string` | `HashSet[string]` | not an ordinal at all |

### Optional types

The `?` prefix denotes optional types, expanding to `Option[T]`:

| AdaScript | Nim equivalent | Read as |
|------|----------------|---------|
| `?int` | `Option[int]` | optional int |
| `?string` | `Option[string]` | optional string |
| `?[]int` | `Option[seq[int]]` | optional sequence |
| `[]?int` | `seq[Option[int]]` | sequence of optionals |
| `?{string}int` | `Option[Table[string, int]]` | optional table |

Works in all contexts: variable declarations, `def` parameters,
return types, class fields, object fields, and type aliases.

#### Return sugar for `?T` functions

When a `def` has a `?T` return type, return statements are
automatically wrapped:

```nim
def findUser(id: int) -> ?string:
  if id == 1:
    return "Alice"       # auto-wrapped to some("Alice")
  return None            # becomes none(string)
```

Returning an already-optional value (e.g., a `?T` field) works
correctly without double-wrapping:

```nim
class Config:
  var port: ?int

  def getPort(self) -> ?int:
    return self.port     # Option[int] passes through unchanged
```

#### Checking for None

Use `== None` and `!= None` to check optional values:

```nim
let user = findUser(1)
if user != None:
  echo "Found: ", user.get
else:
  echo "Not found"

# Also works in reverse
if None == findUser(99):
  echo "Missing"
```

> **Note:** `is None` is not supported because `is` is Nim's
> built-in type-checking operator.  Use `== None` / `!= None` instead.

---

## 2. Declare / Begin blocks (Ada-inspired)

In Ada, every block separates *declarations* from *statements*:

```ada
declare
   X : Integer := 42;
   M : Matrix_T;
begin
   M(1,2) := X;
   Put_Line(Integer'Image(M(1,2)));
end;
```

AdaScript reproduces this pattern.  The type DSL from section 1 works
inside `declare` blocks:

```nim
declare:
  type matrix_T = [3][4]int
  var m: matrix_T
  var count = 0

begin:
  m[1][2] = 99
  count += 1
  echo m[1][2]           # 99
```

Types and variables declared in `declare:` are scoped to the
matching `begin:` block -- they don't leak into surrounding code.

### Labeled scopes

```nim
declare physics:
  type vec3 = [3]float
  var velocity: vec3
  var acceleration: vec3

begin:
  velocity = [1.0, 0.0, 0.0]
  acceleration = [0.0, -9.81, 0.0]
  echo velocity
# velocity and acceleration are no longer visible here
```

### Mixing types, variables, constants and procedures

```nim
declare:
  type grid_T = [10][10]int
  const MAX_ITER = 100
  var grid: grid_T
  var iterations = 0

  def resetGrid(g: var grid_T):
    for i in 0..<10:
      for j in 0..<10:
        g[i][j] = 0

begin:
  resetGrid(grid)
  echo grid[0][0]        # 0
```

### Standalone begin

`begin:` without a preceding `declare:` simply groups statements
with access to the enclosing scope:

```nim
begin:
  let temp = computeSomething()
  echo temp
# temp is no longer visible

### Module-level globals with Ada-style DSL

For module-level declarations, use the `globals:` block. This provides
the same Ada-style DSL as `declare:`/`begin:` but emits declarations
directly at module scope (not wrapped in a block):

```nim
globals:
  const KILO_VERSION = "0.0.1"
  const KILO_TAB_STOP = 8
  
  type EditorKey = enum
    BACKSPACE = 127
    ARROW_LEFT = 1000
    ARROW_RIGHT, ARROW_UP, ARROW_DOWN
    DEL_KEY, HOME_KEY, END_KEY, PAGE_UP, PAGE_DOWN
  
  type ERowHL = []uint8  # DSL: seq[uint8]
  
  type ERow = object
    size, rsize: int
    chars, render: string
    hl: ERowHL
```

**Comparison:**

| Feature | `globals:` | `declare:`/`begin:` |
|---------|-----------|---------------------|
| Scope | Module-level (global) | Block-level (local) |
| Block wrapper | No | Yes |
| Use case | Module constants, types, globals | Local scopes, functions |
```

---

## 3. Tick attributes (Ada-inspired)

Ada queries type and value properties with the tick character (`'`):

```ada
Color'First          -- Red
Color'Last           -- Yellow
Green'Succ           -- Blue
Green'Pos            -- 1
```

Since `'` is reserved in Nim for character literals, AdaScript uses `^`:

### On types

| Expression | Result | Ada equivalent |
|------------|--------|----------------|
| `Color ^ First` | `Red` | `Color'First` |
| `Color ^ Last` | `Yellow` | `Color'Last` |
| `Color ^ Length` | `4` | `Color'Range'Length` |
| `Color ^ Size` | `4` | (same) |

Works on `enum`, `range`, and `array` types:

```nim
type Temp = range[-5..5]
Temp ^ First          # -5
Temp ^ Last           # 5
Temp ^ Size           # 11

type Scores = array[1..10, int]
Scores ^ First        # 1
Scores ^ Last         # 10
Scores ^ Length       # 10
```

### On values

| Expression | Result | Ada equivalent |
|------------|--------|----------------|
| `Green ^ Succ` | `Blue` | `Color'Succ(Green)` |
| `Green ^ Pred` | `Red` | `Color'Pred(Green)` |
| `Green ^ Pos` | `1` | `Color'Pos(Green)` |

Boundary checks raise `RangeDefect` (just like Ada's `Constraint_Error`):

```nim
discard Red ^ Pred     # RangeDefect: no predecessor
discard Yellow ^ Succ  # RangeDefect: no successor
```

### Iterating a type's range

Nim already supports direct iteration over enums and ranges:

```nim
for c in Color:
  echo c               # Red, Green, Blue, Yellow

for i in Scores.low..Scores.high:
  echo scores[i]
```

AdaScript also provides `tickRange` as an Ada-style alias, but it is
not needed -- the above forms are simpler.

---

## 4. Case statements (Ada-inspired)

Ada uses `when` for branches and `when others` for the default:

```ada
case Status is
   when 1 => Put_Line("starting");
   when 2 => Put_Line("running");
   when others => Put_Line("unknown");
end case;
```

AdaScript:

```nim
switch status:
  when 1: echo "starting"
  when 2: echo "running"
  when 3:
    echo "stopping"
    cleanup()
  when others: echo "unknown"
```

This compiles to Nim's native `case`/`of`/`else` -- no runtime overhead.

---


## 5. Loop statement (Ada-inspired)

Ada uses `loop` for infinite loops.  AdaScript provides the same:

```nim
loop:
  echo "Running..."
  if done:
    break
```

This expands to `while true:` at compile time -- zero runtime overhead.

**Comparison:**

| AdaScript | Nim equivalent |
|------|----------------|
| `loop:` | `while true:` |

---
## 6. Functions with `def` (Python-inspired)

The `def` macro provides Python-style function definitions that are
fully interchangeable with `proc`.  Every feature of `proc` is
supported: generics, pragmas, default values, varargs, and
multi-parameter shorthand.

### Basic usage

```nim
def greet(name: string):
  echo "hello " & name

def add(a: int, b: int) -> int:
  a + b

def pi() -> float:
  3.14159
```

### Return types

Use `->` to specify the return type (like Python type hints):

```nim
def square(x: int) -> int:
  x * x
```

### DSL types in parameters and return types

The Odin-style type DSL works directly in `def` parameters and return
types -- no need for pre-defined type aliases:

```nim
# Return a sequence
def getNames() -> []string:
  @["Alice", "Bob", "Charlie"]

# Accept a sequence parameter
def sumAll(nums: []int) -> int:
  var total = 0
  for n in nums: total += n
  total

# Return a fixed array
def getTriple() -> [3]int:
  [10, 20, 30]

# Table parameter
def lookupAge(table: {string}int, key: string) -> int:
  table[key]

# Set parameter
def hasTag(tags: {}string, tag: string) -> bool:
  tags.contains(tag)
```

All DSL patterns are supported: `[N]T`, `[]T`, `{K}V`, `{}T`, and
nested combinations like `[][]int` or `[3][]string`.

### Generics

```nim
def identity[T](x: T) -> T:
  x

def swap[A, B](a: A, b: B) -> (B, A):
  (b, a)
```

### Default values (using `~`)

Since `=` inside macro call parentheses is not valid Nim syntax,
AdaScript uses `~` for default parameter values:

```nim
def greet(name: string ~ "world") -> string:
  "hello " & name

greet()        # "hello world"
greet("Ada")   # "hello Ada"

def connect(host: string ~ "localhost", port: int ~ 8080):
  echo host, ":", port
```

### Varargs

```nim
def total(nums: varargs[int]) -> int:
  var s = 0
  for n in nums: s += n
  s

total(1, 2, 3)   # 6
```

### Pragmas

Attach pragmas after the return type (or after the parameters if
there is no return type):

```nim
def pureAdd(a: int, b: int) -> int {.noSideEffect.}:
  a + b

def logMsg(msg: string) {.deprecated.}:
  echo msg
```

### Multi-parameter shorthand

Multiple parameters of the same type can share a type annotation:

```nim
def sum3(a, b, c: int) -> int:
  a + b + c
```

### Mutable parameters

The `var` modifier works as expected:

```nim
def increment(x: var int):
  x += 1
```

### Ada-style declarative regions inside functions

AdaScript supports Ada-style local declarations within function bodies.
Statements before `begin:` are treated as local declarations:

```nim
def computeWithLocals(x: int) -> int:
  var multiplier = 10
  var offset = 5
  type LocalArray_T = [3]int
  var arr: LocalArray_T

  begin:
    arr = [1, 2, 3]
    result = x * multiplier + offset + arr[0]

computeWithLocals(7)  # returns 76
```

Nested blocks with explicit `declare:`/`begin:` pairs are also supported:

```nim
def nestedFunction(x: int) -> int:
  var outer_val = x * 2
  begin:
    declare:
      var inner_val = outer_val + 10
    begin:
      result = inner_val * 3

nestedFunction(5)  # returns 60
```

### Self type inference

Inside class methods, the `self` parameter type is automatically inferred:

```nim
class Counter:
  var value: int

  def init(self, value: int):      # self inferred as Counter
    self.value = value

  def get_value(self) -> int:      # self inferred as Counter
    self.value

  def increment(self):             # self inferred as var Counter
    self.value += 1
```

For methods that modify `self`, use explicit `var` for clarity:

```nim
def set_value(self: var Counter, value: int):
  self.value = value
```

> **Note:** `proc` still works everywhere -- `def` is fully
> interchangeable, not a replacement.

### Python-style decorators

AdaScript supports Python-style decorators using the `decorated` keyword:

```nim
decorated withInline:
  def fastAdd(x: int, y: int) -> int:
    x + y

decorated logCalls:
  def loggedMultiply(x: int, y: int) -> int:
    x * y
# Output: "Calling loggedMultiply..."
```

Built-in decorators:
- `withInline` - adds `{.inline.}` pragma for performance
- `logCalls` - logs function calls with arguments
- `memoize` - placeholder for caching (full implementation needs cache table)

Custom decorators can be created as compile-time procs:

```nim
proc myDecorator(procDef: NimNode): NimNode {.compileTime.} =
  result = procDef
  # Transform the proc definition at compile-time

decorated myDecorator:
  def foo():
    echo "decorated!"
```

> **Note:** AdaScript uses `decorated` instead of `@` because Nim's prefix
> operators don't work across lines like Python's `@decorator` syntax.

---

## 7. Classes (Python-inspired)

The `class` macro bundles fields and methods into a single block,
generating a Nim object type with public fields and a constructor.

### Recommended Pattern: Type Definition + Init Only

For complex classes with many methods, the **recommended pattern** is to use
the `class` macro **only for the type definition and `init` constructor**,
while keeping other methods as standalone `def` procs:

```nim
class Editor:
  var cx, cy, rx: int
  var rowoff, coloff: int
  var screenrows, screencols: int
  var numrows: int
  var row: seq[string]
  var dirty: bool
  var filename, statusmsg: string

  def init(self: Editor):
    result = Editor(
      cx: 0, cy: 0, rx: 0,
      rowoff: 0, coloff: 0,
      screenrows: 0, screencols: 0,
      numrows: 0, row: @[],
      dirty: false,
      filename: "", statusmsg: ""
    )

# Standalone methods - use `var Editor` for mutating methods
# Note: Nim supports both call syntaxes:
#   editor.insertLine(0, "text")  -- method syntax (recommended)
#   insertLine(editor, 0, "text") -- proc syntax (also works)
def insertLine(self: var Editor, at: int, text: string):
  self.row.insert(text, at)

def getLine(self: Editor, row: int) -> string:
  if row < self.row.len:
    result = self.row[row]
  else:
    result = ""

def save(self: var Editor) =
  let content = self.row.join("\n")
  writeFile(self.filename, content)
  self.dirty = false

# Usage
var editor = newEditor()
editor.insertLine(0, "Hello, World!")
editor.save()
```

**Benefits of this approach:**

1. **Clean constructor generation**: The `class` macro generates `newEditor()` automatically
2. **No macro complexity**: Methods stay as regular procs, avoiding body transformation issues
3. **Clear mutability**: `var Editor` explicitly shows which methods modify state
4. **Better IDE support**: Standard proc signatures work better with tooling
5. **Easier debugging**: Stack traces show actual proc names, not macro expansions
6. **Flexible call syntax**: Use `obj.method()` or `method(obj)` - both work!
7. **Consistent AdaScript style**: Use `def` everywhere for Python-like syntax

**Important:** Methods that modify fields need `self: var Editor` because the
class macro generates a value type (`object of RootObj`), and standalone procs
need explicit `var` to modify their parameters.

### DSL types in class fields

The Odin-style type DSL works directly in class field declarations:

```nim
class Container:
  var items: []int          # seq[int]
  var matrix: [3][4]float   # array[3, array[4, float]]
  var lookup: {string}int   # Table[string, int]
  var tags: {}string        # HashSet[string]

  def init(self: Container):
    self.items = @[]
    self.tags = initHashSet[string]()

  def addItem(self: var Container, item: int):
    self.items.add(item)

  def getItems(self: Container) -> []int:
    self.items
```

### Simple Classes: All Methods Inside

For simple classes with few methods, you can still define everything inside
the class block:

```nim
class Counter:
  var value: int

  def init(self: Counter, initial: int):
    result = Counter(value: initial)

  def increment(self: var Counter):
    inc(self.value)

  def getValue(self: Counter) -> int:
    result = self.value

var c = newCounter(0)
c.increment()
echo c.getValue()  # 1
```

### Inheritance

```nim
class Animal:
  var name: string
  var age: int

  def init(self: Animal, name: string, age: int):
    result = Animal(name: name, age: age)

class Dog(Animal):
  var breed: string

  def init(self: Dog, name: string, age: int, breed: string):
    result = Dog(name: name, age: age, breed: breed)

var d = newDog("Rex", 5, "Labrador")
echo d.name   # "Rex"
echo d.breed  # "Labrador"
```

### Value Semantics

AdaScript classes use Nim's **value semantics** (copy on assignment), not reference
semantics. This is more efficient for small to medium-sized objects:

```nim
class Point:
  var x, y: int
  def init(self: Point, x: int, y: int):
    result = Point(x: x, y: y)

var p1 = newPoint(10, 20)
var p2 = p1  # Copy, not reference
p2.x = 100
echo p1.x  # 10 (unchanged)
echo p2.x  # 100
```

For reference semantics (shared mutable state), use Nim's `ref object` directly:

```nim
type SharedPoint = ref object
  x, y: int

var p1 = SharedPoint(x: 10, y: 20)
var p2 = p1  # Same reference
p2.x = 100
echo p1.x  # 100 (changed)
```

### Call Syntax Flexibility

Nim supports **both** call syntaxes for standalone methods:

```nim
def add(self: Calculator, x: int) -> int:
  result = self.base + x

var calc = newCalculator(10)

# Both work:
echo calc.add(5)    # Method syntax: obj.method(arg) - recommended
echo add(calc, 5)   # Proc syntax: method(obj, arg) - also works
```

The method syntax (`obj.method()`) is generally preferred as it's more
readable and object-oriented.

### Polymorphism (static dispatch)

Regular `class` uses static dispatch. For polymorphic behavior with value types, use generics:

```nim
def printArea[T](shape: T) =
  echo shape.name, ": ", shape.area()

printArea(circle)   # Works with any type that has .name and .area
printArea(rect)
```

### Virtual classes (dynamic dispatch)

Use `virtual class` for true runtime polymorphism. Virtual classes generate
`ref object` types with `method` (instead of `proc`), enabling dynamic dispatch
through base type references:

```nim
virtual class Shape:
  var name: string

  def init(self, name: string):
    self.name = name

  def area(self) -> float:
    0.0

  def describe(self) -> string:
    self.name & ": area=" & $self.area()

virtual class Circle(Shape):
  var radius: float

  def init(self, radius: float):
    self.name = "Circle"
    self.radius = radius

  def area(self) -> float:
    3.14159 * self.radius * self.radius

virtual class Rectangle(Shape):
  var width, height: float

  def init(self, w: float, h: float):
    self.name = "Rectangle"
    self.width = w
    self.height = h

  def area(self) -> float:
    self.width * self.height
```

Dynamic dispatch works through base type references:

```nim
# Pass derived type where base is expected — dispatches at runtime
def printArea(s: Shape) -> float:
  s.area()

var c = newCircle(5.0)
echo printArea(c)  # 78.539... (calls Circle.area, not Shape.area)

# Heterogeneous collections
var shapes: seq[Shape] = @[newCircle(5.0), newRectangle(3.0, 4.0)]
for s in shapes:
  echo s.describe()  # describe() calls area() polymorphically
```

**Key differences from `class`:**

| | `class` | `virtual class` |
|---|---------|-----------------|
| Type | value (`object`) | reference (`ref object`) |
| Dispatch | static (compile-time) | dynamic (runtime vtable) |
| Assign | copy | shared reference |
| Methods | `proc` | `method` with `{.base.}` |

#### Calling the parent with `super`

In a child virtual class, use `super` to call the parent's implementation:

**`super.init(args)`** — runs the parent's field initialization on the current
object (no extra allocation). Like Python's `super().__init__()`:

```nim
virtual class Vehicle:
  var make: string
  var year: int
  def init(self, make: string, year: int):
    self.make = make
    self.year = year

virtual class Car(Vehicle):
  var doors: int
  def init(self, make: string, year: int, doors: int):
    super.init(make, year)   # initialize parent fields
    self.doors = doors
```

**`super.method(args)`** — calls the parent's method, bypassing dynamic dispatch:

```nim
virtual class Logger:
  var prefix: string
  def init(self, prefix: string):
    self.prefix = prefix
  def format(self, msg: string) -> string:
    self.prefix & ": " & msg

virtual class TimestampLogger(Logger):
  var tag: string
  def init(self, prefix: string, tag: string):
    super.init(prefix)
    self.tag = tag
  def format(self, msg: string) -> string:
    "[" & self.tag & "] " & super.format(msg)

var log = newTimestampLogger("APP", "2024")
echo log.format("hello")  # [2024] APP: hello
```

Under the hood: `super.init(args)` calls the parent's initializer proc (field
setup only). `super.method(args)` becomes `procCall ParentType(self).method(args)`.
Both work at any depth of inheritance.

> **Tip:** Use `class` (value types) by default for performance. Use `virtual class`
> when you need runtime polymorphism (heterogeneous collections, plugin systems).

```nim
class Timer:
  var name: string
  var startTime: float

  def init(self: Timer, name: string):
    self.name = name
    self.startTime = 0.0

contextManager(Timer):
  # enter
  self.startTime = epochTime()
  echo "Timer '", self.name, "' started"
do:
  # exit (runs even if an exception is raised)
  let elapsed = epochTime() - self.startTime
  echo "Timer '", self.name, "' finished: ", elapsed, " seconds"
```

### Using `with`

```nim
# Named binding with 'as'
with newTimer("benchmark") as t:
  echo "running: ", t.name
  heavyComputation()
# Timer exit runs here automatically

# Anonymous binding with implicit 'it'
with newTimer("quick"):
  echo it.name
```

The `with` macro generates `try`/`finally` and calls `enter()` on
entry.  On exit it tries `exit()`, then `destroy()`, then `close()`
-- whichever the type provides.

### Multiple resources

```nim
with newTimer("io") as t, newManagedFileHandler("out.txt", fmWrite) as f:
  discard f.writeLine("timed write")
# both resources cleaned up in reverse order
```

---

## 9. Shell command execution

AdaScript includes a powerful `shell` macro for executing shell commands with
Nim-like syntax and full integration with AdaScript features.

### Basic usage

```nim
import adascript

# Simple command
let result = shell: echo "hello"
echo result.output  # "hello"
echo result.exitCode  # 0

# Multiple commands (automatically combined with &&)
let result = shell:
  echo "first"
  echo "second"
```

### Variable interpolation

Use `{variable}` syntax to interpolate Nim variables into shell commands:

```nim
let name = "world"
let result = shell: echo "hello {name}"
# Outputs: "hello world"
```

### Working directory

Execute commands in a specific directory using `cwd` or `workDir`:

```nim
let result = shell(cwd = "/tmp"):
  pwd
  ls -la
```

### Timeout control

Set a timeout in milliseconds:

```nim
let result = shell(timeout = 5000): "long-running-command"
if result.exitCode == 124:
  echo "Command timed out!"
```

### Debug output

Control debug output with `quiet` or custom `debug` options:

```nim
# Quiet mode (default - no debug output)
let result = shell: echo "silent"

# Verbose mode (show all output)
let result = shell(quiet = false):
  make install

# Custom debug options
let result = shell(debug = {dokCommand}):
  echo "show commands only"
```

Debug output kinds:
- `dokCommand` - Show commands before execution
- `dokOutput` - Show command output line by line
- `dokError` - Show error output
- `dokRuntime` - Show runtime errors

### Piping commands

Use `pipe:` to chain commands with pipes:

```nim
let result = shell:
  pipe:
    echo "hello world"
    tr a-z A-Z
# Outputs: "HELLO WORLD"
```

### File redirection

Use raw strings for complex shell syntax like redirection:

```nim
let result = shell:
  "echo 'Line 1' > /tmp/test.txt"
  "echo 'Line 2' >> /tmp/test.txt"
  "cat /tmp/test.txt"
```

### Error handling

Check `exitCode` and `error` for error handling:

```nim
let result = shell: "some-command"
if result.exitCode == 0:
  echo "Success: ", result.output
else:
  echo "Failed: ", result.error
```

### Integration with AdaScript features

The shell macro works seamlessly with other AdaScript features:

```nim
declare shell_test:
  type commands = [3]string
  var cmds: commands

begin:
  cmds = ["echo 1", "echo 2", "echo 3"]
  for i in commands^First .. commands^Last:
    let result = shell: "run {cmds[i]}"
    echo "Command ", i, " result: ", result.output

# With tick attributes
type Status = enum Starting, Running, Done
for s in Status:
  shell: echo "Status: {s}"

# With switch/case
let code = 0
switch code:
  when 0:
    shell: echo "Success"
  when others:
    shell: echo "Error"
```

### Convenience templates

```nim
# Quiet execution
shellQuiet: noisy-command

# Verbose execution
shellVerbose: make install

# Specific directory
shellCwd("/tmp"): pwd

# With timeout
shellTimeout(5000): slow-command
```

### ShellResult type

The `shell` macro returns a `ShellResult` tuple:

```nim
type ShellResult* = tuple[
  output: string,   # Command stdout
  error: string,    # Command stderr
  exitCode: int     # Exit code (0 = success)
]
```


### Getting output as lines

For commands where you want to process output line-by-line, use `shellLines:`:

```nim
# Returns seq[string] instead of ShellResult
let lines = shellLines: ls -la
for line in lines:
  echo "Line: ", line

# Useful for parsing structured output
let statusLines = shellLines: show_tests_status
for line in statusLines:
  if line.contains("SUCCESS"):
    echo "Test passed: ", line
```

This is equivalent to `shell: command.output.splitLines()` but more convenient.

---

## 11. Utility extras

```nim
# Optional type shorthand
var x: ?int                # expands to Option[int]
var y: opt(int)            # also works (legacy)

# None for absent values
var z: ?string = None      # none(string)
if z == None:
  echo "no value"

# String concatenation with +
let greeting = "hello" + " world"

# String repetition with *
let line = "=" * 60
```

---

## 10. Design rationale

### Why Odin for type declarations?

Odin's type syntax reads naturally from left to right.
*"a 3x4 matrix of ints"* becomes `[3][4]int` -- you read the
dimensions first, then the element type.

In standard Nim, the same type is `array[3, array[4, int]]`.
At three levels of nesting the difference is stark:

```
Nim:   seq[array[1..5, seq[char]]]
AdaScript:  [][1..5][]char
```

The AdaScript form stays flat regardless of depth.  The curly-brace
extensions (`{K}V` for tables, `{}T` for sets) follow the same
principle and mirror Odin's map syntax.

### Why Ada for attributes and scoping?

Ada's tick attributes are an elegant, well-proven notation that has
been in production use since 1983.  Replacing Nim's free-function
style (`low(T)`, `high(T)`, `succ(x)`) with a postfix operator
creates a more uniform, discoverable syntax:

```nim
# Nim standard               # AdaScript
low(Color)                    Color ^ First
high(Color)                   Color ^ Last
succ(Green)                   Green ^ Succ
```

The `declare`/`begin` block structure enforces a clear boundary
between *what exists* and *what happens* -- a discipline that Ada
developers have valued for decades.  In larger Nim programs, this
separation prevents declarations from being scattered among logic.

### Why Python for classes and context managers?

Nim's native object system is powerful but spreads type definitions,
constructors and methods across separate sections.  The `class` macro
groups everything in one block, and `def` with `->` return types
matches the mental model most programmers already have from Python.

The `with` statement and context-manager protocol bring Python's
well-known resource-management pattern to Nim, complementing its
native `defer` with structured enter/exit semantics.

---

## 10. Template Method Pattern

The Template Method Pattern defines an algorithm skeleton in a base class,
with child classes overriding specific steps. Use `virtual class` for this:

```nim
virtual class DataProcessor:
  var data: string

  def init(self, data: string):
    self.data = data

  def validate(self) -> string:
    "raw"

  def transform(self) -> string:
    self.data

  def format(self) -> string:
    self.data

  # Template method: calls virtual methods that children override
  def process(self) -> string:
    let v = self.validate()
    let t = self.transform()
    let f = self.format()
    "[" & v & "] {" & t & "} (" & f & ")"

virtual class CSVProcessor(DataProcessor):
  def init(self, data: string):
    self.data = data
  def validate(self) -> string: "csv-ok"
  def transform(self) -> string: self.data.toUpperAscii()

virtual class JSONProcessor(DataProcessor):
  def init(self, data: string):
    self.data = data
  def validate(self) -> string: "json-ok"
  def format(self) -> string: "{" & self.data & "}"

# Template method dispatches to overrides at runtime
var csv: DataProcessor = newCSVProcessor("a,b,c")
echo csv.process()  # [csv-ok] {A,B,C} (a,b,c)

var json: DataProcessor = newJSONProcessor("key:val")
echo json.process()  # [json-ok] {key:val} ({key:val})
```

### Key Points

- `virtual class` generates `ref object` + `method` (dynamic dispatch)
- Base class methods get `{.base.}` automatically
- Child classes override by defining a method with the same name
- Use `super.method()` to call the parent's implementation
- The template method (`process`) calls virtual methods that dispatch at runtime

See `TEST/test_virtual.nim` for complete working examples.

---

## 11. Design rationale

### Why Odin for type declarations?

Odin's type syntax reads naturally from left to right.
*"a 3x4 matrix of ints"* becomes `[3][4]int` -- you read the
dimensions first, then the element type.

In standard Nim, the same type is `array[3, array[4, int]]`.
At three levels of nesting the difference is stark:

```
Nim:   seq[array[1..5, seq[char]]]
AdaScript:  [][1..5][]char
```

The AdaScript form stays flat regardless of depth.  The curly-brace
extensions (`{K}V` for tables, `{}T` for sets) follow the same
principle and mirror Odin's map syntax.

### Why Ada for attributes and scoping?

Ada's tick attributes are an elegant, well-proven notation that has
been in production use since 1983.  Replacing Nim's free-function
style (`low(T)`, `high(T)`, `succ(x)`) with a postfix operator
creates a more uniform, discoverable syntax:

```nim
# Nim standard               # AdaScript
low(Color)                    Color ^ First
high(Color)                   Color ^ Last
succ(Green)                   Green ^ Succ
```

The `declare`/`begin` block structure enforces a clear boundary
between *what exists* and *what happens* -- a discipline that Ada
developers have valued for decades.  In larger Nim programs, this
separation prevents declarations from being scattered among logic.

### Why Python for classes and context managers?

Nim's native object system is powerful but spreads type definitions,
constructors and methods across separate sections.  The `class` macro
groups everything in one block, and `def` with `->` return types
matches the mental model most programmers already have from Python.

The `with` statement and context-manager protocol bring Python's
well-known resource-management pattern to Nim, complementing its
native `defer` with structured enter/exit semantics.

---

## 12. Quick reference

| Feature | AdaScript syntax | Expands to |
|---------|-------------|------------|
| Fixed array | `[8]int` | `array[8, int]` |
| Sequence | `[]int` | `seq[int]` |
| Nested | `[3][]int` | `array[3, seq[int]]` |
| Table | `{string}int` | `Table[string, int]` |
| Set | `{}char` | `set[char]` |
| Declare block | `declare: ... begin: ...` | scoped `block` |
| Globals | `globals: ...` | module-level declarations |
| Type first | `Color ^ First` | `low(Color)` |
| Type last | `Color ^ Last` | `high(Color)` |
| Successor | `val ^ Succ` | `succ(val)` |
| Predecessor | `val ^ Pred` | `pred(val)` |
| Position | `val ^ Pos` | `ord(val)` |
| Length | `Type ^ Length` | element count |
| Case | `switch x: when v: ... when others: ...` | `case x: of v: ... else: ...` |
| DSL in def params | `def f(x: []int): ...` | `proc f*(x: seq[int])` |
| DSL in def return | `def f() -> []string: ...` | `proc f*(): seq[string]` |
| DSL in class field | `var items: []int` | `items*: seq[int]` |
| Function | `def name(params) -> T: ...` | `proc name*(params): T` |
| Generic function | `def name[T](x: T) -> T: ...` | `proc name*[T](x: T): T` |
| Default value | `def f(x: int ~ 5): ...` | `proc f*(x: int = 5)` |
| Pragma | `def f(x: int) -> int {.pure.}: ...` | `proc f*(x: int): int {.pure.}` |
| Varargs | `def f(xs: varargs[int]): ...` | `proc f*(xs: varargs[int])` |
| Ada-style in def | `def f(): var x = 1 begin: ...` | `block: var x = 1; ...` |
| Decorator | `decorated logCalls: def f(): ...` | `proc f*() = echo "..."; ...` |
| Class | `class Name(Parent): ...` | `type Name* = object of Parent` |
| Virtual class | `virtual class Name: ...` | `type Name* = ref object of RootObj` + `method` |
| Super init | `super.init(args)` | `initParent(self, args)` (no allocation) |
| Super call | `super.method(args)` | `procCall Parent(self).method(args)` |
| Constructor | `def init(self: Name, ...): ...` | `proc newName*(...): Name` |
| With | `with expr as v: ...` | `try/finally` with enter/exit |
| Optional type | `?int` | `Option[int]` |
| Optional seq | `?[]int` | `Option[seq[int]]` |
| Seq of optional | `[]?int` | `seq[Option[int]]` |
| None check | `x == None` | `x.isNone` |
| Return value | `return "Alice"` | `return some("Alice")` (in `?T` def) |
| Return None | `return None` | `return none(T)` (in `?T` def) |
| Optional (legacy) | `opt(T)` | `Option[T]` |
| Shell command | `shell: echo "hi"` | `execShell("echo \"hi\"")` |
| Shell with cwd | `shell(cwd = "/tmp"): pwd` | `execShell("cd /tmp && pwd")` |
| Shell with timeout | `shell(timeout = 5000): cmd` | `execShell(cmd, timeoutMs=5000)` |
| Shell pipe | `shell: pipe: a \| b` | `a \| b` |
| Shell variable | `shell: echo "{name}"` | `&"echo \"{name}\""` |
| Super call | `super().init(args)` | `Parent.init(self, args)` |
| Self inference | `def init(self, x: int)` | `def init(self: ClassName, x: int)` |

---

## 13. Testing

Test files are located in the `TEST/` directory:

```
TEST/
├── nim.cfg               # Path to parent directory
├── test_hnim.nim         # Main smoke tests
├── test_declare_begin.nim # Declare/begin tests (20 tests)
└── test_shell.nim        # Shell module tests (15 tests)
```

### Running Tests

```bash
cd HNIM/TEST
nim --hints:off r test_adascript.nim
nim --hints:off r test_declare_begin.nim
nim --hints:off r test_shell.nim
```

### Test Coverage

- **test_hnim.nim**: Type DSL, declare/begin, tick attributes, def features, decorators, classes, inheritance, polymorphism, with statement
- **test_declare_begin.nim**: Nested blocks, variable shadowing, type definitions, Ada-style in functions, nested declare/begin
- **test_shell.nim**: Basic commands, variable interpolation, piping, working directory, timeout, error handling, AdaScript integration
- **test_virtual.nim**: Virtual classes, dynamic dispatch, heterogeneous collections, reference semantics

---

## File structure

```
HNIM/
  adascript.nim                 # entry point -- import this
  adascript_declarations.nim    # declare/begin blocks, Odin type DSL
  adascript_attributes.nim      # Ada tick attributes via ^
  adascript_case.nim            # switch / when / when others
  adascript_classes.nim         # def, class, with, contextManager, super()
  shell.nim                     # shell command execution
  TEST/
    nim.cfg                     # Path configuration
    test_adascript.nim          # smoke test
    test_declare_begin.nim      # declare/begin tests
    test_shell.nim              # shell module tests
    test_virtual.nim            # virtual class tests
  doc/ADASCRIPT.md              # this file
```

## Requirements

- Nim >= 2.2 (tested on 2.2.8)
- No external dependencies beyond Nim's standard library

### Static vs Dynamic Dispatch

**AdaScript classes use static dispatch** (compile-time method resolution):

```nim
class Shape:
  var name: string
  def init(self: Shape, name: string):
    result = Shape(name: name)

def area(self: Shape) -> float:
  result = 0.0

class Circle(Shape):
  var radius: float
  def init(self: Circle, name: string, radius: float):
    result = Circle(name: name, radius: radius)

def area(self: Circle) -> float:
  result = 3.14159 * self.radius * self.radius

var circle = newCircle("Circle", 5.0)
echo circle.area()      # 78.54 - Static dispatch (fast!)

# Via generics - still static dispatch
def printArea[T](shape: T):
  echo shape.name, ": ", shape.area()

printArea(circle)       # 78.54 - Works via generics

# WARNING: Object slicing when using base type!
def processShape(shape: Shape):
  echo shape.area()     # Calls Shape.area(), NOT Circle.area()!

processShape(circle)    # 0.0 - Lost Circle's data!
```

**For true runtime polymorphism**, use `virtual class`:

```nim
# Use virtual class for dynamic dispatch:
virtual class ShapeV:
  var name: string
  def init(self, name: string):
    self.name = name
  def area(self) -> float: 0.0

virtual class CircleV(ShapeV):
  var radius: float
  def init(self, radius: float):
    self.name = "Circle"
    self.radius = radius
  def area(self) -> float:
    3.14159 * self.radius * self.radius

var shape: ShapeV = newCircleV(5.0)
echo shape.area()  # 78.54 - Dynamic dispatch! Correct method called at runtime.
```

| Feature | `class` | `virtual class` |
|---------|---------|-----------------|
| Dispatch | Static (compile-time) | Dynamic (runtime) |
| Performance | Faster (no vtable) | Virtual table lookup |
| Object Slicing | Yes (value copy) | No (reference) |
| Polymorphism | Via generics | Via inheritance |
| Use Case | Most cases, performance-critical | Runtime polymorphism needed |

> **Recommendation:** Use `class` with generics for most cases. 
> Use `virtual class` when you need true runtime polymorphism
> (e.g., heterogeneous collections, plugin architectures).
