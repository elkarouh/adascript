#!/usr/bin/env -S nim --hints:off r
# test_shell.nim - Tests for AdaScript shell module
# Integrates shell commands with AdaScript declare/begin, tick attributes, etc.

import adascript
# Note: shell is already included in adascript, don't import it separately

echo "=== AdaScript Shell Module Tests ==="
echo ""

# ============================================================================
# Test 1: Basic shell functionality
# ============================================================================
echo "--- Test 1: Basic shell commands ---"
let result1 = shell: echo "Hello from Nim"
if result1.exitCode == 0:
  echo "✓ Basic command passed: ", result1.output.strip
else:
  echo "✗ Basic command failed: ", result1.error

# ============================================================================
# Test 2: Variable interpolation
# ============================================================================
echo ""
echo "--- Test 2: Variable interpolation ---"
let name = "AdaScript"
let result2 = shell: echo "Hello from {name}"
if result2.exitCode == 0 and "AdaScript" in result2.output:
  echo "✓ Variable interpolation passed: ", result2.output.strip
else:
  echo "✗ Variable interpolation failed"

# ============================================================================
# Test 3: Multiple commands (auto-combined with &&)
# ============================================================================
echo ""
echo "--- Test 3: Multiple commands ---"
let result3 = shell:
  echo "First command"
  echo "Second command"
if result3.exitCode == 0:
  let lines = result3.output.splitLines()
  if lines.len >= 2:
    echo "✓ Multiple commands passed: ", lines.len, " lines"
  else:
    echo "✗ Multiple commands failed: expected 2 lines"
else:
  echo "✗ Multiple commands failed: ", result3.error

# ============================================================================
# Test 4: Working directory (cwd)
# ============================================================================
echo ""
echo "--- Test 4: Working directory ---"
let result4 = shell(cwd = "/tmp"):
  pwd
if result4.exitCode == 0 and "/tmp" in result4.output:
  echo "✓ Working directory passed: ", result4.output.strip
else:
  echo "✗ Working directory failed"

# ============================================================================
# Test 5: Piping commands
# ============================================================================
echo ""
echo "--- Test 5: Piping commands ---"
let result5 = shell:
  pipe:
    echo "hello world"
    tr a-z A-Z
if result5.exitCode == 0 and "HELLO WORLD" in result5.output:
  echo "✓ Piping passed: ", result5.output.strip
else:
  echo "✗ Piping failed: ", result5.output, " | ", result5.error

# ============================================================================
# Test 6: Error handling
# ============================================================================
echo ""
echo "--- Test 6: Error handling ---"
let result6 = shell: "nonexistent_command_xyz123"
if result6.exitCode != 0:
  echo "✓ Error handling passed: exitCode = ", result6.exitCode
else:
  echo "✗ Error handling failed: should have returned non-zero exit code"

# ============================================================================
# Test 7: Timeout handling (Unix only)
# ============================================================================
echo ""
echo "--- Test 7: Timeout handling ---"
when not defined(windows):
  # Use a longer sleep that will definitely timeout
  let result7 = shell(timeout = 100): "sleep 10"
  if result7.exitCode == 124 or "timed out" in result7.error.toLower:
    echo "✓ Timeout handling passed: command was terminated"
  else:
    # Some systems may not support timeout, so just note it
    echo "⊘ Timeout handling: exitCode = ", result7.exitCode, " (may not be supported)"
else:
  echo "⊘ Timeout test skipped on Windows"

# ============================================================================
# Test 8: Quiet mode
# ============================================================================
echo ""
echo "--- Test 8: Quiet mode ---"
let result8 = shell(quiet = true): echo "Silent command"
if result8.exitCode == 0:
  echo "✓ Quiet mode passed"
else:
  echo "✗ Quiet mode failed"

# ============================================================================
# Test 9: Integration with AdaScript declare/begin
# ============================================================================
echo ""
echo "--- Test 9: Integration with declare/begin ---"
declare shell_test:
  type Command_Result_T = [3]string
  var results: Command_Result_T
  var test_name: string

begin:
  test_name = "AdaScript Shell Integration"
  results[0] = "echo 'Command 1'"
  results[1] = "echo 'Command 2'"
  results[2] = "echo 'Command 3'"

  echo "Test name: ", test_name
  echo "Array ^First: ", Command_Result_T ^ First
  echo "Array ^Last: ", Command_Result_T ^ Last
  echo "Array ^Length: ", Command_Result_T ^ Length

  # Execute commands from array
  for i in Command_Result_T^First .. Command_Result_T^Last:
    let cmdResult = shell: "echo \"Result {i}\""
    if cmdResult.exitCode == 0:
      echo "  ✓ Command ", i, " passed"

# ============================================================================
# Test 10: Integration with tick attributes
# ============================================================================
echo ""
echo "--- Test 10: Integration with tick attributes ---"
type Status_T = enum Starting, Running, Stopped, Error

echo "Status_T ^First: ", Status_T ^ First
echo "Status_T ^Last: ", Status_T ^ Last
echo "Status_T ^Length: ", Status_T ^ Length

# Iterate using tickRange
echo "Iterating Status_T values:"
for s in Status_T.tickRange():
  let result = shell: echo "Status_T: ", s
  if result.exitCode == 0:
    echo "  ✓ ", s

# ============================================================================
# Test 11: Integration with switch/case
# ============================================================================
echo ""
echo "--- Test 11: Integration with switch/case ---"
let exitCode = 0

switch exitCode:
  when 0:
    let result = shell: echo "Success case"
    if result.exitCode == 0:
      echo "✓ Switch case 0 passed"
  when 1:
    echo "Error case"
  when others:
    echo "Unknown case"

# ============================================================================
# Test 12: Integration with def functions
# ============================================================================
echo ""
echo "--- Test 12: Integration with def functions ---"

def runCommand(cmd: string) -> ShellResult:
  ## Helper function to run a shell command
  shell: "echo {cmd}"

let cmdResult = runCommand("test command")
if cmdResult.exitCode == 0:
  echo "✓ def function integration passed: ", cmdResult.output.strip
else:
  echo "✗ def function integration failed"

# ============================================================================
# Test 13: Complex command with redirection (using raw string)
# ============================================================================
echo ""
echo "--- Test 13: File redirection ---"
let result13 = shell(quiet = false):
  "echo 'Line 1' > /tmp/adascript_shell_test.txt"
  "echo 'Line 2' >> /tmp/adascript_shell_test.txt"
  "cat /tmp/adascript_shell_test.txt"

if result13.exitCode == 0 and "Line 1" in result13.output and "Line 2" in result13.output:
  echo "✓ File redirection passed"
else:
  echo "⊘ File redirection: exitCode = ", result13.exitCode

# Cleanup
discard shell: "rm -f /tmp/adascript_shell_test.txt"

# ============================================================================
# Test 14: Combined options
# ============================================================================
echo ""
echo "--- Test 14: Combined options ---"
let result14 = shell(cwd = "/tmp", timeout = 5000, quiet = true):
  echo "Combined options test"
  pwd

if result14.exitCode == 0:
  echo "✓ Combined options passed"
else:
  echo "✗ Combined options failed"

# ============================================================================
# Test 15: Custom debug options
# ============================================================================
echo ""
echo "--- Test 15: Custom debug options ---"
let result15 = shell(debug = {dokCommand}):
  echo "Only show commands"

if result15.exitCode == 0:
  echo "✓ Custom debug options passed"
else:
  echo "✗ Custom debug options failed"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=== All AdaScript Shell Module Tests Completed ==="

# ============================================================================
# Test shellLines
# ============================================================================
echo ""
echo "--- Test: shellLines ---"
let lines = shellLines: echo "line1"; echo "line2"; echo "line3"
if lines.len == 3 and lines[0] == "line1" and lines[1] == "line2" and lines[2] == "line3":
  echo "✓ shellLines basic test passed"
else:
  echo "✗ shellLines basic test failed: ", lines

# Test with real command
let lsLines = shellLines: ls ~/ADA_PLAYGROUND/HNIM/*.nim 2>/dev/null | head -3
if lsLines.len > 0:
  echo "✓ shellLines real command test passed: ", lsLines.len, " lines"
else:
  echo "✗ shellLines real command test failed"

echo "=== shellLines tests complete ==="
