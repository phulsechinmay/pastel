import SwiftUI

@main
struct PastelApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("Pastel")
        } label: {
            Image(systemName: "clipboard")
        }
        .menuBarExtraStyle(.window)
    }
}
