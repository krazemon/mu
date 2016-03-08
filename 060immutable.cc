//: Addresses passed into of a recipe are meant to be immutable unless they're
//: also products. This layer will start enforcing this check.
//:
//: One hole for now: variables in surrounding spaces are implicitly mutable.

:(scenario can_modify_value_ingredients)
def main [
  local-scope
  p:address:shared:point <- new point:type
  foo *p
]
def foo p:point [
  local-scope
  load-ingredients
  x:address:number <- get-address p, x:offset
  *x <- copy 34
]
$error: 0

:(scenario can_modify_ingredients_that_are_also_products)
def main [
  local-scope
  p:address:shared:point <- new point:type
  p <- foo p
]
def foo p:address:shared:point -> p:address:shared:point [
  local-scope
  load-ingredients
  x:address:number <- get-address *p, x:offset
  *x <- copy 34
]
$error: 0

:(scenario ignore_literal_ingredients_for_immutability_checks)
def main [
  local-scope
  p:address:shared:d1 <- new d1:type
  q:number <- foo p
]
def foo p:address:shared:d1 -> q:number [
  local-scope
  load-ingredients
  x:address:shared:d1 <- new d1:type
  y:address:number <- get-address *x, p:offset  # ignore this 'p'
  q <- copy 34
]
container d1 [
  p:number
  q:number
]
$error: 0

:(scenario cannot_modify_immutable_ingredients)
% Hide_errors = true;
def main [
  local-scope
  x:address:shared:number <- new number:type
  foo x
]
def foo x:address:shared:number [
  local-scope
  load-ingredients
  *x <- copy 34
]
+error: foo: cannot modify x in instruction '*x <- copy 34' because it's not also a product of foo

:(scenario cannot_take_address_inside_immutable_ingredients)
% Hide_errors = true;
def main [
  local-scope
  p:address:shared:point <- new point:type
  foo p
]
def foo p:address:shared:point [
  local-scope
  load-ingredients
  x:address:number <- get-address *p, x:offset
  *x <- copy 34
]
+error: foo: cannot modify ingredient p after instruction 'x:address:number <- get-address *p, x:offset' because it's not also a product of foo

:(scenario cannot_call_mutating_recipes_on_immutable_ingredients)
% Hide_errors = true;
def main [
  local-scope
  p:address:shared:point <- new point:type
  foo p
]
def foo p:address:shared:point [
  local-scope
  load-ingredients
  bar p
]
def bar p:address:shared:point -> p:address:shared:point [
  local-scope
  load-ingredients
  x:address:number <- get-address *p, x:offset
  *x <- copy 34
]
+error: foo: cannot modify ingredient p at instruction 'bar p' because it's not also a product of foo

:(scenario cannot_modify_copies_of_immutable_ingredients)
% Hide_errors = true;
def main [
  local-scope
  p:address:shared:point <- new point:type
  foo p
]
def foo p:address:shared:point [
  local-scope
  load-ingredients
  q:address:shared:point <- copy p
  x:address:number <- get-address *q, x:offset
]
+error: foo: cannot modify q after instruction 'x:address:number <- get-address *q, x:offset' because that would modify ingredient p which is not also a product of foo

:(scenario can_modify_copies_of_mutable_ingredients)
def main [
  local-scope
  p:address:shared:point <- new point:type
  foo p
]
def foo p:address:shared:point -> p:address:shared:point [
  local-scope
  load-ingredients
  q:address:shared:point <- copy p
  x:address:number <- get-address *q, x:offset
]
$error: 0

:(scenario cannot_modify_address_inside_immutable_ingredients)
% Hide_errors = true;
container foo [
  x:address:shared:array:number  # contains an address
]
def main [
  # don't run anything
]
def foo a:address:shared:foo [
  local-scope
  load-ingredients
  x:address:shared:array:number <- get *a, x:offset  # just a regular get of the container
  y:address:number <- index-address *x, 0  # but then index-address on the result
  *y <- copy 34
]
+error: foo: cannot modify x after instruction 'y:address:number <- index-address *x, 0' because that would modify ingredient a which is not also a product of foo

:(scenario cannot_modify_address_inside_immutable_ingredients_2)
container foo [
  x:address:shared:array:number  # contains an address
]
def main [
  # don't run anything
]
def foo a:address:shared:foo [
  local-scope
  load-ingredients
  b:foo <- merge 0  # completely unrelated to 'a'
  x:address:shared:array:number <- get b, x:offset  # just a regular get of the container
  y:address:number <- index-address *x, 0  # but then index-address on the result
  *y <- copy 34
]
$error: 0

:(scenario cannot_modify_address_inside_immutable_ingredients_3)
% Hide_errors = true;
container foo [
  x:number
]
def main [
  # don't run anything
]
def foo a:address:shared:array:address:number [
  local-scope
  load-ingredients
  x:address:number <- index *a, 0  # just a regular index of the array
  *x <- copy 34  # but then modify the result
]
# +error: foo: cannot modify x in instruction '*x <- copy 34' because that would modify ingredient a which is not also a product of foo
+error: foo: cannot modify x in instruction '*x <- copy 34' because it's not also a product of foo

:(scenario cannot_modify_address_inside_immutable_ingredients_4)
container foo [
  x:address:shared:array:number  # contains an address
]
def main [
  # don't run anything
]
def foo a:address:shared:array:address:number [
  local-scope
  load-ingredients
  b:address:shared:array:address:number <- new {(address number): type}, 3  # completely unrelated to 'a'
  x:address:number <- index *b, 0  # just a regular index of the array
  *x <- copy 34  # but then modify the result
]
$error: 0

:(scenario can_traverse_immutable_ingredients)
container test-list [
  next:address:shared:test-list
]
def main [
  local-scope
  p:address:shared:test-list <- new test-list:type
  foo p
]
def foo p:address:shared:test-list [
  local-scope
  load-ingredients
  p2:address:shared:test-list <- bar p
]
def bar x:address:shared:test-list -> y:address:shared:test-list [
  local-scope
  load-ingredients
  y <- get *x, next:offset
]
$error: 0

:(scenario handle_optional_ingredients_in_immutability_checks)
def main [
  k:address:shared:number <- new number:type
  test k
]
# recipe taking an immutable address ingredient
def test k:address:shared:number [
  local-scope
  load-ingredients
  foo k
]
# ..calling a recipe with an optional address ingredient
def foo -> [
  local-scope
  load-ingredients
  k:address:shared:number, found?:boolean <- next-ingredient
]
$error: 0

//: when checking for immutable ingredients, remember to take space into account
:(scenario check_space_of_reagents_in_immutability_checks)
def main [
  a:address:shared:array:location <- new-closure
  b:address:shared:number <- new number:type
  run-closure b:address:shared:number, a:address:shared:array:location
]
def new-closure [
  new-default-space
  x:address:shared:number <- new number:type
  return default-space
]
def run-closure x:address:shared:number, s:address:shared:array:location [
  local-scope
  load-ingredients
  0:address:shared:array:location/names:new-closure <- copy s
  *x:address:number/space:1 <- copy 34
]
$error: 0

:(before "End Transforms")
Transform.push_back(check_immutable_ingredients);  // idempotent

:(code)
void check_immutable_ingredients(recipe_ordinal r) {
  // to ensure an address reagent isn't modified, it suffices to show that
  //   a) we never write to its contents directly,
  //   b) we never call get-address or index-address with it, and
  //   c) any non-primitive recipe calls in the body aren't returning it as a product
  const recipe& caller = get(Recipe, r);
  trace(9991, "transform") << "--- check mutability of ingredients in recipe " << caller.name << end();
  if (!caller.has_header) return;  // skip check for old-style recipes calling next-ingredient directly
  for (long long int i = 0; i < SIZE(caller.ingredients); ++i) {
    const reagent& current_ingredient = caller.ingredients.at(i);
    if (!is_mu_address(current_ingredient)) continue;  // will be copied
    if (is_present_in_products(caller, current_ingredient.name)) continue;  // not expected to be immutable
    // End Immutable Ingredients Special-cases
    set<reagent> immutable_vars;
    immutable_vars.insert(current_ingredient);
    for (long long int i = 0; i < SIZE(caller.steps); ++i) {
      const instruction& inst = caller.steps.at(i);
      check_immutable_ingredient_in_instruction(inst, immutable_vars, current_ingredient.name, caller);
      update_aliases(inst, immutable_vars);
    }
  }
}

void update_aliases(const instruction& inst, set<reagent>& current_ingredient_and_aliases) {
  set<long long int> current_ingredient_indices = ingredient_indices(inst, current_ingredient_and_aliases);
  if (!contains_key(Recipe, inst.operation)) {
    // primitive recipe
    switch (inst.operation) {
      case COPY:
        for (set<long long int>::iterator p = current_ingredient_indices.begin(); p != current_ingredient_indices.end(); ++p)
          current_ingredient_and_aliases.insert(inst.products.at(*p).name);
        break;
      case GET:
      case INDEX:
          // current_ingredient_indices can only have 0 or one value
        if (!current_ingredient_indices.empty()) {
          if (is_mu_address(inst.products.at(0)))
            current_ingredient_and_aliases.insert(inst.products.at(0));
        }
        break;
      default: break;
    }
  }
  else {
    // defined recipe
    set<long long int> contained_in_product_indices = scan_contained_in_product_indices(inst, current_ingredient_indices);
    for (set<long long int>::iterator p = contained_in_product_indices.begin(); p != contained_in_product_indices.end(); ++p) {
      if (*p < SIZE(inst.products))
        current_ingredient_and_aliases.insert(inst.products.at(*p));
    }
  }
}

set<long long int> scan_contained_in_product_indices(const instruction& inst, set<long long int>& ingredient_indices) {
  set<reagent> selected_ingredients;
  const recipe& callee = get(Recipe, inst.operation);
  for (set<long long int>::iterator p = ingredient_indices.begin(); p != ingredient_indices.end(); ++p) {
    if (*p >= SIZE(callee.ingredients)) continue;  // optional immutable ingredient
    selected_ingredients.insert(callee.ingredients.at(*p));
  }
  set<long long int> result;
  for (long long int i = 0; i < SIZE(callee.products); ++i) {
    const reagent& current_product = callee.products.at(i);
    // TODO
    const string_tree* contained_in_name = property(current_product, "contained-in");
    if (contained_in_name && selected_ingredients.find(contained_in_name->value) != selected_ingredients.end())
      result.insert(i);
  }
  return result;
}

:(scenarios transform)
:(scenario immutability_infects_contained_in_variables)
% Hide_errors = true;
container test-list [
  next:address:shared:test-list
]
def main [
  local-scope
  p:address:shared:test-list <- new test-list:type
  foo p
]
def foo p:address:shared:test-list [  # p is immutable
  local-scope
  load-ingredients
  p2:address:shared:test-list <- test-next p  # p2 is immutable
  p3:address:address:shared:test-list <- get-address *p2, next:offset  # signal modification of p2
]
def test-next x:address:shared:test-list -> y:address:shared:test-list/contained-in:x [
  local-scope
  load-ingredients
  y <- get *x, next:offset
]
+error: foo: cannot modify p2 after instruction 'p3:address:address:shared:test-list <- get-address *p2, next:offset' because that would modify ingredient p which is not also a product of foo

:(code)
void check_immutable_ingredient_in_instruction(const instruction& inst, const set<reagent>& current_ingredient_and_aliases, const string& original_ingredient_name, const recipe& caller) {
  // first check if the instruction is directly modifying something it shouldn't
  for (long long int i = 0; i < SIZE(inst.products); ++i) {
    if (has_property(inst.products.at(i), "lookup")
        && current_ingredient_and_aliases.find(inst.products.at(i)) != current_ingredient_and_aliases.end()) {
      raise << maybe(caller.name) << "cannot modify " << inst.products.at(i).name << " in instruction '" << to_string(inst) << "' because it's not also a product of " << caller.name << '\n' << end();
      return;
    }
  }
  // check if there's any indirect modification going on
  set<long long int> current_ingredient_indices = ingredient_indices(inst, current_ingredient_and_aliases);
  if (current_ingredient_indices.empty()) return;  // ingredient not found in call
  for (set<long long int>::iterator p = current_ingredient_indices.begin(); p != current_ingredient_indices.end(); ++p) {
    const long long int current_ingredient_index = *p;
    reagent current_ingredient = inst.ingredients.at(current_ingredient_index);
    canonize_type(current_ingredient);
    const string& current_ingredient_name = current_ingredient.name;
    if (!contains_key(Recipe, inst.operation)) {
      // primitive recipe
      if (inst.operation == GET_ADDRESS || inst.operation == INDEX_ADDRESS) {
        // only reason to use get-address or index-address is to modify, so stop right there
        if (current_ingredient_name == original_ingredient_name)
          raise << maybe(caller.name) << "cannot modify ingredient " << current_ingredient_name << " after instruction '" << to_string(inst) << "' because it's not also a product of " << caller.name << '\n' << end();
        else
          raise << maybe(caller.name) << "cannot modify " << current_ingredient_name << " after instruction '" << to_string(inst) << "' because that would modify ingredient " << original_ingredient_name << " which is not also a product of " << caller.name << '\n' << end();
      }
    }
    else {
      // defined recipe
      if (!is_mu_address(current_ingredient)) return;  // making a copy is ok
      if (is_modified_in_recipe(inst.operation, current_ingredient_index, caller)) {
        if (current_ingredient_name == original_ingredient_name)
          raise << maybe(caller.name) << "cannot modify ingredient " << current_ingredient_name << " at instruction '" << to_string(inst) << "' because it's not also a product of " << caller.name << '\n' << end();
        else
          raise << maybe(caller.name) << "cannot modify " << current_ingredient_name << " after instruction '" << to_string(inst) << "' because that would modify ingredient " << original_ingredient_name << " which is not also a product of " << caller.name << '\n' << end();
      }
    }
  }
}

bool is_modified_in_recipe(recipe_ordinal r, long long int ingredient_index, const recipe& caller) {
  const recipe& callee = get(Recipe, r);
  if (!callee.has_header) {
    raise << maybe(caller.name) << "can't check mutability of ingredients in " << callee.name << " because it uses 'next-ingredient' directly, rather than a recipe header.\n" << end();
    return true;
  }
  if (ingredient_index >= SIZE(callee.ingredients)) return false;  // optional immutable ingredient
  return is_present_in_products(callee, callee.ingredients.at(ingredient_index).name);
}

bool is_present_in_products(const recipe& callee, const string& ingredient_name) {
  for (long long int i = 0; i < SIZE(callee.products); ++i) {
    if (callee.products.at(i).name == ingredient_name)
      return true;
  }
  return false;
}

bool is_present_in_ingredients(const recipe& callee, const string& ingredient_name) {
  for (long long int i = 0; i < SIZE(callee.ingredients); ++i) {
    if (callee.ingredients.at(i).name == ingredient_name)
      return true;
  }
  return false;
}

set<long long int> ingredient_indices(const instruction& inst, const set<reagent>& ingredient_names) {
  set<long long int> result;
  for (long long int i = 0; i < SIZE(inst.ingredients); ++i) {
    if (is_literal(inst.ingredients.at(i))) continue;
    if (ingredient_names.find(inst.ingredients.at(i)) != ingredient_names.end())
      result.insert(i);
  }
  return result;
}

//: Sometimes you want to pass in two addresses, one pointing inside the
//: other. For example, you want to delete a node from a linked list. You
//: can't pass both pointers back out, because if a caller tries to make both
//: identical then you can't tell which value will be written on the way out.
//:
//: Experimental solution: just tell mu that one points inside the other.
//: This way we can return just one pointer as high up as necessary to capture
//: all modifications performed by a recipe.
//:
//: We'll see if we end up wanting to abuse /contained-in for other reasons.

:(scenarios transform)
:(scenario can_modify_contained_in_addresses)
container test-list [
  next:address:shared:test-list
]
def main [
  local-scope
  p:address:shared:test-list <- new test-list:type
  foo p
]
def foo p:address:shared:test-list -> p:address:shared:test-list [
  local-scope
  load-ingredients
  p2:address:shared:test-list <- test-next p
  p <- test-remove p2, p
]
def test-next x:address:shared:test-list -> y:address:shared:test-list [
  local-scope
  load-ingredients
  y <- get *x, next:offset
]
def test-remove x:address:shared:test-list/contained-in:from, from:address:shared:test-list -> from:address:shared:test-list [
  local-scope
  load-ingredients
  x2:address:address:shared:test-list <- get-address *x, next:offset  # pretend modification
]
$error: 0

:(before "End Immutable Ingredients Special-cases")
if (has_property(current_ingredient, "contained-in")) {
  const string_tree* tmp = property(current_ingredient, "contained-in");
  if (tmp->left || tmp->right
      || !is_present_in_ingredients(caller, tmp->value)
      || !is_present_in_products(caller, tmp->value))
    raise << maybe(caller.name) << "contained-in can only point to another ingredient+product, but got " << to_string(property(current_ingredient, "contained-in")) << '\n' << end();
  continue;
}
