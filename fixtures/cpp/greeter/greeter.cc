#include "greeter.h"

#include <stdexcept>

namespace greeter {

Greeter::Greeter(const std::string& prefix) : prefix_(prefix) {}

std::string Greeter::Greet(const std::string& name) const {
  if (name.empty()) {
    throw std::invalid_argument("name must not be empty");
  }
  const_cast<Greeter*>(this)->count_++;
  return prefix_ + ", " + name + "!";
}

void Greeter::SetPrefix(const std::string& prefix) { prefix_ = prefix; }

int Greeter::Count() const { return count_; }

int Greeter::Version() { return 3; }

std::vector<std::string> Greeter::GreetAll(
    const std::vector<std::string>& names) const {
  std::vector<std::string> out;
  out.reserve(names.size());
  for (const std::string& name : names) {
    out.push_back(Greet(name));
  }
  return out;
}

}  // namespace greeter
