// A small C++ API, in the shapes a C shim has to flatten.
//
// bindsmith does not parse C++ (see plan.md §1). This header exists so the
// generated `extern "C"` shim has something real to compile against, and so
// the C driver has a header it can actually bind.
#ifndef BINDSMITH_FIXTURE_GREETER_H_
#define BINDSMITH_FIXTURE_GREETER_H_

#include <string>
#include <vector>

namespace greeter {

/// Greets people.
class Greeter {
 public:
  /// Greets with `prefix` in front of every name.
  explicit Greeter(const std::string& prefix);

  /// Greets `name`.
  ///
  /// Throws `std::invalid_argument` when `name` is empty, which is what an
  /// `extern "C"` boundary must not let escape.
  std::string Greet(const std::string& name) const;

  /// Changes the prefix.
  void SetPrefix(const std::string& prefix);

  /// How many greetings this instance has produced.
  int Count() const;

  /// The library version.
  static int Version();

  /// Greets everyone. `std::vector` has no C spelling at all.
  std::vector<std::string> GreetAll(const std::vector<std::string>& names) const;

 private:
  std::string prefix_;
  int count_ = 0;
};

}  // namespace greeter

#endif  // BINDSMITH_FIXTURE_GREETER_H_
