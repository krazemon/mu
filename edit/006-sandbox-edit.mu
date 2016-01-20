## editing sandboxes after they've been created

scenario clicking-on-a-sandbox-moves-it-to-editor [
  trace-until 100/app  # trace too long
  assume-screen 40/width, 10/height
  # basic recipe
  1:address:shared:array:character <- new [ 
recipe foo [
  reply 4
]]
  # run it
  2:address:shared:array:character <- new [foo]
  assume-console [
    press F4
  ]
  3:address:shared:programming-environment-data <- new-programming-environment screen:address:shared:screen, 1:address:shared:array:character, 2:address:shared:array:character
  event-loop screen:address:shared:screen, console:address:shared:console, 3:address:shared:programming-environment-data
  screen-should-contain [
    .                     run (F4)           .
    .                    ┊                   .
    .recipe foo [        ┊━━━━━━━━━━━━━━━━━━━.
    .  reply 4           ┊                  x.
    .]                   ┊foo                .
    .┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┊4                  .
    .                    ┊━━━━━━━━━━━━━━━━━━━.
    .                    ┊                   .
  ]
  # click somewhere on the sandbox
  assume-console [
    left-click 3, 30
  ]
  run [
    event-loop screen:address:shared:screen, console:address:shared:console, 3:address:shared:programming-environment-data
  ]
  # it pops back into editor
  screen-should-contain [
    .                     run (F4)           .
    .                    ┊foo                .
    .recipe foo [        ┊━━━━━━━━━━━━━━━━━━━.
    .  reply 4           ┊                   .
    .]                   ┊                   .
    .┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┊                   .
    .                    ┊                   .
    .                    ┊                   .
  ]
  # cursor should be in the right place
  assume-console [
    type [0]
  ]
  run [
    event-loop screen:address:shared:screen, console:address:shared:console, 3:address:shared:programming-environment-data
  ]
  screen-should-contain [
    .                     run (F4)           .
    .                    ┊0foo               .
    .recipe foo [        ┊━━━━━━━━━━━━━━━━━━━.
    .  reply 4           ┊                   .
    .]                   ┊                   .
    .┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┊                   .
    .                    ┊                   .
    .                    ┊                   .
  ]
]

after <global-touch> [
  # below sandbox editor? pop appropriate sandbox contents back into sandbox editor
  {
    sandbox-left-margin:number <- get *current-sandbox, left:offset
    click-column:number <- get *t, column:offset
    on-sandbox-side?:boolean <- greater-or-equal click-column, sandbox-left-margin
    break-unless on-sandbox-side?
    first-sandbox:address:shared:sandbox-data <- get *env, sandbox:offset
    break-unless first-sandbox
    first-sandbox-begins:number <- get *first-sandbox, starting-row-on-screen:offset
    click-row:number <- get *t, row:offset
    below-sandbox-editor?:boolean <- greater-or-equal click-row, first-sandbox-begins
    break-unless below-sandbox-editor?
    empty-sandbox-editor?:boolean <- empty-editor? current-sandbox
    break-unless empty-sandbox-editor?  # don't clobber existing contents
    # identify the sandbox to edit and remove it from the sandbox list
    sandbox:address:shared:sandbox-data <- extract-sandbox env, click-row
    text:address:shared:array:character <- get *sandbox, data:offset
    current-sandbox <- insert-text current-sandbox, text
    hide-screen screen
    screen <- render-sandbox-side screen, env
    screen <- update-cursor screen, recipes, current-sandbox, *sandbox-in-focus?
    show-screen screen
    loop +next-event:label
  }
]

recipe empty-editor? editor:address:shared:editor-data -> result:boolean [
  local-scope
  load-ingredients
  head:address:shared:duplex-list:character <- get *editor, data:offset
  first:address:shared:duplex-list:character <- next head
  result <- not first
]

recipe extract-sandbox env:address:shared:programming-environment-data, click-row:number -> result:address:shared:sandbox-data, env:address:shared:programming-environment-data [
  local-scope
  load-ingredients
  # assert click-row >= sandbox.starting-row-on-screen
  sandbox:address:address:shared:sandbox-data <- get-address *env, sandbox:offset
  start:number <- get **sandbox, starting-row-on-screen:offset
  clicked-on-sandboxes?:boolean <- greater-or-equal click-row, start
  assert clicked-on-sandboxes?, [extract-sandbox called on click to sandbox editor]
  {
    next-sandbox:address:shared:sandbox-data <- get **sandbox, next-sandbox:offset
    break-unless next-sandbox
    # if click-row < sandbox.next-sandbox.starting-row-on-screen, break
    next-start:number <- get *next-sandbox, starting-row-on-screen:offset
    found?:boolean <- lesser-than click-row, next-start
    break-if found?
    sandbox <- get-address **sandbox, next-sandbox:offset
    loop
  }
  # snip sandbox out of its list
  result <- copy *sandbox
  *sandbox <- copy next-sandbox
  # position cursor in sandbox editor
  sandbox-in-focus?:address:boolean <- get-address *env, sandbox-in-focus?:offset
  *sandbox-in-focus? <- copy 1/true
]

scenario sandbox-with-print-can-be-edited [
  trace-until 100/app  # trace too long
  assume-screen 100/width, 20/height
  # left editor is empty
  1:address:shared:array:character <- new []
  # right editor contains an instruction
  2:address:shared:array:character <- new [print-integer screen, 4]
  3:address:shared:programming-environment-data <- new-programming-environment screen:address:shared:screen, 1:address:shared:array:character, 2:address:shared:array:character
  # run the sandbox
  assume-console [
    press F4
  ]
  event-loop screen:address:shared:screen, console:address:shared:console, 3:address:shared:programming-environment-data
  screen-should-contain [
    .                                                                                 run (F4)           .
    .                                                  ┊                                                 .
    .┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┊━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━.
    .                                                  ┊                                                x.
    .                                                  ┊print-integer screen, 4                          .
    .                                                  ┊screen:                                          .
    .                                                  ┊  .4                             .               .
    .                                                  ┊  .                              .               .
    .                                                  ┊  .                              .               .
    .                                                  ┊  .                              .               .
    .                                                  ┊  .                              .               .
    .                                                  ┊━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━.
    .                                                  ┊                                                 .
  ]
  # edit the sandbox
  assume-console [
    left-click 3, 70
  ]
  run [
    event-loop screen:address:shared:screen, console:address:shared:console, 3:address:shared:programming-environment-data
  ]
  screen-should-contain [
    .                                                                                 run (F4)           .
    .                                                  ┊print-integer screen, 4                          .
    .┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┊━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━.
    .                                                  ┊                                                 .
    .                                                  ┊                                                 .
  ]
]
