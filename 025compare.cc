//: Comparison primitives

:(before "End Primitive Recipe Declarations")
EQUAL,
:(before "End Primitive Recipe Numbers")
Recipe_ordinal["equal"] = EQUAL;
:(before "End Primitive Recipe Implementations")
case EQUAL: {
  if (SIZE(ingredients) <= 1) {
    raise << current_recipe_name() << ": 'equal' needs at least two ingredients to compare in '" << current_instruction().to_string() << "'\n" << end();
    break;
  }
  vector<double>& exemplar = ingredients.at(0);
  bool result = true;
  for (long long int i = 1; i < SIZE(ingredients); ++i) {
    if (!equal(ingredients.at(i).begin(), ingredients.at(i).end(), exemplar.begin())) {
      result = false;
      break;
    }
  }
  products.resize(1);
  products.at(0).push_back(result);
  break;
}

:(scenario equal)
recipe main [
  1:number <- copy 34
  2:number <- copy 33
  3:number <- equal 1:number, 2:number
]
+mem: location 1 is 34
+mem: location 2 is 33
+mem: storing 0 in location 3

:(scenario equal_2)
recipe main [
  1:number <- copy 34
  2:number <- copy 34
  3:number <- equal 1:number, 2:number
]
+mem: location 1 is 34
+mem: location 2 is 34
+mem: storing 1 in location 3

:(scenario equal_multiple)
recipe main [
  1:number <- equal 34, 34, 34
]
+mem: storing 1 in location 1

:(scenario equal_multiple_2)
recipe main [
  1:number <- equal 34, 34, 35
]
+mem: storing 0 in location 1

:(before "End Primitive Recipe Declarations")
GREATER_THAN,
:(before "End Primitive Recipe Numbers")
Recipe_ordinal["greater-than"] = GREATER_THAN;
:(before "End Primitive Recipe Implementations")
case GREATER_THAN: {
  bool result = true;
  if (SIZE(ingredients) <= 1) {
    raise << current_recipe_name() << ": 'greater-than' needs at least two ingredients to compare in '" << current_instruction().to_string() << "'\n" << end();
    break;
  }
  for (long long int i = 0; i < SIZE(ingredients); ++i) {
    if (!scalar(ingredients.at(i))) {
      raise << current_recipe_name() << ": 'greater-than' can only compare numbers; got " << current_instruction().ingredients.at(i).original_string << '\n' << end();
      goto finish_greater_than;
    }
  }
  for (long long int i = /**/1; i < SIZE(ingredients); ++i) {
    if (ingredients.at(i-1).at(0) <= ingredients.at(i).at(0)) {
      result = false;
    }
  }
  finish_greater_than:
  products.resize(1);
  products.at(0).push_back(result);
  break;
}

:(scenario greater_than)
recipe main [
  1:number <- copy 34
  2:number <- copy 33
  3:boolean <- greater-than 1:number, 2:number
]
+mem: storing 1 in location 3

:(scenario greater_than_2)
recipe main [
  1:number <- copy 34
  2:number <- copy 34
  3:boolean <- greater-than 1:number, 2:number
]
+mem: storing 0 in location 3

:(scenario greater_than_multiple)
recipe main [
  1:boolean <- greater-than 36, 35, 34
]
+mem: storing 1 in location 1

:(scenario greater_than_multiple_2)
recipe main [
  1:boolean <- greater-than 36, 35, 35
]
+mem: storing 0 in location 1

:(before "End Primitive Recipe Declarations")
LESSER_THAN,
:(before "End Primitive Recipe Numbers")
Recipe_ordinal["lesser-than"] = LESSER_THAN;
:(before "End Primitive Recipe Implementations")
case LESSER_THAN: {
  bool result = true;
  if (SIZE(ingredients) <= 1) {
    raise << current_recipe_name() << ": 'lesser-than' needs at least two ingredients to compare in '" << current_instruction().to_string() << "'\n" << end();
    break;
  }
  for (long long int i = 0; i < SIZE(ingredients); ++i) {
    if (!scalar(ingredients.at(i))) {
      raise << current_recipe_name() << ": 'lesser-than' can only compare numbers; got " << current_instruction().ingredients.at(i).original_string << '\n' << end();
      goto finish_lesser_than;
    }
  }
  for (long long int i = /**/1; i < SIZE(ingredients); ++i) {
    if (ingredients.at(i-1).at(0) >= ingredients.at(i).at(0)) {
      result = false;
    }
  }
  finish_lesser_than:
  products.resize(1);
  products.at(0).push_back(result);
  break;
}

:(scenario lesser_than)
recipe main [
  1:number <- copy 32
  2:number <- copy 33
  3:boolean <- lesser-than 1:number, 2:number
]
+mem: storing 1 in location 3

:(scenario lesser_than_2)
recipe main [
  1:number <- copy 34
  2:number <- copy 33
  3:boolean <- lesser-than 1:number, 2:number
]
+mem: storing 0 in location 3

:(scenario lesser_than_multiple)
recipe main [
  1:boolean <- lesser-than 34, 35, 36
]
+mem: storing 1 in location 1

:(scenario lesser_than_multiple_2)
recipe main [
  1:boolean <- lesser-than 34, 35, 35
]
+mem: storing 0 in location 1

:(before "End Primitive Recipe Declarations")
GREATER_OR_EQUAL,
:(before "End Primitive Recipe Numbers")
Recipe_ordinal["greater-or-equal"] = GREATER_OR_EQUAL;
:(before "End Primitive Recipe Implementations")
case GREATER_OR_EQUAL: {
  bool result = true;
  if (SIZE(ingredients) <= 1) {
    raise << current_recipe_name() << ": 'greater-or-equal' needs at least two ingredients to compare in '" << current_instruction().to_string() << "'\n" << end();
    break;
  }
  for (long long int i = 0; i < SIZE(ingredients); ++i) {
    if (!scalar(ingredients.at(i))) {
      raise << current_recipe_name() << ": 'greater-or-equal' can only compare numbers; got " << current_instruction().ingredients.at(i).original_string << '\n' << end();
      goto finish_greater_or_equal;
    }
  }
  for (long long int i = /**/1; i < SIZE(ingredients); ++i) {
    if (ingredients.at(i-1).at(0) < ingredients.at(i).at(0)) {
      result = false;
    }
  }
  finish_greater_or_equal:
  products.resize(1);
  products.at(0).push_back(result);
  break;
}

:(scenario greater_or_equal)
recipe main [
  1:number <- copy 34
  2:number <- copy 33
  3:boolean <- greater-or-equal 1:number, 2:number
]
+mem: storing 1 in location 3

:(scenario greater_or_equal_2)
recipe main [
  1:number <- copy 34
  2:number <- copy 34
  3:boolean <- greater-or-equal 1:number, 2:number
]
+mem: storing 1 in location 3

:(scenario greater_or_equal_3)
recipe main [
  1:number <- copy 34
  2:number <- copy 35
  3:boolean <- greater-or-equal 1:number, 2:number
]
+mem: storing 0 in location 3

:(scenario greater_or_equal_multiple)
recipe main [
  1:boolean <- greater-or-equal 36, 35, 35
]
+mem: storing 1 in location 1

:(scenario greater_or_equal_multiple_2)
recipe main [
  1:boolean <- greater-or-equal 36, 35, 36
]
+mem: storing 0 in location 1

:(before "End Primitive Recipe Declarations")
LESSER_OR_EQUAL,
:(before "End Primitive Recipe Numbers")
Recipe_ordinal["lesser-or-equal"] = LESSER_OR_EQUAL;
:(before "End Primitive Recipe Implementations")
case LESSER_OR_EQUAL: {
  bool result = true;
  if (SIZE(ingredients) <= 1) {
    raise << current_recipe_name() << ": 'lesser-or-equal' needs at least two ingredients to compare in '" << current_instruction().to_string() << "'\n" << end();
    break;
  }
  for (long long int i = 0; i < SIZE(ingredients); ++i) {
    if (!scalar(ingredients.at(i))) {
      raise << current_recipe_name() << ": 'lesser-or-equal' can only compare numbers; got " << current_instruction().ingredients.at(i).original_string << '\n' << end();
      goto finish_lesser_or_equal;
    }
  }
  for (long long int i = /**/1; i < SIZE(ingredients); ++i) {
    if (ingredients.at(i-1).at(0) > ingredients.at(i).at(0)) {
      result = false;
    }
  }
  finish_lesser_or_equal:
  products.resize(1);
  products.at(0).push_back(result);
  break;
}

:(scenario lesser_or_equal)
recipe main [
  1:number <- copy 32
  2:number <- copy 33
  3:boolean <- lesser-or-equal 1:number, 2:number
]
+mem: storing 1 in location 3

:(scenario lesser_or_equal_2)
recipe main [
  1:number <- copy 33
  2:number <- copy 33
  3:boolean <- lesser-or-equal 1:number, 2:number
]
+mem: storing 1 in location 3

:(scenario lesser_or_equal_3)
recipe main [
  1:number <- copy 34
  2:number <- copy 33
  3:boolean <- lesser-or-equal 1:number, 2:number
]
+mem: storing 0 in location 3

:(scenario lesser_or_equal_multiple)
recipe main [
  1:boolean <- lesser-or-equal 34, 35, 35
]
+mem: storing 1 in location 1

:(scenario lesser_or_equal_multiple_2)
recipe main [
  1:boolean <- lesser-or-equal 34, 35, 34
]
+mem: storing 0 in location 1