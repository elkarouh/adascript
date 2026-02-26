#!/usr/bin/env -S nim --hints:off r
import adascript

# Smoke test for AdaScript modules

# 1. Test declare/begin with type DSL
declare:
  type MyArr_T = [3]int
  type MySeq_T = []string
  type MyTbl_T = {string}int
  type MySet_T = {}char
  var arr: MyArr_T
  var tbl: MyTbl_T
  var cs: MySet_T

begin:
  arr = [10, 20, 30]
  print "declare/begin: arr = ", arr

  tbl["alice"] = 30
  print "table: ", tbl

  cs.incl('a')
  cs.incl('z')
  print "set: ", cs

  static:
    assert MyArr_T is array[3, int]
    assert MySeq_T is seq[string]
    assert MyTbl_T is Table[string, int]

# Test nested array types
declare nested:
  type Matrix2d_T = [3][4]int
  type SeqOfArrays_T = [3][]string
  type ArrayOfSeqs_T = [][]int
  type NestedSeq_T = [][]string
  var m: Matrix2d_T
  var soa: SeqOfArrays_T
  var aos: ArrayOfSeqs_T
  var ns: NestedSeq_T

begin:
  m = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12]]
  print "nested: matrix2d = ", m

  static:
    assert Matrix2d_T is array[3, array[4, int]]
    assert SeqOfArrays_T is array[3, seq[string]]
    assert ArrayOfSeqs_T is seq[seq[int]]
    assert NestedSeq_T is seq[seq[string]]

# 2. Test tick attributes
type Color_T = enum Red, Green, Blue, Yellow
echo "Color_T^First: ", Color_T^First
echo "Color_T^Last: ", Color_T^Last
echo "Color_T^Length: ", Color_T^Length
let g = Green
echo "Green^Succ: ", g^Succ
echo "Green^Pos: ", g^Pos

# Test tick attributes on range types
type Temp_T = range[-5..5]
echo "Temp_T^First: ", Temp_T^First
echo "Temp_T^Last: ", Temp_T^Last
echo "Temp_T^Size: ", Temp_T^Size
let t: Temp_T = 0
echo "t^Succ: ", t^Succ
echo "t^Pred: ", t^Pred

# Test tick attributes on array types
let scores: array[1..10, int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
echo "scores^Length: ", scores^Length
echo "array[1..10, int]^First: ", array[1..10, int]^First
echo "array[1..10, int]^Last: ", array[1..10, int]^Last

# Test tickRange iterator
echo "Iterating Color_T.tickRange():"
for c in Color_T.tickRange():
  echo "  ", c

echo "Iterating Temp_T.tickRange():"
for i in Temp_T.tickRange():
  echo "  ", i

# Test boundary checks for Succ/Pred
try:
  discard Red^Pred
  echo "ERROR: Should have raised RangeDefect for Red^Pred"
except RangeDefect:
  echo "Correctly raised RangeDefect for Red^Pred"

try:
  discard Yellow^Succ
  echo "ERROR: Should have raised RangeDefect for Yellow^Succ"
except RangeDefect:
  echo "Correctly raised RangeDefect for Yellow^Succ"

# 3. Test defCase
let x = 2
switch x:
  when 1: echo "case: One"
  when 2: echo "case: Two"
  when others: echo "case: Other"

# 4. Test def features

# basic def with return type
def double(x: int) -> int:
  x * 2
assert double(7) == 14
echo "def basic: double(7) = ", double(7)

# def with generics
def identity[T](x: T) -> T:
  x
assert identity(42) == 42
assert identity("hi") == "hi"

print "def generics: identity(42) = ", identity(42)

# def with default values using ~
def greet(name: string ~ "world") -> string:
  "hello " & name
assert greet() == "hello world"
assert greet("Ada") == "hello Ada"
print "def defaults: greet() = ", greet()

# def with varargs
def total(nums: varargs[int]) -> int:
  var s = 0
  for n in nums: s += n
  s
assert total(1, 2, 3) == 6
print "def varargs: total(1,2,3) = ", total(1, 2, 3)

# def with pragma
def pureAdd(a: int, b: int) -> int {.noSideEffect.}:
  a + b
assert pureAdd(3, 4) == 7
print "def pragma: pureAdd(3,4) = ", pureAdd(3, 4)

# def with multi-param same type
def sum3(a, b, c: int) -> int:
  a + b + c
assert sum3(1, 2, 3) == 6
print "def multi-param: sum3(1,2,3) = ", sum3(1, 2, 3)

# 4b. Test def with DSL types in parameters and return types
echo ""
echo "--- DSL Types in def Parameters and Return Types ---"

# def with []T return type (seq)
def getNames() -> []string:
  @["Alice", "Bob", "Charlie"]

let dslNames = getNames()
assert dslNames.len == 3
assert dslNames[0] == "Alice"
print "def DSL return []string: ", dslNames

# def with []T parameter type (seq)
def sumAll(nums: []int) -> int:
  var t = 0
  for n in nums: t += n
  t

assert sumAll(@[1, 2, 3]) == 6
print "def DSL param []int: sumAll(@[1,2,3]) = ", sumAll(@[1, 2, 3])

# def with [N]T return type (fixed array)
def getTriple() -> [3]int:
  [10, 20, 30]

let dslTriple = getTriple()
assert dslTriple[0] == 10
assert dslTriple[2] == 30
print "def DSL return [3]int: ", dslTriple

# def with {K}V parameter type (Table)
def lookupAge(table: {string}int, key: string) -> int:
  table[key]

var dslAges = {"Alice": 30, "Bob": 25}.toTable
assert lookupAge(dslAges, "Alice") == 30
print "def DSL param {string}int: lookupAge = ", lookupAge(dslAges, "Alice")

# def with {}T parameter type (HashSet)
def hasTag(tags: {}string, tag: string) -> bool:
  tags.contains(tag)

var dslTags: HashSet[string]
dslTags.incl("nim")
dslTags.incl("adascript")
assert hasTag(dslTags, "nim")
assert not hasTag(dslTags, "python")
print "def DSL param {}string: hasTag(nim) = ", hasTag(dslTags, "nim")

# varargs still works (regression check)
def totalVarargs(nums: varargs[int]) -> int:
  var s = 0
  for n in nums: s += n
  s

assert totalVarargs(1, 2, 3) == 6
print "def varargs regression: totalVarargs(1,2,3) = ", totalVarargs(1, 2, 3)

echo "✓ DSL types in def parameters and return types passed"
echo ""

# 4c. Test class with DSL types in fields
echo "--- DSL Types in Class Fields ---"

class DslContainer:
  var items: []int
  var data: [5]int

  def init(self: DslContainer):
    self.items = @[]

  def addItem(self: var DslContainer, item: int):
    self.items.add(item)

  def getItems(self: DslContainer) -> []int:
    self.items

var dc = newDslContainer()
dc.addItem(10)
dc.addItem(20)
dc.addItem(30)
let dcItems = dc.getItems()
assert dcItems.len == 3
assert dcItems[0] == 10
print "class DSL field []int: items = ", dcItems

dc.data = [1, 2, 3, 4, 5]
assert dc.data[2] == 3
print "class DSL field [5]int: data = ", dc.data

echo "✓ DSL types in class fields passed"
echo ""

# 5. Test class
class Animal:
  var name: string
  var age: int

  def init(self, name: string, age: int):
    self.name = name
    self.age = age

  def speak(self) -> string:
    self.name & " says hello"

class Dog(Animal):
  var breed: string

  def init(self, name: string, age: int, breed: string):
    self.name = name
    self.age = age
    self.breed = breed

  def speak(self) -> string:
    self.name & " barks"

var d = newDog("Rex", 5, "Labrador")
print "class: ", d.speak()

# ============================================================================
# 5b. Test class inheritance and polymorphism
# ============================================================================
echo ""
echo "--- Inheritance and Polymorphism Tests ---"

# Base class with virtual method
class Shape:
  var name: string
  var x: float
  var y: float

  def init(self, name: string, x: float, y: float):
    self.name = name
    self.x = x
    self.y = y

  def area(self) -> float:
    0.0

  def description(self) -> string:
    self.name & " at (" & $self.x & ", " & $self.y & ")"

# Derived class: Circle
class Circle(Shape):
  var radius: float

  def init(self, x: float, y: float, radius: float):
    self.name = "Circle"
    self.x = x
    self.y = y
    self.radius = radius

  def area(self) -> float:
    3.14159 * self.radius * self.radius

  def circumference(self) -> float:
    2.0 * 3.14159 * self.radius

# Derived class: Rectangle
class Rectangle(Shape):
  var width: float
  var height: float

  def init(self, x: float, y: float, width: float, height: float):
    self.name = "Rectangle"
    self.x = x
    self.y = y
    self.width = width
    self.height = height

  def area(self) -> float:
    self.width * self.height

  def perimeter(self) -> float:
    2.0 * (self.width + self.height)

# Derived class: Triangle
class Triangle(Shape):
  var base: float
  var height: float

  def init(self, x: float, y: float, base: float, height: float):
    self.name = "Triangle"
    self.x = x
    self.y = y
    self.base = base
    self.height = height

  def area(self) -> float:
    0.5 * self.base * self.height

# Test basic inheritance
echo "Creating shapes..."
var circle = newCircle(0.0, 0.0, 5.0)
var rect = newRectangle(10.0, 20.0, 4.0, 6.0)
var tri = newTriangle(5.0, 5.0, 3.0, 4.0)

echo "Circle: ", circle.description(), ", radius = ", circle.radius
echo "Circle area: ", circle.area()
echo "Circle circumference: ", circle.circumference()

echo "Rectangle: ", rect.description(), ", " , rect.width, "x", rect.height
echo "Rectangle area: ", rect.area()
echo "Rectangle perimeter: ", rect.perimeter()

echo "Triangle: ", tri.description(), ", base = ", tri.base, ", height = ", tri.height
echo "Triangle area: ", tri.area()

# Note: In Nim, true runtime polymorphism requires ref objects or templates
# For AdaScript classes, we test that derived methods work correctly
echo ""
echo "Direct polymorphic method calls:"

def printShapeInfo(s: Shape) -> string:
  ## Generic function that works with any Shape
  s.description() & ", area = " & $s.area()

# Test with each shape type
echo "Circle via Shape: ", printShapeInfo(circle)
echo "Rectangle via Shape: ", printShapeInfo(rect)
echo "Triangle via Shape: ", printShapeInfo(tri)

# Test method overriding
echo ""
echo "Method overriding test:"
echo "Circle.area() returns: ", circle.area()
echo "Rectangle.area() returns: ", rect.area()
echo "Triangle.area() returns: ", tri.area()

# Verify area calculations
assert abs(circle.area() - 78.53975) < 0.01
assert abs(rect.area() - 24.0) < 0.01
assert abs(tri.area() - 6.0) < 0.01

echo ""
echo "✓ Inheritance and polymorphism tests passed"

# 6. Test with statement + context manager
class Timer:
  var name: string
  var startTime: float

  def init(self, name: string):
    self.name = name
    self.startTime = 0.0

contextManager(Timer):
  self.startTime = epochTime()
  print "Timer '", self.name, "' started"
do:
  let elapsed = epochTime() - self.startTime
  print "Timer '", self.name, "' finished: ", elapsed.formatFloat(ffDecimal, 3), " seconds"

with newTimer("smoke test") as t:
  print "  inside with block, timer: ", t.name

print ""
print "All AdaScript smoke tests passed!"

# ============================================================================
# Test AdaScript DSL with string-keyed tables and sets
# ============================================================================

# Test {string}int -> Table[string, int]
declare:
  var testTable: {string}int

begin:
  testTable["alice"] = 30
  testTable["bob"] = 25
  print "Table test: ", testTable
  assert testTable["alice"] == 30
  assert testTable["bob"] == 25
  print "✓ {string}int DSL works correctly"

# Test {}string -> HashSet[string]
declare:
  var testSet: {}string

begin:
  testSet.incl("apple")
  testSet.incl("banana")
  testSet.incl("cherry")
  print "Set test: ", testSet
  assert testSet.contains("apple")
  assert testSet.contains("banana")
  assert not testSet.contains("date")
  print "✓ {}string DSL works correctly"

# Test variable declarations with DSL types in declare block
declare:
  var myTable: {string}int
  var mySet: {}string

begin:
  myTable["key1"] = 100
  myTable["key2"] = 200
  mySet.incl("item1")
  mySet.incl("item2")

  print "Variable DSL test - Table: ", myTable
  print "Variable DSL test - Set: ", mySet

  assert myTable["key1"] == 100
  assert mySet.contains("item1")
  print "✓ Variable declarations with DSL types work correctly"

print "=== All AdaScript DSL string-key tests passed ==="
