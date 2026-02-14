import SwiftUI
import SwiftData
import CloudKit
import CoreData

@main
struct PastelApp: App {
    let modelContainer: ModelContainer
    @State private var appState: AppState

    init() {
        // DEBUG-only: Push SwiftData schema to CloudKit Development environment
        // Run once after model changes by adding -initializeCloudKitSchema to launch arguments
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-initializeCloudKitSchema") {
            do {
                try autoreleasepool {
                    let schemaConfig = ModelConfiguration()
                    let desc = NSPersistentStoreDescription(url: schemaConfig.url)
                    let opts = NSPersistentCloudKitContainerOptions(
                        containerIdentifier: "iCloud.app.pastel.Pastel"
                    )
                    desc.cloudKitContainerOptions = opts
                    desc.shouldAddStoreAsynchronously = false
                    if let mom = NSManagedObjectModel.makeManagedObjectModel(
                        for: [ClipboardItem.self, Label.self]
                    ) {
                        let ckContainer = NSPersistentCloudKitContainer(
                            name: "Pastel", managedObjectModel: mom
                        )
                        ckContainer.persistentStoreDescriptions = [desc]
                        ckContainer.loadPersistentStores { _, err in
                            if let err { fatalError("Schema init error: \(err)") }
                        }
                        try ckContainer.initializeCloudKitSchema()
                        if let store = ckContainer.persistentStoreCoordinator.persistentStores.first {
                            try ckContainer.persistentStoreCoordinator.remove(store)
                        }
                    }
                }
            } catch {
                print("CloudKit schema initialization failed: \(error)")
            }
        }
        #endif

        // Create the model container with conditional CloudKit sync
        let syncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")

        let config: ModelConfiguration
        if syncEnabled {
            config = ModelConfiguration(
                cloudKitDatabase: .private("iCloud.app.pastel.Pastel")
            )
        } else {
            config = ModelConfiguration(
                cloudKitDatabase: .none
            )
        }

        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: ClipboardItem.self, Label.self,
                configurations: config
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        self.modelContainer = container

        // Initialize AppState and wire up the clipboard monitor + panel
        let state = AppState()
        state.setup(modelContext: container.mainContext)
        state.setupPanel(modelContainer: container)
        state.modelContainer = container
        MigrationService.migrateLabelsIfNeeded(modelContext: container.mainContext)
        state.handleFirstLaunch()

        // // Auto-open panel on startup for development (commented out for glass testing)
        // if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        //     DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        //         state.togglePanel()
        //     }
        // }

        self._appState = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra {
            StatusPopoverView()
                .environment(appState)
                .modelContainer(modelContainer)
                .frame(width: 260)
        } label: {
            Image("MenuBarIcon")
                .resizable()
                .scaledToFit()
                .frame(height: 18)
        }
        .menuBarExtraStyle(.window)
    }
}
