import Foundation
import SwiftData

enum MedicationKind: String, Codable, CaseIterable, Identifiable {
    case prescription
    case supplement

    var id: Self { self }
    var title: String { self == .prescription ? "处方药" : "保健品" }
}

enum DoseStatus: String, Codable, CaseIterable {
    case taken
    case skipped
    case snoozed
    case missed

    var title: String {
        switch self {
        case .taken: "已服用"
        case .skipped: "已跳过"
        case .snoozed: "已延后"
        case .missed: "漏服"
        }
    }

    var systemImage: String {
        switch self {
        case .taken: "checkmark.circle.fill"
        case .skipped: "forward.end.circle.fill"
        case .snoozed: "clock.badge.fill"
        case .missed: "exclamationmark.circle.fill"
        }
    }
}

enum DoseSource: String, Codable {
    case iPhone
    case watch
    case siri
    case notification
    case healthKit
}

@Model
final class Medication {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRawValue: String
    var dosage: Double
    var unit: String
    var notes: String
    var isActive: Bool
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        kind: MedicationKind,
        dosage: Double,
        unit: String,
        notes: String = "",
        isActive: Bool = true,
        createdAt: Date = .now,
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRawValue = kind.rawValue
        self.dosage = dosage
        self.unit = unit
        self.notes = notes
        self.isActive = isActive
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    var kind: MedicationKind {
        get { MedicationKind(rawValue: kindRawValue) ?? .prescription }
        set { kindRawValue = newValue.rawValue }
    }
}

@Model
final class MedicationSchedule {
    @Attribute(.unique) var id: UUID
    var medicationID: UUID
    var hour: Int
    var minute: Int
    var weekdayNumbers: [Int]
    var startDate: Date
    var endDate: Date?
    var gracePeriodMinutes: Int
    var mealNote: String
    var isAsNeeded: Bool
    var isEnabled: Bool
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        hour: Int,
        minute: Int,
        weekdayNumbers: [Int] = Array(1...7),
        startDate: Date = .now,
        endDate: Date? = nil,
        gracePeriodMinutes: Int = 120,
        mealNote: String = "",
        isAsNeeded: Bool = false,
        isEnabled: Bool = true,
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.medicationID = medicationID
        self.hour = hour
        self.minute = minute
        self.weekdayNumbers = weekdayNumbers
        self.startDate = startDate
        self.endDate = endDate
        self.gracePeriodMinutes = gracePeriodMinutes
        self.mealNote = mealNote
        self.isAsNeeded = isAsNeeded
        self.isEnabled = isEnabled
        self.modifiedAt = modifiedAt
    }
}

@Model
final class DoseEvent {
    @Attribute(.unique) var id: UUID
    var medicationID: UUID
    var scheduleID: UUID?
    var scheduledAt: Date?
    var recordedAt: Date
    var dosage: Double
    var unit: String
    var statusRawValue: String
    var sourceRawValue: String

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        scheduleID: UUID? = nil,
        scheduledAt: Date? = nil,
        recordedAt: Date = .now,
        dosage: Double,
        unit: String,
        status: DoseStatus,
        source: DoseSource = .iPhone
    ) {
        self.id = id
        self.medicationID = medicationID
        self.scheduleID = scheduleID
        self.scheduledAt = scheduledAt
        self.recordedAt = recordedAt
        self.dosage = dosage
        self.unit = unit
        self.statusRawValue = status.rawValue
        self.sourceRawValue = source.rawValue
    }

    var status: DoseStatus { DoseStatus(rawValue: statusRawValue) ?? .taken }
    var source: DoseSource { DoseSource(rawValue: sourceRawValue) ?? .iPhone }
}

struct ScheduledDose: Identifiable, Equatable {
    let id: String
    let medicationID: UUID
    let scheduleID: UUID
    let medicationName: String
    let dosage: Double
    let unit: String
    let scheduledAt: Date
    let gracePeriodMinutes: Int
    let mealNote: String
    let recordedStatus: DoseStatus?
}

enum ScheduleEngine {
    static func doses(
        on date: Date,
        medications: [Medication],
        schedules: [MedicationSchedule],
        events: [DoseEvent],
        calendar: Calendar = .current
    ) -> [ScheduledDose] {
        let medicationByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
        let weekday = calendar.component(.weekday, from: date)

        return schedules.compactMap { schedule in
            guard schedule.isEnabled,
                  !schedule.isAsNeeded,
                  schedule.weekdayNumbers.contains(weekday),
                  calendar.startOfDay(for: date) >= calendar.startOfDay(for: schedule.startDate),
                  schedule.endDate.map({ calendar.startOfDay(for: date) <= calendar.startOfDay(for: $0) }) ?? true,
                  let medication = medicationByID[schedule.medicationID],
                  medication.isActive,
                  let scheduledAt = calendar.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: date) else {
                return nil
            }

            let event = events
                .filter {
                    $0.scheduleID == schedule.id &&
                    $0.scheduledAt.map { calendar.isDate($0, inSameDayAs: date) } == true
                }
                .max { $0.recordedAt < $1.recordedAt }
            return ScheduledDose(
                id: "\(schedule.id.uuidString)-\(calendar.startOfDay(for: date).timeIntervalSince1970)",
                medicationID: medication.id,
                scheduleID: schedule.id,
                medicationName: medication.name,
                dosage: medication.dosage,
                unit: medication.unit,
                scheduledAt: scheduledAt,
                gracePeriodMinutes: schedule.gracePeriodMinutes,
                mealNote: schedule.mealNote,
                recordedStatus: event?.status
            )
        }
        .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    static func effectiveStatus(for dose: ScheduledDose, now: Date = .now) -> DoseStatus? {
        if let recordedStatus = dose.recordedStatus { return recordedStatus }
        let deadline = dose.scheduledAt.addingTimeInterval(TimeInterval(dose.gracePeriodMinutes * 60))
        return now > deadline ? .missed : nil
    }
}
