import SwiftData
import SwiftUI

@main
struct H2027App: App {
    private let modelContainer: ModelContainer
    @AppStorage("appLanguage") private var appLanguageCode = AppLanguage.simplifiedChinese.rawValue

    init() {
        let schema = Schema([Medication.self, MedicationSchedule.self, DoseEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            modelContainer = container
            NotificationManager.shared.configure(modelContainer: container)
            WatchSyncManager.shared.configure(modelContainer: container)
        } catch {
            fatalError("Could not create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
            .environment(\.locale, AppLanguage(rawValue: appLanguageCode)?.locale ?? .current)
            .modelContainer(modelContainer)
    }
}
