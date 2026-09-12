// Fixture for the bindsmith Swift driver: an Objective-C representable class
// next to Swift-only shapes (a value type and a generic) that only exist
// through the wrapper swift2objc generates.

import Foundation

/// Greets people.
public class Greeter {
  /// The prefix put before every name.
  public var prefix: String

  /// The number of greetings so far.
  public private(set) var count: Int = 0

  public init(prefix: String) {
    self.prefix = prefix
  }

  /// Greets `name`.
  /// - Parameter name: The person to greet.
  public func greet(name: String) -> String {
    count += 1
    return "\(prefix), \(name)!"
  }

  /// Greets everyone in `names`, at `volume`.
  ///
  /// The array is what swift2objc cannot parse; `Volume` is a Swift struct
  /// that it *can* carry, so a bridge has to pass it as the wrapper.
  public func greetAll(names: [String], at volume: Volume) -> [String] {
    names.map { _ in greet(name: "\(volume.level)") }
  }

  /// Greets `name` after yielding.
  public func greetSlowly(name: String) async -> String {
    await Task.yield()
    return greet(name: name)
  }
}

/// A Swift value type: it has no Objective-C representation of its own.
public struct Volume {
  public var level: Int

  public init(level: Int) {
    self.level = level
  }

  /// Doubles the level.
  public func louder() -> Volume {
    Volume(level: level * 2)
  }
}

/// A Swift generic, which cannot cross into Objective-C at all.
public struct Box<T> {
  public var value: T

  public init(value: T) {
    self.value = value
  }
}
