import adascript

echo "=== Testing AdaScript Features ==="
echo ""

# Test 1: shellLines
echo "1. shellLines:"
let lines = shellLines: echo "line1"; echo "line2"; echo "line3"
echo "   Lines: ", lines.len
assert lines.len == 3
echo "   ✓ Passed"
echo ""

# Test 2: loop
echo "2. loop:"
var count = 0
loop:
  inc count
  if count >= 3: break
assert count == 3
echo "   Iterations: ", count
echo "   ✓ Passed"
echo ""

# Test 3: {string}int table
echo "3. {string}int table DSL:"
declare:
  var scores: {string}int
begin:
  scores["alice"] = 95
  scores["bob"] = 87
  assert scores["alice"] == 95
  echo "   Table: ", scores
echo "   ✓ Passed"
echo ""

# Test 4: {}string set
echo "4. {}string set DSL:"
declare:
  var tags: {}string
begin:
  tags.incl("nim")
  tags.incl("python")
  assert tags.contains("nim")
  echo "   Set: ", tags
echo "   ✓ Passed"
echo ""

# Test 5: shell:
echo "5. shell:"
let result = shell: echo "Hello from AdaScript"
assert result.exitCode == 0
echo "   Output: ", result.output.strip
echo "   ✓ Passed"
echo ""

# Test 6: def with DSL return type []string
echo "6. def DSL return type []string:"
def featureGetNames() -> []string:
  @["Alice", "Bob"]
let fNames = featureGetNames()
assert fNames.len == 2
assert fNames[0] == "Alice"
echo "   Names: ", fNames
echo "   ✓ Passed"
echo ""

# Test 7: def with DSL parameter type []int
echo "7. def DSL parameter type []int:"
def featureSumAll(nums: []int) -> int:
  var total = 0
  for n in nums: total += n
  total
assert featureSumAll(@[10, 20, 30]) == 60
echo "   Sum: ", featureSumAll(@[10, 20, 30])
echo "   ✓ Passed"
echo ""

# Test 8: def with DSL return type [3]int
echo "8. def DSL return type [3]int:"
def featureGetTriple() -> [3]int:
  [1, 2, 3]
let fTriple = featureGetTriple()
assert fTriple[0] == 1
assert fTriple[2] == 3
echo "   Triple: ", fTriple
echo "   ✓ Passed"
echo ""

# Test 9: class with DSL field types
echo "9. class with DSL field []int:"
class FeatureBox:
  var items: []int
  def init(self: FeatureBox):
    self.items = @[]
  def addItem(self: var FeatureBox, item: int):
    self.items.add(item)
  def getItems(self: FeatureBox) -> []int:
    self.items

var fb = newFeatureBox()
fb.addItem(5)
fb.addItem(10)
assert fb.getItems().len == 2
assert fb.getItems()[0] == 5
echo "   Items: ", fb.getItems()
echo "   ✓ Passed"
echo ""

# Test 10: ?T optional type DSL in globals
echo "10. ?T optional type in globals:"
globals:
  var maybeVal: ?int
maybeVal = some(42)
assert maybeVal.isSome
assert maybeVal.get == 42
echo "   maybeVal: ", maybeVal.get
echo "   ✓ Passed"
echo ""

# Test 11: ?T in def return type with auto-wrapping
echo "11. ?T return type with return sugar:"
def findColor(name: string) -> ?string:
  if name == "sky":
    return "blue"
  return None
let c1 = findColor("sky")
let c2 = findColor("unknown")
assert c1 != None
assert c1.get == "blue"
assert c2 == None
echo "   findColor(sky): ", c1.get
echo "   findColor(unknown) == None: ", c2 == None
echo "   ✓ Passed"
echo ""

# Test 12: ?T in def parameter
echo "12. ?T parameter type:"
def describeAge(age: ?int) -> string:
  if age != None:
    return "age is " & $age.get
  return "unknown"
assert describeAge(some(25)) == "age is 25"
assert describeAge(none(int)) == "unknown"
echo "   describeAge(some(25)): ", describeAge(some(25))
echo "   describeAge(none): ", describeAge(none(int))
echo "   ✓ Passed"
echo ""

# Test 13: ?T in class field with return passthrough
echo "13. ?T in class field:"
class UserProfile:
  var name: string
  var email: ?string

  def init(self, name: string, email: ?string):
    self.name = name
    self.email = email

  def getEmail(self) -> ?string:
    return self.email

let u1 = newUserProfile("Alice", some("alice@example.com"))
let u2 = newUserProfile("Bob", none(string))
assert u1.getEmail() != None
assert u1.getEmail().get == "alice@example.com"
assert u2.getEmail() == None
echo "   u1 email: ", u1.getEmail().get
echo "   u2 email == None: ", u2.getEmail() == None
echo "   ✓ Passed"
echo ""

# Test 14: Nested optional types ?[]int and []?int
echo "14. Nested optional types:"
def getOptionalList() -> ?[]int:
  return @[1, 2, 3]
def getListOfOptionals() -> []?int:
  @[some(1), none(int), some(3)]
let ol = getOptionalList()
let lo = getListOfOptionals()
assert ol != None
assert ol.get.len == 3
assert lo.len == 3
assert lo[1] == None
echo "   ?[]int: ", ol.get
echo "   []?int: ", lo
echo "   ✓ Passed"
echo ""

echo "=== All AdaScript Features Tests Passed ==="
