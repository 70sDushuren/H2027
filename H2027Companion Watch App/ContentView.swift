import SwiftUI

struct ContentView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                WatchBriefingCard(
                    date: .now,
                    completedCount: store.completedCount,
                    totalCount: store.doses.count,
                    copy: store.copy
                )
                if let nextDose = store.nextDose() {
                    Section(store.copy.nextDose) {
                        NavigationLink {
                            WatchDoseDetailView(doseID: nextDose.id)
                        } label: {
                            WatchDoseRow(
                                name: nextDose.name,
                                dosage: nextDose.dosage,
                                unit: nextDose.unit,
                                scheduledAt: nextDose.scheduledAt,
                                status: nextDose.status,
                                copy: store.copy
                            )
                        }
                        .accessibilityIdentifier("watch.nextDose")
                    }
                }
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
                        .accessibilityIdentifier("watch.dose.row.\(dose.id)")
                    }
                }
                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Label(store.copy.settings, systemImage: "gearshape")
                }
            }
            .navigationTitle(store.copy.today)
            .refreshable { store.requestRefresh() }
        }
    }
}

private struct WatchBriefingCard: View {
    let date: Date
    let completedCount: Int
    let totalCount: Int
    let copy: WatchCopy

    var body: some View {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 12 {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.morningBriefing).font(.headline)
                    Text(copy.morningPlan(totalCount)).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "sunrise.fill").foregroundStyle(.orange)
            }
            .accessibilityIdentifier("watch.briefing.morning")
        } else if hour >= 20 {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.eveningBriefing).font(.headline)
                    Text(completedCount == totalCount && totalCount > 0
                         ? copy.allDone
                         : copy.eveningProgress(completed: completedCount, total: totalCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "moon.stars.fill").foregroundStyle(.indigo)
            }
            .accessibilityIdentifier("watch.briefing.evening")
        }
    }
}

private struct WatchSettingsView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        List {
            Section {
                LabeledContent(store.copy.reminders) {
                    Text(notificationStatus)
                        .foregroundStyle(.secondary)
                }
                if store.notificationAuthorizationState == .notRequested {
                    Button(store.copy.enableReminders, systemImage: "bell.badge") {
                        Task { await store.requestNotificationAuthorization() }
                    }
                }
                Text(store.copy.reminderExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(store.copy.settings)
        .task { await store.refreshNotificationAuthorizationState() }
    }

    private var notificationStatus: String {
        switch store.notificationAuthorizationState {
        case .notRequested: store.copy.remindersNotRequested
        case .authorized: store.copy.remindersEnabled
        case .denied: store.copy.remindersDenied
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
                    .accessibilityIdentifier("watch.summary.completed")
                Spacer()
                Image(systemName: isPhoneReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .foregroundStyle(isPhoneReachable ? .green : .secondary)
                    .accessibilityLabel(isPhoneReachable ? copy.connected : copy.offline)
            }
            if pendingActionCount > 0 {
                Label(copy.pendingSync(pendingActionCount), systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("watch.sync.pending")
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
                        .accessibilityIdentifier("watch.dose.taken")
                        Button(store.copy.snooze, systemImage: "clock.fill") {
                            store.record(dose, status: .snoozed)
                            dismiss()
                        }
                        .tint(.orange)
                        .accessibilityIdentifier("watch.dose.snoozed")
                        Button(store.copy.skip, systemImage: "forward.end.fill", role: .destructive) {
                            isConfirmingSkip = true
                        }
                        .accessibilityIdentifier("watch.dose.skipped")
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
