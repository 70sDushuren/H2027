import SwiftData
import SwiftUI

struct MedicationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Medication.name) private var medications: [Medication]
    @State private var isPresentingAddMedication = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(MedicationKind.allCases) { kind in
                    Section(kind.title) {
                        let matching = medications.filter { $0.kind == kind }
                        if matching.isEmpty {
                            Text("暂无\(kind.title)").foregroundStyle(.secondary)
                        } else {
                            ForEach(matching) { medication in
                                NavigationLink {
                                    MedicationDetailView(medication: medication)
                                } label: {
                                    MedicationRow(medication: medication)
                                }
                            }
                            .onDelete { offsets in
                                for offset in offsets { modelContext.delete(matching[offset]) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("药品")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("添加药品", systemImage: "plus") { isPresentingAddMedication = true }
                }
            }
            .sheet(isPresented: $isPresentingAddMedication) { AddMedicationView() }
        }
    }
}

struct MedicationRow: View {
    let medication: Medication

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(medication.name).font(.headline)
            Text("\(medication.dosage, format: .number) \(medication.unit)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct MedicationDetailView: View {
    @Query private var allSchedules: [MedicationSchedule]
    let medication: Medication
    @State private var isAddingSchedule = false

    private var schedules: [MedicationSchedule] {
        allSchedules.filter { $0.medicationID == medication.id }
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    var body: some View {
        List {
            Section("药品信息") {
                LabeledContent("类型", value: medication.kind.title)
                LabeledContent("剂量", value: "\(medication.dosage.formatted()) \(medication.unit)")
                if !medication.notes.isEmpty { LabeledContent("备注", value: medication.notes) }
            }
            Section("提醒计划") {
                if schedules.isEmpty {
                    Text("还没有提醒时间").foregroundStyle(.secondary)
                }
                ForEach(schedules) { schedule in
                    ScheduleRow(schedule: schedule)
                }
                Button("添加提醒时间", systemImage: "plus") { isAddingSchedule = true }
            }
        }
        .navigationTitle(medication.name)
        .sheet(isPresented: $isAddingSchedule) { AddScheduleView(medication: medication) }
    }
}

struct ScheduleRow: View {
    let schedule: MedicationSchedule

    private var time: Date {
        Calendar.current.date(from: DateComponents(hour: schedule.hour, minute: schedule.minute)) ?? .now
    }

    var body: some View {
        HStack {
            Text(time, format: .dateTime.hour().minute())
            Spacer()
            Text("宽限 \(schedule.gracePeriodMinutes) 分钟")
                .foregroundStyle(.secondary)
        }
    }
}

struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Medication.modifiedAt, order: .reverse) private var savedMedications: [Medication]
    @State private var name = ""
    @State private var kind = MedicationKind.prescription
    @State private var dosage = 1.0
    @State private var unit = "片"
    @State private var notes = ""
    @State private var isPresentingReference = false
    @State private var isPresentingScanner = false
    @State private var selectedReference: MedicationReference?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("从常用药参考中选择", systemImage: "books.vertical") {
                        isPresentingReference = true
                    }
                } footer: {
                    Text("参考资料不会自动成为处方，保存前请对照药袋确认。")
                }
                if !savedMedications.isEmpty {
                    Section("我的常用") {
                        ForEach(savedMedications.prefix(5)) { medication in
                            Button(medication.name) {
                                name = medication.name
                                kind = medication.kind
                                dosage = medication.dosage
                                unit = medication.unit
                                notes = medication.notes
                            }
                        }
                    }
                }
                Section("基本信息") {
                    TextField("药品名称", text: $name)
                    Picker("类型", selection: $kind) {
                        ForEach(MedicationKind.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        TextField("剂量", value: $dosage, format: .number)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                        TextField("单位", text: $unit)
                    }
                    TextField("备注（可选）", text: $notes, axis: .vertical)
                }
                if let selectedReference {
                    Section("已选参考") {
                        Text(selectedReference.exampleUse)
                        Text(selectedReference.mealGuidance)
                        Link("查看官方来源", destination: selectedReference.sourceURL)
                    }
                }
                Section {
                    Button("扫描药品包装", systemImage: "camera.viewfinder") {
                        isPresentingScanner = true
                    }
                } footer: {
                    Text("扫描结果只用于辅助填写，保存前请对照药盒或药袋确认。")
                }
            }
            .navigationTitle("添加药品")
            .sheet(isPresented: $isPresentingReference) {
                MedicationReferencePicker { reference in
                    selectedReference = reference
                    name = reference.genericName
                    if let strength = reference.commonStrengths.first {
                        let parts = strength.split(separator: " ")
                        dosage = Double(parts.first ?? "1") ?? 1
                        unit = parts.dropFirst().joined(separator: " ")
                    }
                }
            }
            .sheet(isPresented: $isPresentingScanner) {
                MedicationPackageScannerView { recognizedText in
                    applyRecognizedText(recognizedText)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        modelContext.insert(Medication(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            kind: kind,
                            dosage: dosage,
                            unit: unit,
                            notes: notes
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dosage <= 0 || unit.isEmpty)
                }
            }
        }
    }

    private func applyRecognizedText(_ recognizedText: String) {
        let lines = recognizedText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = lines[0]
        }
        let scanNote = lines.joined(separator: " / ")
        notes = notes.isEmpty ? scanNote : "\(notes)\n\(scanNote)"
    }
}

struct AddScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let medication: Medication
    @State private var time = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    @State private var gracePeriodMinutes = 120
    @State private var mealNote = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("提醒时间", selection: $time, displayedComponents: .hourAndMinute)
                Stepper("漏服宽限：\(gracePeriodMinutes) 分钟", value: $gracePeriodMinutes, in: 15...720, step: 15)
                TextField("随餐说明（可选）", text: $mealNote)
            }
            .navigationTitle("添加提醒")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                        let schedule = MedicationSchedule(
                            medicationID: medication.id,
                            hour: components.hour ?? 8,
                            minute: components.minute ?? 0,
                            gracePeriodMinutes: gracePeriodMinutes,
                            mealNote: mealNote
                        )
                        modelContext.insert(schedule)
                        Task {
                            await NotificationManager.shared.scheduleMedicationReminder(
                                scheduleID: schedule.id,
                                medicationID: medication.id,
                                medicationName: medication.name,
                                dosage: medication.dosage,
                                unit: medication.unit,
                                hour: schedule.hour,
                                minute: schedule.minute,
                                weekdays: schedule.weekdayNumbers
                            )
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
