:(scenario assert)
% Hide_warnings = true;
recipe main [
  assert 0:literal, [this is an assert in mu]
]
+warn: this is an assert in mu

:(before "End Primitive Recipe Declarations")
ASSERT,
:(before "End Primitive Recipe Numbers")
Recipe_number["assert"] = ASSERT;
:(before "End Primitive Recipe Implementations")
case ASSERT: {
  assert(SIZE(ingredients) == 2);
  assert(scalar(ingredients.at(0)));
  if (!ingredients.at(0).at(0)) {
    assert(isa_literal(current_instruction().ingredients.at(1)));
    raise << current_instruction().ingredients.at(1).name << '\n' << die();
  }
  break;
}
