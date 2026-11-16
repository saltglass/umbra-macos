import Foundation

extension SettingsGroupModel {
  /// Makes a change and waits until Umbra has answered it, for a sheet
  /// that must stay open if Umbra says no. Returns Umbra's refusal, or nil
  /// when the change was saved. The page goes back to what Umbra has when
  /// it refuses, exactly as for any other change.
  ///
  /// It cannot see inside the model's queue, so it watches `isSending`: a
  /// change is either on its way within a moment (and then done when
  /// `isSending` drops), or there was nothing to send. It gives up waiting
  /// after a few seconds and then reports what the model shows.
  @MainActor
  public func changeAndWait(
    _ edit: @escaping (inout Value) -> Void
  ) async -> UmbraError? {
    change(edit)
    var sawSending = false
    var quiet = 0
    for _ in 0..<200 {
      try? await Task.sleep(for: .milliseconds(25))
      if isSending {
        sawSending = true
        quiet = 0
        continue
      }
      quiet += 1
      // Finished, or (after a moment with nothing starting) never started.
      if sawSending || quiet >= 8 { break }
    }
    return refusal
  }
}
