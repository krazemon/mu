//: So far we've been calling a fixed recipe in each instruction, but we'd
//: also like to make the recipe a variable, pass recipes to "higher-order"
//: recipes, return recipes from recipes and so on.
//:
//: todo: support storing shape-shifting recipes into recipe variables and calling them

:(scenario call_literal_recipe)
def main [
  1:number <- call f, 34
]
def f x:number -> y:number [
  local-scope
  load-ingredients
  y <- copy x
]
+mem: storing 34 in location 1

:(scenario call_variable)
def main [
  {1: (recipe number -> number)} <- copy f
  2:number <- call {1: (recipe number -> number)}, 34
]
def f x:number -> y:number [
  local-scope
  load-ingredients
  y <- copy x
]
+mem: storing 34 in location 2

:(before "End Mu Types Initialization")
put(Type_ordinal, "recipe-literal", 0);
// 'recipe' variables can store recipe-literal
type_ordinal recipe = put(Type_ordinal, "recipe", Next_type_ordinal++);
get_or_insert(Type, recipe).name = "recipe";

:(before "End Null-type is_disqualified Exceptions")
if (!x.type && contains_key(Recipe_ordinal, x.name)) {
  x.type = new type_tree("recipe-literal");
  x.set_value(get(Recipe_ordinal, x.name));
  return true;
}

:(before "End Primitive Recipe Declarations")
CALL,
:(before "End Primitive Recipe Numbers")
put(Recipe_ordinal, "call", CALL);
:(before "End Primitive Recipe Checks")
case CALL: {
  if (inst.ingredients.empty()) {
    raise << maybe(get(Recipe, r).name) << "'call' requires at least one ingredient (the recipe to call)\n" << end();
    break;
  }
  if (!is_mu_recipe(inst.ingredients.at(0))) {
    raise << maybe(get(Recipe, r).name) << "first ingredient of 'call' should be a recipe, but got '" << inst.ingredients.at(0).original_string << "'\n" << end();
    break;
  }
  break;
}
:(before "End Primitive Recipe Implementations")
case CALL: {
  // Begin Call
  if (Trace_stream) {
    ++Trace_stream->callstack_depth;
    trace("trace") << "indirect 'call': incrementing callstack depth to " << Trace_stream->callstack_depth << end();
    assert(Trace_stream->callstack_depth < 9000);  // 9998-101 plus cushion
  }
  if (!ingredients.at(0).at(0)) {
    raise << maybe(current_recipe_name()) << "tried to call empty recipe in '" << to_string(current_instruction()) << "'" << end();
    break;
  }
  const instruction& caller_instruction = current_instruction();
  Current_routine->calls.push_front(call(ingredients.at(0).at(0)));
  ingredients.erase(ingredients.begin());  // drop the callee
  finish_call_housekeeping(caller_instruction, ingredients);
  continue;
}

//:: check types for 'call' instructions

:(scenario call_check_literal_recipe)
% Hide_errors = true;
def main [
  1:number <- call f, 34
]
def f x:point -> y:point [
  local-scope
  load-ingredients
  y <- copy x
]
+error: main: ingredient 0 has the wrong type at '1:number <- call f, 34'
+error: main: product 0 has the wrong type at '1:number <- call f, 34'

:(scenario call_check_variable_recipe)
% Hide_errors = true;
def main [
  {1: (recipe point -> point)} <- copy f
  2:number <- call {1: (recipe point -> point)}, 34
]
def f x:point -> y:point [
  local-scope
  load-ingredients
  y <- copy x
]
+error: main: ingredient 0 has the wrong type at '2:number <- call {1: (recipe point -> point)}, 34'
+error: main: product 0 has the wrong type at '2:number <- call {1: (recipe point -> point)}, 34'

:(after "Transform.push_back(check_instruction)")
Transform.push_back(check_indirect_calls_against_header);  // idempotent
:(code)
void check_indirect_calls_against_header(const recipe_ordinal r) {
  trace(9991, "transform") << "--- type-check 'call' instructions inside recipe " << get(Recipe, r).name << end();
  const recipe& caller = get(Recipe, r);
  for (int i = 0; i < SIZE(caller.steps); ++i) {
    const instruction& inst = caller.steps.at(i);
    if (inst.operation != CALL) continue;
    if (inst.ingredients.empty()) continue;  // error raised above
    const reagent& callee = inst.ingredients.at(0);
    if (!is_mu_recipe(callee)) continue;  // error raised above
    const recipe callee_header = is_literal(callee) ? get(Recipe, callee.value) : from_reagent(inst.ingredients.at(0));
    if (!callee_header.has_header) continue;
    for (long int i = /*skip callee*/1; i < min(SIZE(inst.ingredients), SIZE(callee_header.ingredients)+/*skip callee*/1); ++i) {
      if (!types_coercible(callee_header.ingredients.at(i-/*skip callee*/1), inst.ingredients.at(i)))
        raise << maybe(caller.name) << "ingredient " << i-/*skip callee*/1 << " has the wrong type at '" << to_original_string(inst) << "'\n" << end();
    }
    for (long int i = 0; i < min(SIZE(inst.products), SIZE(callee_header.products)); ++i) {
      if (is_dummy(inst.products.at(i))) continue;
      if (!types_coercible(callee_header.products.at(i), inst.products.at(i)))
        raise << maybe(caller.name) << "product " << i << " has the wrong type at '" << to_original_string(inst) << "'\n" << end();
    }
  }
}

recipe from_reagent(const reagent& r) {
  assert(r.type->name == "recipe");
  recipe result_header;  // will contain only ingredients and products, nothing else
  result_header.has_header = true;
  const type_tree* curr = r.type->right;
  for (; curr; curr=curr->right) {
    if (curr->name == "->") {
      curr = curr->right;  // skip delimiter
      break;
    }
    result_header.ingredients.push_back(next_recipe_reagent(curr));
  }
  for (; curr; curr=curr->right)
    result_header.products.push_back(next_recipe_reagent(curr));
  return result_header;
}

reagent next_recipe_reagent(const type_tree* curr) {
  if (!curr->left) return reagent("recipe:"+curr->name);
  reagent result;
  result.name = "recipe";
  result.type = new type_tree(*curr->left);
  return result;
}

bool is_mu_recipe(const reagent& r) {
  if (!r.type) return false;
  if (r.type->name == "recipe") return true;
  if (r.type->name == "recipe-literal") return true;
  // End is_mu_recipe Cases
  return false;
}

:(scenario copy_typecheck_recipe_variable)
% Hide_errors = true;
def main [
  3:number <- copy 34  # abc def
  {1: (recipe number -> number)} <- copy f  # store literal in a matching variable
  {2: (recipe boolean -> boolean)} <- copy {1: (recipe number -> number)}  # mismatch between recipe variables
]
def f x:number -> y:number [
  local-scope
  load-ingredients
  y <- copy x
]
+error: main: can't copy '{1: (recipe number -> number)}' to '{2: (recipe boolean -> boolean)}'; types don't match

:(scenario copy_typecheck_recipe_variable_2)
% Hide_errors = true;
def main [
  {1: (recipe number -> number)} <- copy f  # mismatch with a recipe literal
]
def f x:boolean -> y:boolean [
  local-scope
  load-ingredients
  y <- copy x
]
+error: main: can't copy 'f' to '{1: (recipe number -> number)}'; types don't match

:(before "End Matching Types For Literal(to)")
if (is_mu_recipe(to)) {
  if (!contains_key(Recipe, from.value)) {
    raise << "trying to store recipe " << from.name << " into " << to_string(to) << " but there's no such recipe\n" << end();
    return false;
  }
  const recipe& rrhs = get(Recipe, from.value);
  const recipe& rlhs = from_reagent(to);
  for (long int i = 0; i < min(SIZE(rlhs.ingredients), SIZE(rrhs.ingredients)); ++i) {
    if (!types_match(rlhs.ingredients.at(i), rrhs.ingredients.at(i)))
      return false;
  }
  for (long int i = 0; i < min(SIZE(rlhs.products), SIZE(rrhs.products)); ++i) {
    if (!types_match(rlhs.products.at(i), rrhs.products.at(i)))
      return false;
  }
  return true;
}

:(scenario call_variable_compound_ingredient)
def main [
  {1: (recipe (address number) -> number)} <- copy f
  2:address:number <- copy 0
  3:number <- call {1: (recipe (address number) -> number)}, 2:address:number
]
def f x:address:number -> y:number [
  local-scope
  load-ingredients
  y <- copy x
]
$error: 0

//: make sure we don't accidentally break on a function literal
:(scenario jump_forbidden_on_recipe_literals)
% Hide_errors = true;
def foo [
  local-scope
]
def main [
  local-scope
  {
    break-if foo
  }
]
# error should be as if foo is not a recipe
+error: main: missing type for foo in 'break-if {foo: ()}'

:(before "End JUMP_IF Checks")
check_for_recipe_literals(inst, get(Recipe, r));
:(before "End JUMP_UNLESS Checks")
check_for_recipe_literals(inst, get(Recipe, r));
:(code)
void check_for_recipe_literals(const instruction& inst, const recipe& caller) {
  for (int i = 0; i < SIZE(inst.ingredients); ++i) {
    if (is_mu_recipe(inst.ingredients.at(i)))
      raise << maybe(caller.name) << "missing type for " << inst.ingredients.at(i).original_string << " in '" << inst.original_string << "'\n" << end();
  }
}
