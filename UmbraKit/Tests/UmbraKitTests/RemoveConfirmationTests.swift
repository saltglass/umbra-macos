import Foundation
import Testing

@testable import UmbraKit

@Suite("the Remove alert's words") struct RemoveConfirmationTests {
  private let gib: Int64 = 1 << 30

  @Test func nothingSelectedHasNoAlert() {
    #expect(RemoveConfirmation(TorrentSelection([])) == nil)
  }

  @Test func oneTorrentIsNamed() throws {
    let r = listRow(
      torrent("a1", name: "Made.Up.Film") {
        $0.size = 2 * gib
        $0.progress = 0.7
      })
    let c = try #require(RemoveConfirmation(TorrentSelection([r])))
    #expect(c.title == "Remove “Made.Up.Film”?")
    #expect(c.hashes == ["a1"])
    #expect(c.deleteFilesLabel == "Also delete the downloaded files (1.4 GB)")
    #expect(c.removeButton == "Remove")
    #expect(c.cancelButton == "Cancel")
  }

  @Test func severalAreCounted() throws {
    let rs = [
      listRow(
        torrent("a1") {
          $0.size = gib
          $0.progress = 1
        }),
      listRow(
        torrent("b2") {
          $0.size = gib
          $0.progress = 0.5
        }),
      listRow(
        torrent("c3") {
          $0.size = 2 * gib
          $0.progress = 1
        }),
    ]
    let c = try #require(RemoveConfirmation(TorrentSelection(rs)))
    #expect(c.title == "Remove 3 torrents?")
    #expect(c.hashes == ["a1", "b2", "c3"])
    #expect(c.deleteFilesLabel == "Also delete the downloaded files (3.5 GB)")
    #expect(c.message.contains("them"))
  }

  @Test func thePlainTextSaysTheFilesStay() throws {
    let c = try #require(RemoveConfirmation(TorrentSelection([listRow(torrent("a1"))])))
    #expect(c.message(deletingFiles: false).contains("files stay on your Mac"))
    #expect(!c.message(deletingFiles: false).contains("deleted"))
  }

  @Test func tickingTheBoxSaysPlainlyTheFilesAreDeletedForGood() throws {
    let c = try #require(RemoveConfirmation(TorrentSelection([listRow(torrent("a1"))])))
    let text = c.message(deletingFiles: true)
    #expect(text.contains("deletes its downloaded files for good"))
    #expect(text.contains("Trash"))
    #expect(!text.contains("stay"))
  }

  @Test func aTorrentWithNothingDownloadedShowsNoSize() throws {
    let c = try #require(
      RemoveConfirmation(TorrentSelection([listRow(torrent("a1") { $0.size = gib })])))
    #expect(c.deleteFilesLabel == "Also delete the downloaded files")
  }

  // MARK: A torrent made from the person's own files

  private func own(_ hash: String, name: String = "Holiday Photos") -> TorrentRow {
    listRow(
      torrent(hash, name: name) {
        $0.size = 2 * gib
        $0.progress = 1
        $0.madeFromOwnFiles = true
      })
  }

  @Test func anOrdinaryTorrentSaysNothingAboutOwnFiles() throws {
    let c = try #require(RemoveConfirmation(TorrentSelection([listRow(torrent("a1"))])))
    #expect(c.ownFilesCount == 0)
    #expect(!c.message(deletingFiles: true).contains("your own files"))
    #expect(c.removeButton(deletingFiles: true) == "Remove")
  }

  @Test func oneOwnTorrentSaysTheFilesAreTheOriginals() throws {
    let c = try #require(RemoveConfirmation(TorrentSelection([own("a1")])))
    #expect(c.ownFilesCount == 1)
    #expect(
      c.deleteFilesLabel
        == "Also delete its files (2.0 GB): these are your original files, not a download")
    let note = "“Holiday Photos” was made from your own files. Deleting them can't be undone."
    #expect(c.message(deletingFiles: false).hasSuffix(note))
    #expect(c.message(deletingFiles: true).hasSuffix(note))
    #expect(c.message(deletingFiles: false).contains("Its files stay on your Mac."))
    #expect(!c.message(deletingFiles: false).contains("downloaded"))
    #expect(c.message(deletingFiles: true).contains("deletes its files for good"))
  }

  @Test func theButtonSaysFilesAreDeletedOnlyWhenTheBoxIsTicked() throws {
    let c = try #require(RemoveConfirmation(TorrentSelection([own("a1")])))
    // Cancel stays the safe default; Remove alone while the box is off.
    #expect(c.cancelButton == "Cancel")
    #expect(c.removeButton(deletingFiles: false) == "Remove")
    #expect(c.removeButton(deletingFiles: true) == "Remove and Delete Files")
  }

  @Test func someOwnAmongSeveralAreCounted() throws {
    let rows = [own("a1"), listRow(torrent("b2")), own("c3", name: "Talk.mp4")]
    let c = try #require(RemoveConfirmation(TorrentSelection(rows)))
    #expect(c.ownFilesCount == 2)
    let note = "2 of these were made from your own files. Deleting those can't be undone."
    #expect(c.message(deletingFiles: false).hasSuffix(note))
    #expect(c.message(deletingFiles: true).hasSuffix(note))
    #expect(c.deleteFilesLabel == "Also delete their files (4.0 GB)")
    #expect(c.removeButton(deletingFiles: true) == "Remove and Delete Files")
  }

  @Test func severalAllOwnSayAll() throws {
    let c = try #require(RemoveConfirmation(TorrentSelection([own("a1"), own("b2")])))
    #expect(
      c.message(deletingFiles: false).hasSuffix(
        "All of these were made from your own files. Deleting them can't be undone."))
  }
}

@Suite("exported file names and places") struct TorrentFilesTests {
  @Test func namesBecomeTorrentFiles() {
    #expect(TorrentFiles.exportName(for: listRow(torrent("a1", name: "Film"))) == "Film.torrent")
  }

  @Test func slashesAndColonsBecomeDashes() {
    let r = listRow(torrent("a1", name: "A/B: C"))
    #expect(TorrentFiles.exportName(for: r) == "A-B- C.torrent")
  }

  @Test func aLeadingDotOrEmptyNameIsFixed() {
    #expect(TorrentFiles.exportName(for: listRow(torrent("a1", name: ""))) == "Torrent.torrent")
    #expect(TorrentFiles.exportName(for: listRow(torrent("a1", name: ".x"))) == "Torrent.x.torrent")
  }

  @Test func aVeryLongNameIsCut() {
    let name = String(repeating: "é", count: 300)
    #expect(TorrentFiles.exportName(for: listRow(torrent("a1", name: name))).utf8.count <= 255)
  }

  @Test func sameNamesGetANumber() {
    #expect(TorrentFiles.uniqueName("A.torrent", taken: []) == "A.torrent")
    #expect(TorrentFiles.uniqueName("A.torrent", taken: ["A.torrent"]) == "A 2.torrent")
    #expect(
      TorrentFiles.uniqueName("A.torrent", taken: ["A.torrent", "A 2.torrent"]) == "A 3.torrent")
  }

  @Test func filesAreWhereTheSaveFolderPutsThem() {
    let r = listRow(torrent("a1", name: "Film") { $0.savePath = "/Users/x/Downloads" })
    #expect(TorrentFiles.location(of: r).path == "/Users/x/Downloads/Film")
    #expect(TorrentFiles.folder(of: r).path == "/Users/x/Downloads")
  }
}
