//: Introduce a new transform to perform various checks in instructions before
//: we start running them. It'll be extensible, so that we can add checks for
//: new recipes as we extend 'run' to support them.
//:
//: Doing checking in a separate part complicates things, because the values
//: of variables in memory and the processor (current_recipe_name,
//: current_instruction) aren't available at checking time. If I had a more
//: sophisticated layer system I'd introduce the simpler version first and
//: transform it in a separate layer or set of layers.

:(before "End Checks")
Transform.push_back(check_instruction);  // idempotent

:(code)
void check_instruction(const recipe_ordinal r) {
  trace(9991, "transform") << "--- perform checks for recipe " << get(Recipe, r).name << end();
  map<string, vector<type_ordinal> > metadata;
  for (int i = 0; i < SIZE(get(Recipe, r).steps); ++i) {
    instruction& inst = get(Recipe, r).steps.at(i);
    if (inst.is_label) continue;
    switch (inst.operation) {
      // Primitive Recipe Checks
      case COPY: {
        if (SIZE(inst.products) != SIZE(inst.ingredients)) {
          raise << maybe(get(Recipe, r).name) << "ingredients and products should match in '" << to_original_string(inst) << "'\n" << end();
          break;
        }
        for (int i = 0; i < SIZE(inst.ingredients); ++i) {
          if (!types_coercible(inst.products.at(i), inst.ingredients.at(i))) {
            raise << maybe(get(Recipe, r).name) << "can't copy '" << inst.ingredients.at(i).original_string << "' to '" << inst.products.at(i).original_string << "'; types don't match\n" << end();
            goto finish_checking_instruction;
          }
        }
        break;
      }
      // End Primitive Recipe Checks
      default: {
        // Defined Recipe Checks
        // End Defined Recipe Checks
      }
    }
    finish_checking_instruction:;
  }
}

:(scenario copy_checks_reagent_count)
% Hide_errors = true;
def main [
  1:number <- copy 34, 35
]
+error: main: ingredients and products should match in '1:number <- copy 34, 35'

:(scenario write_scalar_to_array_disallowed)
% Hide_errors = true;
def main [
  1:array:number <- copy 34
]
+error: main: can't copy '34' to '1:array:number'; types don't match

:(scenario write_scalar_to_array_disallowed_2)
% Hide_errors = true;
def main [
  1:number, 2:array:number <- copy 34, 35
]
+error: main: can't copy '35' to '2:array:number'; types don't match

:(scenario write_scalar_to_address_disallowed)
% Hide_errors = true;
def main [
  1:address:number <- copy 34
]
+error: main: can't copy '34' to '1:address:number'; types don't match

:(scenario write_address_to_number_allowed)
def main [
  1:address:number <- copy 12/unsafe
  2:number <- copy 1:address:number
]
+mem: storing 12 in location 2
$error: 0

:(scenario write_boolean_to_number_allowed)
def main [
  1:boolean <- copy 1/true
  2:number <- copy 1:boolean
]
+mem: storing 1 in location 2
$error: 0

:(scenario write_number_to_boolean_allowed)
def main [
  1:number <- copy 34
  2:boolean <- copy 1:number
]
+mem: storing 34 in location 2
$error: 0

:(code)
// types_match with some leniency
bool types_coercible(const reagent& to, const reagent& from) {
  if (types_match(to, from)) return true;
  if (is_mu_address(from) && is_mu_number(to)) return true;
  if (is_mu_boolean(from) && is_mu_number(to)) return true;
  if (is_mu_number(from) && is_mu_boolean(to)) return true;
  // End types_coercible Special-cases
  return false;
}

bool types_match(const reagent& to, const reagent& from) {
  // to sidestep type-checking, use /unsafe in the source.
  // this will be highlighted in red inside vim. just for setting up some tests.
  if (is_unsafe(from)) return true;
  if (is_literal(from)) {
    if (is_mu_array(to)) return false;
    // End Matching Types For Literal(to)
    // allow writing 0 to any address
    if (is_mu_address(to)) return from.name == "0";
    if (!to.type) return false;
    if (to.type->value == get(Type_ordinal, "boolean"))
      return boolean_matches_literal(to, from);
    return size_of(to) == 1;  // literals are always scalars
  }
  return types_strictly_match(to, from);
}

bool boolean_matches_literal(const reagent& to, const reagent& from) {
  if (!is_literal(from)) return false;
  if (!to.type) return false;
  if (to.type->value != get(Type_ordinal, "boolean")) return false;
  return from.name == "0" || from.name == "1";
}

// copy arguments because later layers will want to make changes to them
// without perturbing the caller
bool types_strictly_match(reagent/*copy*/ to, reagent/*copy*/ from) {
  // End Preprocess types_strictly_match(reagent to, reagent from)
  if (is_literal(from) && to.type->value == get(Type_ordinal, "number")) return true;
  // to sidestep type-checking, use /unsafe in the source.
  // this will be highlighted in red inside vim. just for setting up some tests.
  if (is_unsafe(from)) return true;
  // '_' never raises type error
  if (is_dummy(to)) return true;
  if (!to.type) return !from.type;
  return types_strictly_match(to.type, from.type);
}

// two types match if the second begins like the first
// (trees perform the same check recursively on each subtree)
bool types_strictly_match(const type_tree* to, const type_tree* from) {
  if (!to) return true;
  if (!from) return to->value == 0;
  if (from->value == -1) return from->name == to->name;
  if (to->value != from->value) return false;
  return types_strictly_match(to->left, from->left) && types_strictly_match(to->right, from->right);
}

void test_unknown_type_does_not_match_unknown_type() {
  reagent a("a:foo");
  reagent b("b:bar");
  CHECK(!types_strictly_match(a, b));
}

void test_unknown_type_matches_itself() {
  reagent a("a:foo");
  reagent b("b:foo");
  CHECK(types_strictly_match(a, b));
}

bool is_unsafe(const reagent& r) {
  return has_property(r, "unsafe");
}

bool is_mu_array(reagent/*copy*/ r) {
  // End Preprocess is_mu_array(reagent r)
  if (!r.type) return false;
  if (is_literal(r)) return false;
  return r.type->value == get(Type_ordinal, "array");
}

bool is_mu_address(reagent/*copy*/ r) {
  // End Preprocess is_mu_address(reagent r)
  if (!r.type) return false;
  if (is_literal(r)) return false;
  return r.type->value == get(Type_ordinal, "address");
}

bool is_mu_boolean(reagent/*copy*/ r) {
  // End Preprocess is_mu_boolean(reagent r)
  if (!r.type) return false;
  if (is_literal(r)) return false;
  return r.type->value == get(Type_ordinal, "boolean");
}

bool is_mu_number(reagent/*copy*/ r) {
  // End Preprocess is_mu_number(reagent r)
  if (!r.type) return false;
  if (is_literal(r)) {
    if (!r.type) return false;
    return r.type->name == "literal-fractional-number"
        || r.type->name == "literal";
  }
  if (r.type->value == get(Type_ordinal, "character")) return true;  // permit arithmetic on unicode code points
  return r.type->value == get(Type_ordinal, "number");
}

bool is_mu_scalar(reagent/*copy*/ r) {
  if (!r.type) return false;
  if (is_literal(r))
    return !r.type || r.type->name != "literal-string";
  if (is_mu_array(r)) return false;
  return size_of(r) == 1;
}
