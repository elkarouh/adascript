# Compile-time storage for pending declarations
var labeledDeclarations {.compileTime.}: Table[string, seq[NimNode]] = initTable[string, seq[NimNode]]()
var unlabeledDeclarations {.compileTime.}: seq[NimNode] = @[]
var lastDeclareLabel {.compileTime.}: string = ""

# ============================================================================
# Error message helpers
# ============================================================================

proc dslError(msg: string, node: NimNode) =
  ## Raise a compile-time error with helpful context for DSL issues.
  error("AdaScript type DSL: " & msg & "\n  Found: " & node.repr, node)

proc declareError(msg: string, node: NimNode) =
  ## Raise a compile-time error with helpful context for declare block issues.
  error("AdaScript declare block: " & msg & "\n  Found: " & node.repr, node)

# ============================================================================
# Nested declare/begin support (Ada-style inside functions)
# ============================================================================

var nestedDeclareActive {.compileTime.}: bool = false

# ============================================================================
# Type DSL helpers
# ============================================================================

const LargeSetTypesArr = ["int", "int64", "uint", "uint64", "float", "float64", "string"]

proc isLargeSetType(typeName: string): bool =
  ## Check if a type name should use HashSet instead of built-in set.
  typeName in LargeSetTypesArr

proc isArrayDSLPattern(expr: NimNode): bool =
  ## Check if an expression looks like an Odin-style type DSL pattern.
  ## Handles: [N]T, []T, [N][M]T, {K}V, {}T
  case expr.kind
  of nnkCommand:
    # [size] elementType or [] elementType or {keyType} valueType
    # Also [outer][inner] elementType for nested arrays
    if expr.len == 2:
      let indexPart = expr[0]
      result = indexPart.kind == nnkBracket or indexPart.kind == nnkBracketExpr or indexPart.kind == nnkCurly
    else:
      result = false
  of nnkBracketExpr:
    # Direct bracket expression [size, elementType]
    # But NOT if first child is an ident (e.g., seq[string], Table[K,V])
    if expr.len >= 1 and expr[0].kind == nnkIdent:
      result = false
    else:
      result = true



  of nnkCurlyExpr:
    # Direct curly expression {keyType, valueType} or {elementType}
    result = true
  of nnkPrefix:
    # ?T for Option[T]
    if expr.len == 2 and expr[0].kind == nnkIdent and expr[0].strVal == "?":
      result = true
    else:
      result = false
  of nnkInfix:
    # []?T parses as Infix("?", Bracket, T) — seq of optional
    if expr.len == 3 and expr[0].kind == nnkIdent and expr[0].strVal == "?" and
       expr[1].kind == nnkBracket:
      result = true
    else:
      result = false
  else:
    result = false

proc shouldUseHashSet(elementType: NimNode): bool =
  ## Determine if we should use HashSet instead of built-in set.
  ## Built-in sets only work with small ordinal types (<= 2^16 elements).
  case elementType.kind
  of nnkIdent:
    result = isLargeSetType(elementType.strVal)
  of nnkInfix:
    # Range types like 1..1000 - check if range is too large for built-in set
    if elementType[0].strVal == "..":
      # Try to parse range bounds to determine size
      let rangeStart = elementType[1]
      let rangeEnd = elementType[2]
      if rangeStart.kind == nnkIntLit and rangeEnd.kind == nnkIntLit:
        let size = rangeEnd.intVal - rangeStart.intVal + 1
        result = size > 256  # Use HashSet for ranges > 256 elements
      else:
        result = true  # Unknown range size, use HashSet to be safe
    else:
      result = false
  else:
    # Complex types or unknown - use HashSet to be safe
    result = true

proc parseBracketContent(node: NimNode): NimNode =
  ## Extract content from bracket node, handling single elements properly.
  if node.kind == nnkBracket:
    if node.len == 0:
      return newEmptyNode()  # Empty brackets []
    elif node.len == 1:
      return node[0]
    else:
      error("Expected single element in brackets, got: " & $node.len, node)
  else:
    return node

proc buildTypeFromBrackets(brackets: NimNode, elementType: NimNode): NimNode =
  ## Build array/seq type from bracket content and element type.
  let content = parseBracketContent(brackets)

  if content.kind == nnkEmpty:
    # Empty brackets [] -> seq
    let seqType = newNimNode(nnkBracketExpr)
    seqType.add(ident("seq"))
    seqType.add(elementType)
    return seqType
  else:
    # Non-empty brackets [N] -> array[N, T]
    let arrayType = newNimNode(nnkBracketExpr)
    arrayType.add(ident("array"))
    arrayType.add(content)
    arrayType.add(elementType)
    return arrayType

proc countBrackets(node: NimNode): int =
  ## Count nested bracket expressions in a node.
  case node.kind
  of nnkBracketExpr:
    1 + countBrackets(node[0])
  of nnkBracket:
    1
  else:
    0

proc extractBracketSequence(node: NimNode): seq[NimNode] =
  ## Extract a sequence of bracket nodes from nested bracket expressions.
  ## E.g., [3][4]int becomes [@[[3], 4], int]
  ## We process brackets from left to right, building types from inside out.
  result = @[]

  case node.kind
  of nnkCommand:
    # Pattern: [index]elementType or [outer][inner]elementType
    if node.len == 2:
      let indexPart = node[0]
      let elemPart = node[1]

      # If indexPart is a bracket expression, it may contain nested brackets
      if indexPart.kind == nnkBracketExpr:
        # Recursively extract brackets from the index part
        result = extractBracketSequence(indexPart)
      elif indexPart.kind == nnkBracket:
        # Single bracket like [3] or []
        result.add(indexPart)

      # If elemPart is also a command, it means more nested brackets
      if elemPart.kind == nnkCommand:
        # elemPart is something like [4]int - extract those brackets too
        let nested = extractBracketSequence(elemPart)
        for n in nested:
          result.add(n)
      elif elemPart.kind == nnkIdent or elemPart.kind == nnkBracketExpr:
        # elemPart is the base type or another bracket expression
        result.add(elemPart)

  of nnkBracketExpr:
    # This is a nested bracket like [3][4] where [3][4] is BracketExpr([3], 4)
    if node.len >= 1:
      if node[0].kind == nnkBracket:
        result.add(node[0])
      elif node[0].kind == nnkBracketExpr:
        let nested = extractBracketSequence(node[0])
        for n in nested:
          result.add(n)

      if node.len >= 2:
        if node[1].kind == nnkBracket or node[1].kind == nnkBracketExpr:
          let nested = extractBracketSequence(node[1])
          for n in nested:
            result.add(n)
        else:
          result.add(node[1])

  of nnkBracket:
    result.add(node)

  of nnkIdent:
    result.add(node)

  else:
    result.add(node)

proc buildNestedArrayType(expr: NimNode): NimNode =
  ## Recursively build nested array types from Odin-style DSL.
  ##
  ## Supported patterns:
  ## - `[N]T` → `array[N, T]`
  ## - `[]T` → `seq[T]`
  ## - `[N][M]T` → `array[N, array[M, T]]`
  ## - `[][N]T` → `seq[array[N, T]]`
  ## - `[N][]T` → `array[N, seq[T]]`
  ## - `[][]T` → `seq[seq[T]]`
  ## - `{K}V` → `Table[K, V]`
  ## - `{}T` → `set[T]` or `HashSet[T]`

  case expr.kind
  of nnkCommand:
    # Main DSL pattern: [index]elementType or {key}valueType
    if expr.len != 2:
      dslError("Expected pattern [index]elementType or {key}valueType with exactly 2 parts, got " & $expr.len, expr)

    let indexExpr = expr[0]
    let elementExpr = expr[1]

    # Recursively process element type if it's also a DSL pattern
    let elementType = if isArrayDSLPattern(elementExpr):
      buildNestedArrayType(elementExpr)
    else:
      elementExpr

    # Handle curly braces for tables and sets
    if indexExpr.kind == nnkCurly:
      if indexExpr.len == 0:
        # {}T -> set or HashSet
        if shouldUseHashSet(elementType):
          let hashSetType = newNimNode(nnkBracketExpr)
          hashSetType.add(ident("HashSet"))
          hashSetType.add(elementType)
          return hashSetType
        else:
          let setType = newNimNode(nnkBracketExpr)
          setType.add(ident("set"))
          setType.add(elementType)
          return setType
      elif indexExpr.len == 1:
        # {K}V -> Table[K, V] (works for all types including string)
        let keyType = indexExpr[0]
        let tableType = newNimNode(nnkBracketExpr)
        tableType.add(ident("Table"))
        tableType.add(keyType)
        tableType.add(elementType)
        return tableType
      else:
        dslError("Hash table syntax must be {keyType}valueType (single key type), got multiple types", indexExpr)

    # Handle square brackets for arrays and sequences
    elif indexExpr.kind == nnkBracket:
      return buildTypeFromBrackets(indexExpr, elementType)

    # Handle nested bracket expressions like [3][4]T or [3][]T
    # AST patterns:
    #   [3][4]int -> BracketExpr(Bracket(3), 4)
    #   [3][]string -> BracketExpr(Bracket(3))  (empty [] is implicit)
    #   [][4]int -> BracketExpr(Bracket) with 4 as element
    elif indexExpr.kind == nnkBracketExpr:
      var brackets: seq[NimNode] = @[]
      var current = indexExpr

      # Walk down the nested BracketExpr structure
      while current.kind == nnkBracketExpr:
        if current.len >= 1:
          brackets.add(current[0])  # Add the bracket (e.g., [3] or [])
        if current.len >= 2:
          # There's an inner index/content
          if current[1].kind == nnkBracketExpr:
            current = current[1]  # Continue down to more nested brackets
          elif current[1].kind == nnkBracket:
            brackets.add(current[1])  # Add inner bracket
            break
          else:
            # This is a raw index value (e.g., 4), wrap it in a bracket
            let wrappedBracket = newNimNode(nnkBracket)
            wrappedBracket.add(current[1])
            brackets.add(wrappedBracket)
            break
        else:
          # BracketExpr with only 1 element means the inner is empty []
          # Add an empty bracket to represent []
          brackets.add(newNimNode(nnkBracket))
          break

      # Now build the type from inside out
      # For [3][4]int: brackets = [[3], wrapped(4)], build array[4,int] then array[3,array[4,int]]
      # For [3][]string: brackets = [[3], empty], build seq[string] then array[3,seq[string]]
      result = elementType
      for i in countdown(brackets.len - 1, 0):
        result = buildTypeFromBrackets(brackets[i], result)

    else:
      dslError("Expected [index] for arrays/seqs or {key} for tables/sets, got " & $indexExpr.kind, indexExpr)

  of nnkBracketExpr:
    # Direct bracket expression [size, elementType]
    # But NOT if first child is an ident (e.g., seq[string], Table[K,V])
    if expr.len == 2 and expr[0].kind != nnkIdent:
      let arrayType = newNimNode(nnkBracketExpr)
      arrayType.add(ident("array"))
      arrayType.add(expr[0])
      arrayType.add(expr[1])
      return arrayType
    elif expr.len == 2 and expr[0].kind == nnkIdent:
      return expr
    else:
      dslError("Expected bracket expression [size, elementType] with 2 elements, got " & $expr.len, expr)

  of nnkCurlyExpr:
    # Direct curly expression {keyType, valueType} or {elementType}
    if expr.len == 1:
      let elementType = expr[0]
      if shouldUseHashSet(elementType):
        let hashSetType = newNimNode(nnkBracketExpr)
        hashSetType.add(ident("HashSet"))
        hashSetType.add(elementType)
        return hashSetType
      else:
        let setType = newNimNode(nnkBracketExpr)
        setType.add(ident("set"))
        setType.add(elementType)
        return setType
    elif expr.len == 2:
      let tableType = newNimNode(nnkBracketExpr)
      tableType.add(ident("Table"))
      tableType.add(expr[0])
      tableType.add(expr[1])
      return tableType
    else:
      dslError("Expected curly expression {elementType} for set or {keyType,valueType} for table, got " & $expr.len, expr)

  of nnkPrefix:
    # ?T -> Option[T]
    if expr.len == 2 and expr[0].kind == nnkIdent and expr[0].strVal == "?":
      let innerType = if isArrayDSLPattern(expr[1]):
        buildNestedArrayType(expr[1])
      else:
        expr[1]
      let optType = newNimNode(nnkBracketExpr)
      optType.add(ident("Option"))
      optType.add(innerType)
      return optType
    else:
      return expr

  of nnkInfix:
    # []?T parses as Infix("?", Bracket, T) — rewrite as seq[Option[T]]
    if expr.len == 3 and expr[0].kind == nnkIdent and expr[0].strVal == "?" and
       expr[1].kind == nnkBracket:
      let brackets = expr[1]
      let elementType = expr[2]
      # Wrap element in Option
      let optType = newNimNode(nnkBracketExpr)
      optType.add(ident("Option"))
      optType.add(elementType)
      # Build seq or array from brackets
      return buildTypeFromBrackets(brackets, optType)
    else:
      return expr

  else:
    # Not a DSL pattern, return as-is
    return expr

proc transformNoneInit(typeExpr, value: NimNode): NimNode =
  ## If type is ?T and value is None, return none(T). Otherwise return value as-is.
  if value.kind == nnkIdent and value.strVal == "None" and
     typeExpr.kind == nnkPrefix and typeExpr.len == 2 and
     typeExpr[0].kind == nnkIdent and typeExpr[0].strVal == "?":
    return newCall(ident("none"), typeExpr[1].copy())
  return value

proc processDeclareBody(body: NimNode): NimNode =
  ## Process declarations from a declare block and return the transformed statements.
  ## This is used for nested declare/begin (inside functions).
  var declarations: seq[NimNode] = @[]

  for stmt in body:
    case stmt.kind
    of nnkVarSection, nnkLetSection, nnkConstSection:
      # Process variable declarations with DSL type annotations
      var newSection = newNimNode(stmt.kind)
      for identDef in stmt:
        if identDef.kind == nnkIdentDefs:
          # identDef has format: nnkIdentDefs(ident, typeExpr, value)
          let ident = identDef[0]
          var typeExpr = identDef[1]
          let value = transformNoneInit(typeExpr,
            if identDef.len > 2: identDef[2] else: newEmptyNode())

          # Check if type expression is a DSL pattern
          if isArrayDSLPattern(typeExpr):
            let processedType = buildNestedArrayType(typeExpr)
            # Use newIdentDefs helper for correct AST construction
            let newIdentDef = newIdentDefs(ident, processedType, value)
            newSection.add(newIdentDef)
          else:
            newSection.add(identDef)
        else:
          newSection.add(identDef)
      declarations.add(newSection)
    of nnkProcDef, nnkFuncDef:
      declarations.add(stmt)
    of nnkTypeSection:
      # Process each type definition in the type section
      for typeDef in stmt:
        if typeDef.kind == nnkTypeDef:
          let typeName = typeDef[0]
          let typeExpr = typeDef[2]

          if isArrayDSLPattern(typeExpr):
            let arrayType = buildNestedArrayType(typeExpr)

            # Create a new type definition with the processed type
            let newTypeDef = newNimNode(nnkTypeDef)
            newTypeDef.add(typeName)
            newTypeDef.add(newEmptyNode())
            newTypeDef.add(arrayType)

            # Create a type section with this single type
            let typeSection = newNimNode(nnkTypeSection)
            typeSection.add(newTypeDef)
            declarations.add(typeSection)
          else:
            # Just add regular type definitions as-is
            let typeSection = newNimNode(nnkTypeSection)
            typeSection.add(typeDef)
            declarations.add(typeSection)
    of nnkCommand:
      # Handle "type typeName = [size]elementType" or "type typeName: [size]elementType"
      if stmt.len >= 3 and stmt[0].kind == nnkIdent and stmt[0].strVal == "type":
        let typeName = stmt[1]

        # Check for both = and : as separators (type Foo = Bar or type Foo: Bar)
        let sepNode = stmt[2]
        var typeExpr: NimNode

        if sepNode.kind == nnkIdent and sepNode.strVal in ["=", "is"]:
          if stmt.len >= 4:
            typeExpr = stmt[3]
          else:
            declareError("Type declaration missing type expression after '" & sepNode.strVal & "'", stmt)
        else:
          # No separator, stmt[2] is the type expression
          typeExpr = sepNode

        # Validate typeExpr before using
        if typeExpr.kind == nnkEmpty:
          declareError("Type declaration has empty type expression", stmt)

        if isArrayDSLPattern(typeExpr):
          let arrayType = buildNestedArrayType(typeExpr)

          # Create a type section with this single type
          let typeSection = newNimNode(nnkTypeSection)
          let typeDef = newNimNode(nnkTypeDef)
          typeDef.add(typeName)
          typeDef.add(newEmptyNode())
          typeDef.add(arrayType)
          typeSection.add(typeDef)

          declarations.add(typeSection)
        else:
          declareError("Expected array DSL pattern like [8]int, {string}int, or {}char. " &
                       "Valid patterns:\n" &
                       "  - [N]T for fixed arrays: type MyArray = [8]int\n" &
                       "  - []T for sequences: type MySeq = []string\n" &
                       "  - [N][M]T for nested: type Matrix = [3][4]int\n" &
                       "  - {K}V for tables: type MyTable = {string}int\n" &
                       "  - {}T for sets: type CharSet = {}char\n" &
                       "Got: " & typeExpr.repr, typeExpr)
      else:
        declareError("Expected type declaration in format 'type Name = [size]elementType'.\n" &
                     "Example: type MyArray = [8]int", stmt)
    else:
      declareError("Only var/let/const/type/proc/func declarations allowed in declare block.\n" &
                   "Got: " & $stmt.kind & " (did you forget 'type' keyword?)", stmt)

  result = newStmtList()
  for decl in declarations:
    result.add(decl)

proc storeDeclareBlock(label: NimNode, body: NimNode) =
  ## Process declarations from a declare block and store them for later use.
  var declarations: seq[NimNode] = @[]

  for stmt in body:
    case stmt.kind
    of nnkVarSection, nnkLetSection, nnkConstSection:
      # Process variable declarations with DSL type annotations
      var newSection = newNimNode(stmt.kind)
      for identDef in stmt:
        if identDef.kind == nnkIdentDefs:
          # identDef has format: nnkIdentDefs(ident, typeExpr, value)
          let ident = identDef[0]
          var typeExpr = identDef[1]
          let value = transformNoneInit(typeExpr,
            if identDef.len > 2: identDef[2] else: newEmptyNode())

          # Check if type expression is a DSL pattern
          if isArrayDSLPattern(typeExpr):
            let processedType = buildNestedArrayType(typeExpr)
            # Use newIdentDefs helper for correct AST construction
            let newIdentDef = newIdentDefs(ident, processedType, value)
            newSection.add(newIdentDef)
          else:
            newSection.add(identDef)
        else:
          newSection.add(identDef)
      declarations.add(newSection)
    of nnkProcDef, nnkFuncDef:
      declarations.add(stmt)
    of nnkTypeSection:
      # Process each type definition in the type section
      for typeDef in stmt:
        if typeDef.kind == nnkTypeDef:
          let typeName = typeDef[0]
          let typeExpr = typeDef[2]

          if isArrayDSLPattern(typeExpr):
            let arrayType = buildNestedArrayType(typeExpr)

            # Create a new type definition with the processed type
            let newTypeDef = newNimNode(nnkTypeDef)
            newTypeDef.add(typeName)
            newTypeDef.add(newEmptyNode())
            newTypeDef.add(arrayType)

            # Create a type section with this single type
            let typeSection = newNimNode(nnkTypeSection)
            typeSection.add(newTypeDef)
            declarations.add(typeSection)
          else:
            # Just add regular type definitions as-is
            let typeSection = newNimNode(nnkTypeSection)
            typeSection.add(typeDef)
            declarations.add(typeSection)
    of nnkCommand:
      # Handle "type typeName = [size]elementType" or "type typeName: [size]elementType"
      if stmt.len >= 3 and stmt[0].kind == nnkIdent and stmt[0].strVal == "type":
        let typeName = stmt[1]

        # Check for both = and : as separators (type Foo = Bar or type Foo: Bar)
        let sepNode = stmt[2]
        var typeExpr: NimNode

        if sepNode.kind == nnkIdent and sepNode.strVal in ["=", "is"]:
          if stmt.len >= 4:
            typeExpr = stmt[3]
          else:
            declareError("Type declaration missing type expression after '" & sepNode.strVal & "'", stmt)
        else:
          # No separator, stmt[2] is the type expression
          typeExpr = sepNode

        # Validate typeExpr before using
        if typeExpr.kind == nnkEmpty:
          declareError("Type declaration has empty type expression", stmt)

        if isArrayDSLPattern(typeExpr):
          let arrayType = buildNestedArrayType(typeExpr)

          # Create a type section with this single type
          let typeSection = newNimNode(nnkTypeSection)
          let typeDef = newNimNode(nnkTypeDef)
          typeDef.add(typeName)
          typeDef.add(newEmptyNode())
          typeDef.add(arrayType)
          typeSection.add(typeDef)

          declarations.add(typeSection)
        else:
          declareError("Expected array DSL pattern like [8]int, {string}int, or {}char. " &
                       "Valid patterns:\n" &
                       "  - [N]T for fixed arrays: type MyArray = [8]int\n" &
                       "  - []T for sequences: type MySeq = []string\n" &
                       "  - [N][M]T for nested: type Matrix = [3][4]int\n" &
                       "  - {K}V for tables: type MyTable = {string}int\n" &
                       "  - {}T for sets: type CharSet = {}char\n" &
                       "Got: " & typeExpr.repr, typeExpr)
      else:
        declareError("Expected type declaration in format 'type Name = [size]elementType'.\n" &
                     "Example: type MyArray = [8]int", stmt)
    else:
      declareError("Only var/let/const/type/proc/func declarations allowed in declare block.\n" &
                   "Got: " & $stmt.kind & " (did you forget 'type' keyword?)", stmt)

  if label != nil:
    let labelStr = label.repr
    labeledDeclarations[labelStr] = declarations
    lastDeclareLabel = labelStr
  else:
    unlabeledDeclarations = declarations
    lastDeclareLabel = ""

macro declare*(body: untyped): untyped =
  ## Unlabeled declare block with new array DSL syntax:
  ## declare:
  ##   type my_array_T = [8]int
  ##   type my_table_T = {string}int
  ##   type my_set_T = {}char
  ##   var x = 42
  ##
  ## Can be used at top-level (paired with begin:) or inside functions (Ada-style).
  ## For nested usage inside functions, use with begin: as a block pair.

  # Check if we're in nested context (inside a function) by checking if there's
  # already a pending declare waiting for begin
  if unlabeledDeclarations.len > 0 or lastDeclareLabel != "":
    # Top-level usage - store for later begin
    storeDeclareBlock(nil, body)
    result = newStmtList()
  else:
    # Nested usage inside function - mark as active and store for begin
    nestedDeclareActive = true
    storeDeclareBlock(nil, body)
    result = newStmtList()

macro declare*(label: untyped, body: untyped): untyped =
  ## Labeled declare block with new array DSL syntax:
  ## declare scope_name:
  ##   type my_array_T = [8]int
  ##   type my_table_T = {string}int
  ##   type my_set_T = {}char
  ##   var data: my_array_T
  ##
  ## Can be used at top-level (paired with begin:) or inside functions (Ada-style).
  let labelStr = label.repr

  # Check if this is top-level usage or nested
  if labelStr in labeledDeclarations or unlabeledDeclarations.len > 0 or lastDeclareLabel != "":
    # Top-level usage - store for later begin
    storeDeclareBlock(label, body)
    result = newStmtList()
  else:
    # Nested usage inside function - mark as active and store for begin
    nestedDeclareActive = true
    storeDeclareBlock(label, body)
    result = newStmtList()

macro `begin`*(body: untyped): untyped =
  ## Handle begin: blocks - automatically pairs with preceding declare:
  ## Works for both unlabeled and labeled declare blocks.
  ## Also supports nested declare/begin inside functions (Ada-style).

  # Check if we have pending unlabeled declarations (top-level or nested)
  if unlabeledDeclarations.len > 0:
    let decls = newStmtList()
    # Add all pending declarations
    for decl in unlabeledDeclarations:
      decls.add(decl)

    # Add the body statements
    for stmt in body:
      decls.add(stmt)

    # Clear pending declarations
    unlabeledDeclarations = @[]
    let wasNested = nestedDeclareActive
    nestedDeclareActive = false
    lastDeclareLabel = ""

    # Create unlabeled block with all declarations and statements
    result = newTree(nnkBlockStmt, newEmptyNode(), decls)
  # Check if we have a recent labeled declare that hasn't been consumed (top-level or nested)
  elif lastDeclareLabel != "" and lastDeclareLabel in labeledDeclarations:
    let decls = newStmtList()
    # Add all pending declarations for the last label
    for decl in labeledDeclarations[lastDeclareLabel]:
      decls.add(decl)

    # Add the body statements
    for stmt in body:
      decls.add(stmt)

    # Remove this label's declarations and clear last label
    labeledDeclarations.del(lastDeclareLabel)
    let label = newIdentNode(lastDeclareLabel)
    let wasNested = nestedDeclareActive
    nestedDeclareActive = false
    lastDeclareLabel = ""

    # Create labeled block with all declarations and statements
    result = newTree(nnkBlockStmt, label, decls)
  else:
    # No pending declarations - standalone begin, just wrap body in block
    result = newTree(nnkBlockStmt, newEmptyNode(), body)

macro `begin`*(label: untyped, body: untyped): untyped =
  ## Explicitly labeled begin block (for standalone use)
  ## Note: Usually not needed since begin: automatically pairs with declare label:
  let labelStr = label.repr
  if labelStr in labeledDeclarations:
    let decls = newStmtList()
    for decl in labeledDeclarations[labelStr]:
      decls.add(decl)

    for stmt in body:
      decls.add(stmt)

    labeledDeclarations.del(labelStr)
    result = newTree(nnkBlockStmt, label, decls)
  else:
    result = newTree(nnkBlockStmt, label, body)


# Usage example and comprehensive tests:

# ============================================================================
# GLOBALS MACRO - Module-level Ada-style declarations
# ============================================================================

proc processGlobalsBody(body: NimNode): NimNode =
  ## Process declarations from a globals block and return transformed statements.
  ## Unlike declare/begin, this emits declarations directly at module scope.
  var declarations: seq[NimNode] = @[]

  for stmt in body:
    case stmt.kind
    of nnkVarSection, nnkLetSection, nnkConstSection:
      # Process variable declarations with DSL type annotations
      var newSection = newNimNode(stmt.kind)
      for identDef in stmt:
        if identDef.kind == nnkIdentDefs:
          let ident = identDef[0]
          var typeExpr = identDef[1]
          let value = transformNoneInit(typeExpr,
            if identDef.len > 2: identDef[2] else: newEmptyNode())

          # Check if type expression is a DSL pattern
          if isArrayDSLPattern(typeExpr):
            let processedType = buildNestedArrayType(typeExpr)
            let newIdentDef = newIdentDefs(ident, processedType, value)
            newSection.add(newIdentDef)
          else:
            newSection.add(identDef)
        else:
          newSection.add(identDef)
      declarations.add(newSection)
    of nnkProcDef, nnkFuncDef:
      declarations.add(stmt)
    of nnkTypeSection:
      # Process each type definition in the type section
      for typeDef in stmt:
        if typeDef.kind == nnkTypeDef:
          let typeName = typeDef[0]
          let typeExpr = typeDef[2]

          if isArrayDSLPattern(typeExpr):
            let arrayType = buildNestedArrayType(typeExpr)
            let newTypeDef = newNimNode(nnkTypeDef)
            newTypeDef.add(typeName)
            newTypeDef.add(newEmptyNode())
            newTypeDef.add(arrayType)
            let typeSection = newNimNode(nnkTypeSection)
            typeSection.add(newTypeDef)
            declarations.add(typeSection)
          else:
            # Check if object fields contain DSL types (like []uint8)
            if typeExpr.kind == nnkObjectTy:
              let newObjectTy = newNimNode(nnkObjectTy)
              # ObjectTy has 3 children: [0]=pragmas, [1]=inheritance, [2]=recList
              newObjectTy.add(typeExpr[0].copy())  # pragmas
              newObjectTy.add(typeExpr[1].copy())  # inheritance

              # Process record fields
              if typeExpr.len >= 3 and typeExpr[2].kind == nnkRecList:
                let newRecList = newNimNode(nnkRecList)
                for field in typeExpr[2]:
                  if field.kind == nnkIdentDefs:
                    # IdentDefs: name1, name2, ..., type, default
                    let fieldType = field[^2]
                    let defaultValue = field[^1]

                    # Check if field type is a DSL pattern
                    if isArrayDSLPattern(fieldType):
                      let processedType = buildNestedArrayType(fieldType)
                      var newField = newNimNode(nnkIdentDefs)
                      for i in 0 ..< field.len - 2:
                        newField.add(field[i].copy())
                      newField.add(processedType)
                      newField.add(defaultValue.copy())
                      newRecList.add(newField)
                    else:
                      newRecList.add(field.copy())
                  else:
                    newRecList.add(field.copy())
                newObjectTy.add(newRecList)
              else:
                # Copy recList as-is if not present or not a RecList
                if typeExpr.len >= 3:
                  newObjectTy.add(typeExpr[2].copy())

              let newTypeDef = newNimNode(nnkTypeDef)
              newTypeDef.add(typeName)
              newTypeDef.add(newEmptyNode())
              newTypeDef.add(newObjectTy)
              let typeSection = newNimNode(nnkTypeSection)
              typeSection.add(newTypeDef)
              declarations.add(typeSection)
            elif typeExpr.kind == nnkCall and typeExpr[0].kind == nnkIdent and
                 typeExpr[0].strVal == "record":
              # record: alias for object — convert to nnkObjectTy
              let recordBody = typeExpr[1]  # StmtList
              let newObjectTy = newNimNode(nnkObjectTy)
              newObjectTy.add(newEmptyNode())  # pragmas
              newObjectTy.add(newEmptyNode())  # inheritance
              let recList = newNimNode(nnkRecList)
              for fieldStmt in recordBody:
                if fieldStmt.kind == nnkCall and fieldStmt.len == 2 and fieldStmt[0].kind == nnkIdent:
                  let fieldName = fieldStmt[0]
                  let fieldTypeExpr = fieldStmt[1][0]
                  let processedType = if isArrayDSLPattern(fieldTypeExpr):
                    buildNestedArrayType(fieldTypeExpr)
                  else:
                    fieldTypeExpr.copy()
                  recList.add(newIdentDefs(fieldName.copy(), processedType, newEmptyNode()))
                elif fieldStmt.kind == nnkVarSection:
                  for identDef in fieldStmt:
                    if identDef.kind == nnkIdentDefs:
                      let fieldType = identDef[^2]
                      let processedType = if isArrayDSLPattern(fieldType):
                        buildNestedArrayType(fieldType)
                      else:
                        fieldType.copy()
                      var newField = newNimNode(nnkIdentDefs)
                      for i in 0 ..< identDef.len - 2:
                        newField.add(identDef[i].copy())
                      newField.add(processedType)
                      newField.add(identDef[^1].copy())
                      recList.add(newField)
              newObjectTy.add(recList)
              let newTypeDef = newNimNode(nnkTypeDef)
              newTypeDef.add(typeName)
              newTypeDef.add(newEmptyNode())
              newTypeDef.add(newObjectTy)
              let typeSection = newNimNode(nnkTypeSection)
              typeSection.add(newTypeDef)
              declarations.add(typeSection)
            else:
              let typeSection = newNimNode(nnkTypeSection)
              typeSection.add(typeDef)
              declarations.add(typeSection)
    of nnkCommand:
      # Handle "type typeName = [size]elementType" or "type typeName: [size]elementType"
      if stmt.len >= 3 and stmt[0].kind == nnkIdent and stmt[0].strVal == "type":
        let typeName = stmt[1]
        let sepNode = stmt[2]
        var typeExpr: NimNode

        if sepNode.kind == nnkIdent and sepNode.strVal in ["=", "is"]:
          if stmt.len >= 4:
            typeExpr = stmt[3]
          else:
            declareError("Type declaration missing type expression after '" & sepNode.strVal & "'", stmt)
        else:
          typeExpr = sepNode

        if typeExpr.kind == nnkEmpty:
          declareError("Type declaration has empty type expression", stmt)

        if isArrayDSLPattern(typeExpr):
          let arrayType = buildNestedArrayType(typeExpr)
          let typeSection = newNimNode(nnkTypeSection)
          let typeDef = newNimNode(nnkTypeDef)
          typeDef.add(typeName)
          typeDef.add(newEmptyNode())
          typeDef.add(arrayType)
          typeSection.add(typeDef)
          declarations.add(typeSection)
        else:
          declareError("Expected array DSL pattern like [8]int, {string}int, or {}char. " &
                       "Valid patterns:\n" &
                       "  - [N]T for fixed arrays: type MyArray = [8]int\n" &
                       "  - []T for sequences: type MySeq = []string\n" &
                       "  - [N][M]T for nested: type Matrix = [3][4]int\n" &
                       "  - {K}V for tables: type MyTable = {string}int\n" &
                       "  - {}T for sets: type CharSet = {}char\n" &
                       "Got: " & typeExpr.repr, typeExpr)
      else:
        declareError("Expected type declaration in format 'type Name = [size]elementType'.\n" &
                     "Example: type MyArray = [8]int", stmt)
    else:
      declareError("Only var/let/const/type/proc/func declarations allowed in globals block.\n" &
                   "Got: " & $stmt.kind & " (did you forget 'type' keyword?)", stmt)

  result = newStmtList()
  for decl in declarations:
    result.add(decl)

macro globals*(body: untyped): untyped =
  ## Module-level global declarations with Ada-style DSL syntax:
  ## globals:
  ##   const KILO_VERSION = "0.0.1"
  ##   const KILO_TAB_STOP = 8
  ##
  ##   type EditorKey = enum
  ##     BACKSPACE = 127
  ##     ARROW_LEFT = 1000
  ##     ARROW_RIGHT, ARROW_UP, ARROW_DOWN
  ##
  ##   type ERow = object
  ##     size, rsize: int
  ##     chars, render: string
  ##     hl: []uint8  # DSL syntax for seq[uint8]
  ##
  ## This macro processes declarations at module scope (unlike declare/begin which wraps in block).
  ## Supports full AdaScript array DSL: [N]T, []T, {K}V, {}T, and nested combinations.

  result = processGlobalsBody(body)
