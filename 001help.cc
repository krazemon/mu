//: Everything this project/binary supports.
//: This should give you a sense for what to look forward to in later layers.

:(before "End Commandline Parsing")
if (argc <= 1 || is_equal(argv[1], "--help")) {
  // this is the functionality later layers will provide
  // currently no automated tests for commandline arg parsing
  cerr << "To load files and run 'main':\n"
       << "  mu file1.mu file2.mu ...\n"
       << "To run all tests:\n"
       << "  mu test\n"
       << "To load files and then run all tests:\n"
       << "  mu test file1.mu file2.mu ...\n"
       << "To load all files with a numeric prefix in a directory:\n"
       << "  mu directory1\n"
       << "You can test directories just like files.\n"
       << "To pass ingredients to a mu program, provide them after '--':\n"
       << "  mu file_or_dir1 file_or_dir2 ... -- ingredient1 ingredient2 ...\n"
       << "\n"
       << "To browse a trace generated by a previous run:\n"
       << "  mu browse-trace file\n"
       ;
  return 0;
}

//:: Helper function used by the above fragment of code (and later layers too,
//:: who knows?).
//: The :(code) directive appends function definitions to the end of the
//: project. Regardless of where functions are defined, we can call them
//: anywhere we like as long as we format the function header in a specific
//: way: put it all on a single line without indent, end the line with ') {'
//: and no trailing whitespace. As long as functions uniformly start this
//: way, our makefile contains a little command to automatically generate
//: declarations for them.
:(code)
bool is_equal(char* s, const char* lit) {
  return strncmp(s, lit, strlen(lit)) == 0;
}

//: I'll throw some style conventions here for want of a better place for them.
//: As a rule I hate style guides. Do what you want, that's my motto. But since
//: we're dealing with C/C++, the one big thing we want to avoid is undefined
//: behavior. If a compiler ever encounters undefined behavior it can make
//: your program do anything it wants.
//:
//: For reference, my checklist of undefined behaviors to watch out for:
//:   out-of-bounds access
//:   uninitialized variables
//:   use after free
//:   dereferencing invalid pointers: null, a new of size 0, others
//:
//:   casting a large number to a type too small to hold it
//:
//:   integer overflow
//:   division by zero and other undefined expressions
//:   left-shift by negative count
//:   shifting values by more than or equal to the number of bits they contain
//:   bitwise operations on signed numbers
//:
//:   Converting pointers to types of different alignment requirements
//:     T* -> void* -> T*: defined
//:     T* -> U* -> T*: defined if non-function pointers and alignment requirements are same
//:     function pointers may be cast to other function pointers
//:
//:       Casting a numeric value into a value that can't be represented by the target type (either directly or via static_cast)
//:
//: To guard against these, some conventions:
//:
//: 0. Initialize all primitive variables in functions and constructors.
//:
//: 1. Minimize use of pointers and pointer arithmetic. Avoid 'new' and
//: 'delete' as far as possible. Rely on STL to perform memory management to
//: avoid use-after-free issues (and memory leaks).
//:
//: 2. Avoid naked arrays to avoid out-of-bounds access. Never use operator[]
//: except with map. Use at() with STL vectors and so on.
//:
//: 3. Valgrind all the things.
//:
//: 4. Avoid unsigned numbers. Not strictly an undefined-behavior issue, but
//: the extra range doesn't matter, and it's one less confusing category of
//: interaction gotchas to worry about.
//:
//: Corollary: don't use the size() method on containers, since it returns an
//: unsigned and that'll cause warnings about mixing signed and unsigned,
//: yadda-yadda. Instead use this macro below to perform an unsafe cast to
//: signed. We'll just give up immediately if a container's ever too large.
//: Basically, Mu is not concerned about this being a little slower than it
//: could be. (https://gist.github.com/rygorous/e0f055bfb74e3d5f0af20690759de5a7)
//:
//: Addendum to corollary: We're going to uniformly use int everywhere, to
//: indicate that we're oblivious to number size, and since Clang on 32-bit
//: platforms doesn't yet support multiplication over 64-bit integers, and
//: since multiplying two integers seems like a more common situation to end
//: up in than integer overflow.
:(before "End Includes")
#define SIZE(X) (assert((X).size() < (1LL<<(sizeof(int)*8-2))), static_cast<int>((X).size()))

//: 5. Integer overflow is guarded against at runtime using the -ftrapv flag
//: to the compiler, supported by Clang (GCC version only works sometimes:
//: http://stackoverflow.com/questions/20851061/how-to-make-gcc-ftrapv-work).
:(before "atexit(teardown)")
initialize_signal_handlers();  // not always necessary, but doesn't hurt
//? cerr << INT_MAX+1 << '\n';  // test overflow
//? assert(false);  // test SIGABRT
:(code)
// based on https://spin.atomicobject.com/2013/01/13/exceptions-stack-traces-c
void initialize_signal_handlers() {
  struct sigaction action;
  action.sa_sigaction = dump_and_exit;
  sigemptyset(&action.sa_mask);
  sigaction(SIGABRT, &action, NULL);  // assert() failure or integer overflow on linux (with -ftrapv)
  sigaction(SIGILL,  &action, NULL);  // integer overflow on OS X (with -ftrapv)
  sigaction(SIGFPE,  &action, NULL);  // floating-point overflow and underflow
}
void dump_and_exit(int sig, siginfo_t* siginfo, unused void* dummy) {
  switch (sig) {
    case SIGABRT:
      #ifndef __APPLE__
        cerr << "SIGABRT: might be an integer overflow if it wasn't an assert() failure\n";
        _Exit(1);
      #endif
      break;
    case SIGILL:
      #ifdef __APPLE__
        cerr << "SIGILL: most likely caused by integer overflow\n";
        _Exit(1);
      #endif
      break;
    case SIGFPE:
      switch(siginfo->si_code)
      {
        case FPE_INTDIV:
          cerr << "SIGFPE: (integer divide by zero)\n";
          break;
        case FPE_INTOVF:
          cerr << "SIGFPE: (integer overflow)\n";  // dormant; requires hardware support
          break;
        case FPE_FLTDIV:
          cerr << "SIGFPE: (floating-point divide by zero)\n";
          break;
        case FPE_FLTOVF:
          cerr << "SIGFPE: (floating-point overflow)\n";
          break;
        case FPE_FLTUND:
          cerr << "SIGFPE: (floating-point underflow)\n";
          break;
        case FPE_FLTRES:
          cerr << "SIGFPE: (floating-point inexact result)\n";
          break;
        case FPE_FLTINV:
          cerr << "SIGFPE: (floating-point invalid operation)\n";
          break;
        case FPE_FLTSUB:
          cerr << "SIGFPE: (subscript out of range)\n";
          break;
        default:
          cerr << "SIGFPE: arithmetic exception\n";
          break;
      }
      _Exit(1);
    default:
      break;
  }
}
:(before "End Includes")
#include <signal.h>

//: 6. Map's operator[] being non-const is fucking evil.
:(before "Globals")  // can't generate prototypes for these
// from http://stackoverflow.com/questions/152643/idiomatic-c-for-reading-from-a-const-map
template<typename T> typename T::mapped_type& get(T& map, typename T::key_type const& key) {
  typename T::iterator iter(map.find(key));
  assert(iter != map.end());
  return iter->second;
}
template<typename T> typename T::mapped_type const& get(const T& map, typename T::key_type const& key) {
  typename T::const_iterator iter(map.find(key));
  assert(iter != map.end());
  return iter->second;
}
template<typename T> typename T::mapped_type const& put(T& map, typename T::key_type const& key, typename T::mapped_type const& value) {
  map[key] = value;
  return map[key];
}
template<typename T> bool contains_key(T& map, typename T::key_type const& key) {
  return map.find(key) != map.end();
}
template<typename T> typename T::mapped_type& get_or_insert(T& map, typename T::key_type const& key) {
  return map[key];
}
//: The contract: any container that relies on get_or_insert should never call
//: contains_key.

//: 7. istreams are a royal pain in the arse. You have to be careful about
//: what subclass you try to putback into. You have to watch out for the pesky
//: failbit and badbit. Just avoid eof() and use this helper instead.
:(code)
bool has_data(istream& in) {
  return in && !in.eof();
}

:(before "End Includes")
#include <assert.h>

#include <iostream>
using std::istream;
using std::ostream;
using std::iostream;
using std::cin;
using std::cout;
using std::cerr;
#include <iomanip>

#include <cstring>
#include <string>
using std::string;
