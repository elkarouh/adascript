import std/parseopt
import std/strutils
import adascript

globals:
  var inputFile: string
  var outputFile: string = "output.txt"
  var verbose: bool = false
  var count: int = 1
  var p = initOptParser(shortNoVal = {'h', 'v'},
                        longNoVal = @["help", "verbose"],
                        mode = NimMode
    )

for kind, key, val in p.getopt():
  switch kind:
    when cmdArgument:
     if inputFile == "":
       inputFile = key
     else:
       print "Unknown argument: ", key
       quit(1)

    when cmdLongOption:
      switch key:
        when "help":
          print "Usage: myapp [options] <input>"
          print "  -o, --output=FILE    Output file (default: output.txt)"
          print "  -v, --verbose        Enable verbose mode"
          print "  -n, --count=N        Repeat count (default: 1)"
          quit(0)
        when "output":
          outputFile = val
        when "verbose":
          verbose = true
        when "count":
          count = parseInt(val)
        when others:
          print "Unknown option: ", key
          quit(1)
    when cmdShortOption:
      switch key:
        when "h":
          print "Usage: myapp [options] <input>"
          print "  -o, --output=FILE    Output file (default: output.txt)"
          print "  -v, --verbose        Enable verbose mode"
          print "  -n, --count=N        Repeat count (default: 1)"
          quit(0)
        when "o":
          outputFile = val
        when "v":
          verbose = true
        when "n":
          count = parseInt(val)
        when others:
          print "Unknown option: ", key
          quit(1)

    when cmdEnd: break

if inputFile == "":
  print "Error: Input file required"
  quit(1)

print "Input: ", inputFile
print "Output: ", outputFile
print "Verbose: ", verbose
print "Count: ", count
