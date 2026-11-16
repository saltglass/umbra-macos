import Foundation
import UmbraAPI

/// What the main window does to torrents beyond the plain actions in
/// `MainWindowModel.swift`: the menu, category and tags, Remove, copying,
/// exporting and slow mode. Umbra decides everything; this only asks, and
/// keeps any refusal in `actionFailure` for an alert.
extension MainWindowModel {
  // MARK: The selection and the menu

  /// The selected torrents.
  public var selectedRows: [TorrentRow] {
    visibleRows.filter { selection.contains($0.id) }
  }

  /// The selected torrents and what can be asked of them.
  public var selectedTorrents: TorrentSelection { TorrentSelection(selectedRows) }

  /// The menu for these torrents (a right-click) or, with none named, for
  /// the selection (the menu bar). `connected` is false while Umbra isn't running.
  public func torrentMenu(for hashes: Set<String>? = nil, connected: Bool) -> TorrentMenu {
    let rows =
      hashes.map { chosen in visibleRows.filter { chosen.contains($0.id) } } ?? selectedRows
    return TorrentMenu(
      TorrentMenuContext(
        selection: TorrentSelection(rows),
        categories: definedCategories + counts.categories.keys, tags: Array(counts.tags.keys),
        connected: connected, slowMode: slowMode))
  }

  /// Whether the toolbar's Pause button can act now.
  public func canPause(with actions: TorrentActions?) -> Bool {
    actions != nil && selectedTorrents.canPause
  }

  /// Whether the toolbar's Resume button can act now.
  public func canResume(with actions: TorrentActions?) -> Bool {
    actions != nil && selectedTorrents.canResume
  }

  /// Space in the list: pauses what runs, otherwise resumes. False if
  /// there was nothing to do (so the key goes on to AppKit).
  public func spaceBar(using actions: TorrentActions?) -> Bool {
    guard actions != nil, let action = selectedTorrents.spaceAction else { return false }
    Task { await perform(action, using: actions) }
    return true
  }

  // MARK: Categories

  /// Asks Umbra which categories are set up (Settings → Downloads). A
  /// failure keeps the list as it was: the menu is still usable.
  public func refreshCategories(using actions: TorrentActions?) async {
    guard let actions, let names = try? await actions.categoryNames() else { return }
    if names != definedCategories { definedCategories = names }
  }

  /// Puts the selected torrents in a category ("" takes the category away).
  public func setCategory(_ category: String, using actions: TorrentActions?) async {
    let hashes = selectedHashes
    guard let actions, !hashes.isEmpty else { return }
    do {
      try await actions.setCategory(category, for: hashes)
    } catch {
      actionFailure = ActionFailure(
        verb: "change the category of", count: hashes.count, message: error.message)
    }
  }

  // MARK: Tags

  /// Gives the selected torrents a tag, or takes it away.
  public func changeTag(_ tag: String, add: Bool, using actions: TorrentActions?) async {
    let name = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    let hashes = selectedHashes
    guard let actions, !hashes.isEmpty, !name.isEmpty else { return }
    do {
      try await actions.changeTags(
        add: add ? [name] : [], remove: add ? [] : [name], for: hashes)
    } catch {
      actionFailure = ActionFailure(
        verb: "change the tags of", count: hashes.count, message: error.message)
    }
  }

  // MARK: Move data

  /// The folder the first selected torrent is saved in: where the folder
  /// chooser for "Move Data To…" starts.
  public var firstSaveFolder: String { selectedRows.first?.savePath ?? "" }

  /// Asks Umbra to move the files of the named torrents to `folder`. Umbra
  /// moves them in the background (the list shows "Moving"); a refusal is
  /// kept in `actionFailure` in Umbra's words.
  public func move(_ hashes: [String], to folder: String, using actions: TorrentActions?) async {
    guard let actions, !hashes.isEmpty else { return }
    do {
      try await actions.move(hashes, to: folder)
    } catch {
      actionFailure = ActionFailure(
        verb: "move the files of", count: hashes.count, message: error.message)
    }
  }

  // MARK: Limits

  /// Opens the Limits sheet for the selection.
  public func showLimits() {
    let rows = selectedRows
    guard !rows.isEmpty else { return }
    limitsRequest = LimitsRequest(rows: rows)
  }

  /// A Limits sheet saved: the inspector reads the limits again.
  public func limitsSaved() { limitsSaves += 1 }

  // MARK: Remove

  /// The words of the Remove alert for the selection; nil with nothing selected.
  public func removeConfirmation() -> RemoveConfirmation? {
    RemoveConfirmation(selectedTorrents)
  }

  /// Removes what the alert named. Call only after the person pressed
  /// Remove; `deleteFiles` is their tick box (Umbra then deletes the files).
  public func remove(
    _ confirmation: RemoveConfirmation, deleteFiles: Bool, using actions: TorrentActions?
  ) async {
    guard let actions else { return }
    do {
      try await actions.remove(confirmation.hashes, deleteFiles: deleteFiles)
    } catch {
      actionFailure = ActionFailure(
        verb: "remove", count: confirmation.hashes.count, message: error.message)
    }
  }

  // MARK: Copying and exporting

  /// What can be copied to the pasteboard.
  public enum CopyKind: Sendable { case magnetLinks, infoHashes }

  /// The text to copy for the selection, one per line; nil if Umbra
  /// refused (the alert is then set up) or nothing is selected.
  public func copyText(_ kind: CopyKind, using actions: TorrentActions?) async -> String? {
    let hashes = selectedHashes
    guard let actions, !hashes.isEmpty else { return nil }
    switch kind {
    case .infoHashes:
      return hashes.joined(separator: "\n")
    case .magnetLinks:
      do {
        var links: [String] = []
        for hash in hashes { links.append(try await actions.magnetLink(of: hash)) }
        return links.joined(separator: "\n")
      } catch {
        actionFailure = ActionFailure(
          verb: "copy the magnet link of", count: hashes.count, message: error.message)
        return nil
      }
    }
  }

  /// Saves each selected torrent's .torrent file. With one torrent,
  /// `destination` is the file to write; with several, a folder, and each
  /// file is named after its torrent. Returns whether everything was saved.
  @discardableResult
  public func exportTorrents(to destination: URL, using actions: TorrentActions?) async -> Bool {
    let rows = selectedRows
    guard let actions, !rows.isEmpty else { return false }
    do {
      if rows.count == 1 {
        try await actions.torrentFile(of: rows[0].id).write(to: destination, options: .atomic)
      } else {
        var taken = Set(
          (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? [])
        for row in rows {
          let name = TorrentFiles.uniqueName(TorrentFiles.exportName(for: row), taken: taken)
          taken.insert(name)
          let data = try await actions.torrentFile(of: row.id)
          try data.write(to: destination.appending(path: name), options: .atomic)
        }
      }
      return true
    } catch let error as UmbraError {
      actionFailure = ActionFailure(
        verb: "export the .torrent file of", count: rows.count, message: error.message)
    } catch {
      // Writing to the chosen place failed (no permission, disk full...).
      actionFailure = ActionFailure(
        verb: "save the .torrent file of", count: rows.count,
        message: error.localizedDescription)
    }
    return false
  }

  // MARK: Slow mode

  /// Whether slow mode is on. The live feed carries it, so a change made
  /// anywhere (Settings, the web page, a schedule) shows here too; a
  /// switch just made shows at once, ahead of the next totals.
  public var slowMode: Bool {
    let transfer = store.transfer
    if let setting = slowModeSetting, setting.base == transfer { return setting.value }
    return transfer?.slowMode ?? false
  }

  /// Turns slow mode on or off. A refusal is kept in `actionFailure`.
  public func setSlowMode(_ on: Bool, using actions: TorrentActions?) async {
    if let error = await applySlowMode(on, using: actions) {
      actionFailure = ActionFailure(
        title: "Couldn't turn slow mode \(on ? "on" : "off")", message: error.message)
    }
  }

  /// Turns slow mode on or off and returns Umbra's refusal, if any, for a
  /// caller that shows it its own way (the menu bar panel).
  func applySlowMode(_ on: Bool, using actions: TorrentActions?) async -> UmbraError? {
    guard let actions else { return nil }
    do {
      let stored = try await actions.setSlowMode(on)
      slowModeSetting = (stored.slowMode, store.transfer)
      return nil
    } catch {
      return error
    }
  }
}
