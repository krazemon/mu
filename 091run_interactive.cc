//: Helper for various programming environments: run arbitrary mu code and
//: return some result in string form.

:(scenario run_interactive_code)
def main [
  1:number/raw <- copy 0
  2:address:array:character <- new [1:number/raw <- copy 34]
  run-interactive 2:address:array:character
  3:number/raw <- copy 1:number/raw
]
+mem: storing 34 in location 3

:(scenario run_interactive_empty)
def main [
  1:address:array:character <- copy 0/unsafe
  2:address:array:character <- run-interactive 1:address:array:character
]
# result is null
+mem: storing 0 in location 2

//: run code in 'interactive mode', i.e. with errors off and return:
//:   stringified output in case we want to print it to screen
//:   any errors encountered
//:   simulated screen any prints went to
//:   any 'app' layer traces generated
:(before "End Primitive Recipe Declarations")
RUN_INTERACTIVE,
:(before "End Primitive Recipe Numbers")
put(Recipe_ordinal, "run-interactive", RUN_INTERACTIVE);
:(before "End Primitive Recipe Checks")
case RUN_INTERACTIVE: {
  if (SIZE(inst.ingredients) != 1) {
    raise << maybe(get(Recipe, r).name) << "'run-interactive' requires exactly one ingredient, but got '" << to_original_string(inst) << "'\n" << end();
    break;
  }
  if (!is_mu_string(inst.ingredients.at(0))) {
    raise << maybe(get(Recipe, r).name) << "first ingredient of 'run-interactive' should be a string, but got '" << to_string(inst.ingredients.at(0)) << "'\n" << end();
    break;
  }
  break;
}
:(before "End Primitive Recipe Implementations")
case RUN_INTERACTIVE: {
  bool new_code_pushed_to_stack = run_interactive(ingredients.at(0).at(0));
  if (!new_code_pushed_to_stack) {
    products.resize(5);
    products.at(0).push_back(0);
    products.at(1).push_back(trace_error_contents());
    products.at(2).push_back(0);
    products.at(3).push_back(trace_app_contents());
    products.at(4).push_back(1);  // completed
    run_code_end();
    break;  // done with this instruction
  }
  else {
    continue;  // not done with caller; don't increment current_step_index()
  }
}

:(before "End Globals")
bool Track_most_recent_products = false;
:(before "End Tracing")
trace_stream* Save_trace_stream = NULL;
string Save_trace_file;
:(before "End Setup")
Track_most_recent_products = false;
:(code)
// reads a string, tries to call it as code (treating it as a test), saving
// all errors.
// returns true if successfully called (no errors found during load and transform)
bool run_interactive(int address) {
  assert(contains_key(Recipe_ordinal, "interactive") && get(Recipe_ordinal, "interactive") != 0);
  // try to sandbox the run as best you can
  // todo: test this
  if (!Current_scenario) {
    for (int i = 1; i < Reserved_for_tests; ++i)
      Memory.erase(i);
  }
  string command = trim(strip_comments(read_mu_string(address)));
  Name[get(Recipe_ordinal, "interactive")].clear();
  run_code_begin(/*should_stash_snapshots*/true);
  if (command.empty()) return false;
  // don't kill the current routine on parse errors
  routine* save_current_routine = Current_routine;
  Current_routine = NULL;
  // call run(string) but without the scheduling
  load(string("recipe! interactive [\n") +
          "new-default-space\n" +  // disable automatic abandon so tests can see changes
          "screen:address:screen <- next-ingredient\n" +
          "$start-tracking-products\n" +
          command + "\n" +
          "$stop-tracking-products\n" +
          "return screen\n" +
       "]\n");
  transform_all();
  Current_routine = save_current_routine;
  if (trace_count("error") > 0) return false;
  // now call 'sandbox' which will run 'interactive' in a separate routine,
  // and wait for it
  if (Save_trace_stream) {
    ++Save_trace_stream->callstack_depth;
    trace(9999, "trace") << "run-interactive: incrementing callstack depth to " << Save_trace_stream->callstack_depth << end();
    assert(Save_trace_stream->callstack_depth < 9000);  // 9998-101 plus cushion
  }
  Current_routine->calls.push_front(call(get(Recipe_ordinal, "sandbox")));
  return true;
}

//: Carefully update all state to exactly how it was -- including snapshots.

:(before "End Globals")
map<string, recipe_ordinal> Recipe_ordinal_snapshot_stash;
map<recipe_ordinal, recipe> Recipe_snapshot_stash;
map<string, type_ordinal> Type_ordinal_snapshot_stash;
map<type_ordinal, type_info> Type_snapshot_stash;
map<recipe_ordinal, map<string, int> > Name_snapshot_stash;
map<string, vector<recipe_ordinal> > Recipe_variants_snapshot_stash;
:(code)
void run_code_begin(bool should_stash_snapshots) {
  // stuff to undo later, in run_code_end()
  Hide_errors = true;
  Disable_redefine_checks = true;
  if (should_stash_snapshots)
    stash_snapshots();
  Save_trace_stream = Trace_stream;
  Save_trace_file = Trace_file;
  Trace_file = "";
  Trace_stream = new trace_stream;
  Trace_stream->collect_depth = App_depth;
}

void run_code_end() {
  Hide_errors = false;
  Disable_redefine_checks = false;
  delete Trace_stream;
  Trace_stream = Save_trace_stream;
  Save_trace_stream = NULL;
  Trace_file = Save_trace_file;
  Save_trace_file.clear();
  Recipe.erase(get(Recipe_ordinal, "interactive"));  // keep past sandboxes from inserting errors
  if (!Recipe_snapshot_stash.empty())
    unstash_snapshots();
}

// keep sync'd with save_snapshots and restore_snapshots
void stash_snapshots() {
  Recipe_ordinal_snapshot_stash = Recipe_ordinal_snapshot;
  Recipe_snapshot_stash = Recipe_snapshot;
  Type_ordinal_snapshot_stash = Type_ordinal_snapshot;
  Type_snapshot_stash = Type_snapshot;
  Name_snapshot_stash = Name_snapshot;
  Recipe_variants_snapshot_stash = Recipe_variants_snapshot;
  save_snapshots();
}
void unstash_snapshots() {
  restore_snapshots();
  Recipe_ordinal_snapshot = Recipe_ordinal_snapshot_stash;  Recipe_ordinal_snapshot_stash.clear();
  Recipe_snapshot = Recipe_snapshot_stash;  Recipe_snapshot_stash.clear();
  Type_ordinal_snapshot = Type_ordinal_snapshot_stash;  Type_ordinal_snapshot_stash.clear();
  Type_snapshot = Type_snapshot_stash;  Type_snapshot_stash.clear();
  Name_snapshot = Name_snapshot_stash;  Name_snapshot_stash.clear();
  Recipe_variants_snapshot = Recipe_variants_snapshot_stash;  Recipe_variants_snapshot_stash.clear();
}

:(before "End Load Recipes")
load(string(
"recipe interactive [\n") +  // just a dummy version to initialize the Recipe_ordinal and so on
"]\n" +
"recipe sandbox [\n" +
  "local-scope\n" +
  "screen:address:screen <- new-fake-screen 30, 5\n" +
  "r:number/routine_id <- start-running interactive, screen\n" +
  "limit-time r, 100000/instructions\n" +
  "wait-for-routine r\n" +
  "sandbox-state:number <- routine-state r/routine_id\n" +
  "completed?:boolean <- equal sandbox-state, 1/completed\n" +
  "output:address:array:character <- $most-recent-products\n" +
  "errors:address:array:character <- save-errors\n" +
  "stashes:address:array:character <- save-app-trace\n" +
  "$cleanup-run-interactive\n" +
  "return output, errors, screen, stashes, completed?\n" +
"]\n");

//: adjust errors in the sandbox
:(after "string maybe(string s)")
  if (s == "interactive") return "";

:(scenario run_interactive_comments)
def main [
  1:address:array:character <- new [# ab
add 2, 2]
  2:address:array:character <- run-interactive 1:address:array:character
  3:array:character <- copy *2:address:array:character
]
+mem: storing 52 in location 4

:(before "End Primitive Recipe Declarations")
_START_TRACKING_PRODUCTS,
:(before "End Primitive Recipe Numbers")
put(Recipe_ordinal, "$start-tracking-products", _START_TRACKING_PRODUCTS);
:(before "End Primitive Recipe Checks")
case _START_TRACKING_PRODUCTS: {
  break;
}
:(before "End Primitive Recipe Implementations")
case _START_TRACKING_PRODUCTS: {
  Track_most_recent_products = true;
  break;
}

:(before "End Primitive Recipe Declarations")
_STOP_TRACKING_PRODUCTS,
:(before "End Primitive Recipe Numbers")
put(Recipe_ordinal, "$stop-tracking-products", _STOP_TRACKING_PRODUCTS);
:(before "End Primitive Recipe Checks")
case _STOP_TRACKING_PRODUCTS: {
  break;
}
:(before "End Primitive Recipe Implementations")
case _STOP_TRACKING_PRODUCTS: {
  Track_most_recent_products = false;
  break;
}

:(before "End Primitive Recipe Declarations")
_MOST_RECENT_PRODUCTS,
:(before "End Primitive Recipe Numbers")
put(Recipe_ordinal, "$most-recent-products", _MOST_RECENT_PRODUCTS);
:(before "End Primitive Recipe Checks")
case _MOST_RECENT_PRODUCTS: {
  break;
}
:(before "End Primitive Recipe Implementations")
case _MOST_RECENT_PRODUCTS: {
  products.resize(1);
  products.at(0).push_back(new_mu_string(Most_recent_products));
  break;
}

:(before "End Primitive Recipe Declarations")
SAVE_ERRORS,
:(before "End Primitive Recipe Numbers")
put(Recipe_ordinal, "save-errors", SAVE_ERRORS);
:(before "End Primitive Recipe Checks")
case SAVE_ERRORS: {
  break;
}
:(before "End Primitive Recipe Implementations")
case SAVE_ERRORS: {
  products.resize(1);
  products.at(0).push_back(trace_error_contents());
  break;
}

:(before "End Primitive Recipe Declarations")
SAVE_APP_TRACE,
:(before "End Primitive Recipe Numbers")
put(Recipe_ordinal, "save-app-trace", SAVE_APP_TRACE);
:(before "End Primitive Recipe Checks")
case SAVE_APP_TRACE: {
  break;
}
:(before "End Primitive Recipe Implementations")
case SAVE_APP_TRACE: {
  products.resize(1);
  products.at(0).push_back(trace_app_contents());
  break;
}

:(before "End Primitive Recipe Declarations")
_CLEANUP_RUN_INTERACTIVE,
:(before "End Primitive Recipe Numbers")
put(Recipe_ordinal, "$cleanup-run-interactive", _CLEANUP_RUN_INTERACTIVE);
:(before "End Primitive Recipe Checks")
case _CLEANUP_RUN_INTERACTIVE: {
  break;
}
:(before "End Primitive Recipe Implementations")
case _CLEANUP_RUN_INTERACTIVE: {
  run_code_end();
  break;
}

:(scenario "run_interactive_converts_result_to_text")
def main [
  # try to interactively add 2 and 2
  1:address:array:character <- new [add 2, 2]
  2:address:array:character <- run-interactive 1:address:array:character
  10:array:character <- copy 2:address:array:character/lookup
]
# first letter in the output should be '4' in unicode
+mem: storing 52 in location 11

:(scenario "run_interactive_returns_text")
def main [
  # try to interactively add 2 and 2
  1:address:array:character <- new [
    x:address:array:character <- new [a]
    y:address:array:character <- new [b]
    z:address:array:character <- append x:address:array:character, y:address:array:character
  ]
  2:address:array:character <- run-interactive 1:address:array:character
  10:array:character <- copy 2:address:array:character/lookup
]
# output contains "ab"
+mem: storing 97 in location 11
+mem: storing 98 in location 12

:(scenario "run_interactive_returns_errors")
def main [
  # run a command that generates an error
  1:address:array:character <- new [x:number <- copy 34
get x:number, foo:offset]
  2:address:array:character, 3:address:array:character <- run-interactive 1:address:array:character
  10:array:character <- copy 3:address:array:character/lookup
]
# error should be "unknown element foo in container number"
+mem: storing 117 in location 11
+mem: storing 110 in location 12
+mem: storing 107 in location 13
+mem: storing 110 in location 14
# ...

:(scenario run_interactive_with_comment)
def main [
  # 2 instructions, with a comment after the first
  1:address:array:number <- new [a:number <- copy 0  # abc
b:number <- copy 0
]
  2:address:array:character, 3:address:array:character <- run-interactive 1:address:array:character
]
# no errors
+mem: storing 0 in location 3

:(before "End Globals")
string Most_recent_products;
:(before "End Setup")
Most_recent_products = "";
:(before "End of Instruction")
if (Track_most_recent_products) {
  track_most_recent_products(current_instruction(), products);
}
:(code)
void track_most_recent_products(const instruction& instruction, const vector<vector<double> >& products) {
  ostringstream out;
  for (int i = 0; i < SIZE(products); ++i) {
    // string
    if (i < SIZE(instruction.products)) {
      if (is_mu_string(instruction.products.at(i))) {
        if (!scalar(products.at(i))) {
          tb_shutdown();
          cerr << read_mu_string(trace_error_contents()) << '\n';
          cerr << SIZE(products.at(i)) << ": ";
          for (int j = 0; j < SIZE(products.at(i)); ++j)
            cerr << no_scientific(products.at(i).at(j)) << ' ';
          cerr << '\n';
        }
        assert(scalar(products.at(i)));
        out << read_mu_string(products.at(i).at(0)) << '\n';
        continue;
      }
      // End Record Product Special-cases
    }
    for (int j = 0; j < SIZE(products.at(i)); ++j)
      out << no_scientific(products.at(i).at(j)) << ' ';
    out << '\n';
  }
  Most_recent_products = out.str();
}

:(code)
string strip_comments(string in) {
  ostringstream result;
  for (int i = 0; i < SIZE(in); ++i) {
    if (in.at(i) != '#') {
      result << in.at(i);
    }
    else {
      while (i+1 < SIZE(in) && in.at(i+1) != '\n')
        ++i;
    }
  }
  return result.str();
}

int stringified_value_of_location(int address) {
  // convert to string
  ostringstream out;
  out << no_scientific(get_or_insert(Memory, address));
  return new_mu_string(out.str());
}

int trace_error_contents() {
  if (!Trace_stream) return 0;
  ostringstream out;
  for (vector<trace_line>::iterator p = Trace_stream->past_lines.begin(); p != Trace_stream->past_lines.end(); ++p) {
    if (p->label != "error") continue;
    out << p->contents;
    if (*--p->contents.end() != '\n') out << '\n';
  }
  string result = out.str();
  if (result.empty()) return 0;
  truncate(result);
  return new_mu_string(result);
}

int trace_app_contents() {
  if (!Trace_stream) return 0;
  ostringstream out;
  for (vector<trace_line>::iterator p = Trace_stream->past_lines.begin(); p != Trace_stream->past_lines.end(); ++p) {
    if (p->depth != App_depth) continue;
    out << p->contents;
    if (*--p->contents.end() != '\n') out << '\n';
  }
  string result = out.str();
  if (result.empty()) return 0;
  truncate(result);
  return new_mu_string(result);
}

void truncate(string& x) {
  if (SIZE(x) > 1024) {
    x.erase(1024);
    *x.rbegin() = '\n';
    *++x.rbegin() = '.';
    *++++x.rbegin() = '.';
  }
}

//: simpler version of run-interactive: doesn't do any running, just loads
//: recipes and reports errors.

:(before "End Primitive Recipe Declarations")
RELOAD,
:(before "End Primitive Recipe Numbers")
put(Recipe_ordinal, "reload", RELOAD);
:(before "End Primitive Recipe Checks")
case RELOAD: {
  if (SIZE(inst.ingredients) != 1) {
    raise << maybe(get(Recipe, r).name) << "'reload' requires exactly one ingredient, but got '" << to_original_string(inst) << "'\n" << end();
    break;
  }
  if (!is_mu_string(inst.ingredients.at(0))) {
    raise << maybe(get(Recipe, r).name) << "first ingredient of 'reload' should be a string, but got '" << inst.ingredients.at(0).original_string << "'\n" << end();
    break;
  }
  break;
}
:(before "End Primitive Recipe Implementations")
case RELOAD: {
  // conundrum: need to support repeated reloads of the same code, but not
  // wipe out state for the current test
  // hacky solution: subset of restore_snapshots() without restoring recipes {
  // can't yet define containers in a test that runs 'reload'
  Type_ordinal = Type_ordinal_snapshot;
  Type = Type_snapshot;
  // can't yet create new specializations of shape-shifting recipes in a test
  // that runs 'reload'
  Recipe_variants = Recipe_variants_snapshot;
  Name = Name_snapshot;
  // }
  string code = read_mu_string(ingredients.at(0).at(0));
  run_code_begin(/*should_stash_snapshots*/false);
  routine* save_current_routine = Current_routine;
  Current_routine = NULL;
  vector<recipe_ordinal> recipes_reloaded = load(code);
  transform_all();
  Trace_stream->newline();  // flush trace
  Current_routine = save_current_routine;
  products.resize(1);
  products.at(0).push_back(trace_error_contents());
  run_code_end();  // wait until we're done with the trace contents
  break;
}

:(scenario reload_continues_past_error)
def main [
  local-scope
  x:address:array:character <- new [recipe foo [
  get 1234:number, foo:offset
]]
  reload x
  1:number/raw <- copy 34
]
+mem: storing 34 in location 1

:(scenario reload_can_repeatedly_load_container_definitions)
# define a container and try to create it (merge requires knowing container size)
def main [
  local-scope
  x:address:array:character <- new [
    container foo [
      x:number
      y:number
    ]
    recipe bar [
      local-scope
      x:foo <- merge 34, 35
    ]
  ]
  # save warning addresses in locations of type 'number' to avoid spurious changes to them due to 'abandon'
  1:number/raw <- reload x
  2:number/raw <- reload x
]
# no errors on either load
+mem: storing 0 in location 1
+mem: storing 0 in location 2
