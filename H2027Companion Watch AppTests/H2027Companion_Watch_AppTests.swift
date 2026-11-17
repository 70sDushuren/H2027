import Foundation
import Testing
@testable import H2027Companion_Watch_App

struct WatchDataModelTests {
    @Test
    func watchDoseStatusRoundTripsThroughCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in [WatchDoseStatus.taken, .snoozed, .skipped, .missed] {
            let data = try encoder.encode(status)
            #expect(try decoder.decode(WatchDoseStatus.self, from: data) == status)
        }
    }

    @Test
    func doseActionPreservesIdempotencyIdentifier() throws {
        let action = WatchDoseAction(
            id: UUID(),
            medicationID: UUID(),
            scheduleID: UUID(),
            scheduledAt: Date(timeIntervalSince1970: 1_000),
            recordedAt: Date(timeIntervalSince1970: 1_100),
            dosage: 500,
            unit: "mg",
            status: WatchDoseStatus.taken.rawValue
        )

        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(WatchDoseAction.self, from: data)

        #expect(decoded == action)
    }

    @Test
    func watchCopyUsesSelectedLanguage() {
        #expect(WatchCopy(languageCode: "en-GB").taken == "Taken")
        #expect(WatchCopy(languageCode: "zh-Hans").taken == "已服用")
        #expect(WatchCopy(languageCode: "zh-Hant").recordDose == "記錄服藥")
        #expect(WatchCopy(languageCode: "yue-Hant").snooze == "遲啲提醒")
        #expect(WatchCopy(languageCode: "pt-PT").skip == "Ignorar")
    }

    @Test
    func reminderBodyIncludesDoseAndOptionalMealGuidance() {
        let copy = WatchCopy(languageCode: "en-GB")
        #expect(copy.reminderBody(dosage: 500, unit: "mg", mealNote: "") == "Take 500 mg")
        #expect(copy.reminderBody(dosage: 1, unit: "tablet", mealNote: "With food") == "Take 1 tablet · With food")
    }
}
