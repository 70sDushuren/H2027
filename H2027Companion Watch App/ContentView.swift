import SwiftUI

struct ContentView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                WatchSummaryHeader(
                    completedCount: store.completedCount,
                    totalCount: store.doses.count,
                    isPhoneReachable: store.isPhoneReachable,
                    pendingActionCount: store.pendingActionCount,
                    lastUpdatedAt: store.lastUpdatedAt,
                    copy: store.copy
                )
                if store.doses.isEmpty {
                    ContentUnavailableView(
                        store.copy.noPlan,
                        systemImage: "checkmark.circle",
                        description: Text(store.copy.openPhone)
                    )
                } else {
                    ForEach(store.doses) { dose in
                        NavigationLink {
                            WatchDoseDetailView(doseID: dose.id)
                        } label: {
                            WatchDoseRow(
                                name: dose.name,
                                dosage: dose.dosage,
                                unit: dose.unit,
                                scheduledAt: dose.scheduledAt,
                                status: dose.status,
                                copy: store.copy
                            )
                        }
                    }
                }
            }
            .navigationTitle(store.copy.today)
            .refreshable { store.requestRefresh() }
        }
    }
}

private struct WatchSummaryHeader: View {
    let completedCount: Int
    let totalCount: Int
    let isPhoneReachable: Bool
    let pendingActionCount: Int
    let lastUpdatedAt: Date?
    let copy: WatchCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(completedCount)/\(totalCount)", systemImage: "pills.fill")
                    .font(.headline)
                Spacer()
                Image(systemName: isPhoneReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .foregroundStyle(isPhoneReachable ? .green : .secondary)
                    .accessibilityLabel(isPhoneReachable ? copy.connected : copy.offline)
            }
            if pendingActionCount > 0 {
                Label(copy.pendingSync(pendingActionCount), systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if let lastUpdatedAt {
                Text(lastUpdatedAt, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(copy.lastSynced)
            }
        }
    }
}

private struct WatchDoseRow: View {
    let name: String
    let dosage: Double
    let unit: String
    let scheduledAt: Date
    let status: WatchDoseStatus?
    let copy: WatchCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                Text(scheduledAt, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("\(dosage, format: .number) \(unit)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let status {
                Label(copy.status(status), systemImage: status.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(status.color)
            }
        }
    }
}

private struct WatchDoseDetailView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingSkip = false

    let doseID: String

    private var dose: WatchDose? {
        store.doses.first { $0.id == doseID }
    }

    var body: some View {
        ScrollView {
            if let dose {
                VStack(spacing: 10) {
                    WatchDoseDetailHeader(
                        name: dose.name,
                        dosage: dose.dosage,
                        unit: dose.unit,
                        scheduledAt: dose.scheduledAt,
                        mealNote: dose.mealNote
                    )
                    if let status = dose.status {
                        Label(store.copy.status(status), systemImage: status.systemImage)
                            .font(.headline)
                            .foregroundStyle(status.color)
                    } else {
                        Button(store.copy.taken, systemImage: "checkmark.circle.fill") {
                            store.record(dose, status: .taken)
                            dismiss()
                        }
                        .tint(.green)
                        Button(store.copy.snooze, systemImage: "clock.fill") {
                            store.record(dose, status: .snoozed)
                            dismiss()
                        }
                        .tint(.orange)
                        Button(store.copy.skip, systemImage: "forward.end.fill", role: .destructive) {
                            isConfirmingSkip = true
                        }
                    }
                }
            } else {
                ContentUnavailableView(store.copy.noPlan, systemImage: "pills")
            }
        }
        .navigationTitle(store.copy.recordDose)
        .confirmationDialog(store.copy.confirmSkip, isPresented: $isConfirmingSkip) {
            if let dose {
                Button(store.copy.skip, role: .destructive) {
                    store.record(dose, status: .skipped)
                    dismiss()
                }
            }
            Button(store.copy.cancel, role: .cancel) {}
        }
    }
}

private struct WatchDoseDetailHeader: View {
    let name: String
    let dosage: Double
    let unit: String
    let scheduledAt: Date
    let mealNote: String

    var body: some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("\(dosage, format: .number) \(unit)")
                .foregroundStyle(.secondary)
            Text(scheduledAt, format: .dateTime.hour().minute())
                .font(.title3.monospacedDigit())
            if !mealNote.isEmpty {
                Label(mealNote, systemImage: "fork.knife")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension WatchDoseStatus {
    var color: Color {
        switch self {
        case .taken: .green
        case .snoozed: .orange
        case .skipped: .secondary
        case .missed: .red
        }
    }
}

#Preview { ContentView().environment(WatchStore.preview) }
