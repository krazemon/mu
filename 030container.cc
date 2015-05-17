//: Containers contain a fixed number of elements of different types.

:(before "End Mu Types Initialization")
//: We'll use this container as a running example, with two number elements.
type_number point = Type_number["point"] = Next_type_number++;
Type[point].size = 2;
Type[point].kind = container;
Type[point].name = "point";
vector<type_number> i;
i.push_back(number);
Type[point].elements.push_back(i);
Type[point].elements.push_back(i);

//: Containers can be copied around with a single instruction just like
//: numbers, no matter how large they are.

:(scenario copy_multiple_locations)
recipe main [
  1:number <- copy 34:literal
  2:number <- copy 35:literal
  3:point <- copy 1:point
]
+run: ingredient 0 is 1
+mem: location 1 is 34
+mem: location 2 is 35
+mem: storing 34 in location 3
+mem: storing 35 in location 4

:(before "End Mu Types Initialization")
// A more complex container, containing another container as one of its
// elements.
type_number point_number = Type_number["point-number"] = Next_type_number++;
Type[point_number].size = 2;
Type[point_number].kind = container;
Type[point_number].name = "point-number";
vector<type_number> p2;
p2.push_back(point);
Type[point_number].elements.push_back(p2);
vector<type_number> i2;
i2.push_back(number);
Type[point_number].elements.push_back(i2);

:(scenario copy_handles_nested_container_elements)
recipe main [
  12:number <- copy 34:literal
  13:number <- copy 35:literal
  14:number <- copy 36:literal
  15:point-number <- copy 12:point-number
]
+mem: storing 36 in location 17

//: Containers can be checked for equality with a single instruction just like
//: numbers, no matter how large they are.

:(scenario compare_multiple_locations)
recipe main [
  1:number <- copy 34:literal  # first
  2:number <- copy 35:literal
  3:number <- copy 36:literal
  4:number <- copy 34:literal  # second
  5:number <- copy 35:literal
  6:number <- copy 36:literal
  7:boolean <- equal 1:point-number, 4:point-number
]
+mem: storing 1 in location 7

:(scenario compare_multiple_locations2)
recipe main [
  1:number <- copy 34:literal  # first
  2:number <- copy 35:literal
  3:number <- copy 36:literal
  4:number <- copy 34:literal  # second
  5:number <- copy 35:literal
  6:number <- copy 37:literal  # different
  7:boolean <- equal 1:point-number, 4:point-number
]
+mem: storing 0 in location 7

:(before "End size_of(types) Cases")
type_info t = Type[types.at(0)];
if (t.kind == container) {
  // size of a container is the sum of the sizes of its elements
  long long int result = 0;
  for (long long int i = 0; i < SIZE(t.elements); ++i) {
    result += size_of(t.elements.at(i));
  }
  return result;
}

//:: To access elements of a container, use 'get'
:(scenario get)
recipe main [
  12:number <- copy 34:literal
  13:number <- copy 35:literal
  15:number <- get 12:point, 1:offset
]
+run: instruction main/2
+run: ingredient 0 is 12
+run: ingredient 1 is 1
+run: address to copy is 13
+run: its type is 1
+mem: location 13 is 35
+run: product 0 is 15
+mem: storing 35 in location 15

:(before "End Primitive Recipe Declarations")
GET,
:(before "End Primitive Recipe Numbers")
Recipe_number["get"] = GET;
:(before "End Primitive Recipe Implementations")
case GET: {
  reagent base = current_instruction().ingredients.at(0);
  long long int base_address = base.value;
  type_number base_type = base.types.at(0);
  assert(Type[base_type].kind == container);
  assert(isa_literal(current_instruction().ingredients.at(1)));
  assert(scalar(ingredients.at(1)));
  long long int offset = ingredients.at(1).at(0);
  long long int src = base_address;
  for (long long int i = 0; i < offset; ++i) {
    src += size_of(Type[base_type].elements.at(i));
  }
  trace("run") << "address to copy is " << src;
  assert(Type[base_type].kind == container);
  assert(SIZE(Type[base_type].elements) > offset);
  type_number src_type = Type[base_type].elements.at(offset).at(0);
  trace("run") << "its type is " << src_type;
  reagent tmp;
  tmp.set_value(src);
  tmp.types.push_back(src_type);
  products.push_back(read_memory(tmp));
  break;
}

:(scenario get_handles_nested_container_elements)
recipe main [
  12:number <- copy 34:literal
  13:number <- copy 35:literal
  14:number <- copy 36:literal
  15:number <- get 12:point-number, 1:offset
]
+run: instruction main/2
+run: ingredient 0 is 12
+run: ingredient 1 is 1
+run: address to copy is 14
+run: its type is 1
+mem: location 14 is 36
+run: product 0 is 15
+mem: storing 36 in location 15

//:: To write to elements of containers, you need their address.

:(scenario get_address)
recipe main [
  12:number <- copy 34:literal
  13:number <- copy 35:literal
  15:address:number <- get-address 12:point, 1:offset
]
+run: instruction main/2
+run: ingredient 0 is 12
+run: ingredient 1 is 1
+run: address to copy is 13
+mem: storing 13 in location 15

:(before "End Primitive Recipe Declarations")
GET_ADDRESS,
:(before "End Primitive Recipe Numbers")
Recipe_number["get-address"] = GET_ADDRESS;
:(before "End Primitive Recipe Implementations")
case GET_ADDRESS: {
  reagent base = current_instruction().ingredients.at(0);
  long long int base_address = base.value;
  type_number base_type = base.types.at(0);
  assert(Type[base_type].kind == container);
  assert(isa_literal(current_instruction().ingredients.at(1)));
  assert(scalar(ingredients.at(1)));
  long long int offset = ingredients.at(1).at(0);
  long long int result = base_address;
  for (long long int i = 0; i < offset; ++i) {
    result += size_of(Type[base_type].elements.at(i));
  }
  trace("run") << "address to copy is " << result;
  products.resize(1);
  products.at(0).push_back(result);
  break;
}

//:: Allow containers to be defined in mu code.

:(scenarios load)
:(scenario container)
container foo [
  x:number
  y:number
]
+parse: reading container foo
+parse:   element name: x
+parse:   type: 1
+parse:   element name: y
+parse:   type: 1

:(before "End Command Handlers")
else if (command == "container") {
  insert_container(command, container, in);
}

:(code)
void insert_container(const string& command, kind_of_type kind, istream& in) {
  skip_whitespace(in);
  string name = next_word(in);
  trace("parse") << "reading " << command << ' ' << name;
//?   cout << name << '\n'; //? 2
//?   if (Type_number.find(name) != Type_number.end()) //? 1
//?     cerr << Type_number[name] << '\n'; //? 1
  if (Type_number.find(name) == Type_number.end()
      || Type_number[name] == 0) {
    Type_number[name] = Next_type_number++;
  }
  skip_bracket(in, "'container' must begin with '['");
  assert(Type.find(Type_number[name]) == Type.end());
  type_info& t = Type[Type_number[name]];
  recently_added_types.push_back(Type_number[name]);
  t.name = name;
  t.kind = kind;
  while (!in.eof()) {
    skip_whitespace_and_comments(in);
    string element = next_word(in);
    if (element == "]") break;
    istringstream inner(element);
    t.element_names.push_back(slurp_until(inner, ':'));
    trace("parse") << "  element name: " << t.element_names.back();
    vector<type_number> types;
    while (!inner.eof()) {
      string type_name = slurp_until(inner, ':');
      if (Type_number.find(type_name) == Type_number.end())
        raise << "unknown type " << type_name << '\n';
      types.push_back(Type_number[type_name]);
      trace("parse") << "  type: " << types.back();
    }
    t.elements.push_back(types);
  }
  assert(SIZE(t.elements) == SIZE(t.element_names));
  t.size = SIZE(t.elements);
}

//: ensure types created in one scenario don't leak outside it.
:(before "End Globals")
vector<type_number> recently_added_types;
:(before "End load_permanently")  //: for non-tests
recently_added_types.clear();
:(before "End Setup")  //: for tests
for (long long int i = 0; i < SIZE(recently_added_types); ++i) {
//?   cout << "erasing " << Type[recently_added_types.at(i)].name << '\n'; //? 1
  Type_number.erase(Type[recently_added_types.at(i)].name);
  Type.erase(recently_added_types.at(i));
}
recently_added_types.clear();
//: lastly, ensure scenarios are consistent by always starting them at the
//: same type number.
Next_type_number = 1000;
:(before "End Test Run Initialization")
assert(Next_type_number < 1000);
:(before "End Setup")
Next_type_number = 1000;

//:: helpers

:(code)
void skip_bracket(istream& in, string message) {
  skip_whitespace_and_comments(in);
  if (in.get() != '[')
    raise << message << '\n';
}
