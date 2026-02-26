################################################
# 0. DEF MACRO - Python-style function definitions
# Supports: generics, pragmas, default values (~ operator),
# varargs, multi-param same type, var params.
# Works both standalone and inside class blocks.

# ============================================================================
# Error message helpers
# ============================================================================

proc defError(msg: string, node: NimNode) =
  ## Raise a compile-time error with helpful context for def syntax issues.
  error("AdaScript def: " & msg & "\n" &
        "  Usage:\n" &
        "    def name(params) -> ReturnType:\n" &
        "      body\n" &
        "  Examples:\n" &
        "    def greet(name: string) -> string: \"hello \" & name\n" &
        "    def add[T](a: T, b: T) -> T: a + b\n" &
        "    def greet(name: string ~ \"world\"): echo name\n" &
        "  Found: " & node.repr, node)

proc classError(msg: string, node: NimNode) =
  ## Raise a compile-time error with helpful context for class syntax issues.
  error("AdaScript class: " & msg & "\n" &
        "  Usage:\n" &
        "    class ClassName:\n" &
        "      var field: Type\n" &
        "      def init(self: ClassName, ...):\n" &
        "        self.field = value\n" &
        "      def method(self: ClassName) -> Type:\n" &
        "        body\n" &
        "  With inheritance:\n" &
        "    class Child(Parent):\n" &
        "      ...\n" &
        "  Found: " & node.repr, node)

# ============================================================================
# Def macro implementation
# ============================================================================

proc buildNestedArrayTypeForDef(expr: NimNode): NimNode =
  ## Build array/seq/table/set types from AdaScript DSL syntax.
  ## [N]T -> array[N, T], []T -> seq[T], {K}V -> Table[K, V], {}T -> set[T]
  case expr.kind
  of nnkCommand:
    if expr.len != 2:
      return expr
    let indexExpr = expr[0]
    let elementExpr = expr[1]
    let elementType = if indexExpr.kind in {nnkCommand, nnkBracketExpr, nnkCurlyExpr}:
      buildNestedArrayTypeForDef(elementExpr)
    else:
      elementExpr

    if indexExpr.kind == nnkCurly:
      if indexExpr.len == 0:
        let setType = newNimNode(nnkBracketExpr)
        setType.add(ident("set"))
        setType.add(elementType)
        return setType
      elif indexExpr.len == 1:
        let tableType = newNimNode(nnkBracketExpr)
        tableType.add(ident("Table"))
        tableType.add(indexExpr[0])
        tableType.add(elementType)
        return tableType
    elif indexExpr.kind == nnkBracket:
      if indexExpr.len == 0:
        let seqType = newNimNode(nnkBracketExpr)
        seqType.add(ident("seq"))
        seqType.add(elementType)
        return seqType
      else:
        let arrayType = newNimNode(nnkBracketExpr)
        arrayType.add(ident("array"))
        arrayType.add(indexExpr[0])
        arrayType.add(elementType)
        return arrayType
    elif indexExpr.kind == nnkBracketExpr:
      return buildNestedArrayTypeForDef(indexExpr)
    else:
      return expr
  of nnkBracketExpr:
    # Only transform if the first element is NOT already a type identifier
    # (e.g., varargs[int], seq[string], Option[T] should pass through)
    if expr.len == 2 and expr[0].kind != nnkIdent:
      let arrayType = newNimNode(nnkBracketExpr)
      arrayType.add(ident("array"))
      arrayType.add(expr[0])
      arrayType.add(expr[1])
      return arrayType
    else:
      return expr
  of nnkCurlyExpr:
    if expr.len == 1:
      let setType = newNimNode(nnkBracketExpr)
      setType.add(ident("set"))
      setType.add(expr[0])
      return setType
    elif expr.len == 2:
      let tableType = newNimNode(nnkBracketExpr)
      tableType.add(ident("Table"))
      tableType.add(expr[0])
      tableType.add(expr[1])
      return tableType
  of nnkPrefix:
    # ?T -> Option[T]
    if expr.len == 2 and expr[0].kind == nnkIdent and expr[0].strVal == "?":
      let innerType = buildNestedArrayTypeForDef(expr[1])
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
      let optType = newNimNode(nnkBracketExpr)
      optType.add(ident("Option"))
      optType.add(elementType)
      # Build seq or array from brackets
      if brackets.len == 0:
        let seqType = newNimNode(nnkBracketExpr)
        seqType.add(ident("seq"))
        seqType.add(optType)
        return seqType
      else:
        let arrayType = newNimNode(nnkBracketExpr)
        arrayType.add(ident("array"))
        arrayType.add(brackets[0])
        arrayType.add(optType)
        return arrayType
    else:
      return expr
  else:
    return expr

proc parseDefSignature(signature: NimNode): (NimNode, seq[NimNode], seq[NimNode]) =
  ## Parse function name, generic params, and regular params from signature
  var procName: NimNode
  var genericParams: seq[NimNode] = @[]
  var params: seq[NimNode] = @[]

  proc extractNameAndGenerics(node: NimNode): NimNode =
    if node.kind == nnkBracketExpr:
      for i in 1..<node.len:
        genericParams.add(node[i])
      return node[0]
    return node

  proc processParams(node: NimNode, startIdx: int) =
    var i = startIdx
    while i < node.len:
      let param = node[i]
      if param.kind == nnkExprColonExpr:
        let paramName = param[0]
        var paramType = param[1]
        var defaultVal = newEmptyNode()

        # Check for default value: type ~ default
        if paramType.kind == nnkInfix and paramType[0].strVal == "~":
          defaultVal = paramType[2]
          paramType = paramType[1]

        # Transform DSL type patterns (e.g., []string -> seq[string])
        paramType = buildNestedArrayTypeForDef(paramType)

        # Check for bare idents before this (multi-param same type: a, b, c: int)
        # Exclude bare `self` — it gets its own param with empty type (for class injection)
        var names: seq[NimNode] = @[]
        var selfNodes: seq[NimNode] = @[]
        var j = i - 1
        while j >= startIdx:
          if node[j].kind == nnkIdent:
            if node[j].strVal == "self":
              selfNodes.insert(node[j], 0)
            else:
              names.insert(node[j], 0)
            j -= 1
          else:
            break

        # Emit bare self as its own param with empty type
        for s in selfNodes:
          params.add(newIdentDefs(s, newEmptyNode(), newEmptyNode()))

        if names.len > 0:
          names.add(paramName)
          var identDefs = newNimNode(nnkIdentDefs)
          for n in names:
            identDefs.add(n)
          identDefs.add(paramType)
          identDefs.add(defaultVal)
          params.add(identDefs)
        else:
          params.add(newIdentDefs(paramName, paramType, defaultVal))
      elif param.kind == nnkIdent and param.strVal == "self" and i == node.len - 1:
        # Trailing bare `self` with no typed param after it (e.g., def speak(self))
        params.add(newIdentDefs(param, newEmptyNode(), newEmptyNode()))
      i += 1

  case signature.kind:
  of nnkIdent:
    procName = signature
  of nnkCall:
    procName = extractNameAndGenerics(signature[0])
    processParams(signature, 1)
  of nnkObjConstr:
    procName = extractNameAndGenerics(signature[0])
    processParams(signature, 1)
  else:
    defError("Invalid function signature syntax. Expected: name, name[T], or name(args)", signature)

  return (procName, genericParams, params)

proc wrapOptionalReturns(node: NimNode, innerType: NimNode): NimNode =
  ## When a def has return type ?T, transform return statements:
  ##   return value  ->  return toOption(value)   (idempotent for Option[T])
  ##   return None   ->  return none(T)
  ## Recurses into all control flow blocks.
  if node.kind == nnkReturnStmt:
    let val = node[0]
    if val.kind == nnkIdent and val.strVal == "None":
      # return None -> return none(T)
      return newTree(nnkReturnStmt, newCall(ident("none"), innerType.copy()))
    elif val.kind != nnkEmpty:
      # return X -> return toOption(X)
      return newTree(nnkReturnStmt, newCall(ident("toOption"), val))
    else:
      return node
  else:
    result = node.copyNimNode()
    for child in node:
      result.add(wrapOptionalReturns(child, innerType))

proc buildDefProc(head, body: NimNode, exported: bool): NimNode =
  var returnType: NimNode = newEmptyNode()
  var rawReturnType: NimNode = newEmptyNode()  # pre-DSL-transform return type
  var pragmas = newEmptyNode()
  var signature: NimNode

  # Check for PragmaExpr wrapping the whole head (pragma without return type)
  if head.kind == nnkPragmaExpr:
    pragmas = head[1]
    signature = head[0]
  # Check for -> return type
  elif head.kind == nnkInfix and head[0].strVal == "->":
    signature = head[1]
    let retNode = head[2]
    if retNode.kind == nnkPragmaExpr:
      rawReturnType = retNode[0]
      returnType = buildNestedArrayTypeForDef(rawReturnType)
      pragmas = retNode[1]
    else:
      rawReturnType = retNode
      returnType = buildNestedArrayTypeForDef(rawReturnType)
  else:
    signature = head

  # If return type is ?T, wrap return statements in some()/none()
  var transformedBody = body
  if rawReturnType.kind == nnkPrefix and rawReturnType.len == 2 and
     rawReturnType[0].kind == nnkIdent and rawReturnType[0].strVal == "?":
    let innerType = rawReturnType[1]
    transformedBody = wrapOptionalReturns(body, innerType)

  let (procName, genericParams, params) = parseDefSignature(signature)

  var formalParams = newNimNode(nnkFormalParams)
  formalParams.add(returnType)
  for p in params:
    formalParams.add(p)

  var genericParamNode = newEmptyNode()
  if genericParams.len > 0:
    genericParamNode = newNimNode(nnkGenericParams)
    for gp in genericParams:
      var identDefs = newNimNode(nnkIdentDefs)
      identDefs.add(gp)
      identDefs.add(newEmptyNode())
      identDefs.add(newEmptyNode())
      genericParamNode.add(identDefs)

  result = newNimNode(nnkProcDef)
  if exported:
    result.add(postfix(procName, "*"))
  else:
    result.add(procName)
  result.add(newEmptyNode())
  result.add(genericParamNode)
  result.add(formalParams)
  result.add(pragmas)
  result.add(newEmptyNode())
  result.add(transformedBody)

proc expandDef*(stmt: NimNode): NimNode =
  ## Convert a 'def' command node into a nnkProcDef node (for use inside class)
  if stmt.kind != nnkCommand or stmt[0].kind != nnkIdent or stmt[0].strVal != "def":
    return nil
  if stmt.len != 3:
    return nil
  return buildDefProc(stmt[1], stmt[^1], false)

proc injectSelfType(procDef: NimNode, typeName: NimNode): NimNode =
  ## Inject the class type for bare `self` or `self: var` parameters.
  ## - bare `self` in call args becomes a param with no type -> inject ClassName
  ## - `self: var` (empty VarTy) -> inject var ClassName
  ## - `self: ClassName` or `self: var ClassName` -> leave alone
  ##
  ## Also handles the case where bare `self` was skipped by parseDefSignature
  ## (it appears as a bare ident, not ExprColonExpr, so it's not added to params).
  result = procDef.copy()
  let formalParams = result.params

  # Check if first param after return type is `self`-typed
  if formalParams.len > 1:
    let firstParam = formalParams[1]
    # firstParam is IdentDefs: name, type, default
    if firstParam.kind == nnkIdentDefs and firstParam.len >= 3:
      let paramName = firstParam[0]
      let paramType = firstParam[1]
      if paramName.kind == nnkIdent and paramName.strVal == "self":
        if paramType.kind == nnkEmpty:
          # self with no type -> inject ClassName
          firstParam[1] = typeName.copy()
        elif paramType.kind == nnkVarTy and paramType.len == 0:
          # self: var (empty VarTy) -> inject var ClassName
          paramType.add(typeName.copy())
  else:
    # No params at all — check if the original def had a bare `self` that was
    # skipped. We need to look at the original statement, but at this point
    # we only have the procDef. Instead, we handle this in the class macro
    # by pre-processing the raw statement before expandDef.
    discard

proc prependSelfParam(procDef: NimNode, typeName: NimNode) =
  ## Add a `self: ClassName` parameter as the first param if no params exist
  ## or if the first param is not named `self`.
  let formalParams = procDef.params
  var hasSelf = false
  if formalParams.len > 1:
    let firstParam = formalParams[1]
    if firstParam.kind == nnkIdentDefs and firstParam.len >= 3:
      let paramName = firstParam[0]
      if paramName.kind == nnkIdent and paramName.strVal == "self":
        hasSelf = true

  if not hasSelf:
    # Insert self: ClassName as first parameter
    let selfParam = newIdentDefs(ident("self"), typeName.copy())
    formalParams.insert(1, selfParam)

proc processObjectFieldsDSL(objectTy: NimNode): NimNode =
  ## Process an object type, converting DSL types in fields.
  ## ObjectTy has 3 children: [0]=pragmas, [1]=inheritance, [2]=recList
  result = newNimNode(nnkObjectTy)
  result.add(objectTy[0].copy())  # pragmas
  result.add(objectTy[1].copy())  # inheritance

  if objectTy.len >= 3 and objectTy[2].kind == nnkRecList:
    let newRecList = newNimNode(nnkRecList)
    for field in objectTy[2]:
      if field.kind == nnkIdentDefs:
        # IdentDefs: name1, name2, ..., type, default
        let fieldType = field[^2]
        let defaultValue = field[^1]

        if fieldType.kind in {nnkCommand, nnkBracketExpr, nnkCurlyExpr, nnkPrefix, nnkInfix}:
          let processedType = buildNestedArrayTypeForDef(fieldType)
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
    result.add(newRecList)
  else:
    if objectTy.len >= 3:
      result.add(objectTy[2].copy())

proc buildRecordObjectTy(callNode: NimNode): NimNode =
  ## Convert a `record:` call node into an nnkObjectTy.
  ## Each field is Call(Ident "name", StmtList(typeExpr)) or
  ## VarSection(IdentDefs(name1, name2, ..., type, default)) for multi-name fields.
  result = newNimNode(nnkObjectTy)
  result.add(newEmptyNode())  # pragmas
  result.add(newEmptyNode())  # inheritance

  let recList = newNimNode(nnkRecList)
  let body = callNode[1]  # StmtList
  for stmt in body:
    if stmt.kind == nnkCall and stmt.len == 2 and stmt[0].kind == nnkIdent:
      # Single field: Call(Ident "name", StmtList(typeExpr))
      let fieldName = stmt[0]
      let typeExpr = stmt[1][0]  # first child of StmtList
      let processedType = buildNestedArrayTypeForDef(typeExpr)
      recList.add(newIdentDefs(fieldName.copy(), processedType, newEmptyNode()))
    elif stmt.kind == nnkVarSection:
      # Multi-name field: var name1, name2: type
      for identDef in stmt:
        if identDef.kind == nnkIdentDefs:
          let fieldType = buildNestedArrayTypeForDef(identDef[^2])
          var newField = newNimNode(nnkIdentDefs)
          for i in 0 ..< identDef.len - 2:
            newField.add(identDef[i].copy())
          newField.add(fieldType)
          newField.add(identDef[^1].copy())
          recList.add(newField)
  result.add(recList)

proc processTypeSectionWithDSL(typeSection: NimNode): NimNode =
  ## Process a type section, converting AdaScript array DSL ([N]T) to Nim types.
  ## Handles both type aliases and object field types.
  ## Also handles `record:` as an alias for `object`.
  result = newNimNode(nnkTypeSection)

  for typeDef in typeSection:
    if typeDef.kind == nnkTypeDef:
      let typeName = typeDef[0]
      let typeExpr = typeDef[2]

      # Check if this is an AdaScript array DSL pattern (type alias)
      if typeExpr.kind in {nnkCommand, nnkBracketExpr, nnkCurlyExpr}:
        let processedType = buildNestedArrayTypeForDef(typeExpr)
        let newTypeDef = newNimNode(nnkTypeDef)
        newTypeDef.add(typeName)
        newTypeDef.add(newEmptyNode())
        newTypeDef.add(processedType)
        result.add(newTypeDef)
      elif typeExpr.kind == nnkObjectTy:
        # Process object fields for DSL types
        let newTypeDef = newNimNode(nnkTypeDef)
        newTypeDef.add(typeName)
        newTypeDef.add(typeDef[1].copy())  # generic params
        newTypeDef.add(processObjectFieldsDSL(typeExpr))
        result.add(newTypeDef)
      elif typeExpr.kind == nnkCall and typeExpr[0].kind == nnkIdent and
           typeExpr[0].strVal == "record":
        # record: alias for object
        let newTypeDef = newNimNode(nnkTypeDef)
        newTypeDef.add(typeName)
        newTypeDef.add(typeDef[1].copy())  # generic params
        newTypeDef.add(buildRecordObjectTy(typeExpr))
        result.add(newTypeDef)
      else:
        # Regular type, add as-is
        result.add(typeDef)

proc processVarSectionDSL(stmt: NimNode): NimNode =
  ## Process a var/let/const section, converting DSL types and None init.
  var newSection = newNimNode(stmt.kind)
  for identDef in stmt:
    if identDef.kind == nnkIdentDefs:
      let typeExpr = identDef[^2]
      let rawValue = identDef[^1]
      if typeExpr.kind in {nnkCommand, nnkBracketExpr, nnkCurlyExpr, nnkPrefix, nnkInfix}:
        let processedType = buildNestedArrayTypeForDef(typeExpr)
        let value = if rawValue.kind == nnkIdent and rawValue.strVal == "None" and
            typeExpr.kind == nnkPrefix and typeExpr.len == 2 and
            typeExpr[0].kind == nnkIdent and typeExpr[0].strVal == "?":
          newCall(ident("none"), typeExpr[1].copy())
        else:
          rawValue
        var newDef = newNimNode(nnkIdentDefs)
        for j in 0 ..< identDef.len - 2:
          newDef.add(identDef[j].copy())
        newDef.add(processedType)
        newDef.add(value)
        newSection.add(newDef)
      else:
        newSection.add(identDef)
    else:
      newSection.add(identDef)
  return newSection

proc transformDefBody(body: NimNode): NimNode =
  ## Transform function body to support Ada-style declarative regions.
  ## Handles both implicit declarations (before begin:) and explicit declare:/begin: pairs.
  ## Type declarations are processed through AdaScript array DSL.

  # First pass: check for implicit declarations (statements before first begin:)
  # But skip if the first statement is an explicit declare:
  var firstBeginIndex = -1
  for i, stmt in body:
    if stmt.kind == nnkCall and stmt.len >= 1 and
       stmt[0].kind == nnkIdent and stmt[0].strVal == "begin":
      firstBeginIndex = i
      break

  # Check if first non-comment statement is explicit declare: - if so, use explicit handling
  var firstNonCommentIdx = -1
  for i, stmt in body:
    if stmt.kind != nnkCommentStmt:
      firstNonCommentIdx = i
      break

  let firstStmt = if firstNonCommentIdx >= 0: body[firstNonCommentIdx] else: nil
  let isDeclareStmt = firstStmt != nil and
    firstStmt.kind in {nnkCall, nnkCommand} and
    firstStmt.len >= 2 and
    firstStmt[0].kind == nnkIdent and
    firstStmt[0].strVal == "declare"

  if firstBeginIndex > 0 and not isDeclareStmt:
    # Check if any statement before begin: is an explicit declare:
    # If so, skip implicit handling and let the while loop handle explicit pairs
    var hasNestedDeclare = false
    for i in 0..<firstBeginIndex:
      let stmt = body[i]
      if stmt.kind in {nnkCall, nnkCommand} and stmt.len >= 2 and
         stmt[0].kind == nnkIdent and stmt[0].strVal == "declare":
        hasNestedDeclare = true
        break

    if not hasNestedDeclare:
      # Pure implicit declarations - use implicit handling
      # There are implicit statements before begin: - treat as implicit declarations
      result = newStmtList()

      # Collect implicit declarations (skip comments)
      var declarations: seq[NimNode] = @[]
      for i in 0..<firstBeginIndex:
        let stmt = body[i]
        if stmt.kind == nnkCommentStmt:
          continue
        case stmt.kind
        of nnkTypeSection:
          let processed = processTypeSectionWithDSL(stmt)
          declarations.add(processed)
        of nnkVarSection, nnkLetSection, nnkConstSection:
          declarations.add(processVarSectionDSL(stmt))
        else:
          declarations.add(stmt)

      # Get begin body
      let beginBlock = body[firstBeginIndex]
      let beginBody = if beginBlock.len >= 2: beginBlock[1] else: newStmtList()

      # Get the actual statements from the StmtList wrapper
      let beginStmts = if beginBody.kind == nnkStmtList: beginBody else: newTree(nnkStmtList, beginBody)

      # Create block with implicit declarations + begin body
      # Structure: BlockStmt -> (Empty, StmtList(declarations + body))
      let blockStmt = newNimNode(nnkBlockStmt)
      blockStmt.add(newEmptyNode())
      let innerStmtList = newStmtList()
      for decl in declarations:
        innerStmtList.add(decl)
      for s in beginStmts:
        innerStmtList.add(s)
      blockStmt.add(innerStmtList)
      result.add(blockStmt)

      # Process remaining statements after begin:
      for i in (firstBeginIndex + 1)..<body.len:
        # Recursively transform to handle nested declare:/begin:
        let transformed = transformDefBody(newTree(nnkStmtList, body[i]))
        for s in transformed:
          result.add(s)

      return result

  # No implicit declarations or has explicit declare: - process for explicit declare:/begin: pairs
  result = newStmtList()
  var i = 0

  while i < body.len:
    let stmt = body[i]

    # Check for labeled declare: label: (must check before unlabeled declare)
    if stmt.kind in {nnkCall, nnkCommand} and stmt.len >= 3 and
       stmt[0].kind == nnkIdent and stmt[0].strVal == "declare":
      # declare label: - collect declarations and look for matching begin:
      let label = stmt[1]
      var declarations: seq[NimNode] = @[]
      let declareBody = stmt[2]

      # Get the actual statements from the StmtList wrapper
      let declareStmts = if declareBody.kind == nnkStmtList: declareBody else: newTree(nnkStmtList, declareBody)

      # Process declarations from declare body
      for declStmt in declareStmts:
        case declStmt.kind
        of nnkTypeSection:
          let processed = processTypeSectionWithDSL(declStmt)
          declarations.add(processed)
        of nnkVarSection, nnkLetSection, nnkConstSection:
          declarations.add(processVarSectionDSL(declStmt))
        else:
          declarations.add(declStmt)

      # Look for matching begin:
      i += 1
      if i < body.len and body[i].kind == nnkCall and
         body[i].len >= 2 and body[i][0].kind == nnkIdent and body[i][0].strVal == "begin":
        let beginBody = body[i][1]
        # Get the actual statements from the StmtList wrapper
        let beginStmts = if beginBody.kind == nnkStmtList: beginBody else: newTree(nnkStmtList, beginBody)

        # Recursively transform begin body to handle nested declare:/begin:
        let transformedBegin = transformDefBody(beginStmts)

        # Create labeled block with declarations + begin body
        # Structure: BlockStmt -> (label, StmtList(declarations + body))
        let blockStmt = newNimNode(nnkBlockStmt)
        blockStmt.add(label)
        let innerStmtList = newStmtList()
        for decl in declarations:
          innerStmtList.add(decl)
        for s in transformedBegin:
          innerStmtList.add(s)
        blockStmt.add(innerStmtList)
        result.add(blockStmt)
        i += 1
      else:
        error("declare label: must be followed by begin: block", stmt)

    # Check for explicit declare: block (unlabeled)
    elif stmt.kind in {nnkCall, nnkCommand} and stmt.len >= 2 and
         stmt[0].kind == nnkIdent and stmt[0].strVal == "declare":
      # Found declare: - collect declarations and look for matching begin:
      var declarations: seq[NimNode] = @[]
      let declareBody = stmt[1]

      # Get the actual statements from the StmtList wrapper
      let declareStmts = if declareBody.kind == nnkStmtList: declareBody else: newTree(nnkStmtList, declareBody)

      # Process declarations from declare body
      for declStmt in declareStmts:
        case declStmt.kind
        of nnkTypeSection:
          let processed = processTypeSectionWithDSL(declStmt)
          declarations.add(processed)
        of nnkVarSection, nnkLetSection, nnkConstSection:
          declarations.add(processVarSectionDSL(declStmt))
        else:
          declarations.add(declStmt)

      # Look for matching begin:
      i += 1
      if i < body.len and body[i].kind == nnkCall and
         body[i].len >= 2 and body[i][0].kind == nnkIdent and body[i][0].strVal == "begin":
        let beginBody = body[i][1]
        # Get the actual statements from the StmtList wrapper
        let beginStmts = if beginBody.kind == nnkStmtList: beginBody else: newTree(nnkStmtList, beginBody)

        # Recursively transform begin body to handle nested declare:/begin:
        let transformedBegin = transformDefBody(beginStmts)

        # Create block with declarations + begin body
        # Structure: BlockStmt -> (Empty, StmtList(declarations + body))
        let blockStmt = newNimNode(nnkBlockStmt)
        blockStmt.add(newEmptyNode())
        let innerStmtList = newStmtList()
        for decl in declarations:
          innerStmtList.add(decl)
        for s in transformedBegin:
          innerStmtList.add(s)
        blockStmt.add(innerStmtList)
        result.add(blockStmt)
        i += 1
      else:
        # declare: without begin: - error
        error("declare: must be followed by begin: block", stmt)

    # Standalone begin: - just use the body
    elif stmt.kind == nnkCall and stmt.len >= 1 and
         stmt[0].kind == nnkIdent and stmt[0].strVal == "begin":
      let beginBody = stmt[1]
      if beginBody.kind == nnkStmtList:
        for s in beginBody:
          result.add(s)
      else:
        result.add(beginBody)
      i += 1

    else:
      # Regular statement - add directly
      result.add(stmt)
      i += 1

macro def*(head, body: untyped): untyped =
  ## Python-style function definition with full Nim feature support.
  ## Supports Ada-style declarative regions: statements before 'begin:' are
  ## automatically treated as local declarations.
  ## Usage:
  ##   def name(params) -> retType:                   # basic
  ##   def name[T](x: T) -> T:                        # generics
  ##   def name(x: int) -> int {.inline.}:             # pragmas
  ##   def name(x: int ~ 0) -> int:                    # default values
  ##   def name(a, b, c: int) -> int:                  # multi-param same type
  ##   def name(args: varargs[string]):                 # varargs
  ##   def name():                                      # Ada-style
  ##     var x = 1                                      # implicit declare
  ##     begin:                                         # starts executable part
  ##       echo x
  let transformedBody = transformDefBody(body)
  result = buildDefProc(head, transformedBody, true)

################################################
# Helper procs for init constructor support

proc replaceSelfWithResult(node: NimNode): NimNode =
  ## Recursively replace all `self` idents with `result` in an AST
  if node.kind == nnkIdent and node.strVal == "self":
    return ident("result")
  result = node.copyNimNode()
  for child in node:
    result.add(replaceSelfWithResult(child))

proc isInitMethod(procDef: NimNode): bool =
  ## Check if a procDef is named 'init'
  let name = if procDef.name.kind == nnkPostfix: procDef.name[1] else: procDef.name
  return name.kind == nnkIdent and name.strVal == "init"

proc buildInitializer(typeName: NimNode, initProc: NimNode): NimNode =
  ## Generate initClassName(self: ClassName, args...) proc.
  ## This contains only the field initialization logic (no allocation).
  ## Used by super.init() to initialize parent fields on an existing object.
  let initializerName = ident("init" & typeName.strVal)
  var initializerParams = newNimNode(nnkFormalParams)
  initializerParams.add(newEmptyNode())  # void return

  # self parameter (var ClassName for mutability)
  var selfDef = newNimNode(nnkIdentDefs)
  selfDef.add(ident("self"))
  selfDef.add(typeName)
  selfDef.add(newEmptyNode())
  initializerParams.add(selfDef)

  # Copy remaining params from init, skipping 'self'
  let initParams = initProc.params
  for i in 1..<initParams.len:
    let paramGroup = initParams[i]
    if paramGroup[0].kind == nnkIdent and paramGroup[0].strVal == "self":
      continue
    initializerParams.add(paramGroup.copyNimTree())

  # Body: just the init body with self intact (no replaceSelfWithResult)
  var initializerBody = newStmtList()
  for stmt in initProc.body:
    initializerBody.add(stmt.copyNimTree())

  result = newNimNode(nnkProcDef)
  result.add(postfix(initializerName, "*"))
  result.add(newEmptyNode())
  result.add(newEmptyNode())
  result.add(initializerParams)
  result.add(newEmptyNode())
  result.add(newEmptyNode())
  result.add(initializerBody)

proc buildInitConstructor(typeName: NimNode, initProc: NimNode, isVirtual: bool = false): NimNode =
  ## Transform an init method into a newClassName constructor proc.
  ## Skips the 'self' parameter and rewrites self.x to result.x.
  ## When isVirtual, uses new(result) + initClassName(result, args) pattern.
  let constructorName = ident("new" & typeName.strVal)
  var constructorParams = newNimNode(nnkFormalParams)
  constructorParams.add(typeName)  # return type = ClassName

  # Collect non-self params
  var argNames = newSeq[NimNode]()
  let initParams = initProc.params
  for i in 1..<initParams.len:
    let paramGroup = initParams[i]
    if paramGroup[0].kind == nnkIdent and paramGroup[0].strVal == "self":
      continue
    constructorParams.add(paramGroup.copyNimTree())
    # Collect arg names for forwarding to initializer
    for j in 0..<paramGroup.len - 2:
      argNames.add(paramGroup[j])

  var constructorBody = newStmtList()
  if isVirtual:
    # ref object: new(result) allocates, then call initializer
    constructorBody.add(newCall(ident("new"), ident("result")))
    var initCall = newCall(ident("init" & typeName.strVal), ident("result"))
    for arg in argNames:
      initCall.add(arg)
    constructorBody.add(initCall)
  else:
    # value object: result = ClassName(); then inline init body
    constructorBody.add(newAssignment(ident("result"), newCall(typeName)))
    for stmt in initProc.body:
      constructorBody.add(replaceSelfWithResult(stmt))

  result = newNimNode(nnkProcDef)
  result.add(postfix(constructorName, "*"))
  result.add(newEmptyNode())
  result.add(newEmptyNode())
  result.add(constructorParams)
  result.add(newEmptyNode())
  result.add(newEmptyNode())
  result.add(constructorBody)

proc transformSuper(node: NimNode, parentType: NimNode): NimNode =
  ## Recursively transform super.method(args) calls:
  ##   super.init(args)   -> initParentName(self, args)  (initializer, no allocation)
  ##   super.method(args) -> procCall ParentType(self).method(args)
  if node.kind == nnkCall and node[0].kind == nnkDotExpr and
     node[0][0].kind == nnkIdent and node[0][0].strVal == "super":
    let methodName = node[0][1]

    if methodName.kind == nnkIdent and methodName.strVal == "init":
      # super.init(args) -> initParentName(self, args)
      # Calls the parent's initializer proc (field setup only, no allocation)
      let initName = ident("init" & parentType.strVal)
      var call = newCall(initName, ident("self"))
      for i in 1..<node.len:
        call.add(node[i].copyNimTree())
      return call
    else:
      # super.method(args) -> procCall ParentType(self).method(args)
      let castExpr = newCall(parentType.copy(), ident("self"))
      let dotExpr = newDotExpr(castExpr, methodName)
      var call = newNimNode(nnkCall)
      call.add(dotExpr)
      for i in 1..<node.len:
        call.add(node[i].copyNimTree())
      result = newNimNode(nnkCommand)
      result.add(ident("procCall"))
      result.add(call)
      return result

  # Recurse into children
  result = node.copyNimNode()
  for child in node:
    result.add(transformSuper(child, parentType))

proc procToMethod(procDef: NimNode, addBase: bool): NimNode =
  ## Convert a nnkProcDef into a nnkMethodDef.
  ## If addBase is true, adds {.base.} pragma (for root virtual classes).
  result = newNimNode(nnkMethodDef)
  for child in procDef:
    result.add(child.copyNimTree())
  if addBase:
    if result.pragma.kind == nnkEmpty:
      result.pragma = newNimNode(nnkPragma)
    result.pragma.add(ident("base"))

proc buildClass(typeName, parentType: NimNode, body: NimNode, isVirtual: bool): NimNode =
  ## Shared implementation for class and virtual class macros.
  result = newStmtList()

  # Create type section
  var typeSection = newNimNode(nnkTypeSection)
  var typeDef = newNimNode(nnkTypeDef)
  typeDef.add(postfix(typeName, "*"))
  typeDef.add(newEmptyNode())

  var objectTy = newNimNode(nnkObjectTy)
  objectTy.add(newEmptyNode())

  # Add inheritance if specified
  if parentType != nil:
    var ofInherit = newNimNode(nnkOfInherit)
    ofInherit.add(parentType)
    objectTy.add(ofInherit)
  else:
    # Always inherit from RootObj if the class has methods (makes it inheritable)
    var hasMethods = false
    for stmt in body:
      if stmt.kind == nnkProcDef:
        hasMethods = true
        break
      if expandDef(stmt) != nil:
        hasMethods = true
        break

    if hasMethods:
      var ofInherit = newNimNode(nnkOfInherit)
      ofInherit.add(ident("RootObj"))
      objectTy.add(ofInherit)
    else:
      objectTy.add(newEmptyNode())

  var recList = newNimNode(nnkRecList)
  var methods = newSeq[NimNode]()
  var initProc: NimNode = nil
  var nestedTypes = newSeq[NimNode]()

  # Parse body for fields, methods, nested types, and init constructor
  for stmt in body:
    case stmt.kind:
    of nnkTypeSection:
      # Nested type definitions inside the class - process DSL and collect
      nestedTypes.add(processTypeSectionWithDSL(stmt))

    of nnkVarSection:
      for identDef in stmt:
        for i in 0..<identDef.len-2:
          let fieldName = identDef[i]
          let fieldType = buildNestedArrayTypeForDef(identDef[^2])
          var newIdentDef = newNimNode(nnkIdentDefs)
          newIdentDef.add(postfix(fieldName, "*"))
          newIdentDef.add(fieldType)
          newIdentDef.add(newEmptyNode())
          recList.add(newIdentDef)

    of nnkProcDef:
      var procDef = stmt.copy()
      if procDef.pragma.kind != nnkEmpty:
        var newPragma = newNimNode(nnkPragma)
        for pragma in procDef.pragma:
          if pragma.kind == nnkIdent and pragma.strVal != "override":
            newPragma.add(pragma)
        procDef.pragma = newPragma
      procDef = injectSelfType(procDef, typeName)
      prependSelfParam(procDef, typeName)
      if isInitMethod(procDef):
        initProc = procDef
      else:
        methods.add(procDef)

    else:
      # Try expanding as a def
      let expanded = expandDef(stmt)
      if expanded != nil:
        var patched = injectSelfType(expanded, typeName)
        prependSelfParam(patched, typeName)
        if isInitMethod(patched):
          initProc = patched
        else:
          methods.add(patched)

  objectTy.add(recList)

  # For virtual classes, wrap object in ref
  if isVirtual:
    var refTy = newNimNode(nnkRefTy)
    refTy.add(objectTy)
    typeDef.add(refTy)
  else:
    typeDef.add(objectTy)

  typeSection.add(typeDef)

  # Emit nested types before the class type definition
  for ts in nestedTypes:
    result.add(ts)

  result.add(typeSection)

  # Transform super.method() calls in child class methods
  if parentType != nil:
    for i in 0..<methods.len:
      let body = methods[i].body
      methods[i].body = transformSuper(body, parentType)
    if initProc != nil:
      initProc.body = transformSuper(initProc.body, parentType)

  # Generate constructor (and initializer for virtual) from init if found
  if initProc != nil:
    if isVirtual:
      # Emit initializer proc: initClassName(self, args...) — field setup only
      # Then constructor: newClassName(args) = new(result); initClassName(result, args)
      methods.insert(buildInitConstructor(typeName, initProc, isVirtual), 0)
      methods.insert(buildInitializer(typeName, initProc), 0)
    else:
      methods.insert(buildInitConstructor(typeName, initProc, isVirtual), 0)

  # For virtual classes, convert proc methods to method (except constructor + initializer)
  if isVirtual:
    let addBase = parentType == nil  # base methods get {.base.} pragma
    # Skip initializer (idx 0) and constructor (idx 1) when initProc existed
    let startIdx = if initProc != nil: 2 else: 0
    for i in startIdx..<methods.len:
      methods[i] = procToMethod(methods[i], addBase)

  # Add methods
  for meth in methods:
    result.add(meth)

################################################
# 1. ENHANCED MACRO SUPPORTING INHERITANCE AND DESTRUCTORS
macro class*(head, body: untyped): untyped =
  var typeName: NimNode
  var parentType: NimNode = nil

  # Parse class declaration (ClassName or ClassName(ParentClass))
  if head.kind == nnkIdent:
    typeName = head
  elif head.kind == nnkCall and head.len == 2:
    typeName = head[0]
    parentType = head[1]
  else:
    error("Invalid class declaration syntax", head)

  result = buildClass(typeName, parentType, body, isVirtual = false)

################################################
# 1b. VIRTUAL CLASS - ref objects with dynamic dispatch
macro virtual*(head, body: untyped): untyped =
  ## virtual class ClassName:          -- base virtual class (ref object of RootObj)
  ## virtual class Child(Parent):      -- derived virtual class
  ##
  ## Methods inside become Nim 'method' (dynamic dispatch).
  ## Base class methods get {.base.} pragma automatically.
  ## Constructor (init) stays as proc.

  # Validate: head must be 'class ClassName' or 'class ClassName(Parent)'
  if head.kind != nnkCommand or head.len != 2 or
     head[0].kind != nnkIdent or head[0].strVal != "class":
    error("AdaScript virtual: expected 'virtual class ClassName:'\n" &
          "  Usage:\n" &
          "    virtual class Base:\n" &
          "      var field: Type\n" &
          "      def method(self) -> Type: ...\n" &
          "    virtual class Child(Base):\n" &
          "      def method(self) -> Type: ...  # override", head)

  let classHead = head[1]
  var typeName: NimNode
  var parentType: NimNode = nil

  if classHead.kind == nnkIdent:
    typeName = classHead
  elif classHead.kind == nnkCall and classHead.len == 2:
    typeName = classHead[0]
    parentType = classHead[1]
  else:
    error("Invalid virtual class declaration syntax", classHead)

  result = buildClass(typeName, parentType, body, isVirtual = true)

# 2. PYTHON-STYLE 'WITH' STATEMENT MACRO
macro `with`*(args: varargs[untyped]): untyped =
  ## Implements Python-style 'with' statement for automatic resource management.
  ##
  ## Usage:
  ##   with myResource:
  ##     it.someMethod()  # 'it' refers to the resource
  ##
  ##   with myResource as varname:
  ##     varname.someMethod()  # custom variable name
  ##
  ## Multiple resources:
  ##   with resource1 as var1, resource2 as var2:
  ##     var1.method()
  ##     var2.method()
  ##
  ## The resource must have an `enter` method (called on entry) and one of
  ## `exit`, `destroy`, or `close` (called on exit in that order).

  if args.len == 0:
    classError("'with' statement requires at least one resource. " &
               "Example: with myResource as r:\n  r.doSomething()", args)

  # Parse arguments to separate resources and body
  var resources: seq[(NimNode, NimNode)] = @[]  # (resource_expr, var_name)
  var body: NimNode = nil

  # Find the body (last argument that's a statement list)
  var bodyIndex = -1
  for i in countdown(args.len - 1, 0):
    if args[i].kind == nnkStmtList:
      bodyIndex = i
      body = args[i]
      break

  if bodyIndex == -1:
    classError("'with' statement requires a body (statement block). " &
               "Example: with myResource as r:\n  r.doSomething()", args)

  # Parse resource specifications
  for i in 0..<bodyIndex:
    let arg = args[i]
    case arg.kind:
    of nnkIdent, nnkCall, nnkDotExpr:
      # Simple resource without 'as' clause - use 'it'
      resources.add((arg, ident("it")))
    of nnkInfix:
      # Check for 'as' infix operator
      if arg[0].kind == nnkIdent and arg[0].strVal == "as":
        let resourceExpr = arg[1]
        let varName = arg[2]
        if varName.kind != nnkIdent:
          classError("Variable name after 'as' must be a simple identifier, got: " & $varName.kind, arg)
        resources.add((resourceExpr, varName))
      else:
        classError("Unknown operator '" & arg[0].strVal & "' in 'with' statement. " &
                   "Use 'as' to bind resource to a variable: with resource as v:", arg)
    else:
      classError("Invalid resource specification. Expected resource or 'resource as varname'", arg)

  if resources.len == 0:
    classError("'with' statement requires at least one resource", args)

  # Generate nested blocks for each resource
  result = body

  for i in countdown(resources.len - 1, 0):
    let (resourceExpr, varName) = resources[i]

    result = quote do:
      block:
        var `varName` = `resourceExpr`
        try:
          # Check if resource has an enter method and call it
          when compiles(`varName`.enter()):
            `varName`.enter()
          `result`
        finally:
          # Check if resource has an exit method and call it
          when compiles(`varName`.exit()):
            `varName`.exit()
          # Otherwise check for destroy method
          elif compiles(`varName`.destroy()):
            `varName`.destroy()
          # Or check for close method
          elif compiles(`varName`.close()):
            `varName`.close()
###########################################
template withFile*(f: untyped, filename: string, mode: FileMode,
                  body: untyped) =
  let fn = filename
  var f: File
  if open(f, fn, mode):
    try:
      body
    finally:
      close(f)
  else:
    quit("cannot open: " & fn)


# 3. CONTEXT MANAGER MIXIN
macro contextManager*(typeName: untyped, enterBody: untyped, exitBody: untyped): untyped =
  ## Creates enter and exit methods for a type to work with 'with' statement
  result = newStmtList()

  # Create enter method
  var enterProc = newProc(
    name = ident("enter"),
    params = [
      newEmptyNode(),
      newIdentDefs(ident("self"), newNimNode(nnkVarTy).add(typeName))
    ],
    body = enterBody)

  # Create exit method
  var exitProc = newProc(
    name = ident("exit"),
    params = [
      newEmptyNode(),
      newIdentDefs(ident("self"), newNimNode(nnkVarTy).add(typeName))
    ],
    body = exitBody)

  result.add(enterProc)
  result.add(exitProc)

# 4. MANAGED FILE HANDLER - Reusable file handling with context management
class ManagedFileHandler:
  var filename: string
  var fileHandle: File
  var isOpen: bool
  var mode: FileMode

  def init(self: ManagedFileHandler, filename: string, mode: FileMode ~ fmRead):
    self.filename = filename
    self.isOpen = false
    self.mode = mode

  def writeData(self: var ManagedFileHandler, data: string) -> bool:
    if self.isOpen and (self.mode == fmWrite or self.mode == fmAppend or self.mode == fmReadWrite or self.mode == fmReadWriteExisting):
      write(self.fileHandle, data)
      return true
    return false

  def readData(self: ManagedFileHandler) -> string:
    if self.isOpen and (self.mode == fmRead or self.mode == fmReadWrite or self.mode == fmReadWriteExisting):
      return readAll(self.fileHandle)
    return ""

  def readLine(self: var ManagedFileHandler) -> string:
    if self.isOpen and (self.mode == fmRead or self.mode == fmReadWrite or self.mode == fmReadWriteExisting):
      var line: string
      if readLine(self.fileHandle, line):
        return line
    return ""

  def writeLine(self: var ManagedFileHandler, line: string) -> bool:
    if self.isOpen and (self.mode == fmWrite or self.mode == fmAppend or self.mode == fmReadWrite or self.mode == fmReadWriteExisting):
      writeLine(self.fileHandle, line)
      return true
    return false

  def getFileSize(self: ManagedFileHandler) -> int64:
    if self.isOpen:
      return getFileSize(self.fileHandle)
    return 0

  def setFilePos(self: var ManagedFileHandler, pos: int64):
    if self.isOpen:
      setFilePos(self.fileHandle, pos)

  def getFilePos(self: ManagedFileHandler) -> int64:
    if self.isOpen:
      return getFilePos(self.fileHandle)
    return 0

  def flush(self: var ManagedFileHandler):
    if self.isOpen:
      flushFile(self.fileHandle)

# Add context manager methods to ManagedFileHandler
contextManager(ManagedFileHandler):
  # enter body
  if open(self.fileHandle, self.filename, self.mode):
    self.isOpen = true
    echo "Opened file: ", self.filename, " in mode: ", self.mode
  else:
    echo "Failed to open file: ", self.filename
    raise newException(IOError, "Cannot open file: " & self.filename)
do:
  # exit body
  if self.isOpen:
    close(self.fileHandle)
    self.isOpen = false
    echo "Closed file: ", self.filename

# Iterator for line-by-line reading
iterator iterLines*(file: var ManagedFileHandler): string =
  if file.isOpen and (file.mode == fmRead or file.mode == fmReadWrite or file.mode == fmReadWriteExisting):
    var line: string
    while readLine(file.fileHandle, line):
      yield line

####################################################################
####################################################################
###############################
macro opt*(T: typed): untyped =
  quote do: Option[`T`]

# ============================================================================
# None support for optional types
# ============================================================================

type NoneType* = object
  ## Sentinel type representing the absence of a value.
const None* = NoneType()

proc `==`*[T](opt: Option[T], n: NoneType): bool = opt.isNone
proc `==`*[T](n: NoneType, opt: Option[T]): bool = opt.isNone
proc `!=`*[T](opt: Option[T], n: NoneType): bool = opt.isSome
proc `!=`*[T](n: NoneType, opt: Option[T]): bool = opt.isSome

proc toOption*[T](val: T): Option[T] = some(val)
  ## Wrap a value in Option. Idempotent for Option[T].
proc toOption*[T](val: Option[T]): Option[T] = val
##############################
macro print*(args: varargs[untyped]): untyped =
  ## Python-style print, alias for echo
  result = newCall(ident("echo"))
  for arg in args:
    result.add(arg)

proc `+`*(a, b: string): string =
  a & b

proc `*`*[T](a: T, b: int): T =
  result = default(T)
  for i in 0..b-1:
    result = result & a

# ============================================================================
# Ada-style loop macro
# ============================================================================

macro loop*(body: untyped): untyped =
  ## Ada-style infinite loop.
  ## Usage: loop: echo "Hello"; if done: break
  result = quote do:
    while true:
      `body`
