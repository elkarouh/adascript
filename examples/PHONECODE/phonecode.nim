## =============================================================================
## phonecode.nim -- AdaScript Feature Showcase
## =============================================================================
##
## Solves the "Phone Code" challenge from:
##   Prechelt, Lutz. "An Empirical Comparison of Seven Programming Languages."
##   IEEE Computer, Vol. 33, No. 10, October 2000, pp. 23-29.
##
import adascript, os, sequtils

globals:
  type Digit_T = enum D0, D1, D2, D3, D4, D5, D6, D7, D8, D9
  type Result_T = [][] string
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

virtual class TrieNode:
  var children: [Digit_T] TrieNode
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

  def findExactWord(self, digits: [] Digit_T) -> ?string:
    var node = self
    for idx in digits:
      if node.children[idx].isNil:
        return None
      node = node.children[idx]
    if node.words.len > 0:
      return node.words[0]
    return None

  def wordsAt(self, digits: [] Digit_T) -> [] string:
    var node: TrieNode = self
    var found: [] string = @[]
    begin:
      for idx in digits:
        if node.children[idx].isNil:
          return found
        node = node.children[idx]
      return node.words

  def loadDictionary(self, filename: string, verbose: bool ~ false):
    var wordCount = 0
    proc wordToDigits(word: string): seq[Digit_T] =
      for c in word.toLowerAscii():
        if c notin charToDigit:
          return @[]
        result.add(charToDigit[c])

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

def cleanNumber(num: string) -> [] Digit_T:
  for c in num:
    if c in charToDigit:
      result.add(charToDigit[c])

def formatSolution(originalNum: string, solution: [] string) -> string:
  originalNum & ": " & solution.join(" ")

when isMainModule:
  if paramCount() < 2:
    print "Usage: phonecode <dictionary_file> <phone_numbers_file>"
    print "Example: phonecode words.txt phones.txt"
    quit(1)

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

    let trie = newTrieNode()
    trie.loadDictionary(dictFile, verbose = true)

    declare:
      let testDigits: []Digit_T = @[D3, D5]
      let exactMatch: ?string = trie.findExactWord(testDigits)
    begin:
      if exactMatch != None:
        print "Exact match for digits 3,5: ", exactMatch.get
      else:
        print "No exact match for digits 3,5"
      let wordsAtD3D5 = trie.wordsAt(testDigits)
      print "Words at [3,5]: ", wordsAtD3D5

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
      for sol in results:
        print formatSolution(original, sol)
