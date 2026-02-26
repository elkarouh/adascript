# test_timing.nim - Monitor test execution with timing information
import adascript, re, times, os

globals:
  var completedTests: {}string  ## All completed tests (persistent)
  var intervalTests: {}string   ## Tests since last 5-min summary

def stripAnsiProc(s: string) -> string:
  result = ""
  var i = 0
  while i < s.len:
    if s[i] == '\x1b' and i+1 < s.len and s[i+1] == '[':
      while i < s.len and s[i] != 'm':
        inc i
      inc i
    else:
      result.add(s[i])
      inc i

def getTestStatusLines() -> []string:
  ## Run show_tests_status and return output as lines.
  shellLines: show_tests_status -raw


def parseRunningTest(lines: []string) -> string:
  ## Extract the currently running test name from status lines.
  result = ""
  for i, line in lines:
    if line.strip() == "RUNNING:":
      if i + 1 < lines.len:
        var test = lines[i + 1].strip()
        while test.startsWith("-"): test = test[1..^1]
        while test.endsWith("-"): test = test[0..^2]
        test = test.strip()
        if test.len > 0:
          result = test
      break

def parseCompletedTests(lines: []string) -> []string:
  ## Extract all completed test names from status lines.
  result = @[]
  let successRe = re"SUCCESS:\s*(\S+)"
  for line in lines:
    for match in line.findAll(successRe):
      result.add(match)

def parseStatusSummary(lines: []string) -> []string:
  ## Extract the status summary lines (last 5 lines).
  let startIdx = max(0, lines.len - 5)
  lines[startIdx ..< lines.len]

def formatTime(dt: DateTime) -> string:
  dt.format("HH:mm:ss")

# Main program
print "Current directory: ", getCurrentDir()
print "=== Initial Test Status (", formatTime(now()), ") ==="
let initialLines = getTestStatusLines()
print "Output lines: ", initialLines.len
for line in initialLines: print line

# Capture already completed tests at startup
for test in parseCompletedTests(initialLines):
  completedTests.incl(test)

print "Initial tests: ", completedTests.len

loop:
  sleep(60000) # one minute polling interval
  let lines = getTestStatusLines()
  let currentMinute = now().minute

  # Track newly completed tests
  for test in parseCompletedTests(lines):
    if not completedTests.contains(test):
      completedTests.incl(test)
      intervalTests.incl(test)

  switch currentMinute mod 5:
    when 0:
      let displayLines = getTestStatusLines()
      let displayRunning = parseRunningTest(displayLines)
      print ""
      print "=== ", formatTime(now()), " - Test Timing Summary ==="
      print ""

      if intervalTests.len > 0:
        for test in intervalTests:
          print "< 1 min: ", test
        intervalTests = initHashSet[string]()
      else:
        print "(no new tests completed yet)"

      print ""
      print "--- Currently Running ---"
      if displayRunning.len > 0:
        print displayRunning
      else:
        print "(no test running)"

      print ""
      print "--- Current Status ---"
      for line in parseStatusSummary(displayLines):
        print line
      print ""

    when others: discard

  var nextUpdate = (5 - (currentMinute mod 5)) mod 5
  if nextUpdate == 0: nextUpdate = 5
  print "[", formatTime(now()), "] Monitoring... Next timing update in ", nextUpdate, " minute(s)"
