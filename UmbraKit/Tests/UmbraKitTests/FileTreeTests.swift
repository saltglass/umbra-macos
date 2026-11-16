import Testing
import UmbraAPI

@testable import UmbraKit

@Suite("the file tree") struct FileTreeTests {
  typealias Priority = Components.Schemas.FilePriority

  /// A season: two episodes and a subtitles folder with one file, all in one top folder.
  func season() -> FileTree {
    FileTree(files: [
      Sample.file(0, "Show/ep2.mkv", size: 3000, done: 1500, .normal),
      Sample.file(1, "Show/ep10.mkv", size: 1000, done: 0, .skip),
      Sample.file(2, "Show/Subs/ep2.srt", size: 10, done: 10, .high),
      Sample.file(3, "Show/Subs/ep10.srt", size: 20, done: 0, .high),
    ])
  }

  func node(_ id: String, in tree: FileTree) -> FileTree.Node {
    tree.nodes.first { $0.id == id }!
  }

  @Test("nests files in folders, folders first, then by name the way Finder does")
  func nesting() {
    let tree = season()
    #expect(
      tree.nodes.map(\.id) == [
        "Show", "Show/Subs", "Show/Subs/ep2.srt", "Show/Subs/ep10.srt", "Show/ep2.mkv",
        "Show/ep10.mkv",
      ])
    #expect(tree.nodes.map(\.depth) == [0, 1, 2, 2, 1, 1])
    #expect(tree.nodes.map(\.isFolder) == [true, true, false, false, false, false])
    #expect(node("Show/Subs/ep2.srt", in: tree).name == "ep2.srt")
  }

  @Test("sums size and progress for each folder") func sums() {
    let tree = season()
    let top = node("Show", in: tree)
    #expect(top.size == 4030)
    #expect(top.done == 1510)
    #expect(top.fileCount == 4)
    #expect(abs(top.progress - 1510.0 / 4030.0) < 1e-9)
    let subs = node("Show/Subs", in: tree)
    #expect(subs.size == 30)
    #expect(subs.done == 10)
    #expect(subs.fileCount == 2)
  }

  @Test("a folder's tick is on, off or mixed by its files") func ticks() {
    let tree = season()
    #expect(node("Show", in: tree).tick == .mixed)
    #expect(node("Show/Subs", in: tree).tick == .on)
    #expect(node("Show/ep2.mkv", in: tree).tick == .on)
    #expect(node("Show/ep10.mkv", in: tree).tick == .off)
    let none = FileTree(files: [Sample.file(0, "A/x", .skip), Sample.file(1, "A/y", .skip)])
    #expect(node("A", in: none).tick == .off)
  }

  @Test("a folder shows a priority only when all its files share it") func priorities() {
    let tree = season()
    #expect(node("Show/Subs", in: tree).priority == .high)
    #expect(node("Show", in: tree).priority == nil)
    #expect(node("Show/ep10.mkv", in: tree).priority == .skip)
  }

  @Test("ticking a folder turns skipped files to Normal and leaves the rest") func tickingOn() {
    let tree = season()
    // Show: ep10 is the only skipped file; the High subtitles stay High.
    #expect(tree.changes(tick: true, for: node("Show", in: tree)) == [1: .normal])
    // Clicking a mixed box ticks it.
    #expect(tree.changesForClick(on: node("Show", in: tree)) == [1: .normal])
  }

  @Test("unticking a folder skips every file under it") func tickingOff() {
    let tree = season()
    #expect(
      tree.changes(tick: false, for: node("Show/Subs", in: tree)) == [2: .skip, 3: .skip])
    // Clicking a box that is on unticks it.
    #expect(
      tree.changesForClick(on: node("Show/Subs", in: tree)) == [2: .skip, 3: .skip])
    // Files already skipped aren't named.
    #expect(
      tree.changes(tick: false, for: node("Show", in: tree)) == [0: .skip, 2: .skip, 3: .skip])
  }

  @Test("choosing a priority for a folder changes the files that differ") func choosing() {
    let tree = season()
    #expect(
      tree.changes(priority: .high, for: node("Show", in: tree)) == [0: .high, 1: .high])
    #expect(tree.changes(priority: .high, for: node("Show/Subs", in: tree)).isEmpty)
  }

  @Test("a single-file torrent is one file at the top, with no folder") func singleFile() {
    let tree = FileTree(files: [Sample.file(0, "movie.mkv", size: 700, done: 700)])
    #expect(tree.nodes.count == 1)
    let only = tree.nodes[0]
    #expect(!only.isFolder)
    #expect(only.depth == 0)
    #expect(only.progress == 1)
    #expect(tree.changes(tick: false, for: only) == [0: .skip])
    #expect(tree.totals == .init(fileCount: 1, size: 700, wantedSize: 700))
  }

  @Test("no files (a magnet without its details) is an empty tree") func empty() {
    let tree = FileTree(files: [])
    #expect(tree.isEmpty)
    #expect(tree.nodes.isEmpty)
    #expect(tree.visibleNodes(collapsed: ["x"]).isEmpty)
  }

  @Test("a closed folder hides what is inside it") func collapsing() {
    let tree = season()
    #expect(tree.visibleNodes(collapsed: []).count == 6)
    #expect(
      tree.visibleNodes(collapsed: ["Show/Subs"]).map(\.id) == [
        "Show", "Show/Subs", "Show/ep2.mkv", "Show/ep10.mkv",
      ])
    #expect(tree.visibleNodes(collapsed: ["Show"]).map(\.id) == ["Show"])
    // Closing a file's id does nothing.
    #expect(tree.visibleNodes(collapsed: ["Show/ep2.mkv"]).count == 6)
  }

  @Test("tells which file indexes are under a node") func indexes() {
    let tree = season()
    #expect(tree.fileIndexes(under: node("Show/Subs", in: tree)) == [2, 3])
    #expect(tree.fileIndexes(under: node("Show", in: tree)) == [2, 3, 0, 1])
    #expect(tree.fileIndexes(under: node("Show/ep10.mkv", in: tree)) == [1])
  }

  @Test("totals count what is ticked") func totals() {
    #expect(season().totals == .init(fileCount: 4, size: 4030, wantedSize: 3030))
  }

  @Test("an update with only new progress keeps the shape and changes the figures")
  func updatingKeepsShape() {
    let tree = season()
    var files = [
      Sample.file(0, "Show/ep2.mkv", size: 3000, done: 3000, .normal),
      Sample.file(1, "Show/ep10.mkv", size: 1000, done: 0, .skip),
      Sample.file(2, "Show/Subs/ep2.srt", size: 10, done: 10, .high),
      Sample.file(3, "Show/Subs/ep10.srt", size: 20, done: 20, .high),
    ]
    let newer = tree.updating(with: files)
    #expect(newer.nodes.map(\.id) == tree.nodes.map(\.id))
    #expect(node("Show", in: newer).done == 4030 - 1000)
    // The very same list again is the very same tree.
    #expect(newer.updating(with: files) == newer)
    // A new file means a new shape.
    files.append(Sample.file(4, "Show/extra.txt"))
    #expect(newer.updating(with: files).nodes.count == tree.nodes.count + 1)
  }

  @Test("applying a change shows it before Umbra answers") func applying() {
    let tree = season()
    let after = tree.applying([1: .normal])
    #expect(node("Show/ep10.mkv", in: after).tick == .on)
    #expect(node("Show", in: after).tick == .on)
    #expect(node("Show/ep10.mkv", in: tree).tick == .off)
    #expect(tree.applying([:]) == tree)
  }

  @Test("a few thousand files build and update quickly and keep their order") func big() {
    var files: [FileTree.File] = []
    for folder in 0..<50 {
      for n in 0..<80 {
        files.append(
          Sample.file(folder * 80 + n, "Big/d\(folder)/f\(n).bin", size: 1000, done: Int64(n)))
      }
    }
    let tree = FileTree(files: files)
    #expect(tree.nodes.count == 1 + 50 + 4000)
    #expect(node("Big", in: tree).size == 4_000_000)
    #expect(tree.nodes[1].id == "Big/d0")
    #expect(tree.nodes[2].id == "Big/d0/f0.bin")
    #expect(tree.nodes[3].id == "Big/d0/f1.bin")
    #expect(tree.visibleNodes(collapsed: ["Big/d0"]).count == 1 + 50 + 3920)
  }
}
