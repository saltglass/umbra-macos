import Foundation
import UmbraAPI

/// A torrent's files as a folder tree, for the Files tab.
///
/// Umbra lists files flat, each with a "/"-separated path. This builds the
/// folders from those paths and works out, for every folder, the size and
/// progress of everything under it, whether its tick box is on, off or
/// mixed, and what a click on it should change. Umbra still decides what a
/// priority means; this only works out which files a click names.
///
/// A few thousand files is normal, and the list is fetched every few
/// seconds, so the tree keeps its shape between fetches: when only progress
/// or priorities moved, `updating(with:)` reuses the folders and just
/// works out the figures again.
public struct FileTree: Equatable, Sendable {
  public typealias File = Components.Schemas.TorrentFile
  public typealias Priority = Components.Schemas.FilePriority

  /// How a tick box reads: all of the files under it are wanted, none, or some.
  public enum Tick: Sendable, Equatable {
    case on, off, mixed
  }

  /// One line of the tree: a folder or a file.
  public struct Node: Identifiable, Equatable, Sendable {
    /// The full path: unique within a torrent, and the same from fetch to fetch.
    public let id: String
    public let name: String
    /// 0 for the top level.
    public let depth: Int
    public let isFolder: Bool
    /// How many files are under it (1 for a file).
    public let fileCount: Int
    /// Total bytes of the files under it.
    public let size: Int64
    /// Bytes downloaded and checked, over the same files.
    public let done: Int64
    public let tick: Tick
    /// The one priority all its files share; nil when they differ (a
    /// folder only). `.skip` when unticked.
    public let priority: Priority?

    public var progress: Double { size > 0 ? min(1, Double(done) / Double(size)) : 0 }
  }

  /// The tree in display order (folders first, then by name, each folder
  /// followed by what is in it), every folder included.
  public private(set) var nodes: [Node]

  /// The files as Umbra gave them.
  private var files: [File]
  /// What doesn't change while only progress and priorities do.
  private var shapes: [Shape]
  /// The files' positions in `files`, in display order. Everything under a
  /// folder is one run of this list, which is what `Shape.span` points at.
  private var order: [Int]

  private struct Shape: Equatable, Sendable {
    let id: String
    let name: String
    let depth: Int
    let isFolder: Bool
    /// Where the next thing that isn't inside this node starts in `nodes`.
    let subtreeEnd: Int
    let span: Range<Int>
  }

  public var isEmpty: Bool { files.isEmpty }

  /// The whole torrent in numbers, for the line above the tree.
  public struct Totals: Equatable, Sendable {
    public let fileCount: Int
    public let size: Int64
    /// Bytes in the files that are ticked.
    public let wantedSize: Int64
  }

  public var totals: Totals {
    Totals(
      fileCount: files.count, size: files.reduce(0) { $0 + $1.size },
      wantedSize: files.reduce(0) { $0 + ($1.priority == .skip ? 0 : $1.size) })
  }

  public init(files: [File] = []) {
    self.files = files
    let built = Self.build(files)
    shapes = built.shapes
    order = built.order
    nodes = Self.summarize(built.shapes, built.order, files)
  }

  /// The tree for a newer list of the same torrent. When the files and
  /// folders are unchanged this keeps the shape and only works out the
  /// figures again; when nothing changed at all it returns the tree as is.
  public func updating(with newFiles: [File]) -> FileTree {
    if newFiles == files { return self }
    guard sameShape(as: newFiles) else { return FileTree(files: newFiles) }
    var copy = self
    copy.files = newFiles
    copy.nodes = Self.summarize(shapes, order, newFiles)
    return copy
  }

  /// This tree as it will be once `changes` (file index to priority) have
  /// been made, so a click shows at once, before Umbra has answered.
  public func applying(_ changes: [Int: Priority]) -> FileTree {
    guard !changes.isEmpty else { return self }
    var changed = files
    for position in changed.indices {
      if let priority = changes[changed[position].index] { changed[position].priority = priority }
    }
    return updating(with: changed)
  }

  public static func == (lhs: FileTree, rhs: FileTree) -> Bool { lhs.files == rhs.files }

  // MARK: What a node shows

  /// The nodes to draw: all of them, minus what is inside the folders
  /// whose ids are in `collapsed`.
  public func visibleNodes(collapsed: Set<String>) -> [Node] {
    guard !collapsed.isEmpty else { return nodes }
    var shown: [Node] = []
    var at = 0
    while at < nodes.count {
      shown.append(nodes[at])
      at = nodes[at].isFolder && collapsed.contains(nodes[at].id) ? shapes[at].subtreeEnd : at + 1
    }
    return shown
  }

  // MARK: What a click changes

  /// The file indexes under a node (the node's own for a file).
  public func fileIndexes(under node: Node) -> [Int] {
    guard let at = position(of: node) else { return [] }
    return shapes[at].span.map { files[order[$0]].index }
  }

  /// What ticking (or unticking) a node's box changes. Ticking turns files
  /// that are skipped to Normal and leaves the ones already wanted as they
  /// are (a High file stays High); unticking skips them all. Files that
  /// need no change aren't named.
  public func changes(tick wanted: Bool, for node: Node) -> [Int: Priority] {
    var result: [Int: Priority] = [:]
    for file in files(under: node) {
      if wanted, file.priority == .skip {
        result[file.index] = .normal
      } else if !wanted, file.priority != .skip {
        result[file.index] = .skip
      }
    }
    return result
  }

  /// What choosing `priority` for a node changes: every file under it that
  /// doesn't have it already.
  public func changes(priority: Priority, for node: Node) -> [Int: Priority] {
    var result: [Int: Priority] = [:]
    for file in files(under: node) where file.priority != priority {
      result[file.index] = priority
    }
    return result
  }

  /// What a click on a node's tick box does, as `changes(tick:for:)`: a box
  /// that is on turns off; one that is off or mixed turns on.
  public func changesForClick(on node: Node) -> [Int: Priority] {
    changes(tick: node.tick != .on, for: node)
  }

  private func files(under node: Node) -> [File] {
    guard let at = position(of: node) else { return [] }
    return shapes[at].span.map { files[order[$0]] }
  }

  private func position(of node: Node) -> Int? {
    // Nodes are looked up by id; a click is rare, so a search is fine.
    nodes.firstIndex { $0.id == node.id }
  }

  // MARK: Building

  private func sameShape(as newFiles: [File]) -> Bool {
    guard newFiles.count == files.count else { return false }
    for (new, old) in zip(newFiles, files)
    where new.index != old.index || new.path != old.path || new.size != old.size {
      return false
    }
    return true
  }

  /// A folder or file while the tree is being made.
  private final class Pending {
    let name: String
    let id: String
    var children: [Pending] = []
    var byName: [String: Pending] = [:]
    /// Where the file is in the list, for a file.
    var filePosition: Int?
    init(name: String, id: String) {
      self.name = name
      self.id = id
    }
  }

  private static func build(_ files: [File]) -> (shapes: [Shape], order: [Int]) {
    let root = Pending(name: "", id: "")
    for (position, file) in files.enumerated() {
      var parts = file.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
      if parts.isEmpty { parts = [file.path.isEmpty ? "(unnamed)" : file.path] }
      var at = root
      var path = ""
      for (n, part) in parts.enumerated() {
        path += (n == 0 ? "" : "/") + part
        if let existing = at.byName[part] {
          at = existing
        } else {
          let next = Pending(name: part, id: path)
          at.byName[part] = next
          at.children.append(next)
          at = next
        }
      }
      at.filePosition = position
    }

    var shapes: [Shape] = []
    var order: [Int] = []
    func walk(_ node: Pending, depth: Int) {
      // Folders first, then by name the way Finder sorts ("2" before "10").
      let sorted = node.children.sorted { a, b in
        let aFolder = a.filePosition == nil
        let bFolder = b.filePosition == nil
        if aFolder != bFolder { return aFolder }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
      }
      for child in sorted {
        let at = shapes.count
        let start = order.count
        let isFolder = child.filePosition == nil
        // Placeholder, filled in once what is inside it is known.
        shapes.append(
          Shape(
            id: child.id, name: child.name, depth: depth, isFolder: isFolder, subtreeEnd: 0,
            span: 0..<0))
        if let position = child.filePosition { order.append(position) }
        walk(child, depth: depth + 1)
        let old = shapes[at]
        shapes[at] = Shape(
          id: old.id, name: old.name, depth: old.depth, isFolder: old.isFolder,
          subtreeEnd: shapes.count, span: start..<order.count)
      }
    }
    walk(root, depth: 0)
    return (shapes, order)
  }

  private static func summarize(_ shapes: [Shape], _ order: [Int], _ files: [File]) -> [Node] {
    shapes.map { shape in
      var size: Int64 = 0
      var done: Int64 = 0
      var wanted = 0
      var common: Priority?
      var differ = false
      for slot in shape.span {
        let file = files[order[slot]]
        size += file.size
        done += file.done
        if file.priority != .skip { wanted += 1 }
        if let common {
          if common != file.priority { differ = true }
        } else {
          common = file.priority
        }
      }
      let count = shape.span.count
      return Node(
        id: shape.id, name: shape.name, depth: shape.depth, isFolder: shape.isFolder,
        fileCount: count, size: size, done: done,
        tick: wanted == count ? .on : wanted == 0 ? .off : .mixed,
        priority: differ ? nil : common)
    }
  }
}
