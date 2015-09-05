## the basic editor data structure, and how it displays text to the screen

scenario editor-initially-prints-string-to-screen [
  assume-screen 10/width, 5/height
  run [
    1:address:array:character <- new [abc]
    new-editor 1:address:array:character, screen:address, 0/left, 10/right
  ]
  screen-should-contain [
    # top line of screen reserved for menu
    .          .
    .abc       .
    .          .
  ]
]

container editor-data [
  # editable text: doubly linked list of characters (head contains a special sentinel)
  data:address:duplex-list:character
  top-of-screen:address:duplex-list:character
  bottom-of-screen:address:duplex-list:character
  # location before cursor inside data
  before-cursor:address:duplex-list:character

  # raw bounds of display area on screen
  # always displays from row 1 (leaving row 0 for a menu) and at most until bottom of screen
  left:number
  right:number
  # raw screen coordinates of cursor
  cursor-row:number
  cursor-column:number
]

# editor:address, screen <- new-editor s:address:array:character, screen:address, left:number, right:number
# creates a new editor widget and renders its initial appearance to screen.
#   top/left/right constrain the screen area available to the new editor.
#   right is exclusive.
recipe new-editor [
  local-scope
  s:address:array:character <- next-ingredient
  screen:address <- next-ingredient
  # no clipping of bounds
  left:number <- next-ingredient
  right:number <- next-ingredient
  right <- subtract right, 1
  result:address:editor-data <- new editor-data:type
  # initialize screen-related fields
  x:address:number <- get-address *result, left:offset
  *x <- copy left
  x <- get-address *result, right:offset
  *x <- copy right
  # initialize cursor
  x <- get-address *result, cursor-row:offset
  *x <- copy 1/top
  x <- get-address *result, cursor-column:offset
  *x <- copy left
  init:address:address:duplex-list <- get-address *result, data:offset
  *init <- push-duplex 167/§, 0/tail
  top-of-screen:address:address:duplex-list <- get-address *result, top-of-screen:offset
  *top-of-screen <- copy *init
  y:address:address:duplex-list <- get-address *result, before-cursor:offset
  *y <- copy *init
  result <- insert-text result, s
  # initialize cursor to top of screen
  y <- get-address *result, before-cursor:offset
  *y <- copy *init
  # initial render to screen, just for some old tests
  _, _, screen, result <- render screen, result
  <editor-initialization>
  reply result
]

recipe insert-text [
  local-scope
  editor:address:editor-data <- next-ingredient
  text:address:array:character <- next-ingredient
  # early exit if text is empty
  reply-unless text, editor/same-as-ingredient:0
  len:number <- length *text
  reply-unless len, editor/same-as-ingredient:0
  idx:number <- copy 0
  # now we can start appending the rest, character by character
  curr:address:duplex-list <- get *editor, data:offset
  {
    done?:boolean <- greater-or-equal idx, len
    break-if done?
    c:character <- index *text, idx
    insert-duplex c, curr
    # next iter
    curr <- next-duplex curr
    idx <- add idx, 1
    loop
  }
  reply editor/same-as-ingredient:0
]

scenario editor-initializes-without-data [
  assume-screen 5/width, 3/height
  run [
    1:address:editor-data <- new-editor 0/data, screen:address, 2/left, 5/right
    2:editor-data <- copy *1:address:editor-data
  ]
  memory-should-contain [
    # 2 (data) <- just the § sentinel
    # 3 (top of screen) <- the § sentinel
    4 <- 0  # bottom-of-screen; null since text fits on screen
    # 5 (before cursor) <- the § sentinel
    6 <- 2  # left
    7 <- 4  # right  (inclusive)
    8 <- 1  # cursor row
    9 <- 2  # cursor column
  ]
  screen-should-contain [
    .     .
    .     .
    .     .
  ]
]

# last-row:number, last-column:number, screen, editor <- render screen:address, editor:address:editor-data
#
# Assumes cursor should be at coordinates (cursor-row, cursor-column) and
# updates before-cursor to match. Might also move coordinates if they're
# outside text.
recipe render [
  local-scope
  screen:address <- next-ingredient
  editor:address:editor-data <- next-ingredient
  reply-unless editor, 1/top, 0/left, screen/same-as-ingredient:0, editor/same-as-ingredient:1
  left:number <- get *editor, left:offset
  screen-height:number <- screen-height screen
  right:number <- get *editor, right:offset
  # traversing editor
  curr:address:duplex-list <- get *editor, top-of-screen:offset
  prev:address:duplex-list <- copy curr  # just in case curr becomes null and we can't compute prev-duplex
  curr <- next-duplex curr
  # traversing screen
  +render-loop-initialization
  color:number <- copy 7/white
  row:number <- copy 1/top
  column:number <- copy left
  cursor-row:address:number <- get-address *editor, cursor-row:offset
  cursor-column:address:number <- get-address *editor, cursor-column:offset
  before-cursor:address:address:duplex-list <- get-address *editor, before-cursor:offset
  screen <- move-cursor screen, row, column
  {
    +next-character
    break-unless curr
    off-screen?:boolean <- greater-or-equal row, screen-height
    break-if off-screen?
    # update editor-data.before-cursor
    # Doing so at the start of each iteration ensures it stays one step behind
    # the current character.
    {
      at-cursor-row?:boolean <- equal row, *cursor-row
      break-unless at-cursor-row?
      at-cursor?:boolean <- equal column, *cursor-column
      break-unless at-cursor?
      *before-cursor <- copy prev
    }
    c:character <- get *curr, value:offset
    <character-c-received>
    {
      # newline? move to left rather than 0
      newline?:boolean <- equal c, 10/newline
      break-unless newline?
      # adjust cursor if necessary
      {
        at-cursor-row?:boolean <- equal row, *cursor-row
        break-unless at-cursor-row?
        left-of-cursor?:boolean <- lesser-than column, *cursor-column
        break-unless left-of-cursor?
        *cursor-column <- copy column
        *before-cursor <- prev-duplex curr
      }
      # clear rest of line in this window
      clear-line-delimited screen, column, right
      # skip to next line
      row <- add row, 1
      column <- copy left
      screen <- move-cursor screen, row, column
      curr <- next-duplex curr
      prev <- next-duplex prev
      loop +next-character:label
    }
    {
      # at right? wrap. even if there's only one more letter left; we need
      # room for clicking on the cursor after it.
      at-right?:boolean <- equal column, right
      break-unless at-right?
      # print wrap icon
      print-character screen, 8617/loop-back-to-left, 245/grey
      column <- copy left
      row <- add row, 1
      screen <- move-cursor screen, row, column
      # don't increment curr
      loop +next-character:label
    }
    print-character screen, c, color
    curr <- next-duplex curr
    prev <- next-duplex prev
    column <- add column, 1
    loop
  }
  # save first character off-screen
  bottom-of-screen:address:address:duplex-list <- get-address *editor, bottom-of-screen:offset
  *bottom-of-screen <- copy curr
  # is cursor to the right of the last line? move to end
  {
    at-cursor-row?:boolean <- equal row, *cursor-row
    cursor-outside-line?:boolean <- lesser-or-equal column, *cursor-column
    before-cursor-on-same-line?:boolean <- and at-cursor-row?, cursor-outside-line?
    above-cursor-row?:boolean <- lesser-than row, *cursor-row
    before-cursor?:boolean <- or before-cursor-on-same-line?, above-cursor-row?
    break-unless before-cursor?
    *cursor-row <- copy row
    *cursor-column <- copy column
    *before-cursor <- copy prev
  }
  reply row, column, screen/same-as-ingredient:0, editor/same-as-ingredient:1
]

recipe clear-line-delimited [
  local-scope
  screen:address <- next-ingredient
  column:number <- next-ingredient
  right:number <- next-ingredient
  {
    done?:boolean <- greater-than column, right
    break-if done?
    print-character screen, 32/space
    column <- add column, 1
    loop
  }
]

recipe clear-screen-from [
  local-scope
  screen:address <- next-ingredient
  row:number <- next-ingredient
  column:number <- next-ingredient
  left:number <- next-ingredient
  right:number <- next-ingredient
  # if it's the real screen, use the optimized primitive
  {
    break-if screen
    clear-display-from row, column, left, right
    reply screen/same-as-ingredient:0
  }
  # if not, go the slower route
  screen <- move-cursor screen, row, column
  clear-line-delimited screen, column, right
  clear-rest-of-screen screen, row, left, right
  reply screen/same-as-ingredient:0
]

recipe clear-rest-of-screen [
  local-scope
  screen:address <- next-ingredient
  row:number <- next-ingredient
  left:number <- next-ingredient
  right:number <- next-ingredient
  row <- add row, 1
  screen <- move-cursor screen, row, left
  screen-height:number <- screen-height screen
  {
    at-bottom-of-screen?:boolean <- greater-or-equal row, screen-height
    break-if at-bottom-of-screen?
    screen <- move-cursor screen, row, left
    clear-line-delimited screen, left, right
    row <- add row, 1
    loop
  }
]

scenario editor-initially-prints-multiple-lines [
  assume-screen 5/width, 5/height
  run [
    s:address:array:character <- new [abc
def]
    new-editor s:address:array:character, screen:address, 0/left, 5/right
  ]
  screen-should-contain [
    .     .
    .abc  .
    .def  .
    .     .
  ]
]

scenario editor-initially-handles-offsets [
  assume-screen 5/width, 5/height
  run [
    s:address:array:character <- new [abc]
    new-editor s:address:array:character, screen:address, 1/left, 5/right
  ]
  screen-should-contain [
    .     .
    . abc .
    .     .
  ]
]

scenario editor-initially-prints-multiple-lines-at-offset [
  assume-screen 5/width, 5/height
  run [
    s:address:array:character <- new [abc
def]
    new-editor s:address:array:character, screen:address, 1/left, 5/right
  ]
  screen-should-contain [
    .     .
    . abc .
    . def .
    .     .
  ]
]

scenario editor-initially-wraps-long-lines [
  assume-screen 5/width, 5/height
  run [
    s:address:array:character <- new [abc def]
    new-editor s:address:array:character, screen:address, 0/left, 5/right
  ]
  screen-should-contain [
    .     .
    .abc ↩.
    .def  .
    .     .
  ]
  screen-should-contain-in-color 245/grey [
    .     .
    .    ↩.
    .     .
    .     .
  ]
]

scenario editor-initially-wraps-barely-long-lines [
  assume-screen 5/width, 5/height
  run [
    s:address:array:character <- new [abcde]
    new-editor s:address:array:character, screen:address, 0/left, 5/right
  ]
  # still wrap, even though the line would fit. We need room to click on the
  # end of the line
  screen-should-contain [
    .     .
    .abcd↩.
    .e    .
    .     .
  ]
  screen-should-contain-in-color 245/grey [
    .     .
    .    ↩.
    .     .
    .     .
  ]
]

scenario editor-initializes-empty-text [
  assume-screen 5/width, 5/height
  run [
    1:address:array:character <- new []
    2:address:editor-data <- new-editor 1:address:array:character, screen:address, 0/left, 5/right
    3:number <- get *2:address:editor-data, cursor-row:offset
    4:number <- get *2:address:editor-data, cursor-column:offset
  ]
  screen-should-contain [
    .     .
    .     .
    .     .
  ]
  memory-should-contain [
    3 <- 1  # cursor row
    4 <- 0  # cursor column
  ]
]

# just a little color for mu code

scenario render-colors-comments [
  assume-screen 5/width, 5/height
  run [
    s:address:array:character <- new [abc
# de
f]
    new-editor s:address:array:character, screen:address, 0/left, 5/right
  ]
  screen-should-contain [
    .     .
    .abc  .
    .# de .
    .f    .
    .     .
  ]
  screen-should-contain-in-color 12/lightblue, [
    .     .
    .     .
    .# de .
    .     .
    .     .
  ]
  screen-should-contain-in-color 7/white, [
    .     .
    .abc  .
    .     .
    .f    .
    .     .
  ]
]

after <character-c-received> [
  color <- get-color color, c
]

# color <- get-color color:number, c:character
# so far the previous color is all the information we need; that may change
recipe get-color [
  local-scope
  color:number <- next-ingredient
  c:character <- next-ingredient
  color-is-white?:boolean <- equal color, 7/white
  # if color is white and next character is '#', switch color to blue
  {
    break-unless color-is-white?
    starting-comment?:boolean <- equal c, 35/#
    break-unless starting-comment?
    trace 90, [app], [switch color back to blue]
    color <- copy 12/lightblue
    jump +exit:label
  }
  # if color is blue and next character is newline, switch color to white
  {
    color-is-blue?:boolean <- equal color, 12/lightblue
    break-unless color-is-blue?
    ending-comment?:boolean <- equal c, 10/newline
    break-unless ending-comment?
    trace 90, [app], [switch color back to white]
    color <- copy 7/white
    jump +exit:label
  }
  # if color is white (no comments) and next character is '<', switch color to red
  {
    break-unless color-is-white?
    starting-assignment?:boolean <- equal c, 60/<
    break-unless starting-assignment?
    color <- copy 1/red
    jump +exit:label
  }
  # if color is red and next character is space, switch color to white
  {
    color-is-red?:boolean <- equal color, 1/red
    break-unless color-is-red?
    ending-assignment?:boolean <- equal c, 32/space
    break-unless ending-assignment?
    color <- copy 7/white
    jump +exit:label
  }
  # otherwise no change
  +exit
  reply color
]

scenario render-colors-assignment [
  assume-screen 8/width, 5/height
  run [
    s:address:array:character <- new [abc
d <- e
f]
    new-editor s:address:array:character, screen:address, 0/left, 8/right
  ]
  screen-should-contain [
    .        .
    .abc     .
    .d <- e  .
    .f       .
    .        .
  ]
  screen-should-contain-in-color 1/red, [
    .        .
    .        .
    .  <-    .
    .        .
    .        .
  ]
]