# shell.nim - Shell command execution with AdaScript-style syntax
# Provides shell macro for executing shell commands with:
#   - Variable interpolation
#   - Pipe support
#   - Working directory control
#   - Timeout handling
#   - Debug output configuration

import macros, options, strutils, strformat
when not defined(NimScript):
  import osproc, streams, os
  export osproc

# ============================================================================
# Types and Constants
# ============================================================================

type
  ShellResult* = tuple[output, error: string, exitCode: int]
    ## Result of a shell command execution

  DebugOutputKind* = enum
    dokCommand   ## Show commands before execution
    dokError     ## Show error output
    dokOutput    ## Show command output line by line
    dokRuntime   ## Show runtime errors

const
  defaultDebugConfig*: set[DebugOutputKind] = {}  ## Quiet by default
  verboseDebugConfig* = {dokOutput, dokError, dokCommand, dokRuntime}

when defined(windows):
  const defaultProcessOptions* = {poStdErrToStdOut, poEvalCommand, poDaemon, poUsePath}
else:
  const defaultProcessOptions* = {poStdErrToStdOut, poEvalCommand}

const defaultProcessOptionsErr* = {poEvalCommand}

# ============================================================================
# Error helper
# ============================================================================

proc shellError(msg: string, node: NimNode) =
  error("AdaScript shell: " & msg & "\n" &
        "  Usage:\n" &
        "    shell: echo \"hello\"\n" &
        "    shell(cwd = \"/tmp\"): ls -la\n" &
        "    shell(timeout = 5000): \"sleep 10\"\n" &
        "    shell(quiet = false): make install\n" &
        "  Found: " & node.repr, node)

# ============================================================================
# Core shell execution
# ============================================================================

proc getPrompt(pid: int): string =
  when defined(shellShowPid): "shell " & $pid & "> "
  else: "shell> "

proc execViaGorge(cmd, workDir: string): ShellResult =
  ## Execute a shell command via gorgeEx (compile-time / NimScript).
  let fullCmd = if workDir.len > 0: &"cd {workDir} && {cmd}" else: cmd
  let (res, code) = gorgeEx(fullCmd, "", "")
  (output: res.strip, error: "", exitCode: code)

proc stripQuotes(cmd: string): string =
  ## Remove surrounding double-quotes from a command string.
  if cmd.len > 2 and cmd[0] == '"' and cmd[^1] == '"': cmd[1..^2]
  else: cmd

proc execShell*(
  cmd: string,
  debugConfig: set[DebugOutputKind] = defaultDebugConfig,
  options: set[ProcessOption] = defaultProcessOptionsErr,
  workDir: string = "",
  timeoutMs: int = 0
): ShellResult =
  ## Execute a shell command with optional working directory and timeout.
  let cleanCmd = stripQuotes(cmd)

  if dokCommand in debugConfig:
    echo "shellCmd: ", cleanCmd

  when nimvm:
    return execViaGorge(cleanCmd, workDir)
  else:
    when not defined(NimScript):
      let actualCmd = if workDir.len > 0: &"cd {workDir} && {cleanCmd}" else: cleanCmd

      var prcs: Process
      try:
        prcs = startProcess(actualCmd, options = options)
      except OSError as e:
        return (output: "", error: e.msg, exitCode: 1)

      let pid = prcs.processId
      let outStream = prcs.outputStream

      if timeoutMs == 0:
        # No timeout: wait for completion, then read all output
        discard prcs.waitForExit()
        let output = outStream.readAll().strip
        if dokOutput in debugConfig:
          for line in output.splitLines:
            if line.len > 0: echo getPrompt(pid), line

        let exitCode = prcs.peekExitCode
        let errorText = prcs.errorStream.readAll()

        if exitCode != 0:
          if dokRuntime in debugConfig:
            echo "Error when executing: ", cleanCmd
          if dokError in debugConfig:
            for line in errorText.splitLines:
              if line.len > 0: echo "err> ", line

        prcs.close()
        return (output: output, error: errorText.strip, exitCode: exitCode)

      else:
        # Timeout path: poll for output while process runs
        var output = ""
        var elapsed = 0

        while prcs.running and elapsed < timeoutMs:
          try:
            var line = ""
            if outStream.readLine(line):
              if dokOutput in debugConfig:
                echo getPrompt(pid), line
              output.add line & "\n"
          except IOError, OSError:
            break
          sleep(10)
          elapsed += 10

        if elapsed >= timeoutMs and prcs.running:
          prcs.terminate()
          return (output: output.strip, error: "Command timed out", exitCode: 124)

        # Read remaining output after process exits
        if not outStream.atEnd:
          let remaining = outStream.readAll()
          output.add remaining
          if dokOutput in debugConfig:
            for line in remaining.splitLines:
              if line.len > 0: echo getPrompt(pid), line

        let exitCode = prcs.peekExitCode
        let errorText = prcs.errorStream.readAll()

        if exitCode != 0:
          if dokRuntime in debugConfig:
            echo "Error when executing: ", cleanCmd
          if dokError in debugConfig:
            for line in errorText.splitLines:
              if line.len > 0: echo "err> ", line

        prcs.close()
        return (output: output.strip, error: errorText.strip, exitCode: exitCode)
    else:
      return execViaGorge(cleanCmd, workDir)

# ============================================================================
# Command processing for macro
# ============================================================================

proc processCommand(cmd: NimNode): string =
  ## Convert a NimNode to a shell command string.
  case cmd.kind
  of nnkStrLit, nnkTripleStrLit, nnkRStrLit:
    cmd.strVal
  of nnkIdent:
    cmd.strVal
  of nnkInfix:
    if cmd[0].strVal == "-":
      processCommand(cmd[1]) & "-" & processCommand(cmd[2])
    else:
      processCommand(cmd[1]) & " " & cmd[0].strVal & " " & processCommand(cmd[2])
  of nnkCurly:
    if cmd.len == 1:
      "{" & cmd[0].repr & "}"
    else:
      shellError("Invalid variable interpolation. Use {varName}", cmd)
      ""
  of nnkCommand, nnkCall:
    var parts: seq[string]
    for child in cmd:
      parts.add processCommand(child)
    parts.join(" ")
  else:
    cmd.repr

proc buildShellCommand(cmds: NimNode, isPipe: bool = false): seq[string] =
  ## Convert a statement list to a sequence of shell commands.
  ## Handles pipe: blocks for command piping.

  proc flush(cmds: var seq[string], into: var seq[string], isPipe: bool) =
    ## Flush accumulated commands: join with && for sequential, keep separate for pipes.
    if cmds.len == 0: return
    if isPipe:
      for c in cmds:
        if c.strip.len > 0: into.add c
    else:
      let combined = cmds.join(" && ")
      if combined.strip.len > 0: into.add combined
    cmds.setLen(0)

  result = @[]
  var current: seq[string] = @[]

  for cmd in cmds:
    if cmd.kind == nnkCall and cmd[0].kind == nnkIdent and cmd[0].strVal == "pipe":
      flush(current, result, isPipe)
      let pipeCmds = buildShellCommand(cmd[1], isPipe = true)
      if pipeCmds.len > 0:
        let pipeStr = pipeCmds.join(" | ")
        if pipeStr.strip.len > 0: result.add pipeStr
    else:
      let cmdStr = processCommand(cmd)
      if cmdStr.strip.len > 0:
        current.add cmdStr

  flush(current, result, isPipe)

# ============================================================================
# Shell macro implementation
# ============================================================================

proc shellImpl(debugConfig, options, workDir, timeoutMs, cmds: NimNode): NimNode =
  ## Core implementation: generates code to execute commands with options.
  let shellCommands = buildShellCommand(cmds)

  var validCommands: seq[string]
  for cmd in shellCommands:
    let trimmed = cmd.strip
    if trimmed.len > 0:
      validCommands.add trimmed

  if validCommands.len == 0:
    return quote do:
      (output: "", error: "", exitCode: 0)

  let outputSym = genSym(nskVar, "output")
  let errorSym = genSym(nskVar, "error")
  let exitCodeSym = genSym(nskVar, "exitCode")

  result = newStmtList()
  result.add quote do:
    var `outputSym` = ""
    var `errorSym` = ""
    var `exitCodeSym` = 0

  for cmd in validCommands:
    let qCmd = newStrLitNode(cmd)
    result.add quote do:
      if `exitCodeSym` == 0:
        let finalCmd = if "{" in `qCmd`: &`qCmd` else: `qCmd`
        let tmp = execShell(finalCmd, `debugConfig`, `options`, `workDir`, `timeoutMs`)
        if `outputSym`.len > 0 and tmp.output.len > 0:
          `outputSym`.add "\n"
        `outputSym`.add tmp.output
        `errorSym` = tmp.error
        `exitCodeSym` = tmp.exitCode
      else:
        if dokRuntime in `debugConfig`:
          echo "Skipped command due to failure: ", `qCmd`

  result.add quote do:
    (output: `outputSym`, error: `errorSym`, exitCode: `exitCodeSym`)

proc parseShellArgs(args: NimNode): (NimNode, NimNode, NimNode, NimNode, NimNode) =
  ## Parse shell macro arguments into (debug, options, workDir, timeout, cmds).
  var debugArg, optionsArg, workDirArg, timeoutArg, cmds: NimNode

  for i, arg in args:
    case arg.kind
    of nnkExprEqExpr:
      case arg[0].strVal
      of "debug":
        debugArg = arg[1]
      of "quiet":
        debugArg = if arg[1].kind == nnkIdent and arg[1].strVal == "true":
          ident("defaultDebugConfig")
        else:
          ident("verboseDebugConfig")
      of "options":
        optionsArg = arg[1]
      of "workDir", "cwd":
        workDirArg = arg[1]
      of "timeout":
        timeoutArg = arg[1]
      else:
        shellError("Unknown argument: " & arg[0].strVal &
                   ". Valid: debug, quiet, options, workDir/cwd, timeout", arg)
    of nnkStmtList, nnkCommand, nnkIdent, nnkStrLit:
      cmds = arg
    else:
      if i == args.len - 1:
        cmds = arg
      else:
        shellError("Invalid argument type", arg)

  # Apply defaults
  if debugArg.isNil: debugArg = ident("defaultDebugConfig")
  if optionsArg.isNil: optionsArg = ident("defaultProcessOptionsErr")
  if workDirArg.isNil: workDirArg = newLit("")
  if timeoutArg.isNil: timeoutArg = newLit(0)
  if cmds.kind != nnkStmtList: cmds = nnkStmtList.newTree(cmds)

  (debugArg, optionsArg, workDirArg, timeoutArg, cmds)

macro shell*(args: varargs[untyped]): ShellResult =
  ## Execute shell commands and return a ShellResult.
  ##
  ## ```nim
  ## let result = shell: echo "hello"
  ## let result = shell(cwd = "/tmp"): ls -la
  ## let result = shell(timeout = 5000): "sleep 10"
  ## let result = shell(quiet = false): make install
  ##
  ## # Piping
  ## let result = shell:
  ##   pipe:
  ##     echo "hello"
  ##     tr a-z A-Z
  ##
  ## # Variable interpolation
  ## let name = "world"
  ## let result = shell: echo "hello {name}"
  ## ```
  let (debugArg, optionsArg, workDirArg, timeoutArg, cmds) = parseShellArgs(args)
  shellImpl(debugArg, optionsArg, workDirArg, timeoutArg, cmds)

# ============================================================================
# Convenience templates
# ============================================================================

template shellQuiet*(body: untyped): ShellResult =
  ## Execute shell commands without debug output.
  shell(debug = defaultDebugConfig): body

template shellVerbose*(body: untyped): ShellResult =
  ## Execute shell commands with full debug output.
  shell(debug = verboseDebugConfig): body

template shellCwd*(dir: string, body: untyped): ShellResult =
  ## Execute shell commands in a specific directory.
  shell(workDir = dir): body

template shellTimeout*(ms: int, body: untyped): ShellResult =
  ## Execute shell commands with a timeout.
  shell(timeout = ms): body

# ============================================================================
# shellLines - return output as seq[string]
# ============================================================================

macro shellLines*(args: varargs[untyped]): untyped =
  ## Execute a shell command and return output as seq[string] (lines).
  ##
  ## ```nim
  ## let lines = shellLines: ls -la
  ## for line in lines: echo line
  ## ```
  if args.len != 1 or args[0].kind != nnkStmtList:
    shellError("shellLines expects: shellLines: command", args)

  let command = args[0]
  result = quote do:
    block:
      let shellResult = `shell`(`command`)
      if shellResult.exitCode == 0:
        shellResult.output.splitLines()
      else:
        @[]
