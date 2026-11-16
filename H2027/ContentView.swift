import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("今日", systemImage: "sun.max.fill") { TodayView() }
            Tab("药品", systemImage: "pills.fill") { MedicationListView() }
            Tab("记录", systemImage: "list.bullet.clipboard.fill") { DoseHistoryView() }
            Tab("设置", systemImage: "gearshape.fill") { SettingsView() }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Medication.self, MedicationSchedule.self, DoseEvent.self], inMemory: true)
}
