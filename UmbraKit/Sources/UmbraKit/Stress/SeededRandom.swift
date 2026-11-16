/// A random number source that gives the same numbers every time for the
/// same seed (the "SplitMix64" recipe), so the stress feed is repeatable:
/// a test, a picture or a measurement sees exactly the same torrents.
struct SeededRandom: RandomNumberGenerator, Sendable {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// True with probability `p` (0 to 1).
  mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &self) < p }

  /// One of `items`, picked by their weights.
  mutating func weighted<T>(_ items: [(T, Int)]) -> T {
    var pick = Int.random(in: 0..<items.reduce(0) { $0 + $1.1 }, using: &self)
    for (item, weight) in items {
      if pick < weight { return item }
      pick -= weight
    }
    return items[items.count - 1].0
  }

  /// One of `items` (which mustn't be empty).
  mutating func pick<T>(_ items: [T]) -> T { items[Int.random(in: 0..<items.count, using: &self)] }

  /// A 40-character hex string, like a torrent's info hash.
  mutating func hash() -> String {
    (0..<5).map { _ in
      let text = String(next() & 0xFFFF_FFFF, radix: 16)
      return String(repeating: "0", count: 8 - text.count) + text
    }.joined()
  }
}
