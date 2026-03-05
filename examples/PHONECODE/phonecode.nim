## =============================================================================
## phonecode.nim -- AdaScript Feature Showcase
## =============================================================================
##
## Solves the "Phone Code" challenge from:
##   Prechelt, Lutz. "An Empirical Comparison of Seven Programming Languages."
##   IEEE Computer, Vol. 33, No. 10, October 2000, pp. 23-29.
##
## AdaScript features exercised:
##   1.  virtual class         -- TrieNode with ref semantics & methods
##   2.  class (value)         -- Stats as value class with self: var
##   3.  def                   -- Python-style function definitions
##   4.  def with ~ defaults   -- Default parameter values
##   5.  def with -> return    -- Explicit return types with DSL
##   6.  declare:/begin:       -- Ada-style declarative blocks (top-level)
##   7.  implicit declare      -- Declarations before begin: inside class def
##   8.  globals               -- Module-level DSL declarations
##   9.  switch/when           -- Ada-style case statements
##  10.  ^ tick attributes     -- First, Last, Length, Pos, Succ
##  11.  ? optional types      -- Option[T] with None
##  12.  []T seq DSL           -- seq[string], seq[Digit_T]
##  13.  [N]T array DSL        -- array[Digit_T, TrieNode]
##  14.  {K}V table DSL        -- Table[char, Digit_T]
##  15.  record:               -- Ada-style record type (DigitInfo)
##  16.  print                 -- Variadic print macro
##  17.  loop                  -- Ada-style infinite loop
##  18.  shell                 -- Shell command execution

import adascript, os, sequtils

# =============================================================================
# [Feature 8: globals] -- Module-level declarations with DSL types
# =============================================================================

globals:
  type Digit_T = enum
    D0
    D1
    D2
    D3
    D4
    D5
    D6
    D7
    D8
    D9

  type Result_T = [][]string

  type DigitInfo = record:
    digit:
      Digit_T
    label:
      string
    letterCount:
      int

# =============================================================================
# [Feature 14: {K}V table DSL] -- Character-to-digit mapping
# =============================================================================

const charToDigit = block:
  var t = initTable[char, Digit_T]()
  proc m(chars: string, digit: Digit_T) =
    for c in chars:
      t[c] = digit
      t[c.toUpperAscii()] = digit

  m("e", D0)
  m("jnq", D1)
  m("rwx", D2)
  m("dsy", D3)
  m("ft", D4)
  m("am", D5)
  m("civ", D6)
  m("bku", D7)
  m("lop", D8)
  m("ghz", D9)
  for d in "0123456789":
    t[d] = Digit_T(ord(d) - ord('0'))
  t

# =============================================================================
# [Feature 9: switch/when] -- Digit classification
# =============================================================================

def classifyDigit(d: Digit_T) -> string:
  switch d:
    when D0:
      "vowel-mapped (e)"
    when D1:
      "consonant-triple (j,n,q)"
    when D2:
      "consonant-triple (r,w,x)"
    when D3:
      "consonant-triple (d,s,y)"
    when D4:
      "consonant-pair (f,t)"
    when D5:
      "consonant-pair (a,m)"
    when D6:
      "consonant-triple (c,i,v)"
    when D7:
      "consonant-triple (b,k,u)"
    when D8:
      "consonant-triple (l,o,p)"
    when D9:
      "consonant-triple (g,h,z)"

# =============================================================================
# [Feature 10: ^ tick attributes] -- Digit_T metadata
# =============================================================================

def printDigitInfo():
  print "Digit enum info:"
  print "  First digit: ", Digit_T ^ First
  print "  Last digit:  ", Digit_T ^ Last
  print "  Num digits:  ", Digit_T ^ Length
  let mid = D5
  print "  D5 position:  ", mid ^ Pos
  print "  D5 successor: ", mid ^ Succ
  print "  D5 classify:  ", classifyDigit(mid)
  # [Feature 15: record]
  let info = DigitInfo(digit: D5, label: "consonant-pair (a,m)", letterCount: 2)
  print "  DigitInfo:     ", info.label, " (", info.letterCount, " letters)"

# =============================================================================
# [Feature 1: virtual class] -- Trie node
# =============================================================================

virtual class TrieNode:
  var children: array[Digit_T, TrieNode]
  var words: [] string

  def init(self):
    for i in Digit_T:
      self.children[i] = nil
    self.words = @[]

  def addWord(self, word: string, digits: [] Digit_T):
    var node = self
    for idx in digits:
      if node.children[idx].isNil:
        node.children[idx] = newTrieNode()
      node = node.children[idx]
    node.words.add(word)

  ## [Feature 11: ? optional] -- Returns None if no word matches
  def findExactWord(self, digits: [] Digit_T) -> ?string:
    var node = self
    for idx in digits:
      if node.children[idx].isNil:
        return None
      node = node.children[idx]
    if node.words.len > 0:
      return node.words[0]
    return None

  ## [Feature 7: implicit declare/begin] -- DSL types before begin: in class method
  def wordsAt(self, digits: [] Digit_T) -> [] string:
    var node: TrieNode = self
    var found: [] string = @[]
    begin:
      for idx in digits:
        if node.children[idx].isNil:
          return found
        node = node.children[idx]
      return node.words

  ## [Feature 4: ~ default] -- verbose defaults to false
  def loadDictionary(self, filename: string, verbose: bool ~ false):
    var wordCount = 0
    proc wordToDigits(word: string): seq[Digit_T] =
      for c in word.toLowerAscii():
        if c in charToDigit:
          result.add(charToDigit[c])
        else:
          return @[]

    for line in lines(filename):
      let word = line.strip()
      if word.len > 0:
        let digits = wordToDigits(word)
        if digits.len > 0 and digits.len == word.len:
          self.addWord(word, digits)
          inc wordCount
    if verbose:
      print "Loaded ", wordCount, " words from ", filename

  def findEncodings(
    self, digits: [] Digit_T, pos: int, current: [] string, results: var Result_T
  ):
    if pos == digits.len:
      results.add(@current)
      return
    var next = @current
    next.add($digits[pos].int)
    self.findEncodings(digits, pos + 1, next, results)
    var node = self
    for i in pos ..< digits.len:
      let idx = digits[i]
      if node.children[idx].isNil:
        break
      node = node.children[idx]
      for word in node.words:
        var wordNext: seq[string] = @[]
        for x in current:
          wordNext.add(x)
        wordNext.add(word)
        self.findEncodings(digits, i + 1, wordNext, results)

# =============================================================================
# [Feature 2: class (value)] -- Stats tracking
# =============================================================================

class Stats:
  var numbersProcessed: int
  var numbersWithSolutions: int
  var totalSolutions: int
  var longestNumber: int

  def init(self):
    self.numbersProcessed = 0
    self.numbersWithSolutions = 0
    self.totalSolutions = 0
    self.longestNumber = 0

  def recordNumber(self: var, numDigits: int, numSolutions: int):
    inc self.numbersProcessed
    self.totalSolutions += numSolutions
    if numSolutions > 0:
      inc self.numbersWithSolutions
    if numDigits > self.longestNumber:
      self.longestNumber = numDigits

  def printSummary(self):
    print "--- Encoding Statistics ---"
    print "  Numbers processed:      ", self.numbersProcessed
    print "  Numbers with solutions: ", self.numbersWithSolutions
    print "  Total solutions found:  ", self.totalSolutions
    print "  Longest number (digits):", self.longestNumber

# =============================================================================
# [Feature 3,5: def with DSL return types]
# =============================================================================

def cleanNumber(num: string) -> [] Digit_T:
  for c in num:
    if c in charToDigit:
      result.add(charToDigit[c])

def formatSolution(originalNum: string, solution: [] string) -> string:
  originalNum & ": " & solution.join(" ")

# =============================================================================
# Entry Point: [Feature 6,16,17,18: declare/begin, print, loop, shell]
# =============================================================================

when isMainModule:
  if paramCount() < 2:
    print "Usage: phonecode <dictionary_file> <phone_numbers_file>"
    print "Example: phonecode words.txt phones.txt"
    quit(1)

  # [Feature 6: declare:/begin:]
  declare:
    let dictFile = paramStr(1)
    let phoneFile = paramStr(2)

  begin:
    if not fileExists(dictFile):
      print "Error: Dictionary file not found: ", dictFile
      quit(1)
    if not fileExists(phoneFile):
      print "Error: Phone numbers file not found: ", phoneFile
      quit(1)

    # [Feature 18: shell]
    let info = shell:
      echo "phonecode running on $(uname -s)"
    if info.exitCode == 0:
      print info.output

    # [Feature 10: ^ tick attributes]
    printDigitInfo()

    let trie = newTrieNode()
    trie.loadDictionary(dictFile, verbose = true)

    # [Feature 11: ? optional]
    let testDigits: seq[Digit_T] = @[D3, D5]
    let exactMatch = trie.findExactWord(testDigits)
    if exactMatch != None:
      print "Exact match for digits 3,5: ", exactMatch.get
    else:
      print "No exact match for digits 3,5"

    # [Feature 7: implicit declare] -- wordsAt uses []T DSL before begin:
    let wordsAtD3D5 = trie.wordsAt(testDigits)
    print "Words at [3,5]: ", wordsAtD3D5

    var stats = newStats()

    # [Feature 17: loop]
    var lineIdx = 0
    let allLines = toSeq(lines(phoneFile))
    loop:
      if lineIdx >= allLines.len:
        break
      let original = allLines[lineIdx].strip()
      inc lineIdx
      if original.len == 0:
        continue
      let digits = cleanNumber(original)
      if digits.len == 0:
        continue
      var results: Result_T = @[]
      trie.findEncodings(digits, 0, @[], results)
      stats.recordNumber(digits.len, results.len)
      for sol in results:
        print formatSolution(original, sol)

    stats.printSummary()
