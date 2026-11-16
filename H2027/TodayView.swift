import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query private var schedules: [MedicationSchedule]
    @Query(sort: \DoseEvent.recordedAt, order: .reverse) private var events: [DoseEvent]
    @AppStorage("appLanguage") private var appLanguageCode = AppLanguage.simplifiedChinese.rawValue

    private var todayDoses: [ScheduledDose] {
        ScheduleEngine.doses(on: .now, medications: medications, schedules: schedules, events: events)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    MorningBriefingCard(
                        plannedCount: todayDoses.count,
                        completedCount: todayDoses.filter { $0.recordedStatus == .taken }.count
                    )
                    if todayDoses.isEmpty {
                        ContentUnavailableView(
                            "今天没有用药计划",
                            systemImage: "checkmark.circle",
                            description: Text("可以在“药品”中添加药品和提醒时间。")
                        )
                        .frame(minHeight: 260)
                    } else {
                        ForEach(todayDoses) { dose in
                            DoseCard(
                                dose: dose,
                                effectiveStatus: ScheduleEngine.effectiveStatus(for: dose),
                                onRecord: { record(dose, status: $0) }
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("今日")
            .task { syncToWatch() }
            .onChange(of: todayDoses) { _, _ in syncToWatch() }
            .onChange(of: appLanguageCode) { _, _ in syncToWatch() }
        }
    }

    private func syncToWatch() {
        WatchSyncManager.shared.send(doses: todayDoses, languageCode: appLanguageCode)
    }

    private func record(_ dose: ScheduledDose, status: DoseStatus) {
        modelContext.insert(
            DoseEvent(
                medicationID: dose.medicationID,
                scheduleID: dose.scheduleID,
                scheduledAt: dose.scheduledAt,
                dosage: dose.dosage,
                unit: dose.unit,
                status: status
            )
        )
    }
}

struct MorningBriefingCard: View {
    let plannedCount: Int
    let completedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("早上好", systemImage: "sun.horizon.fill")
                .font(.title2.bold())
            Text("今天计划服用 \(plannedCount) 次，已完成 \(completedCount) 次。")
            Label("天气与穿衣建议将在位置权限开启后显示", systemImage: "cloud.sun.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.blue.gradient.opacity(0.16), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

struct DoseCard: View {
    let dose: ScheduledDose
    let effectiveStatus: DoseStatus?
    let onRecord: (DoseStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dose.medicationName).font(.headline)
                    Text("\(dose.dosage, format: .number) \(dose.unit)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(dose.scheduledAt, format: .dateTime.hour().minute())
                    .font(.headline.monospacedDigit())
            }
            if !dose.mealNote.isEmpty {
                Label(dose.mealNote, systemImage: "fork.knife")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let effectiveStatus {
                Label(effectiveStatus.title, systemImage: effectiveStatus.systemImage)
                    .font(.subheadline.weight(.semibold))
            } else {
                HStack {
                    Button("已服用", systemImage: "checkmark") { onRecord(.taken) }
                        .buttonStyle(.borderedProminent)
                    Button("延后", systemImage: "clock") { onRecord(.snoozed) }
                        .buttonStyle(.bordered)
                    Menu("更多", systemImage: "ellipsis") {
                        Button("跳过本次", systemImage: "forward.end") { onRecord(.skipped) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.quaternary) }
    }
}
