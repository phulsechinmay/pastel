#if SPARKLE
import SwiftUI

struct CheckForUpdatesView: View {
    @ObservedObject var updaterService: UpdaterService

    var body: some View {
        Button(action: {
            updaterService.checkForUpdates()
        }) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Check for Updates...")
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(!updaterService.canCheckForUpdates)
    }
}
#endif
