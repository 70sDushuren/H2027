import SwiftData
import SwiftUI

struct ContentView: View {
    @AppStorage("quickRecordRequested") private var quickRecordRequested = false
    @State private var isPresentingQuickRecord = false

    var body: some View {
        TabView {
            Tab("今日", systemImage: "sun.max.fill") { TodayView() }
            Tab("药品", systemImage: "pills.fill") { MedicationListView() }
            Tab("记录", systemImage: "list.bullet.clipboard.fill") { DoseHistoryView() }
            Tab("设置", systemImage: "gearshape.fill") { SettingsView() }
        }
        .sheet(isPresented: $isPresentingQuickRecord) {
            QuickDoseRecordView()
        }
        .onAppear { consumeQuickRecordRequest() }
        .onChange(of: quickRecordRequested) { _, requested in
            if requested { consumeQuickRecordRequest() }
        }
    }

    private func consumeQuickRecordRequest() {
        guard quickRecordRequested else { return }
        quickRecordRequested = false
        isPresentingQuickRecord = true
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Medication.self, MedicationSchedule.self, DoseEvent.self], inMemory: true)
}
