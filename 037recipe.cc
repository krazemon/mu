//: So far we've been calling a fixed recipe in each instruction, but we'd
//: also like to make the recipe a variable, pass recipes to "higher-order"
//: recipes, return recipes from recipes and so on.

:(scenario call_literal_recipe)
recipe main [
  1:number <- call f:recipe, 34
]
recipe f [
  2:number <- next-ingredient
  reply 2:number
]
+mem: storing 34 in location 1

:(scenario call_variable)
recipe main [
  1:recipe-ordinal <- copy f:recipe
  2:number <- call 1:recipe-ordinal, 34
]
recipe f [
  3:number <- next-ingredient
  reply 3:number
]
+mem: storing 34 in location 2

:(before "End Mu Types Initialization")
// 'recipe' is a literal
Type_ordinal["recipe"] = 0;
// 'recipe-ordinal' is the literal that can store recipe literals
type_ordinal recipe_ordinal = Type_ordinal["recipe-ordinal"] = Next_type_ordinal++;
Type[recipe_ordinal].name = "recipe-ordinal";

:(before "End Reagent-parsing Exceptions")
if (!r.properties.at(0).second.empty() && r.properties.at(0).second.at(0) == "recipe") {
  r.set_value(Recipe_ordinal[r.name]);
  return;
}

:(before "End Primitive Recipe Declarations")
CALL,
:(before "End Primitive Recipe Numbers")
Recipe_ordinal["call"] = CALL;
:(before "End Primitive Recipe Checks")
case CALL: {
  if (inst.ingredients.empty()) {
    raise_error << maybe(Recipe[r].name) << "'call' requires at least one ingredient (the recipe to call)\n" << end();
    break;
  }
  if (!is_mu_scalar(inst.ingredients.at(0))) {
    raise_error << maybe(Recipe[r].name) << "first ingredient of 'call' should be a recipe, but got " << inst.ingredients.at(0).original_string << '\n' << end();
    break;
  }
  break;
}
:(before "End Primitive Recipe Implementations")
case CALL: {
  // Begin Call
  Current_routine->calls.push_front(call(ingredients.at(0).at(0)));
  ingredients.erase(ingredients.begin());  // drop the callee
  goto call_housekeeping;
}
