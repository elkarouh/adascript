# Kilo Text Editor in Nim - Class-based using AdaScript class macro
# Python-style indentation: all methods inside the class block
import adascript
import os, posix, posix/termios, strutils, times

globals:
  const KILO_VERSION = "0.0.1"
  const KILO_TAB_STOP = 8

class Editor:
  type EditorKey_T = enum
    CTRL_F = 6
    CTRL_H = 8
    CTRL_L = 12
    ENTER = 13
    CTRL_Q = 17
    CTRL_S = 19
    ESC = 27
    BACKSPACE = 127
    ARROW_LEFT = 1000
    ARROW_RIGHT, ARROW_UP, ARROW_DOWN
    DEL_KEY, HOME_KEY, END_KEY, PAGE_UP, PAGE_DOWN

  type Row_T = record:
    size: int       # number of characters in the row
    rsize: int      # number of characters in the rendered row
    chars: string   # raw character data
    render: string  # rendered characters (tabs expanded)

  var cx, cy, rx: int
  var rowoff, coloff: int
  var screenrows, screencols: int
  var numrows: int
  var row: []Row_T
  var dirty: int
  var filename, statusmsg: string
  var statusmsgTime: times.Time
  var quitTimes: int
  var lastMatch: int
  var findDirection: int
  var origTermios: Termios

  def init(self):
    self.cx = 0
    self.cy = 0
    self.rx = 0
    self.rowoff = 0
    self.coloff = 0
    self.screenrows = 0
    self.screencols = 0
    self.numrows = 0
    self.row = @[]
    self.dirty = 0
    self.filename = ""
    self.statusmsg = ""
    self.statusmsgTime = times.getTime()
    self.quitTimes = 2
    self.lastMatch = -1
    self.findDirection = 1

  def die(self, s: string):
    stdout.write("\x1b[2J")
    stdout.write("\x1b[H")
    stderr.writeLine(s, ": ", osErrorMsg(osLastError()))
    quit(1)

  def enableRawMode(self):
    if tcgetattr(STDIN_FILENO, addr self.origTermios) == -1: return
    var raw = self.origTermios
    raw.c_iflag = raw.c_iflag and not Cflag(BRKINT or ICRNL or INPCK or ISTRIP or IXON)
    raw.c_oflag = raw.c_oflag and not Cflag(OPOST)
    raw.c_cflag = raw.c_cflag or Cflag(CS8)
    raw.c_lflag = raw.c_lflag and not Cflag(ECHO or ICANON or IEXTEN or ISIG)
    raw.c_cc[VMIN] = 0.cuchar
    raw.c_cc[VTIME] = 1.cuchar
    if tcsetattr(STDIN_FILENO, TCSAFLUSH, addr raw) == -1:
      self.die("tcsetattr")

  def disableRawMode(self):
    discard tcsetattr(STDIN_FILENO, TCSAFLUSH, addr self.origTermios)

  def readKey(self) -> EditorKey_T:
    var c: char
    while true:
      let nread = read(STDIN_FILENO, addr c, 1)
      if nread == 1: break
      if nread == -1 and osLastError() != OsErrorCode(EAGAIN):
        self.die("read")
    if ord(c) == 27:
      var seq: array[3, char]
      if read(STDIN_FILENO, addr seq[0], 1) != 1: return ESC
      if read(STDIN_FILENO, addr seq[1], 1) != 1: return ESC
      if seq[0] == '[':
        if seq[1] >= '0' and seq[1] <= '9':
          if read(STDIN_FILENO, addr seq[2], 1) != 1: return ESC
          if seq[2] == '~':
            switch seq[1]:
              when '1': return HOME_KEY
              when '7': return HOME_KEY
              when '3': return DEL_KEY
              when '4': return END_KEY
              when '8': return END_KEY
              when '5': return PAGE_UP
              when '6': return PAGE_DOWN
              when others: discard
        else:
          switch seq[1]:
            when 'A': return ARROW_UP
            when 'B': return ARROW_DOWN
            when 'C': return ARROW_RIGHT
            when 'D': return ARROW_LEFT
            when 'H': return HOME_KEY
            when 'F': return END_KEY
            when others: discard
      elif seq[0] == 'O':
        switch seq[1]:
          when 'H': return HOME_KEY
          when 'F': return END_KEY
          when others: discard
      return ESC
    return EditorKey_T(ord(c))

  def getWindowSize(self) -> tuple[rows, cols: int]:
    var ws: IOctl_WinSize
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, addr ws) == -1 or ws.ws_col == 0:
      result.cols = 80
      result.rows = 24
      return
    result.cols = int(ws.ws_col)
    result.rows = int(ws.ws_row)

  def rowCxToRx(self, row: Row_T, cx: int) -> int:
    for j in 0..<cx:
      if row.chars[j] == '\t':
        result += (KILO_TAB_STOP - 1) - (result mod KILO_TAB_STOP)
      inc(result)

  def rowRxToCx(self, row: Row_T, rx: int) -> int:
    var curRx = 0
    for cx in 0..<row.size:
      if row.chars[cx] == '\t':
        curRx += (KILO_TAB_STOP - 1) - (curRx mod KILO_TAB_STOP)
      inc(curRx)
      if curRx > rx: return cx
    return result

  def updateRow(self: var, row: var Row_T):
    var tabs = 0
    for j in 0..<row.size:
      if row.chars[j] == '\t': inc(tabs)
    row.render = newStringOfCap(row.size + tabs * (KILO_TAB_STOP - 1))
    for j in 0..<row.size:
      if row.chars[j] == '\t':
        row.render.add(' ')
        while row.render.len mod KILO_TAB_STOP != 0: row.render.add(' ')
      else:
        row.render.add(row.chars[j])
    row.rsize = row.render.len

  def insertRow(self: var, at: int, s: string, length: int):
    if at < 0 or at > self.numrows: return
    self.row.setLen(self.numrows + 1)
    for i in countdown(self.numrows - 1, at):
      self.row[i + 1] = self.row[i]
    self.row[at].size = length
    self.row[at].chars = s
    self.row[at].rsize = 0
    self.row[at].render = ""
    self.updateRow(self.row[at])
    inc(self.numrows)
    inc(self.dirty)

  def freeRow(self, row: var Row_T):
    row.render = ""
    row.chars = ""

  def delRow(self: var, at: int):
    if at < 0 or at >= self.numrows: return
    self.freeRow(self.row[at])
    for i in at..<self.numrows - 1:
      self.row[i] = self.row[i + 1]
    self.row.setLen(self.numrows - 1)
    dec(self.numrows)
    inc(self.dirty)

  def rowInsertChar(self: var, row: var Row_T, at: int, c: char):
    var actualAt = at
    if actualAt < 0 or actualAt > row.size: actualAt = row.size
    row.chars.insert($c, actualAt)
    inc(row.size)
    self.updateRow(row)
    inc(self.dirty)

  def rowAppendString(self: var, row: var Row_T, s: string, length: int):
    row.chars.add(s[0..<length])
    row.size += length
    self.updateRow(row)
    inc(self.dirty)

  def rowDelChar(self: var, row: var Row_T, at: int):
    if at < 0 or at >= row.size: return
    row.chars.delete(at..at)
    row.size -= 1
    self.updateRow(row)
    inc(self.dirty)

  def insertChar(self: var, c: char):
    if self.cy == self.numrows:
      self.insertRow(self.numrows, "", 0)
    self.rowInsertChar(self.row[self.cy], self.cx, c)
    inc(self.cx)

  def insertNewline(self: var):
    if self.cx == 0:
      self.insertRow(self.cy, "", 0)
    else:
      let row = self.row[self.cy]
      self.insertRow(self.cy + 1, row.chars[self.cx..<row.size], row.size - self.cx)
      self.row[self.cy].size = self.cx
      self.row[self.cy].chars.setLen(self.cx)
      self.updateRow(self.row[self.cy])
    inc(self.cy)
    self.cx = 0

  def delChar(self: var):
    if self.cy == self.numrows or (self.cx == 0 and self.cy == 0): return
    if self.cx > 0:
      self.rowDelChar(self.row[self.cy], self.cx - 1)
      dec(self.cx)
    else:
      self.cx = self.row[self.cy - 1].size
      self.rowAppendString(self.row[self.cy - 1], self.row[self.cy].chars, self.row[self.cy].size)
      self.delRow(self.cy)
      dec(self.cy)

  def rowsToString(self) -> string:
    for j in 0..<self.numrows:
      result.add(self.row[j].chars & '\n')

  def open(self: var, filename: string):
    self.filename = filename
    let fd = open(filename, O_RDONLY)
    if fd == -1:
      self.statusmsg = "New file: " & filename
      self.statusmsgTime = times.getTime()
      return
    var buf: string = ""
    var c: char
    var n: int
    while true:
      n = read(fd, addr c, 1)
      if n != 1: break
      if c == '\n':
        if buf.len > 0:
          if buf[buf.len-1] == '\r': buf.setLen(buf.len - 1)
        self.insertRow(self.numrows, buf, buf.len)
        buf = ""
      else:
        buf.add(c)
    if buf.len > 0:
      if buf.len > 0 and buf[buf.len-1] == '\r': buf.setLen(buf.len - 1)
      self.insertRow(self.numrows, buf, buf.len)
    discard close(fd)
    self.dirty = 0

  def scroll(self: var):
    self.rx = 0
    if self.cy < self.numrows:
      self.rx = self.rowCxToRx(self.row[self.cy], self.cx)
    if self.cy < self.rowoff:
      self.rowoff = self.cy
    if self.cy >= self.rowoff + self.screenrows:
      self.rowoff = self.cy - self.screenrows + 1
    if self.rx < self.coloff:
      self.coloff = self.rx
    if self.rx >= self.coloff + self.screencols:
      self.coloff = self.rx - self.screencols + 1

  def drawRows(self) -> string:
    for y in 0..<self.screenrows:
      let filerow = y + self.rowoff
      if filerow >= self.numrows:
        if self.numrows == 0 and y == self.screenrows div 3:
          let welcome = "Kilo editor -- version " & KILO_VERSION
          var welcomelen = min(welcome.len, self.screencols)
          var padding = (self.screencols - welcomelen) div 2
          if padding > 0: result.add("~"); dec(padding)
          while padding > 0: result.add(" "); dec(padding)
          result.add(welcome[0..<welcomelen])
        else:
          result.add("~")
      else:
        var len = self.row[filerow].rsize - self.coloff
        if len < 0: len = 0
        if len > self.screencols: len = self.screencols
        for j in 0..<len:
          let ch = self.row[filerow].render[self.coloff + j]
          if ch.isDigit:
            result.add("\x1b[31m" & ch & "\x1b[39m")
          else:
            result.add(ch)
      result.add("\x1b[K\r\n")

  def drawStatusBar(self) -> string:
    result.add("\x1b[7m")
    let fname = if self.filename != "": self.filename else: "[No Name]"
    let modified = if self.dirty > 0: "(modified)" else: ""
    let status = fname[0..<min(fname.len, 20)] & " - " & $self.numrows & " lines " & modified
    let rstatus = $(self.cy + 1) & "/" & $self.numrows
    var len = min(status.len, self.screencols)
    result.add(status[0..<len])
    while len < self.screencols:
      if self.screencols - len == rstatus.len:
        result.add(rstatus)
        break
      result.add(" ")
      inc(len)
    result.add("\x1b[m\r\n")

  def drawMessageBar(self) -> string:
    result.add("\x1b[K")
    let msglen = min(self.statusmsg.len, self.screencols)
    if msglen > 0 and (times.getTime().toUnix - self.statusmsgTime.toUnix) < 5:
      result.add(self.statusmsg[0..<msglen])

  def refreshScreen(self: var):
    self.scroll()
    var ab: string
    ab.add("\x1b[?25l\x1b[H")
    ab.add(self.drawRows())
    ab.add(self.drawStatusBar())
    ab.add(self.drawMessageBar())
    ab.add("\x1b[" & $(self.cy - self.rowoff + 1) & ";" & $(self.rx - self.coloff + 1) & "H")
    ab.add("\x1b[?25h")
    stdout.write(ab)

  def setStatusMessage(self: var, fmt: string, args: varargs[string]):
    self.statusmsg = fmt % args
    self.statusmsgTime = times.getTime()

  def prompt(self: var, prompt: string) -> string:
    var buf = ""
    while true:
      self.setStatusMessage(prompt.replace("%s", "$1"), buf)
      self.refreshScreen()
      stdout.flushFile()
      let c = self.readKey()
      switch c:
        when DEL_KEY:
          if buf.len > 0: buf.setLen(buf.len - 1)
        when BACKSPACE:
          if buf.len > 0: buf.setLen(buf.len - 1)
        when CTRL_H:
          if buf.len > 0: buf.setLen(buf.len - 1)
        when ESC:
          self.setStatusMessage("")
          return ""
        when ENTER:
          if buf.len > 0:
            self.setStatusMessage("")
            return buf
        when others:
          let code = ord(c)
          if code >= 32 and code < 127:
            buf.add(char(code))

  def save(self: var):
    if self.filename == "":
      self.refreshScreen()
      stdout.flushFile()
      self.filename = self.prompt("Save as: %s (ESC to cancel)")
      if self.filename == "":
        self.setStatusMessage("Save aborted")
        self.refreshScreen()
        stdout.flushFile()
        return
      self.refreshScreen()
      stdout.flushFile()
    let buf = self.rowsToString()
    let fd = open(self.filename, O_WRONLY or O_CREAT or O_TRUNC, 0o644)
    if fd != -1:
      let written = write(fd, cstring(buf), buf.len)
      if written == buf.len:
        if fsync(fd) == 0:
          discard close(fd)
          self.dirty = 0
          self.setStatusMessage("$1 bytes written to disk", $(buf.len))
          self.refreshScreen()
          stdout.flushFile()
          return
        else:
          discard close(fd)
          self.setStatusMessage("fsync failed: " & osErrorMsg(osLastError()))
      else:
        discard close(fd)
        self.setStatusMessage("Write failed: wrote $1 of $2 bytes", $(written), $(buf.len))
    else:
      self.setStatusMessage("Can't save: " & osErrorMsg(osLastError()))

  def findCallback(self: var, query: string, key: EditorKey_T):
    switch key:
      when ENTER:
        self.lastMatch = -1
        self.findDirection = 1
        return
      when ESC:
        self.lastMatch = -1
        self.findDirection = 1
        return
      when ARROW_RIGHT:
        self.findDirection = 1
      when ARROW_DOWN:
        self.findDirection = 1
      when ARROW_LEFT:
        self.findDirection = -1
      when ARROW_UP:
        self.findDirection = -1
      when others:
        self.lastMatch = -1
        self.findDirection = 1
    if self.lastMatch == -1: self.findDirection = 1
    var current = self.lastMatch
    for i in 0..<self.numrows:
      inc(current, self.findDirection)
      if current == -1: current = self.numrows - 1
      elif current == self.numrows: current = 0
      let row = self.row[current]
      let matchIdx = row.render.find(query)
      if matchIdx != -1:
        self.lastMatch = current
        self.cy = current
        self.cx = self.rowRxToCx(row, matchIdx)
        self.rowoff = self.numrows
        break

  def find(self: var):
    let savedCx = self.cx
    let savedCy = self.cy
    let savedColoff = self.coloff
    let savedRowoff = self.rowoff
    self.refreshScreen()
    stdout.flushFile()
    let query = self.prompt("Search: %s (Use ESC/Arrows/Enter)")
    if query == "":
      self.cx = savedCx
      self.cy = savedCy
      self.coloff = savedColoff
      self.rowoff = savedRowoff

  def moveCursor(self: var, key: EditorKey_T):
    var row: Row_T
    if self.cy >= self.numrows:
      row.size = 0
    else:
      row = self.row[self.cy]
    switch key:
      when ARROW_LEFT:
        if self.cx != 0: dec(self.cx)
        elif self.cy > 0:
          dec(self.cy)
          self.cx = self.row[self.cy].size
      when ARROW_RIGHT:
        if self.cx < row.size: inc(self.cx)
        elif self.cx == row.size:
          inc(self.cy)
          self.cx = 0
      when ARROW_UP:
        if self.cy != 0: dec(self.cy)
      when ARROW_DOWN:
        if self.cy < self.numrows: inc(self.cy)
      when others: discard
    let rowlen = if self.cy < self.numrows: self.row[self.cy].size else: 0
    if self.cx > rowlen: self.cx = rowlen

  def processKeypress(self: var):
    let c = self.readKey()
    switch c:
      when ENTER: self.insertNewline()
      when CTRL_Q:
        if self.dirty > 0:
          if self.quitTimes > 0:
            self.setStatusMessage("WARNING!!! File has unsaved changes. Press Ctrl-Q $1 more times to quit.", $(self.quitTimes))
            dec(self.quitTimes)
            return
          else:
            stdout.write("\x1b[2J\x1b[H")
            quit(0)
        else:
          stdout.write("\x1b[2J\x1b[H")
          quit(0)
      when CTRL_S:
        self.save()
        self.quitTimes = 2
      when HOME_KEY: self.cx = 0
      when END_KEY:
        if self.cy < self.numrows: self.cx = self.row[self.cy].size
      when CTRL_F: self.find()
      when BACKSPACE: self.delChar()
      when CTRL_H: self.delChar()
      when DEL_KEY:
        self.moveCursor(ARROW_RIGHT)
        self.delChar()
      when PAGE_UP:
        self.cy = self.rowoff
        for i in 0..<self.screenrows:
          self.moveCursor(ARROW_UP)
      when PAGE_DOWN:
        self.cy = self.rowoff + self.screenrows - 1
        if self.cy > self.numrows: self.cy = self.numrows
        for i in 0..<self.screenrows:
          self.moveCursor(ARROW_DOWN)
      when ARROW_UP: self.moveCursor(c)
      when ARROW_DOWN: self.moveCursor(c)
      when ARROW_LEFT: self.moveCursor(c)
      when ARROW_RIGHT: self.moveCursor(c)
      when CTRL_L: discard
      when ESC: discard
      when others: self.insertChar(char(ord(c)))
    self.quitTimes = 2

when isMainModule:
  var editor = newEditor()
  editor.enableRawMode()
  let winSize = editor.getWindowSize()
  if winSize.rows == -1: editor.die("getWindowSize")
  editor.screenrows = winSize.rows - 2
  editor.screencols = winSize.cols
  if paramCount() >= 1: editor.open(paramStr(1))
  stdout.write("\x1b[2J\x1b[H")
  stdout.flushFile()
  editor.setStatusMessage("HELP: Ctrl-S = save | Ctrl-Q = quit | Ctrl-F = find")
  editor.refreshScreen()
  stdout.flushFile()
  try:
    while true:
      editor.refreshScreen()
      editor.processKeypress()
  finally:
    editor.disableRawMode()
    stdout.write("\x1b[2J\x1b[H")
    stdout.flushFile()
