## special shortcuts for manipulating the editor
# Some keys on the keyboard generate unicode characters, others generate
# terminfo key codes. We need to modify different places in the two cases.

# tab - insert two spaces

scenario editor-inserts-two-spaces-on-tab [
  assume-screen 10/width, 5/height
  # just one character in final line
  1:address:array:character <- new [ab
cd]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 5/right
  assume-console [
    press tab
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .  ab      .
    .cd        .
  ]
]

after <handle-special-character> [
  {
    tab?:boolean <- equal c, 9/tab
    break-unless tab?
    <insert-character-begin>
    editor, screen, go-render?:boolean <- insert-at-cursor editor, 32/space, screen
    editor, screen, go-render?:boolean <- insert-at-cursor editor, 32/space, screen
    <insert-character-end>
    go-render? <- copy 1/true
    return
  }
]

# backspace - delete character before cursor

scenario editor-handles-backspace-key [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abc]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  assume-console [
    left-click 1, 1
    press backspace
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    4:number <- get *2:address:editor-data, cursor-row:offset
    5:number <- get *2:address:editor-data, cursor-column:offset
  ]
  screen-should-contain [
    .          .
    .bc        .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
  memory-should-contain [
    4 <- 1
    5 <- 0
  ]
  check-trace-count-for-label 3, [print-character]  # length of original line to overwrite
]

after <handle-special-character> [
  {
    delete-previous-character?:boolean <- equal c, 8/backspace
    break-unless delete-previous-character?
    <backspace-character-begin>
    editor, screen, go-render?:boolean, backspaced-cell:address:duplex-list:character <- delete-before-cursor editor, screen
    <backspace-character-end>
    return
  }
]

# return values:
#   go-render? - whether caller needs to update the screen
#   backspaced-cell - value deleted (or 0 if nothing was deleted) so we can save it for undo, etc.
def delete-before-cursor editor:address:editor-data, screen:address:screen -> editor:address:editor-data, screen:address:screen, go-render?:boolean, backspaced-cell:address:duplex-list:character [
  local-scope
  load-ingredients
  before-cursor:address:duplex-list:character <- get *editor, before-cursor:offset
  data:address:duplex-list:character <- get *editor, data:offset
  # if at start of text (before-cursor at § sentinel), return
  prev:address:duplex-list:character <- prev before-cursor
  go-render?, backspaced-cell <- copy 0/no-more-render, 0/nothing-deleted
  return-unless prev
  go-render? <- copy 1/true
  trace 10, [app], [delete-before-cursor]
  original-row:number <- get *editor, cursor-row:offset
  editor <- move-cursor-coordinates-left editor
  backspaced-cell:address:duplex-list:character <- copy before-cursor
  data <- remove before-cursor, data  # will also neatly trim next/prev pointers in backspaced-cell/before-cursor
  before-cursor <- copy prev
  *editor <- put *editor, before-cursor:offset, before-cursor
  screen-width:number <- screen-width screen
  cursor-row:number <- get *editor, cursor-row:offset
  cursor-column:number <- get *editor, cursor-column:offset
  # did we just backspace over a newline?
  same-row?:boolean <- equal cursor-row, original-row
  return-unless same-row?
  left:number <- get *editor, left:offset
  right:number <- get *editor, right:offset
  curr:address:duplex-list:character <- next before-cursor
  screen <- move-cursor screen, cursor-row, cursor-column
  curr-column:number <- copy cursor-column
  {
    # hit right margin? give up and let caller render
    at-right?:boolean <- greater-or-equal curr-column, right
    return-if at-right?
    break-unless curr
    # newline? done.
    currc:character <- get *curr, value:offset
    at-newline?:boolean <- equal currc, 10/newline
    break-if at-newline?
    screen <- print screen, currc
    curr-column <- add curr-column, 1
    curr <- next curr
    loop
  }
  # we're guaranteed not to be at the right margin
  space:character <- copy 32/space
  screen <- print screen, space
  go-render? <- copy 0/false
]

def move-cursor-coordinates-left editor:address:editor-data -> editor:address:editor-data [
  local-scope
  load-ingredients
  before-cursor:address:duplex-list:character <- get *editor, before-cursor:offset
  cursor-row:number <- get *editor, cursor-row:offset
  cursor-column:number <- get *editor, cursor-column:offset
  left:number <- get *editor, left:offset
  # if not at left margin, move one character left
  {
    at-left-margin?:boolean <- equal cursor-column, left
    break-if at-left-margin?
    trace 10, [app], [decrementing cursor column]
    cursor-column <- subtract cursor-column, 1
    *editor <- put *editor, cursor-column:offset, cursor-column
    return
  }
  # if at left margin, we must move to previous row:
  top-of-screen?:boolean <- equal cursor-row, 1  # exclude menu bar
  {
    break-if top-of-screen?
    cursor-row <- subtract cursor-row, 1
    *editor <- put *editor, cursor-row:offset, cursor-row
  }
  {
    break-unless top-of-screen?
    # no scroll, so do nothing
  }
  {
    # case 1: if previous character was newline, figure out how long the previous line is
    previous-character:character <- get *before-cursor, value:offset
    previous-character-is-newline?:boolean <- equal previous-character, 10/newline
    break-unless previous-character-is-newline?
    # compute length of previous line
    trace 10, [app], [switching to previous line]
    d:address:duplex-list:character <- get *editor, data:offset
    end-of-line:number <- previous-line-length before-cursor, d
    right:number <- get *editor, right:offset
    width:number <- subtract right, left
    wrap?:boolean <- greater-than end-of-line, width
    {
      break-unless wrap?
      _, column-offset:number <- divide-with-remainder end-of-line, width
      cursor-column <- add left, column-offset
      *editor <- put *editor, cursor-column:offset, cursor-column
    }
    {
      break-if wrap?
      cursor-column <- add left, end-of-line
      *editor <- put *editor, cursor-column:offset, cursor-column
    }
    return
  }
  # case 2: if previous-character was not newline, we're just at a wrapped line
  trace 10, [app], [wrapping to previous line]
  right:number <- get *editor, right:offset
  cursor-column <- subtract right, 1  # leave room for wrap icon
  *editor <- put *editor, cursor-column:offset, cursor-column
]

# takes a pointer 'curr' into the doubly-linked list and its sentinel, counts
# the length of the previous line before the 'curr' pointer.
def previous-line-length curr:address:duplex-list:character, start:address:duplex-list:character -> result:number [
  local-scope
  load-ingredients
  result:number <- copy 0
  return-unless curr
  at-start?:boolean <- equal curr, start
  return-if at-start?
  {
    curr <- prev curr
    break-unless curr
    at-start?:boolean <- equal curr, start
    break-if at-start?
    c:character <- get *curr, value:offset
    at-newline?:boolean <- equal c, 10/newline
    break-if at-newline?
    result <- add result, 1
    loop
  }
]

scenario editor-clears-last-line-on-backspace [
  assume-screen 10/width, 5/height
  # just one character in final line
  1:address:array:character <- new [ab
cd]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  assume-console [
    left-click 2, 0  # cursor at only character in final line
    press backspace
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    4:number <- get *2:address:editor-data, cursor-row:offset
    5:number <- get *2:address:editor-data, cursor-column:offset
  ]
  screen-should-contain [
    .          .
    .abcd      .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
  memory-should-contain [
    4 <- 1
    5 <- 2
  ]
]

scenario editor-joins-and-wraps-lines-on-backspace [
  assume-screen 10/width, 5/height
  # initialize editor with two long-ish but non-wrapping lines
  1:address:array:character <- new [abc def
ghi jkl]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # position the cursor at the start of the second and hit backspace
  assume-console [
    left-click 2, 0
    press backspace
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # resulting single line should wrap correctly
  screen-should-contain [
    .          .
    .abc defgh↩.
    .i jkl     .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

scenario editor-wraps-long-lines-on-backspace [
  assume-screen 10/width, 5/height
  # initialize editor in part of the screen with a long line
  1:address:array:character <- new [abc def ghij]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 8/right
  editor-render screen, 2:address:editor-data
  # confirm that it wraps
  screen-should-contain [
    .          .
    .abc def↩  .
    . ghij     .
    .┈┈┈┈┈┈┈┈  .
  ]
  $clear-trace
  # position the cursor somewhere in the middle of the top screen line and hit backspace
  assume-console [
    left-click 1, 4
    press backspace
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # resulting single line should wrap correctly and not overflow its bounds
  screen-should-contain [
    .          .
    .abcdef ↩  .
    .ghij      .
    .┈┈┈┈┈┈┈┈  .
    .          .
  ]
]

# delete - delete character at cursor

scenario editor-handles-delete-key [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abc]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  assume-console [
    press delete
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .bc        .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
  check-trace-count-for-label 3, [print-character]  # length of original line to overwrite
  $clear-trace
  assume-console [
    press delete
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .c         .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
  check-trace-count-for-label 2, [print-character]  # new length to overwrite
]

after <handle-special-key> [
  {
    delete-next-character?:boolean <- equal k, 65522/delete
    break-unless delete-next-character?
    <delete-character-begin>
    editor, screen, go-render?:boolean, deleted-cell:address:duplex-list:character <- delete-at-cursor editor, screen
    <delete-character-end>
    return
  }
]

def delete-at-cursor editor:address:editor-data, screen:address:screen -> editor:address:editor-data, screen:address:screen, go-render?:boolean, deleted-cell:address:duplex-list:character [
  local-scope
  load-ingredients
  before-cursor:address:duplex-list:character <- get *editor, before-cursor:offset
  data:address:duplex-list:character <- get *editor, data:offset
  deleted-cell:address:duplex-list:character <- next before-cursor
  go-render? <- copy 0/false
  return-unless deleted-cell
  currc:character <- get *deleted-cell, value:offset
  data <- remove deleted-cell, data
  deleted-newline?:boolean <- equal currc, 10/newline
  go-render? <- copy 1/true
  return-if deleted-newline?
  # wasn't a newline? render rest of line
  curr:address:duplex-list:character <- next before-cursor  # refresh after remove above
  cursor-row:number <- get *editor, cursor-row:offset
  cursor-column:number <- get *editor, cursor-column:offset
  screen <- move-cursor screen, cursor-row, cursor-column
  curr-column:number <- copy cursor-column
  screen-width:number <- screen-width screen
  {
    # hit right margin? give up and let caller render
    at-right?:boolean <- greater-or-equal curr-column, screen-width
    go-render? <- copy 1/true
    return-if at-right?
    break-unless curr
    # newline? done.
    currc:character <- get *curr, value:offset
    at-newline?:boolean <- equal currc, 10/newline
    break-if at-newline?
    screen <- print screen, currc
    curr-column <- add curr-column, 1
    curr <- next curr
    loop
  }
  # we're guaranteed not to be at the right margin
  space:character <- copy 32/space
  screen <- print screen, space
  go-render? <- copy 0/false
]

# right arrow

scenario editor-moves-cursor-right-with-key [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abc]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  assume-console [
    press right-arrow
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .a0bc      .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
  check-trace-count-for-label 3, [print-character]  # 0 and following characters
]

after <handle-special-key> [
  {
    move-to-next-character?:boolean <- equal k, 65514/right-arrow
    break-unless move-to-next-character?
    # if not at end of text
    next-cursor:address:duplex-list:character <- next before-cursor
    break-unless next-cursor
    # scan to next character
    <move-cursor-begin>
    before-cursor <- copy next-cursor
    *editor <- put *editor, before-cursor:offset, before-cursor
    editor, go-render?:boolean <- move-cursor-coordinates-right editor, screen-height
    screen <- move-cursor screen, cursor-row, cursor-column
    undo-coalesce-tag:number <- copy 2/right-arrow
    <move-cursor-end>
    return
  }
]

def move-cursor-coordinates-right editor:address:editor-data, screen-height:number -> editor:address:editor-data, go-render?:boolean [
  local-scope
  load-ingredients
  before-cursor:address:duplex-list:character <- get *editor before-cursor:offset
  cursor-row:number <- get *editor, cursor-row:offset
  cursor-column:number <- get *editor, cursor-column:offset
  left:number <- get *editor, left:offset
  right:number <- get *editor, right:offset
  # if crossed a newline, move cursor to start of next row
  {
    old-cursor-character:character <- get *before-cursor, value:offset
    was-at-newline?:boolean <- equal old-cursor-character, 10/newline
    break-unless was-at-newline?
    cursor-row <- add cursor-row, 1
    *editor <- put *editor, cursor-row:offset, cursor-row
    cursor-column <- copy left
    *editor <- put *editor, cursor-column:offset, cursor-column
    below-screen?:boolean <- greater-or-equal cursor-row, screen-height  # must be equal
    go-render? <- copy 0/false
    return-unless below-screen?
    cursor-row <- subtract cursor-row, 1  # bring back into screen range
    *editor <- put *editor, cursor-row:offset, cursor-row
    go-render? <- copy 1/true
    return
  }
  # if the line wraps, move cursor to start of next row
  {
    # if we're at the column just before the wrap indicator
    wrap-column:number <- subtract right, 1
    at-wrap?:boolean <- equal cursor-column, wrap-column
    break-unless at-wrap?
    # and if next character isn't newline
    next:address:duplex-list:character <- next before-cursor
    break-unless next
    next-character:character <- get *next, value:offset
    newline?:boolean <- equal next-character, 10/newline
    break-if newline?
    cursor-row <- add cursor-row, 1
    *editor <- put *editor, cursor-row:offset, cursor-row
    cursor-column <- copy left
    *editor <- put *editor, cursor-column:offset, cursor-column
    below-screen?:boolean <- greater-or-equal cursor-row, screen-height  # must be equal
    return-unless below-screen?, editor/same-as-ingredient:0, 0/no-more-render
    cursor-row <- subtract cursor-row, 1  # bring back into screen range
    *editor <- put *editor, cursor-row:offset, cursor-row
    go-render? <- copy 1/true
    return
  }
  # otherwise move cursor one character right
  cursor-column <- add cursor-column, 1
  *editor <- put *editor, cursor-column:offset, cursor-column
  go-render? <- copy 0/false
]

scenario editor-moves-cursor-to-next-line-with-right-arrow [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abc
d]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # type right-arrow a few times to get to start of second line
  assume-console [
    press right-arrow
    press right-arrow
    press right-arrow
    press right-arrow  # next line
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  check-trace-count-for-label 0, [print-character]
  # type something and ensure it goes where it should
  assume-console [
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .abc       .
    .0d        .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
  check-trace-count-for-label 2, [print-character]  # new length of second line
]

scenario editor-moves-cursor-to-next-line-with-right-arrow-2 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abc
d]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 1/left, 10/right
  editor-render screen, 2:address:editor-data
  assume-console [
    press right-arrow
    press right-arrow
    press right-arrow
    press right-arrow  # next line
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    . abc      .
    . 0d       .
    . ┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

scenario editor-moves-cursor-to-next-wrapped-line-with-right-arrow [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abcdef]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 5/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  assume-console [
    left-click 1, 3
    press right-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  screen-should-contain [
    .          .
    .abcd↩     .
    .ef        .
    .┈┈┈┈┈     .
    .          .
  ]
  memory-should-contain [
    3 <- 2
    4 <- 0
  ]
  check-trace-count-for-label 0, [print-character]
]

scenario editor-moves-cursor-to-next-wrapped-line-with-right-arrow-2 [
  assume-screen 10/width, 5/height
  # line just barely wrapping
  1:address:array:character <- new [abcde]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 5/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # position cursor at last character before wrap and hit right-arrow
  assume-console [
    left-click 1, 3
    press right-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  memory-should-contain [
    3 <- 2
    4 <- 0
  ]
  # now hit right arrow again
  assume-console [
    press right-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  memory-should-contain [
    3 <- 2
    4 <- 1
  ]
  check-trace-count-for-label 0, [print-character]
]

scenario editor-moves-cursor-to-next-wrapped-line-with-right-arrow-3 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abcdef]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 1/left, 6/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  assume-console [
    left-click 1, 4
    press right-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  screen-should-contain [
    .          .
    . abcd↩    .
    . ef       .
    . ┈┈┈┈┈    .
    .          .
  ]
  memory-should-contain [
    3 <- 2
    4 <- 1
  ]
  check-trace-count-for-label 0, [print-character]
]

scenario editor-moves-cursor-to-next-line-with-right-arrow-at-end-of-line [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abc
d]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # move to end of line, press right-arrow, type a character
  assume-console [
    left-click 1, 3
    press right-arrow
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # new character should be in next line
  screen-should-contain [
    .          .
    .abc       .
    .0d        .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
  check-trace-count-for-label 2, [print-character]
]

# todo: ctrl-right: next word-end

# left arrow

scenario editor-moves-cursor-left-with-key [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abc]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  assume-console [
    left-click 1, 2
    press left-arrow
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .a0bc      .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
  check-trace-count-for-label 3, [print-character]
]

after <handle-special-key> [
  {
    move-to-previous-character?:boolean <- equal k, 65515/left-arrow
    break-unless move-to-previous-character?
    trace 10, [app], [left arrow]
    # if not at start of text (before-cursor at § sentinel)
    prev:address:duplex-list:character <- prev before-cursor
    go-render? <- copy 0/false
    return-unless prev
    <move-cursor-begin>
    editor <- move-cursor-coordinates-left editor
    before-cursor <- copy prev
    *editor <- put *editor, before-cursor:offset, before-cursor
    undo-coalesce-tag:number <- copy 1/left-arrow
    <move-cursor-end>
    return
  }
]

scenario editor-moves-cursor-to-previous-line-with-left-arrow-at-start-of-line [
  assume-screen 10/width, 5/height
  # initialize editor with two lines
  1:address:array:character <- new [abc
d]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # position cursor at start of second line (so there's no previous newline)
  assume-console [
    left-click 2, 0
    press left-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  memory-should-contain [
    3 <- 1
    4 <- 3
  ]
  check-trace-count-for-label 0, [print-character]
]

scenario editor-moves-cursor-to-previous-line-with-left-arrow-at-start-of-line-2 [
  assume-screen 10/width, 5/height
  # initialize editor with three lines
  1:address:array:character <- new [abc
def
g]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # position cursor further down (so there's a newline before the character at
  # the cursor)
  assume-console [
    left-click 3, 0
    press left-arrow
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .abc       .
    .def0      .
    .g         .
    .┈┈┈┈┈┈┈┈┈┈.
  ]
  check-trace-count-for-label 1, [print-character]  # just the '0'
]

scenario editor-moves-cursor-to-previous-line-with-left-arrow-at-start-of-line-3 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abc
def
g]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # position cursor at start of text, press left-arrow, then type a character
  assume-console [
    left-click 1, 0
    press left-arrow
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # left-arrow should have had no effect
  screen-should-contain [
    .          .
    .0abc      .
    .def       .
    .g         .
    .┈┈┈┈┈┈┈┈┈┈.
  ]
  check-trace-count-for-label 4, [print-character]  # length of first line
]

scenario editor-moves-cursor-to-previous-line-with-left-arrow-at-start-of-line-4 [
  assume-screen 10/width, 5/height
  # initialize editor with text containing an empty line
  1:address:array:character <- new [abc

d]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # position cursor right after empty line
  assume-console [
    left-click 3, 0
    press left-arrow
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .abc       .
    .0         .
    .d         .
    .┈┈┈┈┈┈┈┈┈┈.
  ]
  check-trace-count-for-label 1, [print-character]  # just the '0'
]

scenario editor-moves-across-screen-lines-across-wrap-with-left-arrow [
  assume-screen 10/width, 5/height
  # initialize editor with a wrapping line
  1:address:array:character <- new [abcdef]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 5/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  screen-should-contain [
    .          .
    .abcd↩     .
    .ef        .
    .┈┈┈┈┈     .
    .          .
  ]
  # position cursor right after empty line
  assume-console [
    left-click 2, 0
    press left-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  memory-should-contain [
    3 <- 1  # previous row
    4 <- 3  # right margin except wrap icon
  ]
  check-trace-count-for-label 0, [print-character]
]

scenario editor-moves-across-screen-lines-to-wrapping-line-with-left-arrow [
  assume-screen 10/width, 5/height
  # initialize editor with a wrapping line followed by a second line
  1:address:array:character <- new [abcdef
g]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 5/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  screen-should-contain [
    .          .
    .abcd↩     .
    .ef        .
    .g         .
    .┈┈┈┈┈     .
  ]
  # position cursor right after empty line
  assume-console [
    left-click 3, 0
    press left-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  memory-should-contain [
    3 <- 2  # previous row
    4 <- 2  # end of wrapped line
  ]
  check-trace-count-for-label 0, [print-character]
]

scenario editor-moves-across-screen-lines-to-non-wrapping-line-with-left-arrow [
  assume-screen 10/width, 5/height
  # initialize editor with a line on the verge of wrapping, followed by a second line
  1:address:array:character <- new [abcd
e]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 5/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  screen-should-contain [
    .          .
    .abcd      .
    .e         .
    .┈┈┈┈┈     .
    .          .
  ]
  # position cursor right after empty line
  assume-console [
    left-click 2, 0
    press left-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  memory-should-contain [
    3 <- 1  # previous row
    4 <- 4  # end of wrapped line
  ]
  check-trace-count-for-label 0, [print-character]
]

# todo: ctrl-left: previous word-start

# up arrow

scenario editor-moves-to-previous-line-with-up-arrow [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abc
def]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  assume-console [
    left-click 2, 1
    press up-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  memory-should-contain [
    3 <- 1
    4 <- 1
  ]
  check-trace-count-for-label 0, [print-character]
  assume-console [
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .a0bc      .
    .def       .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

after <handle-special-key> [
  {
    move-to-previous-line?:boolean <- equal k, 65517/up-arrow
    break-unless move-to-previous-line?
    <move-cursor-begin>
    editor, go-render? <- move-to-previous-line editor
    undo-coalesce-tag:number <- copy 3/up-arrow
    <move-cursor-end>
    return
  }
]

def move-to-previous-line editor:address:editor-data -> editor:address:editor-data, go-render?:boolean [
  local-scope
  load-ingredients
  cursor-row:number <- get *editor, cursor-row:offset
  cursor-column:number <- get *editor, cursor-column:offset
  before-cursor:address:duplex-list:character <- get *editor, before-cursor:offset
  left:number <- get *editor, left:offset
  right:number <- get *editor, right:offset
  already-at-top?:boolean <- lesser-or-equal cursor-row, 1/top
  {
    # if cursor not at top, move it
    break-if already-at-top?
    # if not at newline, move to start of line (previous newline)
    # then scan back another line
    # if either step fails, give up without modifying cursor or coordinates
    curr:address:duplex-list:character <- copy before-cursor
    {
      old:address:duplex-list:character <- copy curr
      c2:character <- get *curr, value:offset
      at-newline?:boolean <- equal c2, 10/newline
      break-if at-newline?
      curr:address:duplex-list:character <- before-previous-line curr, editor
      no-motion?:boolean <- equal curr, old
      go-render? <- copy 0/false
      return-if no-motion?
    }
    {
      old <- copy curr
      curr <- before-previous-line curr, editor
      no-motion?:boolean <- equal curr, old
      go-render? <- copy 0/false
      return-if no-motion?
    }
    before-cursor <- copy curr
    *editor <- put *editor, before-cursor:offset, before-cursor
    cursor-row <- subtract cursor-row, 1
    *editor <- put *editor, cursor-row:offset, cursor-row
    # scan ahead to right column or until end of line
    target-column:number <- copy cursor-column
    cursor-column <- copy left
    *editor <- put *editor, cursor-column:offset, cursor-column
    {
      done?:boolean <- greater-or-equal cursor-column, target-column
      break-if done?
      curr:address:duplex-list:character <- next before-cursor
      break-unless curr
      currc:character <- get *curr, value:offset
      at-newline?:boolean <- equal currc, 10/newline
      break-if at-newline?
      #
      before-cursor <- copy curr
      *editor <- put *editor, before-cursor:offset, before-cursor
      cursor-column <- add cursor-column, 1
      *editor <- put *editor, cursor-column:offset, cursor-column
      loop
    }
    go-render? <- copy 0/false
    return
  }
  {
    # if cursor already at top, do nothing
    break-unless already-at-top?
    go-render? <- copy 0/true
    return
  }
]

scenario editor-adjusts-column-at-previous-line [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [ab
def]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  assume-console [
    left-click 2, 3
    press up-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  memory-should-contain [
    3 <- 1
    4 <- 2
  ]
  check-trace-count-for-label 0, [print-character]
  assume-console [
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .ab0       .
    .def       .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

scenario editor-adjusts-column-at-empty-line [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [
def]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  assume-console [
    left-click 2, 3
    press up-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  memory-should-contain [
    3 <- 1
    4 <- 0
  ]
  check-trace-count-for-label 0, [print-character]
  assume-console [
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .0         .
    .def       .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

scenario editor-moves-to-previous-line-from-left-margin [
  assume-screen 10/width, 5/height
  # start out with three lines
  1:address:array:character <- new [abc
def
ghi]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # click on the third line and hit up-arrow, so you end up just after a newline
  assume-console [
    left-click 3, 0
    press up-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  memory-should-contain [
    3 <- 2
    4 <- 0
  ]
  check-trace-count-for-label 0, [print-character]
  assume-console [
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .abc       .
    .0def      .
    .ghi       .
    .┈┈┈┈┈┈┈┈┈┈.
  ]
]

# down arrow

scenario editor-moves-to-next-line-with-down-arrow [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abc
def]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # cursor starts out at (1, 0)
  assume-console [
    press down-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  # ..and ends at (2, 0)
  memory-should-contain [
    3 <- 2
    4 <- 0
  ]
  check-trace-count-for-label 0, [print-character]
  assume-console [
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .abc       .
    .0def      .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

after <handle-special-key> [
  {
    move-to-next-line?:boolean <- equal k, 65516/down-arrow
    break-unless move-to-next-line?
    <move-cursor-begin>
    editor <- move-to-next-line editor, screen-height
    undo-coalesce-tag:number <- copy 4/down-arrow
    <move-cursor-end>
    return
  }
]

def move-to-next-line editor:address:editor-data, screen-height:number -> editor:address:editor-data [
  local-scope
  load-ingredients
  cursor-row:number <- get *editor, cursor-row:offset
  cursor-column:number <- get *editor, cursor-column:offset
  before-cursor:address:duplex-list:character <- get *editor, before-cursor:offset
  left:number <- get *editor, left:offset
  right:number <- get *editor, right:offset
  last-line:number <- subtract screen-height, 1
  already-at-bottom?:boolean <- greater-or-equal cursor-row, last-line
  # if cursor not at bottom
  return-if already-at-bottom?
  # scan to start of next line, then to right column or until end of line
  max:number <- subtract right, left
  next-line:address:duplex-list:character <- before-start-of-next-line before-cursor, max
  # already at end of buffer? do nothing
  no-motion?:boolean <- equal next-line, before-cursor
  return-if no-motion?
  cursor-row <- add cursor-row, 1
  *editor <- put *editor, cursor-row:offset, cursor-row
  before-cursor <- copy next-line
  *editor <- put *editor, before-cursor:offset, before-cursor
  target-column:number <- copy cursor-column
  cursor-column <- copy left
  *editor <- put *editor, cursor-column:offset, cursor-column
  {
    done?:boolean <- greater-or-equal cursor-column, target-column
    break-if done?
    curr:address:duplex-list:character <- next before-cursor
    break-unless curr
    currc:character <- get *curr, value:offset
    at-newline?:boolean <- equal currc, 10/newline
    break-if at-newline?
    #
    before-cursor <- copy curr
    *editor <- put *editor, before-cursor:offset, before-cursor
    cursor-column <- add cursor-column, 1
    *editor <- put *editor, cursor-column:offset, cursor-column
    loop
  }
]

scenario editor-adjusts-column-at-next-line [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [abc
de]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  assume-console [
    left-click 1, 3
    press down-arrow
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  memory-should-contain [
    3 <- 2
    4 <- 2
  ]
  check-trace-count-for-label 0, [print-character]
  assume-console [
    type [0]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  screen-should-contain [
    .          .
    .abc       .
    .de0       .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

# ctrl-a/home - move cursor to start of line

scenario editor-moves-to-start-of-line-with-ctrl-a [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # start on second line, press ctrl-a
  assume-console [
    left-click 2, 3
    press ctrl-a
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    4:number <- get *2:address:editor-data, cursor-row:offset
    5:number <- get *2:address:editor-data, cursor-column:offset
  ]
  # cursor moves to start of line
  memory-should-contain [
    4 <- 2
    5 <- 0
  ]
  check-trace-count-for-label 0, [print-character]
]

after <handle-special-character> [
  {
    move-to-start-of-line?:boolean <- equal c, 1/ctrl-a
    break-unless move-to-start-of-line?
    <move-cursor-begin>
    move-to-start-of-line editor
    undo-coalesce-tag:number <- copy 0/never
    <move-cursor-end>
    go-render? <- copy 0/false
    return
  }
]

after <handle-special-key> [
  {
    move-to-start-of-line?:boolean <- equal k, 65521/home
    break-unless move-to-start-of-line?
    <move-cursor-begin>
    move-to-start-of-line editor
    undo-coalesce-tag:number <- copy 0/never
    <move-cursor-end>
    go-render? <- copy 0/false
    return
  }
]

def move-to-start-of-line editor:address:editor-data -> editor:address:editor-data [
  local-scope
  load-ingredients
  # update cursor column
  left:number <- get *editor, left:offset
  cursor-column:number <- copy left
  *editor <- put *editor, cursor-column:offset, cursor-column
  # update before-cursor
  before-cursor:address:duplex-list:character <- get *editor, before-cursor:offset
  init:address:duplex-list:character <- get *editor, data:offset
  # while not at start of line, move 
  {
    at-start-of-text?:boolean <- equal before-cursor, init
    break-if at-start-of-text?
    prev:character <- get *before-cursor, value:offset
    at-start-of-line?:boolean <- equal prev, 10/newline
    break-if at-start-of-line?
    before-cursor <- prev before-cursor
    *editor <- put *editor, before-cursor:offset, before-cursor
    assert before-cursor, [move-to-start-of-line tried to move before start of text]
    loop
  }
]

scenario editor-moves-to-start-of-line-with-ctrl-a-2 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # start on first line (no newline before), press ctrl-a
  assume-console [
    left-click 1, 3
    press ctrl-a
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    4:number <- get *2:address:editor-data, cursor-row:offset
    5:number <- get *2:address:editor-data, cursor-column:offset
  ]
  # cursor moves to start of line
  memory-should-contain [
    4 <- 1
    5 <- 0
  ]
  check-trace-count-for-label 0, [print-character]
]

scenario editor-moves-to-start-of-line-with-home [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  $clear-trace
  # start on second line, press 'home'
  assume-console [
    left-click 2, 3
    press home
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  # cursor moves to start of line
  memory-should-contain [
    3 <- 2
    4 <- 0
  ]
  check-trace-count-for-label 0, [print-character]
]

scenario editor-moves-to-start-of-line-with-home-2 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # start on first line (no newline before), press 'home'
  assume-console [
    left-click 1, 3
    press home
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  # cursor moves to start of line
  memory-should-contain [
    3 <- 1
    4 <- 0
  ]
  check-trace-count-for-label 0, [print-character]
]

# ctrl-e/end - move cursor to end of line

scenario editor-moves-to-end-of-line-with-ctrl-e [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # start on first line, press ctrl-e
  assume-console [
    left-click 1, 1
    press ctrl-e
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    4:number <- get *2:address:editor-data, cursor-row:offset
    5:number <- get *2:address:editor-data, cursor-column:offset
  ]
  # cursor moves to end of line
  memory-should-contain [
    4 <- 1
    5 <- 3
  ]
  check-trace-count-for-label 0, [print-character]
  # editor inserts future characters at cursor
  assume-console [
    type [z]
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    4:number <- get *2:address:editor-data, cursor-row:offset
    5:number <- get *2:address:editor-data, cursor-column:offset
  ]
  memory-should-contain [
    4 <- 1
    5 <- 4
  ]
  screen-should-contain [
    .          .
    .123z      .
    .456       .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
  check-trace-count-for-label 1, [print-character]
]

after <handle-special-character> [
  {
    move-to-end-of-line?:boolean <- equal c, 5/ctrl-e
    break-unless move-to-end-of-line?
    <move-cursor-begin>
    move-to-end-of-line editor
    undo-coalesce-tag:number <- copy 0/never
    <move-cursor-end>
    go-render? <- copy 0/false
    return
  }
]

after <handle-special-key> [
  {
    move-to-end-of-line?:boolean <- equal k, 65520/end
    break-unless move-to-end-of-line?
    <move-cursor-begin>
    move-to-end-of-line editor
    undo-coalesce-tag:number <- copy 0/never
    <move-cursor-end>
    go-render? <- copy 0/false
    return
  }
]

def move-to-end-of-line editor:address:editor-data -> editor:address:editor-data [
  local-scope
  load-ingredients
  before-cursor:address:duplex-list:character <- get *editor, before-cursor:offset
  cursor-column:number <- get *editor, cursor-column:offset
  # while not at start of line, move 
  {
    next:address:duplex-list:character <- next before-cursor
    break-unless next  # end of text
    nextc:character <- get *next, value:offset
    at-end-of-line?:boolean <- equal nextc, 10/newline
    break-if at-end-of-line?
    before-cursor <- copy next
    *editor <- put *editor, before-cursor:offset, before-cursor
    cursor-column <- add cursor-column, 1
    *editor <- put *editor, cursor-column:offset, cursor-column
    loop
  }
]

scenario editor-moves-to-end-of-line-with-ctrl-e-2 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # start on second line (no newline after), press ctrl-e
  assume-console [
    left-click 2, 1
    press ctrl-e
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    4:number <- get *2:address:editor-data, cursor-row:offset
    5:number <- get *2:address:editor-data, cursor-column:offset
  ]
  # cursor moves to end of line
  memory-should-contain [
    4 <- 2
    5 <- 3
  ]
  check-trace-count-for-label 0, [print-character]
]

scenario editor-moves-to-end-of-line-with-end [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # start on first line, press 'end'
  assume-console [
    left-click 1, 1
    press end
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  # cursor moves to end of line
  memory-should-contain [
    3 <- 1
    4 <- 3
  ]
  check-trace-count-for-label 0, [print-character]
]

scenario editor-moves-to-end-of-line-with-end-2 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  editor-render screen, 2:address:editor-data
  $clear-trace
  # start on second line (no newline after), press 'end'
  assume-console [
    left-click 2, 1
    press end
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  # cursor moves to end of line
  memory-should-contain [
    3 <- 2
    4 <- 3
  ]
  check-trace-count-for-label 0, [print-character]
]

# ctrl-u - delete text from start of line until (but not at) cursor

scenario editor-deletes-to-start-of-line-with-ctrl-u [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  # start on second line, press ctrl-u
  assume-console [
    left-click 2, 2
    press ctrl-u
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # cursor deletes to start of line
  screen-should-contain [
    .          .
    .123       .
    .6         .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

after <handle-special-character> [
  {
    delete-to-start-of-line?:boolean <- equal c, 21/ctrl-u
    break-unless delete-to-start-of-line?
    <delete-to-start-of-line-begin>
    deleted-cells:address:duplex-list:character <- delete-to-start-of-line editor
    <delete-to-start-of-line-end>
    go-render? <- copy 1/true
    return
  }
]

def delete-to-start-of-line editor:address:editor-data -> result:address:duplex-list:character, editor:address:editor-data [
  local-scope
  load-ingredients
  # compute range to delete
  init:address:duplex-list:character <- get *editor, data:offset
  before-cursor:address:duplex-list:character <- get *editor, before-cursor:offset
  start:address:duplex-list:character <- copy before-cursor
  end:address:duplex-list:character <- next before-cursor
  {
    at-start-of-text?:boolean <- equal start, init
    break-if at-start-of-text?
    curr:character <- get *start, value:offset
    at-start-of-line?:boolean <- equal curr, 10/newline
    break-if at-start-of-line?
    start <- prev start
    assert start, [delete-to-start-of-line tried to move before start of text]
    loop
  }
  # snip it out
  result:address:duplex-list:character <- next start
  remove-between start, end
  # adjust cursor
  before-cursor <- copy start
  *editor <- put *editor, before-cursor:offset, before-cursor
  left:number <- get *editor, left:offset
  *editor <- put *editor, cursor-column:offset, left
]

scenario editor-deletes-to-start-of-line-with-ctrl-u-2 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  # start on first line (no newline before), press ctrl-u
  assume-console [
    left-click 1, 2
    press ctrl-u
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # cursor deletes to start of line
  screen-should-contain [
    .          .
    .3         .
    .456       .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

scenario editor-deletes-to-start-of-line-with-ctrl-u-3 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  # start past end of line, press ctrl-u
  assume-console [
    left-click 1, 3
    press ctrl-u
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # cursor deletes to start of line
  screen-should-contain [
    .          .
    .          .
    .456       .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

scenario editor-deletes-to-start-of-final-line-with-ctrl-u [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  # start past end of final line, press ctrl-u
  assume-console [
    left-click 2, 3
    press ctrl-u
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # cursor deletes to start of line
  screen-should-contain [
    .          .
    .123       .
    .          .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

# ctrl-k - delete text from cursor to end of line (but not the newline)

scenario editor-deletes-to-end-of-line-with-ctrl-k [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  # start on first line, press ctrl-k
  assume-console [
    left-click 1, 1
    press ctrl-k
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # cursor deletes to end of line
  screen-should-contain [
    .          .
    .1         .
    .456       .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

after <handle-special-character> [
  {
    delete-to-end-of-line?:boolean <- equal c, 11/ctrl-k
    break-unless delete-to-end-of-line?
    <delete-to-end-of-line-begin>
    deleted-cells:address:duplex-list:character <- delete-to-end-of-line editor
    <delete-to-end-of-line-end>
    go-render? <- copy 1/true
    return
  }
]

def delete-to-end-of-line editor:address:editor-data -> result:address:duplex-list:character, editor:address:editor-data [
  local-scope
  load-ingredients
  # compute range to delete
  start:address:duplex-list:character <- get *editor, before-cursor:offset
  end:address:duplex-list:character <- next start
  {
    at-end-of-text?:boolean <- equal end, 0/null
    break-if at-end-of-text?
    curr:character <- get *end, value:offset
    at-end-of-line?:boolean <- equal curr, 10/newline
    break-if at-end-of-line?
    end <- next end
    loop
  }
  # snip it out
  result <- next start
  remove-between start, end
]

scenario editor-deletes-to-end-of-line-with-ctrl-k-2 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  # start on second line (no newline after), press ctrl-k
  assume-console [
    left-click 2, 1
    press ctrl-k
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # cursor deletes to end of line
  screen-should-contain [
    .          .
    .123       .
    .4         .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

scenario editor-deletes-to-end-of-line-with-ctrl-k-3 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  # start at end of line
  assume-console [
    left-click 1, 2
    press ctrl-k
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # cursor deletes just last character
  screen-should-contain [
    .          .
    .12        .
    .456       .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

scenario editor-deletes-to-end-of-line-with-ctrl-k-4 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  # start past end of line
  assume-console [
    left-click 1, 3
    press ctrl-k
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # cursor deletes nothing
  screen-should-contain [
    .          .
    .123       .
    .456       .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

scenario editor-deletes-to-end-of-line-with-ctrl-k-5 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  # start at end of text
  assume-console [
    left-click 2, 2
    press ctrl-k
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # cursor deletes just the final character
  screen-should-contain [
    .          .
    .123       .
    .45        .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

scenario editor-deletes-to-end-of-line-with-ctrl-k-6 [
  assume-screen 10/width, 5/height
  1:address:array:character <- new [123
456]
  2:address:editor-data <- new-editor 1:address:array:character, screen:address:screen, 0/left, 10/right
  # start past end of text
  assume-console [
    left-click 2, 3
    press ctrl-k
  ]
  run [
    editor-event-loop screen:address:screen, console:address:console, 2:address:editor-data
  ]
  # cursor deletes nothing
  screen-should-contain [
    .          .
    .123       .
    .456       .
    .┈┈┈┈┈┈┈┈┈┈.
    .          .
  ]
]

# takes a pointer into the doubly-linked list, scans ahead at most 'max'
# positions until the next newline
# beware: never return null pointer.
def before-start-of-next-line original:address:duplex-list:character, max:number -> curr:address:duplex-list:character [
  local-scope
  load-ingredients
  count:number <- copy 0
  curr:address:duplex-list:character <- copy original
  # skip the initial newline if it exists
  {
    c:character <- get *curr, value:offset
    at-newline?:boolean <- equal c, 10/newline
    break-unless at-newline?
    curr <- next curr
    count <- add count, 1
  }
  {
    return-unless curr, original
    done?:boolean <- greater-or-equal count, max
    break-if done?
    c:character <- get *curr, value:offset
    at-newline?:boolean <- equal c, 10/newline
    break-if at-newline?
    curr <- next curr
    count <- add count, 1
    loop
  }
  return-unless curr, original
  return curr
]

# takes a pointer into the doubly-linked list, scans back to before start of
# previous *wrapped* line
# beware: never return null pointer
def before-previous-line in:address:duplex-list:character, editor:address:editor-data -> out:address:duplex-list:character [
  local-scope
  load-ingredients
  curr:address:duplex-list:character <- copy in
  c:character <- get *curr, value:offset
  # compute max, number of characters to skip
  #   1 + len%(width-1)
  #   except rotate second term to vary from 1 to width-1 rather than 0 to width-2
  left:number <- get *editor, left:offset
  right:number <- get *editor, right:offset
  max-line-length:number <- subtract right, left, -1/exclusive-right, 1/wrap-icon
  sentinel:address:duplex-list:character <- get *editor, data:offset
  len:number <- previous-line-length curr, sentinel
  {
    break-if len
    # empty line; just skip this newline
    prev:address:duplex-list:character <- prev curr
    return-unless prev, curr
    return prev
  }
  _, max:number <- divide-with-remainder len, max-line-length
  # remainder 0 => scan one width-worth
  {
    break-if max
    max <- copy max-line-length
  }
  max <- add max, 1
  count:number <- copy 0
  # skip 'max' characters
  {
    done?:boolean <- greater-or-equal count, max
    break-if done?
    prev:address:duplex-list:character <- prev curr
    break-unless prev
    curr <- copy prev
    count <- add count, 1
    loop
  }
  return curr
]
