#if SPARKLE
import Sparkle
import Combine

/// User-facing Sparkle update check behavior modes.
///
/// Each case maps to a combination of the two `SPUUpdater` boolean
/// properties Sparkle persists in `UserDefaults`:
/// - `.manual`         → automaticallyChecksForUpdates = false, automaticallyDownloadsUpdates = false
/// - `.checkAndNotify` → automaticallyChecksForUpdates = true,  automaticallyDownloadsUpdates = false
/// - `.autoInstall`    → automaticallyChecksForUpdates = true,  automaticallyDownloadsUpdates = true
enum UpdateCheckMode: String, CaseIterable, Identifiable {
    case manual
    case checkAndNotify
    case autoInstall

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: return "Manual checks only"
        case .checkAndNotify: return "Automatically check and notify"
        case .autoInstall: return "Automatically download and install"
        }
    }
}

@MainActor
final class UpdaterService: ObservableObject {
    let controller: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false
    /// Mirrors `SPUUpdater.automaticallyChecksForUpdates` /
    /// `automaticallyDownloadsUpdates` so SwiftUI can bind to a single value.
    /// Persistence is handled by Sparkle (`SUEnableAutomaticChecks`,
    /// `SUAutomaticallyUpdate` keys in UserDefaults) — do NOT add
    /// a parallel `@AppStorage` for this.
    @Published var updateMode: UpdateCheckMode
    private var cancellable: AnyCancellable?

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller

        // Derive the initial mode from current Sparkle state so the UI
        // reflects whatever is already persisted in UserDefaults.
        let updater = controller.updater
        if !updater.automaticallyChecksForUpdates {
            self.updateMode = .manual
        } else if updater.automaticallyDownloadsUpdates {
            self.updateMode = .autoInstall
        } else {
            self.updateMode = .checkAndNotify
        }

        self.cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)

        // Start updater after initialization completes
        DispatchQueue.main.async { [weak self] in
            self?.startUpdater()
        }
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

    /// Apply a new update mode by writing through to Sparkle's runtime
    /// properties. Sparkle persists these to UserDefaults automatically.
    ///
    /// Called from a SwiftUI `Picker`'s custom `Binding.set` (NOT from a
    /// `didSet` on `updateMode` — that would create a setter loop with
    /// the binding).
    func applyUpdateMode(_ mode: UpdateCheckMode) {
        switch mode {
        case .manual:
            controller.updater.automaticallyChecksForUpdates = false
            controller.updater.automaticallyDownloadsUpdates = false
        case .checkAndNotify:
            controller.updater.automaticallyChecksForUpdates = true
            controller.updater.automaticallyDownloadsUpdates = false
        case .autoInstall:
            controller.updater.automaticallyChecksForUpdates = true
            controller.updater.automaticallyDownloadsUpdates = true
        }
        self.updateMode = mode
    }
}
#endif
