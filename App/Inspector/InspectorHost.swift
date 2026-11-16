import SwiftUI
import UmbraKit

/// Makes and keeps the inspector's model, then shows the inspector. The
/// main window only has to say where the inspector goes.
struct InspectorHost: View {
  @State private var model: InspectorModel

  init(session: AppSession, window: MainWindowModel) {
    _model = State(
      initialValue: InspectorModel(window: window, actions: { session.actions }))
  }

  var body: some View {
    InspectorView(model: model)
  }
}
