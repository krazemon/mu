//: Routines can be put in a 'waiting' state, from which it will be ready to
//: run again when a specific memory location changes its value. This is mu's
//: basic technique for orchestrating the order in which different routines
//: operate.

:(scenario wait_for_location)
recipe f1 [
  1:integer <- copy 0:literal
  start-running f2:recipe
  wait-for-location 1:integer
  # now wait for f2 to run and modify location 1 before using its value
  2:integer <- copy 1:integer
]
recipe f2 [
  1:integer <- copy 34:literal
]
# if we got the synchronization wrong we'd be storing 0 in location 2
+mem: storing 34 in location 2

//: define the new state that all routines can be in

:(before "End routine States")
WAITING,
:(before "End routine Fields")
// only if state == WAITING
index_t waiting_on_location;
int old_value_of_wating_location;
:(before "End routine Constructor")
waiting_on_location = old_value_of_wating_location = 0;

//: primitive recipe to put routines in that state

:(before "End Primitive Recipe Declarations")
WAIT_FOR_LOCATION,
:(before "End Primitive Recipe Numbers")
Recipe_number["wait-for-location"] = WAIT_FOR_LOCATION;
:(before "End Primitive Recipe Implementations")
case WAIT_FOR_LOCATION: {
  reagent loc = canonize(current_instruction().ingredients.at(0));
  Current_routine->state = WAITING;
  Current_routine->waiting_on_location = loc.value;
  Current_routine->old_value_of_wating_location = Memory[loc.value];
  trace("run") << "waiting for location " << loc.value << " to change from " << Memory[loc.value];
  break;
}

//: scheduler tweak to get routines out of that state

:(before "End Scheduler State Transitions")
for (index_t i = 0; i < Routines.size(); ++i) {
  if (Routines[i]->state != WAITING) continue;
  if (Memory[Routines[i]->waiting_on_location] &&
      Memory[Routines[i]->waiting_on_location] != Routines[i]->old_value_of_wating_location) {
    trace("schedule") << "waking up routine\n";
    Routines[i]->state = RUNNING;
    Routines[i]->waiting_on_location = Routines[i]->old_value_of_wating_location = 0;
  }
}

//: also allow waiting on a routine

:(scenario wait_for_routine)
recipe f1 [
  1:integer <- copy 0:literal
  2:integer/routine <- start-running f2:recipe
  wait-for-routine 2:integer/routine
  # now wait for f2 to run and modify location 1 before using its value
  3:integer <- copy 1:integer
]
recipe f2 [
  1:integer <- copy 34:literal
]
# if we got the synchronization wrong we'd be storing 0 in location 3
+mem: storing 34 in location 3

:(before "End routine Fields")
// only if state == WAITING
index_t waiting_on_routine;
:(before "End routine Constructor")
waiting_on_routine = 0;

:(before "End Primitive Recipe Declarations")
WAIT_FOR_ROUTINE,
:(before "End Primitive Recipe Numbers")
Recipe_number["wait-for-routine"] = WAIT_FOR_ROUTINE;
:(before "End Primitive Recipe Implementations")
case WAIT_FOR_ROUTINE: {
  reagent loc = canonize(current_instruction().ingredients.at(0));
  Current_routine->state = WAITING;
  Current_routine->waiting_on_routine = loc.value;
  trace("run") << "waiting for routine " << loc.value;
  break;
}

:(before "End Scheduler State Transitions")
for (index_t i = 0; i < Routines.size(); ++i) {
  if (Routines[i]->state != WAITING) continue;
  if (!Routines[i]->waiting_on_routine) continue;
  index_t id = Routines[i]->waiting_on_routine;
  assert(id != i);
  for (index_t j = 0; j < Routines.size(); ++j) {
    if (Routines[j]->id == id && Routines[j]->state != WAITING) {
      trace("schedule") << "waking up routine\n";
      Routines[i]->state = RUNNING;
      Routines[i]->waiting_on_routine = 0;
    }
  }
}

