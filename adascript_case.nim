# Macro to create Ada-style case statements
# ============================================================================
# Error message helper
# ============================================================================

proc caseError(msg: string, node: NimNode) =
  ## Raise a compile-time error with helpful context for switch/case issues.
  error("AdaScript switch statement: " & msg & "\n" &
        "  Usage:\n" &
        "    switch expression:\n" &
        "      when value1: statements\n" &
        "      when value2: statements\n" &
        "      when others: default_statements\n" &
        "  Found: " & node.repr, node)

# ============================================================================
# Switch macro
# ============================================================================

macro switch*(expr: untyped, body: untyped): untyped =
  ## Create Ada-style case statements with when/others syntax.
  ##
  ## Usage:
  ##   switch status:
  ##     when 1: echo "starting"
  ##     when 2: echo "running"
  ##     when 3:
  ##       echo "stopping"
  ##       cleanup()
  ##     when others: echo "unknown"
  ##
  ## This compiles to Nim's native case/of/else with zero overhead.

  result = newNimNode(nnkCaseStmt)
  result.add(expr)

  # Process the body directly
  for stmt in body:
    case stmt.kind:
    of nnkWhenStmt:
      # Handle WhenStmt nodes
      for branch in stmt:
        if branch.kind == nnkElifBranch:
          # ElifBranch has: condition, body
          let condition = branch[0]
          let branchBody = branch[1]

          if condition.kind == nnkIdent and $condition == "others":
            # Handle "when others" -> else branch
            var elseBranch = newNimNode(nnkElse)
            elseBranch.add(branchBody)
            result.add(elseBranch)
          else:
            # Handle regular "when value" -> of branch
            var ofBranch = newNimNode(nnkOfBranch)
            ofBranch.add(condition)
            ofBranch.add(branchBody)
            result.add(ofBranch)
    of nnkIdent:
      # Allow bare identifiers as shorthand (e.g., when Foo:)
      var ofBranch = newNimNode(nnkOfBranch)
      ofBranch.add(stmt)
      ofBranch.add(newStmtList())
      result.add(ofBranch)
    else:
      caseError("Expected 'when' clause inside switch body. " &
                "Each branch should be: when value: statements", stmt)

  # Validate that we have at least one branch
  if result.len < 2:
    caseError("Switch statement must have at least one 'when' branch", body)
