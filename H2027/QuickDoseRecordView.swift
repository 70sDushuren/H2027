import SwiftData
import SwiftUI

struct QuickDoseRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query private var schedules: [MedicationSchedule]
    @Query(sort: \DoseEvent.recordedAt, order: .reverse) private var events: [DoseEvent]
    @State private var selectedDose: ScheduledDose?

    private var todayDoses: [ScheduledDose] {
        ScheduleEngine.doses(on: .now, medications: medications, schedules: schedules, events: events)
    }

    var body: some View {
        NavigationStack {
            Group {
                if todayDoses.isEmpty {
                    ContentUnavailableView(
                        "今天没有可记录的用药计划",
                        systemImage: "pills",
                        description: Text("请先在“药品”中添加药品和提醒时间。")
                    )
                } else {
                    List(todayDoses) { dose in
                        QuickDoseRow(
                            medicationName: dose.medicationName,
                            dosage: dose.dosage,
                            unit: dose.unit,
                            scheduledAt: dose.scheduledAt,
                            recordedStatus: dose.recordedStatus
                        ) {
                            selectedDose = dose
                        }
                    }
                }
            }
            .navigationTitle("快速记录服药")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .confirmationDialog(
                "确认已服用？",
                isPresented: confirmationBinding,
                titleVisibility: .visible,
                presenting: selectedDose
            ) { dose in
                Button("确认记录 \(dose.medicationName)") {
                    recordTaken(dose)
                }
                Button("取消", role: .cancel) {}
            } message: { dose in
                Text("\(dose.dosage, format: .number) \(dose.unit) · 计划时间 \(dose.scheduledAt, format: .dateTime.hour().minute())")
            }
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { selectedDose != nil },
            set: { if !$0 { selectedDose = nil } }
        )
    }

    private func recordTaken(_ dose: ScheduledDose) {
        modelContext.insert(
            DoseEvent(
                medicationID: dose.medicationID,
                scheduleID: dose.scheduleID,
                scheduledAt: dose.scheduledAt,
                dosage: dose.dosage,
                unit: dose.unit,
                status: .taken,
                source: .siri
            )
        )
        try? modelContext.save()
        dismiss()
    }
}

private struct QuickDoseRow: View {
    let medicationName: String
    let dosage: Double
    let unit: String
    let scheduledAt: Date
    let recordedStatus: DoseStatus?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: recordedStatus?.systemImage ?? "circle")
                    .foregroundStyle(recordedStatus == nil ? .blue : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(medicationName)
                        .font(.headline)
                    Text("\(dosage, format: .number) \(unit)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(scheduledAt, format: .dateTime.hour().minute())
                    if let recordedStatus {
                        Text(recordedStatus.title)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
        .buttonStyle(.plain)
        .disabled(recordedStatus != nil)
        .accessibilityHint(recordedStatus == nil ? "双击以确认已服用" : "本次计划已有记录")
    }
}
