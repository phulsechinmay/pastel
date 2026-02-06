import SwiftUI
import SwiftData

@main
struct PastelApp: App {
    let modelContainer: ModelContainer
    @State private var appState: AppState

    init() {
        // Create the model container eagerly so we can pass its context to AppState
        let container: ModelContainer
        do {
            container = try ModelContainer(for: ClipboardItem.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        self.modelContainer = container

        // Initialize AppState and wire up the clipboard monitor + panel
        let state = AppState()
        state.setup(modelContext: container.mainContext)
        state.setupPanel(modelContainer: container)
        self._appState = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra {
            StatusPopoverView()
                .environment(appState)
                .modelContainer(modelContainer)
                .frame(width: 260, height: 160)
        } label: {
            Image(systemName: "clipboard")
        }
        .menuBarExtraStyle(.window)
    }
}
