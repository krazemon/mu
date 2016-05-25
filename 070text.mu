# Some useful helpers for dealing with text (arrays of characters)

# to-text-line gets called implicitly in various places
# define it to be identical to 'to-text' by default
def to-text-line x:_elem -> y:address:array:character [
  local-scope
  load-ingredients
  y <- to-text x
]

# variant for arrays (since we can't pass them around otherwise)
def array-to-text-line x:address:array:_elem -> y:address:array:character [
  local-scope
  load-ingredients
  y <- to-text *x
]

def equal a:address:array:character, b:address:array:character -> result:boolean [
  local-scope
  load-ingredients
  a-len:number <- length *a
  b-len:number <- length *b
  # compare lengths
  {
    trace 99, [text-equal], [comparing lengths]
    length-equal?:boolean <- equal a-len, b-len
    break-if length-equal?
    return 0
  }
  # compare each corresponding character
  trace 99, [text-equal], [comparing characters]
  i:number <- copy 0
  {
    done?:boolean <- greater-or-equal i, a-len
    break-if done?
    a2:character <- index *a, i
    b2:character <- index *b, i
    {
      chars-match?:boolean <- equal a2, b2
      break-if chars-match?
      return 0
    }
    i <- add i, 1
    loop
  }
  return 1
]

scenario text-equal-reflexive [
  run [
    default-space:address:array:location <- new location:type, 30
    x:address:array:character <- new [abc]
    3:boolean/raw <- equal x, x
  ]
  memory-should-contain [
    3 <- 1  # x == x for all x
  ]
]

scenario text-equal-identical [
  run [
    default-space:address:array:location <- new location:type, 30
    x:address:array:character <- new [abc]
    y:address:array:character <- new [abc]
    3:boolean/raw <- equal x, y
  ]
  memory-should-contain [
    3 <- 1  # abc == abc
  ]
]

scenario text-equal-distinct-lengths [
  run [
    default-space:address:array:location <- new location:type, 30
    x:address:array:character <- new [abc]
    y:address:array:character <- new [abcd]
    3:boolean/raw <- equal x, y
  ]
  memory-should-contain [
    3 <- 0  # abc != abcd
  ]
  trace-should-contain [
    text-equal: comparing lengths
  ]
  trace-should-not-contain [
    text-equal: comparing characters
  ]
]

scenario text-equal-with-empty [
  run [
    default-space:address:array:location <- new location:type, 30
    x:address:array:character <- new []
    y:address:array:character <- new [abcd]
    3:boolean/raw <- equal x, y
  ]
  memory-should-contain [
    3 <- 0  # "" != abcd
  ]
]

scenario text-equal-common-lengths-but-distinct [
  run [
    default-space:address:array:location <- new location:type, 30
    x:address:array:character <- new [abc]
    y:address:array:character <- new [abd]
    3:boolean/raw <- equal x, y
  ]
  memory-should-contain [
    3 <- 0  # abc != abd
  ]
]

# A new type to help incrementally construct texts.
container buffer [
  length:number
  data:address:array:character
]

def new-buffer capacity:number -> result:address:buffer [
  local-scope
  load-ingredients
  result <- new buffer:type
  *result <- put *result, length:offset, 0
  data:address:array:character <- new character:type, capacity
  *result <- put *result, data:offset, data
  return result
]

def grow-buffer in:address:buffer -> in:address:buffer [
  local-scope
  load-ingredients
  # double buffer size
  olddata:address:array:character <- get *in, data:offset
  oldlen:number <- length *olddata
  newlen:number <- multiply oldlen, 2
  newdata:address:array:character <- new character:type, newlen
  *in <- put *in, data:offset, newdata
  # copy old contents
  i:number <- copy 0
  {
    done?:boolean <- greater-or-equal i, oldlen
    break-if done?
    src:character <- index *olddata, i
    *newdata <- put-index *newdata, i, src
    i <- add i, 1
    loop
  }
]

def buffer-full? in:address:buffer -> result:boolean [
  local-scope
  load-ingredients
  len:number <- get *in, length:offset
  s:address:array:character <- get *in, data:offset
  capacity:number <- length *s
  result <- greater-or-equal len, capacity
]

# most broadly applicable definition of append to a buffer: just call to-text
def append buf:address:buffer, x:_elem -> buf:address:buffer [
  local-scope
  load-ingredients
  text:address:array:character <- to-text x
  len:number <- length *text
  i:number <- copy 0
  {
    done?:boolean <- greater-or-equal i, len
    break-if done?
    c:character <- index *text, i
    buf <- append buf, c
    i <- add i, 1
    loop
  }
]

def append in:address:buffer, c:character -> in:address:buffer [
  local-scope
  load-ingredients
  len:number <- get *in, length:offset
  {
    # backspace? just drop last character if it exists and return
    backspace?:boolean <- equal c, 8/backspace
    break-unless backspace?
    empty?:boolean <- lesser-or-equal len, 0
    return-if empty?
    len <- subtract len, 1
    *in <- put *in, length:offset, len
    return
  }
  {
    # grow buffer if necessary
    full?:boolean <- buffer-full? in
    break-unless full?
    in <- grow-buffer in
  }
  s:address:array:character <- get *in, data:offset
  *s <- put-index *s, len, c
  len <- add len, 1
  *in <- put *in, length:offset, len
]

scenario buffer-append-works [
  run [
    local-scope
    x:address:buffer <- new-buffer 3
    s1:address:array:character <- get *x, data:offset
    c:character <- copy 97/a
    x <- append x, c
    c:character <- copy 98/b
    x <- append x, c
    c:character <- copy 99/c
    x <- append x, c
    s2:address:array:character <- get *x, data:offset
    1:boolean/raw <- equal s1, s2
    2:array:character/raw <- copy *s2
    +buffer-filled
    c:character <- copy 100/d
    x <- append x, c
    s3:address:array:character <- get *x, data:offset
    10:boolean/raw <- equal s1, s3
    11:number/raw <- get *x, length:offset
    12:array:character/raw <- copy *s3
  ]
  memory-should-contain [
    # before +buffer-filled
    1 <- 1   # no change in data pointer
    2 <- 3   # size of data
    3 <- 97  # data
    4 <- 98
    5 <- 99
    # in the end
    10 <- 0   # data pointer has grown
    11 <- 4   # final length
    12 <- 6   # but data's capacity has doubled
    13 <- 97  # data
    14 <- 98
    15 <- 99
    16 <- 100
    17 <- 0
    18 <- 0
  ]
]

scenario buffer-append-handles-backspace [
  run [
    local-scope
    x:address:buffer <- new-buffer 3
    c:character <- copy 97/a
    x <- append x, c
    c:character <- copy 98/b
    x <- append x, c
    c:character <- copy 8/backspace
    x <- append x, c
    s:address:array:character <- buffer-to-array x
    1:array:character/raw <- copy *s
  ]
  memory-should-contain [
    1 <- 1   # length
    2 <- 97  # contents
    3 <- 0
  ]
]

def buffer-to-array in:address:buffer -> result:address:array:character [
  local-scope
  load-ingredients
  {
    # propagate null buffer
    break-if in
    return 0
  }
  len:number <- get *in, length:offset
  s:address:array:character <- get *in, data:offset
  # we can't just return s because it is usually the wrong length
  result <- new character:type, len
  i:number <- copy 0
  {
    done?:boolean <- greater-or-equal i, len
    break-if done?
    src:character <- index *s, i
    *result <- put-index *result, i, src
    i <- add i, 1
    loop
  }
]

def append a:address:array:character, b:address:array:character -> result:address:array:character [
  local-scope
  load-ingredients
  # handle null addresses
  reply-unless a, b
  reply-unless b, a
  # result = new character[a.length + b.length]
  a-len:number <- length *a
  b-len:number <- length *b
  result-len:number <- add a-len, b-len
  result <- new character:type, result-len
  # copy a into result
  result-idx:number <- copy 0
  i:number <- copy 0
  {
    # while i < a.length
    a-done?:boolean <- greater-or-equal i, a-len
    break-if a-done?
    # result[result-idx] = a[i]
    in:character <- index *a, i
    *result <- put-index *result, result-idx, in
    i <- add i, 1
    result-idx <- add result-idx, 1
    loop
  }
  # copy b into result
  i <- copy 0
  {
    # while i < b.length
    b-done?:boolean <- greater-or-equal i, b-len
    break-if b-done?
    # result[result-idx] = a[i]
    in:character <- index *b, i
    *result <- put-index *result, result-idx, in
    i <- add i, 1
    result-idx <- add result-idx, 1
    loop
  }
]

scenario text-append-1 [
  run [
    1:address:array:character/raw <- new [hello,]
    2:address:array:character/raw <- new [ world!]
    3:address:array:character/raw <- append 1:address:array:character/raw, 2:address:array:character/raw
    4:array:character/raw <- copy *3:address:array:character/raw
  ]
  memory-should-contain [
    4:array:character <- [hello, world!]
  ]
]

scenario text-append-null [
  run [
    1:address:array:character/raw <- copy 0
    2:address:array:character/raw <- new [ world!]
    3:address:array:character/raw <- append 1:address:array:character/raw, 2:address:array:character/raw
    4:array:character/raw <- copy *3:address:array:character/raw
  ]
  memory-should-contain [
    4:array:character <- [ world!]
  ]
]

scenario text-append-null-2 [
  run [
    1:address:array:character/raw <- new [hello,]
    2:address:array:character/raw <- copy 0
    3:address:array:character/raw <- append 1:address:array:character/raw, 2:address:array:character/raw
    4:array:character/raw <- copy *3:address:array:character/raw
  ]
  memory-should-contain [
    4:array:character <- [hello,]
  ]
]

scenario replace-character-in-text [
  run [
    1:address:array:character/raw <- new [abc]
    1:address:array:character/raw <- replace 1:address:array:character/raw, 98/b, 122/z
    2:array:character/raw <- copy *1:address:array:character/raw
  ]
  memory-should-contain [
    2:array:character <- [azc]
  ]
]

def replace s:address:array:character, oldc:character, newc:character, from:number/optional -> s:address:array:character [
  local-scope
  load-ingredients
  len:number <- length *s
  i:number <- find-next s, oldc, from
  done?:boolean <- greater-or-equal i, len
  return-if done?, s/same-as-ingredient:0
  *s <- put-index *s, i, newc
  i <- add i, 1
  s <- replace s, oldc, newc, i
]

scenario replace-character-at-start [
  run [
    1:address:array:character/raw <- new [abc]
    1:address:array:character/raw <- replace 1:address:array:character/raw, 97/a, 122/z
    2:array:character/raw <- copy *1:address:array:character/raw
  ]
  memory-should-contain [
    2:array:character <- [zbc]
  ]
]

scenario replace-character-at-end [
  run [
    1:address:array:character/raw <- new [abc]
    1:address:array:character/raw <- replace 1:address:array:character/raw, 99/c, 122/z
    2:array:character/raw <- copy *1:address:array:character/raw
  ]
  memory-should-contain [
    2:array:character <- [abz]
  ]
]

scenario replace-character-missing [
  run [
    1:address:array:character/raw <- new [abc]
    1:address:array:character/raw <- replace 1:address:array:character/raw, 100/d, 122/z
    2:array:character/raw <- copy *1:address:array:character/raw
  ]
  memory-should-contain [
    2:array:character <- [abc]
  ]
]

scenario replace-all-characters [
  run [
    1:address:array:character/raw <- new [banana]
    1:address:array:character/raw <- replace 1:address:array:character/raw, 97/a, 122/z
    2:array:character/raw <- copy *1:address:array:character/raw
  ]
  memory-should-contain [
    2:array:character <- [bznznz]
  ]
]

# replace underscores in first with remaining args
def interpolate template:address:array:character -> result:address:array:character [
  local-scope
  load-ingredients  # consume just the template
  # compute result-len, space to allocate for result
  tem-len:number <- length *template
  result-len:number <- copy tem-len
  {
    # while ingredients remain
    a:address:array:character, arg-received?:boolean <- next-ingredient
    break-unless arg-received?
    # result-len = result-len + arg.length - 1 (for the 'underscore' being replaced)
    a-len:number <- length *a
    result-len <- add result-len, a-len
    result-len <- subtract result-len, 1
    loop
  }
  rewind-ingredients
  _ <- next-ingredient  # skip template
  result <- new character:type, result-len
  # repeatedly copy sections of template and 'holes' into result
  result-idx:number <- copy 0
  i:number <- copy 0
  {
    # while arg received
    a:address:array:character, arg-received?:boolean <- next-ingredient
    break-unless arg-received?
    # copy template into result until '_'
    {
      # while i < template.length
      tem-done?:boolean <- greater-or-equal i, tem-len
      break-if tem-done?, +done:label
      # while template[i] != '_'
      in:character <- index *template, i
      underscore?:boolean <- equal in, 95/_
      break-if underscore?
      # result[result-idx] = template[i]
      *result <- put-index *result, result-idx, in
      i <- add i, 1
      result-idx <- add result-idx, 1
      loop
    }
    # copy 'a' into result
    j:number <- copy 0
    {
      # while j < a.length
      arg-done?:boolean <- greater-or-equal j, a-len
      break-if arg-done?
      # result[result-idx] = a[j]
      in:character <- index *a, j
      *result <- put-index *result, result-idx, in
      j <- add j, 1
      result-idx <- add result-idx, 1
      loop
    }
    # skip '_' in template
    i <- add i, 1
    loop  # interpolate next arg
  }
  +done
  # done with holes; copy rest of template directly into result
  {
    # while i < template.length
    tem-done?:boolean <- greater-or-equal i, tem-len
    break-if tem-done?
    # result[result-idx] = template[i]
    in:character <- index *template, i
    *result <- put-index *result, result-idx, in
    i <- add i, 1
    result-idx <- add result-idx, 1
    loop
  }
]

scenario interpolate-works [
  run [
    1:address:array:character/raw <- new [abc _]
    2:address:array:character/raw <- new [def]
    3:address:array:character/raw <- interpolate 1:address:array:character/raw, 2:address:array:character/raw
    4:array:character/raw <- copy *3:address:array:character/raw
  ]
  memory-should-contain [
    4:array:character <- [abc def]
  ]
]

scenario interpolate-at-start [
  run [
    1:address:array:character/raw <- new [_, hello!]
    2:address:array:character/raw <- new [abc]
    3:address:array:character/raw <- interpolate 1:address:array:character/raw, 2:address:array:character/raw
    4:array:character/raw <- copy *3:address:array:character/raw
  ]
  memory-should-contain [
    4:array:character <- [abc, hello!]
    16 <- 0  # out of bounds
  ]
]

scenario interpolate-at-end [
  run [
    1:address:array:character/raw <- new [hello, _]
    2:address:array:character/raw <- new [abc]
    3:address:array:character/raw <- interpolate 1:address:array:character/raw, 2:address:array:character/raw
    4:array:character/raw <- copy *3:address:array:character/raw
  ]
  memory-should-contain [
    4:array:character <- [hello, abc]
  ]
]

# result:boolean <- space? c:character
def space? c:character -> result:boolean [
  local-scope
  load-ingredients
  # most common case first
  result <- equal c, 32/space
  return-if result
  result <- equal c, 10/newline
  return-if result
  result <- equal c, 9/tab
  return-if result
  result <- equal c, 13/carriage-return
  return-if result
  # remaining uncommon cases in sorted order
  # http://unicode.org code-points in unicode-set Z and Pattern_White_Space
  result <- equal c, 11/ctrl-k
  return-if result
  result <- equal c, 12/ctrl-l
  return-if result
  result <- equal c, 133/ctrl-0085
  return-if result
  result <- equal c, 160/no-break-space
  return-if result
  result <- equal c, 5760/ogham-space-mark
  return-if result
  result <- equal c, 8192/en-quad
  return-if result
  result <- equal c, 8193/em-quad
  return-if result
  result <- equal c, 8194/en-space
  return-if result
  result <- equal c, 8195/em-space
  return-if result
  result <- equal c, 8196/three-per-em-space
  return-if result
  result <- equal c, 8197/four-per-em-space
  return-if result
  result <- equal c, 8198/six-per-em-space
  return-if result
  result <- equal c, 8199/figure-space
  return-if result
  result <- equal c, 8200/punctuation-space
  return-if result
  result <- equal c, 8201/thin-space
  return-if result
  result <- equal c, 8202/hair-space
  return-if result
  result <- equal c, 8206/left-to-right
  return-if result
  result <- equal c, 8207/right-to-left
  return-if result
  result <- equal c, 8232/line-separator
  return-if result
  result <- equal c, 8233/paragraph-separator
  return-if result
  result <- equal c, 8239/narrow-no-break-space
  return-if result
  result <- equal c, 8287/medium-mathematical-space
  return-if result
  result <- equal c, 12288/ideographic-space
]

def trim s:address:array:character -> result:address:array:character [
  local-scope
  load-ingredients
  len:number <- length *s
  # left trim: compute start
  start:number <- copy 0
  {
    {
      at-end?:boolean <- greater-or-equal start, len
      break-unless at-end?
      result <- new character:type, 0
      return
    }
    curr:character <- index *s, start
    whitespace?:boolean <- space? curr
    break-unless whitespace?
    start <- add start, 1
    loop
  }
  # right trim: compute end
  end:number <- subtract len, 1
  {
    not-at-start?:boolean <- greater-than end, start
    assert not-at-start?, [end ran up against start]
    curr:character <- index *s, end
    whitespace?:boolean <- space? curr
    break-unless whitespace?
    end <- subtract end, 1
    loop
  }
  # result = new character[end+1 - start]
  new-len:number <- subtract end, start, -1
  result:address:array:character <- new character:type, new-len
  # copy the untrimmed parts between start and end
  i:number <- copy start
  j:number <- copy 0
  {
    # while i <= end
    done?:boolean <- greater-than i, end
    break-if done?
    # result[j] = s[i]
    src:character <- index *s, i
    *result <- put-index *result, j, src
    i <- add i, 1
    j <- add j, 1
    loop
  }
]

scenario trim-unmodified [
  run [
    1:address:array:character <- new [abc]
    2:address:array:character <- trim 1:address:array:character
    3:array:character <- copy *2:address:array:character
  ]
  memory-should-contain [
    3:array:character <- [abc]
  ]
]

scenario trim-left [
  run [
    1:address:array:character <- new [  abc]
    2:address:array:character <- trim 1:address:array:character
    3:array:character <- copy *2:address:array:character
  ]
  memory-should-contain [
    3:array:character <- [abc]
  ]
]

scenario trim-right [
  run [
    1:address:array:character <- new [abc  ]
    2:address:array:character <- trim 1:address:array:character
    3:array:character <- copy *2:address:array:character
  ]
  memory-should-contain [
    3:array:character <- [abc]
  ]
]

scenario trim-left-right [
  run [
    1:address:array:character <- new [  abc   ]
    2:address:array:character <- trim 1:address:array:character
    3:array:character <- copy *2:address:array:character
  ]
  memory-should-contain [
    3:array:character <- [abc]
  ]
]

scenario trim-newline-tab [
  run [
    1:address:array:character <- new [	abc
]
    2:address:array:character <- trim 1:address:array:character
    3:array:character <- copy *2:address:array:character
  ]
  memory-should-contain [
    3:array:character <- [abc]
  ]
]

def find-next text:address:array:character, pattern:character, idx:number -> next-index:number [
  local-scope
  load-ingredients
  len:number <- length *text
  {
    eof?:boolean <- greater-or-equal idx, len
    break-if eof?
    curr:character <- index *text, idx
    found?:boolean <- equal curr, pattern
    break-if found?
    idx <- add idx, 1
    loop
  }
  return idx
]

scenario text-find-next [
  run [
    1:address:array:character <- new [a/b]
    2:number <- find-next 1:address:array:character, 47/slash, 0/start-index
  ]
  memory-should-contain [
    2 <- 1
  ]
]

scenario text-find-next-empty [
  run [
    1:address:array:character <- new []
    2:number <- find-next 1:address:array:character, 47/slash, 0/start-index
  ]
  memory-should-contain [
    2 <- 0
  ]
]

scenario text-find-next-initial [
  run [
    1:address:array:character <- new [/abc]
    2:number <- find-next 1:address:array:character, 47/slash, 0/start-index
  ]
  memory-should-contain [
    2 <- 0  # prefix match
  ]
]

scenario text-find-next-final [
  run [
    1:address:array:character <- new [abc/]
    2:number <- find-next 1:address:array:character, 47/slash, 0/start-index
  ]
  memory-should-contain [
    2 <- 3  # suffix match
  ]
]

scenario text-find-next-missing [
  run [
    1:address:array:character <- new [abc]
    2:number <- find-next 1:address:array:character, 47/slash, 0/start-index
  ]
  memory-should-contain [
    2 <- 3  # no match
  ]
]

scenario text-find-next-invalid-index [
  run [
    1:address:array:character <- new [abc]
    2:number <- find-next 1:address:array:character, 47/slash, 4/start-index
  ]
  memory-should-contain [
    2 <- 4  # no change
  ]
]

scenario text-find-next-first [
  run [
    1:address:array:character <- new [ab/c/]
    2:number <- find-next 1:address:array:character, 47/slash, 0/start-index
  ]
  memory-should-contain [
    2 <- 2  # first '/' of multiple
  ]
]

scenario text-find-next-second [
  run [
    1:address:array:character <- new [ab/c/]
    2:number <- find-next 1:address:array:character, 47/slash, 3/start-index
  ]
  memory-should-contain [
    2 <- 4  # second '/' of multiple
  ]
]

# search for a pattern of multiple characters
# fairly dumb algorithm
def find-next text:address:array:character, pattern:address:array:character, idx:number -> next-index:number [
  local-scope
  load-ingredients
  first:character <- index *pattern, 0
  # repeatedly check for match at current idx
  len:number <- length *text
  {
    # does some unnecessary work checking even when there isn't enough of text left
    done?:boolean <- greater-or-equal idx, len
    break-if done?
    found?:boolean <- match-at text, pattern, idx
    break-if found?
    idx <- add idx, 1
    # optimization: skip past indices that definitely won't match
    idx <- find-next text, first, idx
    loop
  }
  return idx
]

scenario find-next-text-1 [
  run [
    1:address:array:character <- new [abc]
    2:address:array:character <- new [bc]
    3:number <- find-next 1:address:array:character, 2:address:array:character, 0
  ]
  memory-should-contain [
    3 <- 1
  ]
]

scenario find-next-text-2 [
  run [
    1:address:array:character <- new [abcd]
    2:address:array:character <- new [bc]
    3:number <- find-next 1:address:array:character, 2:address:array:character, 1
  ]
  memory-should-contain [
    3 <- 1
  ]
]

scenario find-next-no-match [
  run [
    1:address:array:character <- new [abc]
    2:address:array:character <- new [bd]
    3:number <- find-next 1:address:array:character, 2:address:array:character, 0
  ]
  memory-should-contain [
    3 <- 3  # not found
  ]
]

scenario find-next-suffix-match [
  run [
    1:address:array:character <- new [abcd]
    2:address:array:character <- new [cd]
    3:number <- find-next 1:address:array:character, 2:address:array:character, 0
  ]
  memory-should-contain [
    3 <- 2
  ]
]

scenario find-next-suffix-match-2 [
  run [
    1:address:array:character <- new [abcd]
    2:address:array:character <- new [cde]
    3:number <- find-next 1:address:array:character, 2:address:array:character, 0
  ]
  memory-should-contain [
    3 <- 4  # not found
  ]
]

# checks if pattern matches at index 'idx'
def match-at text:address:array:character, pattern:address:array:character, idx:number -> result:boolean [
  local-scope
  load-ingredients
  pattern-len:number <- length *pattern
  # check that there's space left for the pattern
  {
    x:number <- length *text
    x <- subtract x, pattern-len
    enough-room?:boolean <- lesser-or-equal idx, x
    break-if enough-room?
    return 0/not-found
  }
  # check each character of pattern
  pattern-idx:number <- copy 0
  {
    done?:boolean <- greater-or-equal pattern-idx, pattern-len
    break-if done?
    c:character <- index *text, idx
    exp:character <- index *pattern, pattern-idx
    {
      match?:boolean <- equal c, exp
      break-if match?
      return 0/not-found
    }
    idx <- add idx, 1
    pattern-idx <- add pattern-idx, 1
    loop
  }
  return 1/found
]

scenario match-at-checks-pattern-at-index [
  run [
    1:address:array:character <- new [abc]
    2:address:array:character <- new [ab]
    3:boolean <- match-at 1:address:array:character, 2:address:array:character, 0
  ]
  memory-should-contain [
    3 <- 1  # match found
  ]
]

scenario match-at-reflexive [
  run [
    1:address:array:character <- new [abc]
    3:boolean <- match-at 1:address:array:character, 1:address:array:character, 0
  ]
  memory-should-contain [
    3 <- 1  # match found
  ]
]

scenario match-at-outside-bounds [
  run [
    1:address:array:character <- new [abc]
    2:address:array:character <- new [a]
    3:boolean <- match-at 1:address:array:character, 2:address:array:character, 4
  ]
  memory-should-contain [
    3 <- 0  # never matches
  ]
]

scenario match-at-empty-pattern [
  run [
    1:address:array:character <- new [abc]
    2:address:array:character <- new []
    3:boolean <- match-at 1:address:array:character, 2:address:array:character, 0
  ]
  memory-should-contain [
    3 <- 1  # always matches empty pattern given a valid index
  ]
]

scenario match-at-empty-pattern-outside-bound [
  run [
    1:address:array:character <- new [abc]
    2:address:array:character <- new []
    3:boolean <- match-at 1:address:array:character, 2:address:array:character, 4
  ]
  memory-should-contain [
    3 <- 0  # no match
  ]
]

scenario match-at-empty-text [
  run [
    1:address:array:character <- new []
    2:address:array:character <- new [abc]
    3:boolean <- match-at 1:address:array:character, 2:address:array:character, 0
  ]
  memory-should-contain [
    3 <- 0  # no match
  ]
]

scenario match-at-empty-against-empty [
  run [
    1:address:array:character <- new []
    3:boolean <- match-at 1:address:array:character, 1:address:array:character, 0
  ]
  memory-should-contain [
    3 <- 1  # matches because pattern is also empty
  ]
]

scenario match-at-inside-bounds [
  run [
    1:address:array:character <- new [abc]
    2:address:array:character <- new [bc]
    3:boolean <- match-at 1:address:array:character, 2:address:array:character, 1
  ]
  memory-should-contain [
    3 <- 1  # match
  ]
]

scenario match-at-inside-bounds-2 [
  run [
    1:address:array:character <- new [abc]
    2:address:array:character <- new [bc]
    3:boolean <- match-at 1:address:array:character, 2:address:array:character, 0
  ]
  memory-should-contain [
    3 <- 0  # no match
  ]
]

def split s:address:array:character, delim:character -> result:address:array:address:array:character [
  local-scope
  load-ingredients
  # empty text? return empty array
  len:number <- length *s
  {
    empty?:boolean <- equal len, 0
    break-unless empty?
    result <- new {(address array character): type}, 0
    return
  }
  # count #pieces we need room for
  count:number <- copy 1  # n delimiters = n+1 pieces
  idx:number <- copy 0
  {
    idx <- find-next s, delim, idx
    done?:boolean <- greater-or-equal idx, len
    break-if done?
    idx <- add idx, 1
    count <- add count, 1
    loop
  }
  # allocate space
  result <- new {(address array character): type}, count
  # repeatedly copy slices start..end until delimiter into result[curr-result]
  curr-result:number <- copy 0
  start:number <- copy 0
  {
    # while next delim exists
    done?:boolean <- greater-or-equal start, len
    break-if done?
    end:number <- find-next s, delim, start
    # copy start..end into result[curr-result]
    dest:address:array:character <- copy-range s, start, end
    *result <- put-index *result, curr-result, dest
    # slide over to next slice
    start <- add end, 1
    curr-result <- add curr-result, 1
    loop
  }
]

scenario text-split-1 [
  run [
    1:address:array:character <- new [a/b]
    2:address:array:address:array:character <- split 1:address:array:character, 47/slash
    3:number <- length *2:address:array:address:array:character
    4:address:array:character <- index *2:address:array:address:array:character, 0
    5:address:array:character <- index *2:address:array:address:array:character, 1
    10:array:character <- copy *4:address:array:character
    20:array:character <- copy *5:address:array:character
  ]
  memory-should-contain [
    3 <- 2  # length of result
    10:array:character <- [a]
    20:array:character <- [b]
  ]
]

scenario text-split-2 [
  run [
    1:address:array:character <- new [a/b/c]
    2:address:array:address:array:character <- split 1:address:array:character, 47/slash
    3:number <- length *2:address:array:address:array:character
    4:address:array:character <- index *2:address:array:address:array:character, 0
    5:address:array:character <- index *2:address:array:address:array:character, 1
    6:address:array:character <- index *2:address:array:address:array:character, 2
    10:array:character <- copy *4:address:array:character
    20:array:character <- copy *5:address:array:character
    30:array:character <- copy *6:address:array:character
  ]
  memory-should-contain [
    3 <- 3  # length of result
    10:array:character <- [a]
    20:array:character <- [b]
    30:array:character <- [c]
  ]
]

scenario text-split-missing [
  run [
    1:address:array:character <- new [abc]
    2:address:array:address:array:character <- split 1:address:array:character, 47/slash
    3:number <- length *2:address:array:address:array:character
    4:address:array:character <- index *2:address:array:address:array:character, 0
    10:array:character <- copy *4:address:array:character
  ]
  memory-should-contain [
    3 <- 1  # length of result
    10:array:character <- [abc]
  ]
]

scenario text-split-empty [
  run [
    1:address:array:character <- new []
    2:address:array:address:array:character <- split 1:address:array:character, 47/slash
    3:number <- length *2:address:array:address:array:character
  ]
  memory-should-contain [
    3 <- 0  # empty result
  ]
]

scenario text-split-empty-piece [
  run [
    1:address:array:character <- new [a/b//c]
    2:address:array:address:array:character <- split 1:address:array:character, 47/slash
    3:number <- length *2:address:array:address:array:character
    4:address:array:character <- index *2:address:array:address:array:character, 0
    5:address:array:character <- index *2:address:array:address:array:character, 1
    6:address:array:character <- index *2:address:array:address:array:character, 2
    7:address:array:character <- index *2:address:array:address:array:character, 3
    10:array:character <- copy *4:address:array:character
    20:array:character <- copy *5:address:array:character
    30:array:character <- copy *6:address:array:character
    40:array:character <- copy *7:address:array:character
  ]
  memory-should-contain [
    3 <- 4  # length of result
    10:array:character <- [a]
    20:array:character <- [b]
    30:array:character <- []
    40:array:character <- [c]
  ]
]

def split-first text:address:array:character, delim:character -> x:address:array:character, y:address:array:character [
  local-scope
  load-ingredients
  # empty text? return empty texts
  len:number <- length *text
  {
    empty?:boolean <- equal len, 0
    break-unless empty?
    x:address:array:character <- new []
    y:address:array:character <- new []
    return
  }
  idx:number <- find-next text, delim, 0
  x:address:array:character <- copy-range text, 0, idx
  idx <- add idx, 1
  y:address:array:character <- copy-range text, idx, len
]

scenario text-split-first [
  run [
    1:address:array:character <- new [a/b]
    2:address:array:character, 3:address:array:character <- split-first 1:address:array:character, 47/slash
    10:array:character <- copy *2:address:array:character
    20:array:character <- copy *3:address:array:character
  ]
  memory-should-contain [
    10:array:character <- [a]
    20:array:character <- [b]
  ]
]

def copy-range buf:address:array:character, start:number, end:number -> result:address:array:character [
  local-scope
  load-ingredients
  # if end is out of bounds, trim it
  len:number <- length *buf
  end:number <- min len, end
  # allocate space for result
  len <- subtract end, start
  result:address:array:character <- new character:type, len
  # copy start..end into result[curr-result]
  src-idx:number <- copy start
  dest-idx:number <- copy 0
  {
    done?:boolean <- greater-or-equal src-idx, end
    break-if done?
    src:character <- index *buf, src-idx
    *result <- put-index *result, dest-idx, src
    src-idx <- add src-idx, 1
    dest-idx <- add dest-idx, 1
    loop
  }
]

scenario text-copy-copies-partial-text [
  run [
    1:address:array:character <- new [abc]
    2:address:array:character <- copy-range 1:address:array:character, 1, 3
    3:array:character <- copy *2:address:array:character
  ]
  memory-should-contain [
    3:array:character <- [bc]
  ]
]

scenario text-copy-out-of-bounds [
  run [
    1:address:array:character <- new [abc]
    2:address:array:character <- copy-range 1:address:array:character, 2, 4
    3:array:character <- copy *2:address:array:character
  ]
  memory-should-contain [
    3:array:character <- [c]
  ]
]

scenario text-copy-out-of-bounds-2 [
  run [
    1:address:array:character <- new [abc]
    2:address:array:character <- copy-range 1:address:array:character, 3, 3
    3:array:character <- copy *2:address:array:character
  ]
  memory-should-contain [
    3:array:character <- []
  ]
]
