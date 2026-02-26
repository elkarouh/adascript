# Macro-based approach for Ada-style tick attributes
# Supports: enum types, range types, array types, seq, and user-defined ordinals

# ============================================================================
# Error message helper
# ============================================================================

proc attrError(msg: string, node: NimNode) =
  ## Raise a compile-time error with helpful context for tick attribute issues.
  error("AdaScript tick attribute (^): " & msg & "\n" &
        "  Valid type-level attributes: First, Last, Range, Size, Length, Dimensions\n" &
        "  Valid value-level attributes: Succ, Pred, Pos, Length, First, Last\n" &
        "  Found: " & node.repr, node)

# ============================================================================
# Main tick attribute macro
# ============================================================================

macro `^`*(t: untyped, attr: untyped): untyped =
  ## Ada-style tick attributes for types and values.
  ##
  ## Type-level usage:
  ##   Color ^ First      # low(Color)
  ##   Color ^ Last       # high(Color)
  ##   Color ^ Length     # number of elements in enum
  ##
  ## Value-level usage:
  ##   Green ^ Succ       # succ(Green) with bounds check
  ##   Green ^ Pred       # pred(Green) with bounds check
  ##   Green ^ Pos        # ord(Green)

  proc getAttrName(node: NimNode): string =
    case node.kind
    of nnkIdent:
      node.strVal
    of nnkAccQuoted:
      if node.len == 1: node[0].strVal else: ""
    else:
      ""

  let attrName = getAttrName(attr)
  if attrName == "":
    attrError("Invalid attribute syntax. Expected an identifier like First, Last, Succ, etc.", attr)

  # For simple operations, generate directly
  # For complex type-dependent operations, use templates
  case attrName
  of "First":
    result = quote do: low(`t`)
  of "Last":
    result = quote do: high(`t`)
  of "Range":
    result = quote do: (low(`t`), high(`t`))
  of "Pos":
    result = quote do: ord(`t`)
  of "Succ":
    # Use template for complex logic
    result = quote do:
      block:
        let v = `t`
        when v is enum:
          if ord(v) >= ord(high(type(v))):
            raise newException(RangeDefect, "No successor for value at upper bound")
          succ(v)
        elif v is range:
          if v >= high(type(v)):
            raise newException(RangeDefect, "No successor for range value at upper bound")
          v + 1
        else:
          succ(v)
  of "Pred":
    result = quote do:
      block:
        let v = `t`
        when v is enum:
          if ord(v) <= ord(low(type(v))):
            raise newException(RangeDefect, "No predecessor for value at lower bound")
          pred(v)
        elif v is range:
          if v <= low(type(v)):
            raise newException(RangeDefect, "No predecessor for range value at lower bound")
          v - 1
        else:
          pred(v)
  of "Size", "Length":
    result = quote do:
      when `t` is enum:
        ord(high(`t`)) - ord(low(`t`)) + 1
      elif `t` is range:
        high(`t`) - low(`t`) + 1
      elif `t` is array:
        len(`t`)
      elif `t` is seq:
        len(`t`)
      else:
        0
  of "Dimensions":
    result = quote do:
      when `t` is array: 1
      else: 0
  else:
    attrError("Unknown attribute '" & attrName & "'.", attr)

# Iterators for ranging over type elements
iterator tickRange*[T: enum](t: typedesc[T]): T =
  ## Iterate over all values of an enum type.
  for val in low(T)..high(T):
    yield val

iterator tickRange*[T: range](t: typedesc[T]): T =
  ## Iterate over all values of a range type.
  for val in low(T)..high(T):
    yield val

iterator tickRange*[I, T](t: typedesc[array[I, T]]): I =
  ## Iterate over all indices of an array type.
  for val in low(I)..high(I):
    yield val

iterator tickRange*[I, T](a: array[I, T]): I =
  ## Iterate over all indices of an array value.
  for val in low(a.type)..high(a.type):
    yield val

# Helper: check if type supports tick attributes
template hasTick*(T: typedesc): bool =
  T is enum or T is range or T is array

# Helper aliases
template tick*[T](t: T, attr: untyped): untyped =
  t ^ attr

template tick*[T: typedesc](t: T, attr: untyped): untyped =
  t ^ attr
