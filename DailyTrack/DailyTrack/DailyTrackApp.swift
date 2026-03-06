import SwiftUI
import SwiftData

@main
struct DailyTrackApp: App {
    let modelContainer: ModelContainer
    @State private var syncManager = SyncManager()

    init() {
        // Migrate existing store to App Group container if needed
        AppGroupContainer.migrateExistingStoreIfNeeded()

        do {
            let schema = Schema([TaskDefinition.self, DailyEntry.self])
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .identifier(AppGroupContainer.appGroupIdentifier)
            )
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Seed initial tasks on first launch
        let context = modelContainer.mainContext
        SeedData.seedIfNeeded(context: context)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(syncManager)
                .task {
                    let context = modelContainer.mainContext
                    await syncManager.sync(context: context)
                }
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .defaultSize(width: 900, height: 700)
        #endif
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            DailyView()
                .tabItem {
                    Label(String(localized: "Today"), systemImage: "checkmark.circle")
                }

            HistoryView()
                .tabItem {
                    Label(String(localized: "History"), systemImage: "chart.line.uptrend.xyaxis")
                }

            SettingsView()
                .tabItem {
                    Label(String(localized: "Settings"), systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TaskDefinition.self, DailyEntry.self], inMemory: true)
        .environment(SyncManager())
}
