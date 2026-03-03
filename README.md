# AdaScript

**Ada/Python-style syntax extensions for Nim**

AdaScript provides a collection of Nim macros that enable more expressive, readable code by borrowing syntax patterns from Ada, Python, and Odin.

## Features

### 1. Odin-style Type DSL

Concise type declarations using bracket syntax:

```nim
import adascript

declare:
  type MyArray = [8]int           # array[8, int]
  type MySeq = []string           # seq[string]
  type MyTable = {string}int      # Table[string, int]
  type MySet = {}char             # set[char] or HashSet[char]
  var arr: MyArray
  var tbl: MyTable
```

### 2. Ada-style Declare/Begin Blocks

Separate declarations from statements, Ada-style:

```nim
declare:
  type Matrix = [3][4]float
  var m: Matrix
  x: int = 5

begin:
  m = [[1.0, 2.0, 3.0, 4.0],
       [5.0, 6.0, 7.0, 8.0],
       [9.0, 10.0, 11.0, 12.0]]
  print "Matrix: ", m
```

### 3. Ada-style Tick Attributes

Access enum and sequence metadata with `^` operator:

```nim
type Color = enum Red, Green, Blue

print Color^First    # Red
print Color^Last     # Blue
print Color^Length   # 3

for c in Color:
  print c
```

### 4. Ada-style Switch/Case

Clean case statements with `when` and `when others`:

```nim

let person = ("Alice", 30, true)

switch person:
  when ("Alice", _, true):
    print "Alice is employed"
  when (_, 30, _):
    print "Someone is 30 years old"
  when (_, _, false):
    print "Someone is not employed"
  when others:
    print "I don’t know"  
```

### 5. Optional Types with `?`

Nim's `Option[T]` is powerful but verbose. AdaScript makes it first-class
with `?` syntax, `None`, and automatic wrapping -- inspired by
TypeScript, Kotlin, and Swift:

| AdaScript | Nim | 
|-----------|-----|
| `?string` | `Option[string]` |
| `?[]int` | `Option[seq[int]]` |
| `[]?int` | `seq[Option[int]]` |
| `return "hello"` | `return some("hello")` |
| `return None` | `return none(string)` |
| `var x: ?int = None` | `var x: Option[int] = none(int)` |
| `if x != None:` | `if x.isSome:` |

**Side-by-side comparison:**

```nim
# -------- Standard Nim --------
import options

proc findUser(id: int): Option[string] =
  if id == 1:
    return some("Alice")
  return none(string)

let user = findUser(1)
if user.isSome:
  print "Found: ", user.get

var cache: Option[seq[string]] = none(seq[string])

# -------- AdaScript --------
import adascript

def findUser(id: int) -> ?string:
  if id == 1:
    return "Alice"
  return None

let user = findUser(1)
if user != None:
  print "Found: ", user.get

globals:
  var cache: ?[]string = None
```

Optional types work everywhere: `globals:`, `declare:`, `def` parameters,
return types, class fields, and declaration sections inside functions.

### 6. Python-style `def` Functions

Python-like function syntax with full DSL type support:

```nim
def greet(name: string) -> string:
  "Hello, " & name

def add[T](a: T, b: T) -> T:
  a + b

def greet2(name: string ~ "world") -> string:
  "Hello, " & name

# DSL types work in parameters and return types
def getNames() -> []string:           # returns seq[string]
  @["Alice", "Bob"]

def sumAll(nums: []int) -> int:       # accepts seq[int]
  var total = 0
  for n in nums: total += n
  total

def getTriple() -> [3]int:            # returns array[3, int]
  [10, 20, 30]
```

### 7. Python-style Classes

Class definitions with inheritance and DSL field types:

```nim
class Animal:
  var name: string
  var age: int
  var tags: []string        # DSL: seq[string] works in fields
  var nickname: ?string     # DSL: Option[string]

  def init(self, name: string, age: int):
    self.name = name
    self.age = age

  def speak(self) -> string:
    self.name & " makes a sound"

class Dog(Animal):
  var breed: string

  def init(self, name: string, age: int, breed: string):
    self.name = name
    self.age = age
    self.breed = breed

  def speak(self) -> string:
    self.name & " barks"
```

### 8. Virtual Classes (Dynamic Dispatch)

Use `virtual class` for runtime polymorphism — generates `ref object` + `method`:

```nim
virtual class Shape:
  var name: string
  def init(self, name: string):
    self.name = name
  def area(self) -> float: 0.0

virtual class Circle(Shape):
  var radius: float
  def init(self, r: float):
    self.name = "Circle"
    self.radius = r
  def area(self) -> float:
    3.14159 * self.radius * self.radius

# Dynamic dispatch through base type
var shapes: seq[Shape] = @[newCircle(5.0), newCircle(1.0)]
for s in shapes:
  print s.area()  # calls Circle.area(), not Shape.area()
```

### 9. Shell Command Execution

Run shell commands with full integration:

```nim
# Basic usage
let result = shell: print "hello"
print result.output

# Variable interpolation
let name = "world"
let result = shell: print "hello {name}"

# Get output as lines
let lines = shellLines: ls -la
for line in lines:
  print line

# Working directory
let result = shell(cwd = "/tmp"): pwd

# Timeout
let result = shell(timeout = 5000): slow-command
```

### 10. Loop Statement

Ada-style infinite loop:

```nim
loop:
  print "Running..."
  if done:
    break
```

## Installation

### Requirements

- Nim 2.0+
- Standard Nim toolchain

### Setup

1. Clone or download this repository

2. Add HNIM to your project path:
   ```bash
   export NIM_PATH="$NIM_PATH:/path/to/HNIM"
   ```

3. Or copy `adascript.nim` and supporting files to your project

4. Import in your Nim code:
   ```nim
   import adascript
   ```

## Usage Examples

### Complete Example

```nim
import adascript

# Module-level declarations with DSL types
globals:
  type Config = {string}string
  var cfg: Config

cfg["host"] = "localhost"
cfg["port"] = "8080"

# Functions with def, default values, and optional types
def connect(host: string, port: ?int) -> ?string:
  if port == None:
    return None
  return host & ":" & $port.get

let addr = connect("localhost", some(8080))
if addr != None:
  print "Connected to ", addr.get

# Shell commands with variable interpolation
let lines = shellLines: print "test"; print "output"
for line in lines:
  print "Line: ", line

# Ada-style loop
var count = 0
loop:
  inc count
  if count >= 5:
    break

print "Done!"
```

### Test Suite

Run the test suite:

```bash
cd TEST
nim c -p:../ -r test_adascript.nim
nim c -p:../ -r test_shell.nim
nim c -p:../ -r test_declare_begin.nim
nim c -p:../ -r test_features.nim
```

## Documentation

See [ADASCRIPT.md](doc/ADASCRIPT.md) for complete documentation including:
- Detailed syntax reference
- All supported features
- Design rationale
- Pattern examples

## License

MIT License - See LICENSE file for details

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Add tests for new features
4. Submit a pull request

## Acknowledgments

AdaScript draws inspiration from:
- **Ada** - declare/begin blocks, tick attributes, case statements
- **Python** - def functions, classes, with statement
- **Odin** - Type DSL syntax with brackets
