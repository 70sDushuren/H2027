import SwiftData
import SwiftUI

@main
struct H2027App: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([Medication.self, MedicationSchedule.self, DoseEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(modelContainer)
    }
}
