#!/usr/bin/env -S nim --hints:off r
# Test for AdaScript class macro - partial usage pattern
# Using class macro for type definition + init only, with standalone def methods
import adascript

# ============================================================================
# Test 1: Simple class with standalone def methods
# ============================================================================
echo "--- Test: Class with Standalone Def Methods ---"

class Counter:
  var value: int
  def init(self: Counter, initial: int):
    result = Counter(value: initial)

# Standalone def methods - use `:` syntax (AdaScript Python-style)
def increment(self: var Counter):
  inc(self.value)

def getValue(self: Counter) -> int:
  result = self.value

def reset(self: var Counter):
  self.value = 0

var c = newCounter(0)
c.increment()
c.increment()
assert c.getValue() == 2, "Counter should be 2"
c.reset()
assert c.getValue() == 0, "Counter should be 0 after reset"
echo "✓ Counter class with standalone def methods passed"

# ============================================================================
# Test 2: Complex class with mutating and non-mutating methods
# ============================================================================
echo ""
echo "--- Test: Complex Class with var Editor ---"

class TextBuffer:
  var lines: seq[string]
  var cursorX, cursorY: int
  var dirty: bool
  var filename: string
  def init(self: TextBuffer):
    result = TextBuffer(
      lines: @[],
      cursorX: 0,
      cursorY: 0,
      dirty: false,
      filename: ""
    )

# Mutating methods need `var TextBuffer`
def insertLine(self: var TextBuffer, at: int, text: string):
  self.lines.insert(text, at)
  self.dirty = true

def deleteLine(self: var TextBuffer, at: int):
  if at < self.lines.len:
    self.lines.delete(at)
    self.dirty = true

def setFilename(self: var TextBuffer, name: string):
  self.filename = name

# Non-mutating methods can use immutable `TextBuffer`
def getLine(self: TextBuffer, at: int) -> string:
  if at < self.lines.len:
    result = self.lines[at]
  else:
    result = ""

def lineCount(self: TextBuffer) -> int:
  result = self.lines.len

def isDirty(self: TextBuffer) -> bool:
  result = self.dirty

# Test it
var buf = newTextBuffer()
buf.insertLine(0, "First line")
buf.insertLine(1, "Second line")
assert buf.lineCount() == 2, "Should have 2 lines"
assert buf.getLine(0) == "First line", "First line mismatch"
assert buf.getLine(1) == "Second line", "Second line mismatch"
assert buf.isDirty() == true, "Should be dirty"
buf.setFilename("test.txt")
assert buf.filename == "test.txt", "Filename mismatch"
buf.deleteLine(0)
assert buf.lineCount() == 1, "Should have 1 line after delete"
echo "✓ TextBuffer class with var methods passed"

# ============================================================================
# Test 3: Class with inheritance and standalone def methods
# ============================================================================
echo ""
echo "--- Test: Inheritance with Standalone Def Methods ---"

class Shape:
  var name: string
  var x, y: float
  def init(self: Shape, name: string, x: float, y: float):
    result = Shape(name: name, x: x, y: y)

class Circle(Shape):
  var radius: float
  def init(self: Circle, x: float, y: float, radius: float):
    result = Circle(name: "Circle", x: x, y: y, radius: radius)

# Standalone def for Circle - call with method syntax: circle.getArea()
def getArea(self: Circle) -> float:
  result = 3.14159 * self.radius * self.radius

def getCircumference(self: Circle) -> float:
  result = 2.0 * 3.14159 * self.radius

var circle = newCircle(10.0, 20.0, 5.0)
assert circle.name == "Circle", "Name should be Circle"
assert circle.x == 10.0, "X position mismatch"
assert circle.y == 20.0, "Y position mismatch"
assert abs(circle.getArea() - 78.53975) < 0.01, "Area calculation wrong"
assert abs(circle.getCircumference() - 31.4159) < 0.01, "Circumference wrong"
echo "✓ Inheritance with standalone def methods passed"

# ============================================================================
# Test 4: Value semantics (AdaScript classes use value types, not ref types)
# ============================================================================
echo ""
echo "--- Test: Value Semantics ---"

class Point:
  var x, y: int
  def init(self: Point, x: int, y: int):
    result = Point(x: x, y: y)

def move(self: var Point, dx: int, dy: int):
  self.x += dx
  self.y += dy

var p1 = newPoint(10, 20)
var p2 = p1  # Copy, not reference (value semantics)
p2.move(5, 5)
assert p1.x == 10 and p1.y == 20, "p1 should be unchanged (value semantics)"
assert p2.x == 15 and p2.y == 25, "p2 should be moved"
echo "✓ Value semantics test passed"

# ============================================================================
# Test 5: Verify both call syntaxes work
# ============================================================================
echo ""
echo "--- Test: Call Syntax Flexibility ---"

class Calculator:
  var base: int
  def init(self: Calculator, b: int):
    result = Calculator(base: b)

def add(self: Calculator, x: int) -> int:
  result = self.base + x

var calc = newCalculator(10)
# Both syntaxes work in Nim!
assert calc.add(5) == 15, "Method syntax should work"
assert add(calc, 5) == 15, "Proc syntax should work"
echo "✓ Both call syntaxes work (calc.add(5) and add(calc, 5))"

echo ""
echo "=== All class partial usage tests passed ==="

# ============================================================================
# Test 6: Static vs Dynamic Dispatch
# ============================================================================
echo ""
echo "--- Test: Static vs Dynamic Dispatch ---"

# Static dispatch with AdaScript classes
class BaseShape:
  var name: string
  def init(self: BaseShape, name: string):
    result = BaseShape(name: name)

def getArea(self: BaseShape) -> float:
  result = 0.0

class CircleShape(BaseShape):
  var radius: float
  def init(self: CircleShape, name: string, radius: float):
    result = CircleShape(name: name, radius: radius)

def getArea(self: CircleShape) -> float:
  result = 3.14159 * self.radius * self.radius

var circleShape = newCircleShape("Circle", 5.0)
assert circleShape.getArea() == 78.53975, "Direct call should work"

# Via generic - static dispatch
def processShapeGeneric[T](shape: T) -> float:
  shape.getArea()

assert processShapeGeneric(circleShape) == 78.53975, "Generic should work"

# Object slicing warning - base type parameter loses derived data
def processShapeBase(shape: BaseShape) -> float:
  shape.getArea()

assert processShapeBase(circleShape) == 0.0, "Object slicing: calls BaseShape.getArea()"

echo "✓ Static dispatch test passed (direct and generic work, slicing warned)"
