// Swift-only value types: no @objc, so Dart reaches them through bindsmith's
// generated wrapper (wrapper: auto).

/// A playback level. A struct, so swift2objc cannot represent it as-is.
public struct Volume {
  public var level: Int

  public init(level: Int) {
    self.level = level
  }

  /// Doubles the level.
  public func louder() -> Volume {
    Volume(level: level * 2)
  }

  public func label() -> String {
    "\(level)"
  }
}

/// Mixes volumes. The array parameter is what swift2objc drops.
public struct Mixer {
  public init() {}

  public func mix(volumes: [Volume]) -> Volume {
    Volume(level: volumes.reduce(0) { $0 + $1.level })
  }
}
