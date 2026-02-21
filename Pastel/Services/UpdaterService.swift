#if SPARKLE
import Sparkle
import Combine

@MainActor
final class UpdaterService: ObservableObject {
    let controller: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false
    private var cancellable: AnyCancellable?

    init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    func startUpdater() {
        do {
            try controller.updater.start()
        } catch {
            print("Failed to start Sparkle updater: \(error)")
        }
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
#endif
