import Foundation
import Observation
import SwiftData
import UserNotifications

enum NotificationPermissionState: Equatable {
    case notDetermined
    case denied
    case authorized

    var title: String {
        switch self {
        case .notDetermined: "尚未请求"
        case .denied: "已关闭"
        case .authorized: "已开启"
        }
    }
}

@MainActor
@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private(set) var permissionState = NotificationPermissionState.notDetermined
    private(set) var lastErrorMessage: String?
    private let center = UNUserNotificationCenter.current()
    private var modelContainer: ModelContainer?

    private override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func refreshPermissionState() async {
        let settings = await center.notificationSettings()
        permissionState = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        default: .notDetermined
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshPermissionState()
            lastErrorMessage = nil
            return granted
        } catch {
            lastErrorMessage = error.localizedDescription
            await refreshPermissionState()
            return false
        }
    }

    func scheduleDailyBriefings(wakeHour: Int, bedtimeHour: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: ["briefing.morning", "briefing.bedtime"])

        let morning = UNMutableNotificationContent()
        morning.title = "早上好"
        morning.body = "查看今日天气、穿衣建议和用药计划。"
        morning.sound = .default
        morning.categoryIdentifier = NotificationCategory.briefing

        let bedtime = UNMutableNotificationContent()
        bedtime.title = "睡前用药检查"
        bedtime.body = "查看今天的服药完成情况和未处理事项。"
        bedtime.sound = .default
        bedtime.categoryIdentifier = NotificationCategory.briefing

        do {
            try await center.add(UNNotificationRequest(
                identifier: "briefing.morning",
                content: morning,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: wakeHour, minute: 0),
                    repeats: true
                )
            ))
            try await center.add(UNNotificationRequest(
                identifier: "briefing.bedtime",
                content: bedtime,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: bedtimeHour, minute: 0),
                    repeats: true
                )
            ))
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func scheduleMedicationReminder(
        scheduleID: UUID,
        medicationID: UUID,
        medicationName: String,
        dosage: Double,
        unit: String,
        hour: Int,
        minute: Int,
        weekdays: [Int]
    ) async {
        let prefix = "dose.\(scheduleID.uuidString)."
        center.removePendingNotificationRequests(withIdentifiers: (1...7).map { prefix + String($0) })

        for weekday in weekdays {
            let content = UNMutableNotificationContent()
            content.title = "该服用 \(medicationName) 了"
            content.body = "计划剂量：\(dosage.formatted()) \(unit)"
            content.sound = .default
            content.categoryIdentifier = NotificationCategory.medication
            content.userInfo = [
                "medicationID": medicationID.uuidString,
                "scheduleID": scheduleID.uuidString,
                "dosage": dosage,
                "unit": unit,
                "weekday": weekday,
            ]

            do {
                try await center.add(UNNotificationRequest(
                    identifier: prefix + String(weekday),
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                        repeats: true
                    )
                ))
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func registerCategories() {
        let taken = UNNotificationAction(identifier: NotificationAction.taken, title: "已服用")
        let snooze = UNNotificationAction(identifier: NotificationAction.snooze, title: "延后15分钟")
        let skip = UNNotificationAction(identifier: NotificationAction.skip, title: "跳过", options: [.destructive])
        let medication = UNNotificationCategory(
            identifier: NotificationCategory.medication,
            actions: [taken, snooze, skip],
            intentIdentifiers: []
        )
        let briefing = UNNotificationCategory(
            identifier: NotificationCategory.briefing,
            actions: [],
            intentIdentifiers: []
        )
        center.setNotificationCategories([medication, briefing])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let medicationIDText = info["medicationID"] as? String,
              let medicationID = UUID(uuidString: medicationIDText),
              let scheduleIDText = info["scheduleID"] as? String,
              let scheduleID = UUID(uuidString: scheduleIDText),
              let dosage = info["dosage"] as? Double,
              let unit = info["unit"] as? String else {
            return
        }
        let status: DoseStatus?
        switch response.actionIdentifier {
        case NotificationAction.taken: status = .taken
        case NotificationAction.skip: status = .skipped
        case NotificationAction.snooze: status = .snoozed
        default: status = nil
        }
        guard let status else { return }
        await recordNotificationAction(
            medicationID: medicationID,
            scheduleID: scheduleID,
            dosage: dosage,
            unit: unit,
            status: status,
            deliveredAt: response.notification.date
        )
    }

    private func recordNotificationAction(
        medicationID: UUID,
        scheduleID: UUID,
        dosage: Double,
        unit: String,
        status: DoseStatus,
        deliveredAt: Date
    ) async {
        guard let modelContainer else { return }
        modelContainer.mainContext.insert(DoseEvent(
            medicationID: medicationID,
            scheduleID: scheduleID,
            scheduledAt: deliveredAt,
            dosage: dosage,
            unit: unit,
            status: status,
            source: .notification
        ))
        try? modelContainer.mainContext.save()

        guard status == .snoozed else { return }
        let content = UNMutableNotificationContent()
        content.title = "延后的用药提醒"
        content.body = "请确认是否已完成本次用药。"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.medication
        content.userInfo = [
            "medicationID": medicationID.uuidString,
            "scheduleID": scheduleID.uuidString,
            "dosage": dosage,
            "unit": unit,
        ]
        try? await center.add(UNNotificationRequest(
            identifier: "snooze.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
        ))
    }
}

enum NotificationCategory {
    static let medication = "MEDICATION_REMINDER"
    static let briefing = "DAILY_BRIEFING"
}

enum NotificationAction {
    static let taken = "DOSE_TAKEN"
    static let snooze = "DOSE_SNOOZE"
    static let skip = "DOSE_SKIP"
}
