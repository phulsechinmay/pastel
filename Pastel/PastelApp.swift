import SwiftUI
import SwiftData

@main
struct PastelApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            StatusPopoverView()
                .environment(appState)
                .frame(width: 260, height: 160)
        } label: {
            Image(systemName: "clipboard")
        }
        .menuBarExtraStyle(.window)
        .modelContainer(for: ClipboardItem.self)
    }
}
