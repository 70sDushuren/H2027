import Foundation
import Testing
@testable import H2027

struct ScheduleEngineTests {
    @Test
    func createsDoseForMatchingWeekday() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 10)))
        let medication = Medication(name: "测试药品", kind: .prescription, dosage: 1, unit: "片")
        let weekday = calendar.component(.weekday, from: date)
        let schedule = MedicationSchedule(
            medicationID: medication.id,
            hour: 8,
            minute: 30,
            weekdayNumbers: [weekday],
            startDate: calendar.date(byAdding: .day, value: -1, to: date) ?? date
        )
        let doses = ScheduleEngine.doses(
            on: date,
            medications: [medication],
            schedules: [schedule],
            events: [],
            calendar: calendar
        )
        #expect(doses.count == 1)
        #expect(doses.first?.medicationName == "测试药品")
        #expect(calendar.component(.hour, from: doses[0].scheduledAt) == 8)
        #expect(calendar.component(.minute, from: doses[0].scheduledAt) == 30)
    }

    @Test
    func marksDoseMissedAfterGracePeriod() throws {
        let calendar = Calendar(identifier: .gregorian)
        let scheduledAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 8)))
        let dose = ScheduledDose(
            id: "dose",
            medicationID: UUID(),
            scheduleID: UUID(),
            medicationName: "测试药品",
            dosage: 1,
            unit: "片",
            scheduledAt: scheduledAt,
            gracePeriodMinutes: 120,
            mealNote: "",
            recordedStatus: nil
        )
        let now = try #require(calendar.date(byAdding: .minute, value: 121, to: scheduledAt))
        #expect(ScheduleEngine.effectiveStatus(for: dose, now: now) == .missed)
    }

    @Test
    func recordedStatusWinsOverMissedCalculation() {
        let dose = ScheduledDose(
            id: "dose",
            medicationID: UUID(),
            scheduleID: UUID(),
            medicationName: "测试药品",
            dosage: 1,
            unit: "片",
            scheduledAt: Date(timeIntervalSince1970: 1_000),
            gracePeriodMinutes: 15,
            mealNote: "",
            recordedStatus: .taken
        )
        #expect(ScheduleEngine.effectiveStatus(for: dose, now: .now) == .taken)
    }
}

struct MedicationReferenceCatalogTests {
    @Test
    func referenceIdentifiersAreUnique() {
        let identifiers = MedicationReferenceCatalog.entries.map(\.id)
        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test
    func everyReferenceHasTraceableSourceAndStrength() {
        for entry in MedicationReferenceCatalog.entries {
            #expect(!entry.commonStrengths.isEmpty)
            #expect(!entry.sourceTitle.isEmpty)
            #expect(entry.sourceURL.scheme == "https")
            #expect(!entry.regions.isEmpty)
        }
    }
}
