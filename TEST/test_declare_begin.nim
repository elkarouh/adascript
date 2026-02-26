#!/usr/bin/env -S nim --hints:off r
# test_declare_begin.nim - Comprehensive tests for declare/begin blocks
# Tests nested blocks, scoping, variable shadowing, and edge cases
# All user-defined types follow _T suffix convention

import adascript

echo "=== Comprehensive Declare/Begin Block Tests ==="
echo ""

# ============================================================================
# Test 1: Basic declare/begin functionality
# ============================================================================
echo "--- Test 1: Basic declare/begin ---"
declare:
  type MyArray_T = [5]int
  var arr: MyArray_T
  let const_val = 42

begin:
  arr = [1, 2, 3, 4, 5]
  assert arr[0] == 1
  assert const_val == 42
  echo "✓ Basic declare/begin passed"

# ============================================================================
# Test 2: Nested declare/begin blocks (inner should not affect outer)
# ============================================================================
echo ""
echo "--- Test 2: Nested declare/begin blocks ---"
declare outer:
  type OuterArray_T = [3]int
  var outer_val = 100
  var arr: OuterArray_T

begin:
  arr = [10, 20, 30]
  assert outer_val == 100

  # Nested declare inside begin
  declare inner:
    type InnerArray_T = [2]int
    var inner_val = 200
    var inner_arr: InnerArray_T

  begin:
    inner_arr = [1, 2]
    assert inner_val == 200
    # Can access outer scope
    assert outer_val == 100
    echo "  Inner block: outer_val = ", outer_val, ", inner_val = ", inner_val

  # After inner block, inner_val should not be visible
  # But outer_val should still be visible
  assert outer_val == 100
  echo "✓ Nested declare/begin passed"

# ============================================================================
# Test 3: Variable shadowing in nested blocks
# ============================================================================
echo ""
echo "--- Test 3: Variable shadowing ---"
declare shadow_outer:
  var x = 10
  var y = 20

begin:
  assert x == 10
  assert y == 20

  declare shadow_inner:
    var x = 100  # Shadows outer x
    var z = 30   # New variable

  begin:
    assert x == 100  # Inner x
    assert y == 20   # Outer y (not shadowed)
    assert z == 30   # Inner z
    echo "  Inner: x = ", x, ", y = ", y, ", z = ", z

  # Back to outer scope
  assert x == 10  # Original x
  assert y == 20
  # z should not be visible here
  echo "  Outer: x = ", x, ", y = ", y
  echo "✓ Variable shadowing passed"

# ============================================================================
# Test 4: Multiple sequential declare/begin pairs
# ============================================================================
echo ""
echo "--- Test 4: Multiple sequential blocks ---"
declare first:
  var first_val = 1

begin:
  assert first_val == 1
  echo "  First block: ", first_val

declare second:
  var second_val = 2

begin:
  assert second_val == 2
  echo "  Second block: ", second_val

declare third:
  var third_val = 3

begin:
  assert third_val == 3
  echo "  Third block: ", third_val

echo "✓ Multiple sequential blocks passed"

# ============================================================================
# Test 5: Deep nesting (3 levels)
# ============================================================================
echo ""
echo "--- Test 5: Deep nesting (3 levels) ---"
declare level1:
  var l1 = 1

begin:
  assert l1 == 1

  declare level2:
    var l2 = 2

  begin:
    assert l1 == 1
    assert l2 == 2

    declare level3:
      var l3 = 3

    begin:
      assert l1 == 1
      assert l2 == 2
      assert l3 == 3
      echo "  Level 3: l1 = ", l1, ", l2 = ", l2, ", l3 = ", l3

    # Back to level 2
    assert l1 == 1
    assert l2 == 2
    echo "  Level 2: l1 = ", l1, ", l2 = ", l2

  # Back to level 1
  assert l1 == 1
  echo "  Level 1: l1 = ", l1

echo "✓ Deep nesting passed"

# ============================================================================
# Test 6: Type definitions in nested blocks
# ============================================================================
echo ""
echo "--- Test 6: Type definitions in nested blocks ---"
declare type_outer:
  type OuterType_T = [3]int
  var outer_arr: OuterType_T

begin:
  outer_arr = [1, 2, 3]

  declare type_inner:
    type InnerType_T = [2]string
    var inner_arr: InnerType_T

  begin:
    inner_arr = ["a", "b"]
    assert outer_arr[0] == 1
    assert inner_arr[0] == "a"
    echo "  Outer type: ", outer_arr
    echo "  Inner type: ", inner_arr

  # Outer type should still work
  outer_arr[0] = 100
  echo "  Modified outer: ", outer_arr

echo "✓ Type definitions in nested blocks passed"

# ============================================================================
# Test 7: Procedures outside declare blocks (procs work in begin)
# ============================================================================
echo ""
echo "--- Test 7: Procedures with declare blocks ---"
var counter = 0

def increment() -> int:
  counter += 1
  result = counter

def get_counter() -> int:
  result = counter

declare proc_test:
  var local_val = 10

begin:
  assert local_val == 10
  assert get_counter() == 0
  assert increment() == 1
  assert increment() == 2
  echo "  Counter after 2 increments: ", get_counter()
  echo "✓ Procedures with declare blocks passed"

# ============================================================================
# Test 8: Constants in declare blocks
# ============================================================================
echo ""
echo "--- Test 8: Constants in declare blocks ---"
declare const_block:
  const PI = 3.14159
  const MAX_SIZE = 100
  var size = 50

begin:
  assert PI == 3.14159
  assert MAX_SIZE == 100
  assert size == 50
  size = 75  # Can modify var
  assert size == 75
  echo "  PI = ", PI, ", MAX_SIZE = ", MAX_SIZE, ", size = ", size
  echo "✓ Constants in declare blocks passed"

# ============================================================================
# Test 9: Complex nested types
# ============================================================================
echo ""
echo "--- Test 9: Complex nested types ---"
declare complex:
  type Matrix3x4_T = [3][4]int
  type SeqOfArrays_T = [5][]string
  type ArrayOfSeqs_T = [][]int
  type NestedSeqs_T = [][]string
  type TableType_T = {string}int
  type SetType_T = {}char

  var matrix: Matrix3x4_T
  var soa: SeqOfArrays_T
  var aos: ArrayOfSeqs_T
  var ns: NestedSeqs_T
  var tbl: TableType_T
  var st: SetType_T

begin:
  # Test matrix
  matrix[0] = [1, 2, 3, 4]
  matrix[1] = [5, 6, 7, 8]
  matrix[2] = [9, 10, 11, 12]
  assert matrix[1][2] == 7

  # Test seq of arrays
  soa[0] = @["a", "b"]
  soa[1] = @["c", "d", "e"]

  # Test array of seqs
  aos.add(@[1, 2, 3])
  aos.add(@[4, 5])

  # Test nested seqs
  ns.add(@["hello", "world"])

  # Test table
  tbl["key"] = 42
  assert tbl["key"] == 42

  # Test set
  st.incl('a')
  st.incl('b')
  assert 'a' in st

  echo "  Matrix[1][2] = ", matrix[1][2]
  echo "  Table[\"key\"] = ", tbl["key"]
  echo "  Set contains 'a': ", 'a' in st
  echo "✓ Complex nested types passed"

# ============================================================================
# Test 10: Labeled vs unlabeled blocks
# ============================================================================
echo ""
echo "--- Test 10: Labeled vs unlabeled blocks ---"

# Unlabeled block
declare:
  var unlabeled_val = 1

begin:
  assert unlabeled_val == 1
  echo "  Unlabeled: ", unlabeled_val

# Labeled block
declare labeled:
  var labeled_val = 2

begin labeled:
  assert labeled_val == 2
  echo "  Labeled: ", labeled_val

echo "✓ Labeled vs unlabeled blocks passed"

# ============================================================================
# Test 11: Standalone begin blocks (no declare)
# ============================================================================
echo ""
echo "--- Test 11: Standalone begin blocks ---"
var outer_var = 10

begin:
  let inner_var = 20
  assert outer_var == 10
  assert inner_var == 20
  echo "  Standalone begin: outer = ", outer_var, ", inner = ", inner_var

# inner_var should not be visible here
assert outer_var == 10
echo "✓ Standalone begin blocks passed"

# ============================================================================
# Test 12: Mixing declare with other Nim constructs
# ============================================================================
echo ""
echo "--- Test 12: Mixing with Nim constructs ---"

# For loop with declare
for i in 1..3:
  declare loop_block:
    var loop_val = i * 10

  begin:
    assert loop_val == i * 10
    echo "  Loop iteration ", i, ": loop_val = ", loop_val

# If statement with declare
declare condition_test:
  var flag = true

begin:
  if flag:
    declare if_block:
      var if_val = 42

    begin:
      assert if_val == 42
      echo "  If block: ", if_val

echo "✓ Mixing with Nim constructs passed"

# ============================================================================
# Test 13: Tick attributes within declare blocks
# ============================================================================
echo ""
echo "--- Test 13: Tick attributes in declare blocks ---"
declare tick_test:
  type TestDirection_T = enum North, South, East, West
  type TestArray_T = [1..10]int
  var arr: TestArray_T

begin:
  assert TestDirection_T ^ First == North
  assert TestDirection_T ^ Last == West
  assert TestDirection_T ^ Length == 4
  assert TestArray_T ^ First == 1
  assert TestArray_T ^ Last == 10
  assert TestArray_T ^ Length == 10

  arr[5] = 100
  assert arr[5] == 100

  echo "  TestDirection_T ^ First: ", TestDirection_T ^ First
  echo "  TestDirection_T ^ Last: ", TestDirection_T ^ Last
  echo "  TestDirection_T ^ Length: ", TestDirection_T ^ Length
  echo "✓ Tick attributes in declare blocks passed"

# ============================================================================
# Test 14: Switch/case within declare blocks
# ============================================================================
echo ""
echo "--- Test 14: Switch/case in declare blocks ---"
declare switch_test:
  var status = 1

begin:
  switch status:
    when 0:
      echo "  Status 0"
      assert false  # Should not reach here
    when 1:
      echo "  Status 1"
      assert true
    when others:
      echo "  Status other"
      assert false  # Should not reach here

echo "✓ Switch/case in declare blocks passed"

# ============================================================================
# Test 15: Def functions with declare blocks
# ============================================================================
echo ""
echo "--- Test 15: Def functions with declare blocks ---"

var accumulator = 0

def add(x: int) -> int:
  accumulator += x
  result = accumulator

def multiply(x: int, y: int) -> int:
  result = x * y

def generic[T](val: T) -> T:
  result = val

declare def_test:
  var local_val = 100

begin:
  assert local_val == 100
  assert add(5) == 5
  assert add(10) == 15
  assert multiply(3, 4) == 12
  assert generic(42) == 42
  assert generic("hello") == "hello"
  echo "  Accumulator: ", accumulator
  echo "  Multiply: ", multiply(3, 4)
  echo "✓ Def functions with declare blocks passed"

# ============================================================================
# Test 16: Edge case - minimal declare block
# ============================================================================
echo ""
echo "--- Test 16: Edge case - minimal declare ---"
declare minimal:
  var x = 1

begin:
  assert x == 1
  echo "  Minimal block: x = ", x
echo "✓ Minimal declare passed"

# ============================================================================
# Test 17: Scope isolation - variables don't leak
# ============================================================================
echo ""
echo "--- Test 17: Scope isolation ---"

declare scope_test_1:
  var leak_test = "inner1"

begin:
  assert leak_test == "inner1"

declare scope_test_2:
  var leak_test = "inner2"  # Should not conflict with scope_test_1

begin:
  assert leak_test == "inner2"
  echo "  Scope test: ", leak_test

echo "✓ Scope isolation passed"

# ============================================================================
# Test 18: Array DSL with various index types
# ============================================================================
echo ""
echo "--- Test 18: Array DSL with various index types ---"
declare array_dsl:
  type LocalDirection_T = enum North, South, East, West
  type IntIndex_T = [10]int
  type RangeIndex_T = [1..10]int
  type EnumIndex_T = [LocalDirection_T]int
  type CharRange_T = ['a'..'z']int

  var int_arr: IntIndex_T
  var range_arr: RangeIndex_T
  var enum_arr: EnumIndex_T
  var char_arr: CharRange_T

begin:
  int_arr[0] = 1
  int_arr[9] = 10

  range_arr[1] = 100
  range_arr[10] = 1000

  enum_arr[North] = 1
  enum_arr[South] = 2

  char_arr['a'] = 1
  char_arr['z'] = 26

  assert int_arr[0] == 1
  assert range_arr[1] == 100
  assert enum_arr[North] == 1
  assert char_arr['a'] == 1

  echo "  IntIndex_T[0] = ", int_arr[0]
  echo "  RangeIndex_T[1] = ", range_arr[1]
  echo "  EnumIndex_T[North] = ", enum_arr[North]
  echo "  CharRange_T['a'] = ", char_arr['a']
echo "✓ Array DSL with various index types passed"

# ============================================================================
# Test 19: Ada-style declarations inside def functions (implicit, no 'declare')
# ============================================================================
echo ""
echo "--- Test 19: Ada-style declarations inside def functions ---"

type ResultArray_T = array[0..4, int]

def computeWithLocals(x: int) -> int:
  ## Ada-style: declarations directly in function body before begin:
  var multiplier = 10
  var offset = 5
  type LocalArray_T = [3]int
  var arr: LocalArray_T

  begin:
    arr = [1, 2, 3]
    result = x * multiplier + offset + arr[0]

assert computeWithLocals(7) == 7 * 10 + 5 + 1
echo "  computeWithLocals(7) = ", computeWithLocals(7)

def processArray(input: int) -> ResultArray_T:
  ## Ada-style: type and variable declarations before begin:
  type TempArray_T = [5]int
  var temp: TempArray_T
  var scale = 2

  begin:
    for i in 0..4:
      temp[i] = (input + i) * scale
    result = temp

let processed = processArray(10)
echo "  processArray(10) = ", processed
assert processed[0] == 20
assert processed[4] == 28

echo "✓ Ada-style declarations inside def functions passed"

# ============================================================================
# Test 20: Nested declare:/begin: blocks inside functions (Ada-style)
# ============================================================================
echo ""
echo "--- Test 20: Nested declare:/begin: blocks inside functions ---"

def nestedBeginBlocks(x: int) -> int:
  ## Ada-style: outer declarations, then nested declare:/begin: blocks
  var outer_val = x * 2
  begin:
    declare:
      var inner_val = outer_val + 10
    begin:
      result = inner_val * 3

assert nestedBeginBlocks(5) == (5 * 2 + 10) * 3
echo "  nestedBeginBlocks(5) = ", nestedBeginBlocks(5)

def complexNestedFunction(x: int) -> int:
  ## Ada-style: complex nesting with explicit declare:/begin: pairs
  var level1 = x * 10
  var level2 = x * 100
  begin:
    declare:
      var inner1 = level1 + 1
    begin:
      declare:
        var inner2 = level2 + 2
      begin:
        var inner3 = inner1 + inner2
        result = inner3

assert complexNestedFunction(5) == (5 * 10 + 1) + (5 * 100 + 2)
echo "  complexNestedFunction(5) = ", complexNestedFunction(5)

echo "✓ Nested declare:/begin: blocks inside functions passed"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=== All Declare/Begin Block Tests Passed! ==="
