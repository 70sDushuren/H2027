import Foundation
import Observation
import UserNotifications
import WatchConnectivity
import WatchKit

enum WatchNotificationAuthorizationState: Equatable {
    case notRequested
    case authorized
    case denied
}

enum WatchDoseStatus: String, Codable, Equatable {
    case taken
    case snoozed
    case skipped
    case missed

    var systemImage: String {
        switch self {
        case .taken: "checkmark.circle.fill"
        case .snoozed: "clock.fill"
        case .skipped: "forward.end.circle.fill"
        case .missed: "exclamationmark.circle.fill"
        }
    }
}

struct WatchDose: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let unit: String
    let mealNote: String
    let medicationID: UUID
    let scheduleID: UUID
    let dosage: Double
    let scheduledAt: Date
    var status: WatchDoseStatus?
}

private struct WatchSnapshot: Codable {
    let generatedAt: Date
    let languageCode: String
    let doses: [WatchDose]
}

struct WatchDoseAction: Codable, Identifiable, Equatable {
    let id: UUID
    let medicationID: UUID
    let scheduleID: UUID
    let scheduledAt: Date
    let recordedAt: Date
    let dosage: Double
    let unit: String
    let status: String
}

@Observable
@MainActor
final class WatchStore: NSObject, WCSessionDelegate, UNUserNotificationCenterDelegate {
    var doses: [WatchDose] = []
    var languageCode = "zh-Hans"
    var isPhoneReachable = false
    var lastUpdatedAt: Date?
    var notificationAuthorizationState = WatchNotificationAuthorizationState.notRequested
    private(set) var pendingActions: [WatchDoseAction] = []

    private let snapshotKey = "watchSnapshot"
    private let pendingActionsKey = "pendingWatchDoseActions"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var copy: WatchCopy { WatchCopy(languageCode: languageCode) }
    var completedCount: Int { doses.filter { $0.status == .taken }.count }
    var pendingActionCount: Int { pendingActions.count }

    func nextDose(at date: Date = .now) -> WatchDose? {
        let incomplete = doses.filter { $0.status == nil || $0.status == .snoozed || $0.status == .missed }
        return incomplete
            .filter { $0.scheduledAt >= date }
            .min { $0.scheduledAt < $1.scheduledAt }
            ?? incomplete.min { $0.scheduledAt < $1.scheduledAt }
    }

    override init() {
        super.init()
        restoreSnapshot()
        restorePendingActions()
#if DEBUG
        configureDebugScenarioIfNeeded()
#endif
        configureNotificationCategories()
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshNotificationAuthorizationState() }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func record(_ dose: WatchDose, status: WatchDoseStatus) {
        guard let index = doses.firstIndex(where: { $0.id == dose.id }) else { return }
        doses[index].status = status
        persistCurrentSnapshot()
        let action = WatchDoseAction(
            id: UUID(),
            medicationID: dose.medicationID,
            scheduleID: dose.scheduleID,
            scheduledAt: dose.scheduledAt,
            recordedAt: .now,
            dosage: dose.dosage,
            unit: dose.unit,
            status: status.rawValue
        )
        pendingActions.append(action)
        persistPendingActions()
        transmit(action)
        playHaptic(for: status)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(for: dose)])
    }

    private func playHaptic(for status: WatchDoseStatus) {
        let haptic: WKHapticType = status == .taken ? .success : .click
        WKInterfaceDevice.current().play(haptic)
    }

    func requestNotificationAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            notificationAuthorizationState = .denied
        }
        await refreshNotificationAuthorizationState()
    }

    func refreshNotificationAuthorizationState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationAuthorizationState = .authorized
            scheduleDoseReminders()
        case .denied:
            notificationAuthorizationState = .denied
        case .notDetermined:
            notificationAuthorizationState = .notRequested
        @unknown default:
            notificationAuthorizationState = .notRequested
        }
    }

    func requestRefresh() {
        guard WCSession.isSupported(), WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["requestSnapshot": true], replyHandler: nil)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            if session.isReachable { self.retryPendingActions() }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            if session.isReachable { self.retryPendingActions() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context["snapshot"] as? Data else { return }
        Task { @MainActor in self.applySnapshot(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["snapshot"] as? Data else { return }
        Task { @MainActor in self.applySnapshot(data) }
    }

    private func applySnapshot(_ data: Data) {
        guard let snapshot = try? decoder.decode(WatchSnapshot.self, from: data) else { return }
        doses = snapshot.doses
        languageCode = snapshot.languageCode
        lastUpdatedAt = snapshot.generatedAt
        pendingActions.removeAll { action in
            snapshot.doses.contains {
                $0.scheduleID == action.scheduleID &&
                $0.scheduledAt == action.scheduledAt &&
                $0.status?.rawValue == action.status
            }
        }
        persistPendingActions()
        UserDefaults.standard.set(data, forKey: snapshotKey)
        configureNotificationCategories()
        if notificationAuthorizationState == .authorized { scheduleDoseReminders() }
    }

    private func restoreSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else { return }
        applySnapshot(data)
    }

    private func persistCurrentSnapshot() {
        let snapshot = WatchSnapshot(generatedAt: .now, languageCode: languageCode, doses: doses)
        if let data = try? encoder.encode(snapshot) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }

    private func transmit(_ action: WatchDoseAction) {
        guard let data = try? encoder.encode(action), WCSession.isSupported() else { return }
        let message: [String: Any] = ["doseAction": data]
        guard WCSession.default.isReachable else {
            WCSession.default.transferUserInfo(message)
            return
        }
        WCSession.default.sendMessage(message) { reply in
            guard reply["accepted"] as? Bool == true else { return }
            Task { @MainActor in self.markActionDelivered(action.id) }
        } errorHandler: { _ in
            WCSession.default.transferUserInfo(message)
        }
    }

    private func retryPendingActions() {
        pendingActions.forEach(transmit)
    }

    private func markActionDelivered(_ actionID: UUID) {
        pendingActions.removeAll { $0.id == actionID }
        persistPendingActions()
    }

    private func restorePendingActions() {
        guard let data = UserDefaults.standard.data(forKey: pendingActionsKey),
              let actions = try? decoder.decode([WatchDoseAction].self, from: data) else { return }
        pendingActions = actions
    }

    private func persistPendingActions() {
        guard let data = try? encoder.encode(pendingActions) else { return }
        UserDefaults.standard.set(data, forKey: pendingActionsKey)
    }

#if DEBUG
    private func configureDebugScenarioIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--watch-demo-dose") else { return }
        let calendar = Calendar.current
        let scheduledAt = calendar.date(
            bySetting: .second,
            value: 0,
            of: calendar.date(byAdding: .minute, value: 1, to: .now) ?? .now
        ) ?? .now.addingTimeInterval(60)
        doses = [
            WatchDose(
                id: "watch-demo-dose",
                name: "Demo Medication",
                unit: "tablet",
                mealNote: "With food",
                medicationID: UUID(uuidString: "00000000-0000-0000-0000-000000000101") ?? UUID(),
                scheduleID: UUID(uuidString: "00000000-0000-0000-0000-000000000102") ?? UUID(),
                dosage: 1,
                scheduledAt: scheduledAt,
                status: nil
            )
        ]
        pendingActions = []
        lastUpdatedAt = .now
        UserDefaults.standard.removeObject(forKey: pendingActionsKey)
    }
#endif

    private func configureNotificationCategories() {
        let actions = [
            UNNotificationAction(identifier: "dose.taken", title: copy.taken),
            UNNotificationAction(identifier: "dose.snoozed", title: copy.snooze),
            UNNotificationAction(identifier: "dose.skipped", title: copy.skip, options: .destructive),
        ]
        let category = UNNotificationCategory(
            identifier: "watch.dose.reminder",
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func scheduleDoseReminders(now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for dose in doses where dose.status == nil && dose.scheduledAt > now {
            let content = UNMutableNotificationContent()
            content.title = dose.name
            content.body = copy.reminderBody(dosage: dose.dosage, unit: dose.unit, mealNote: dose.mealNote)
            content.sound = .default
            content.categoryIdentifier = "watch.dose.reminder"
            content.userInfo = ["doseID": dose.id]
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dose.scheduledAt
            )
            let request = UNNotificationRequest(
                identifier: notificationIdentifier(for: dose),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            center.add(request)
        }
    }

    private func notificationIdentifier(for dose: WatchDose) -> String {
        "watch-dose-\(dose.id)"
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let doseID = response.notification.request.content.userInfo["doseID"] as? String else { return }
        let status: WatchDoseStatus?
        switch response.actionIdentifier {
        case "dose.taken": status = .taken
        case "dose.snoozed": status = .snoozed
        case "dose.skipped": status = .skipped
        default: status = nil
        }
        guard let status else { return }
        await MainActor.run {
            guard let dose = self.doses.first(where: { $0.id == doseID }) else { return }
            self.record(dose, status: status)
        }
    }

    static var preview: WatchStore {
        let store = WatchStore()
        store.doses = [
            WatchDose(
                id: "preview",
                name: "Metformin",
                unit: "mg",
                mealNote: "",
                medicationID: UUID(),
                scheduleID: UUID(),
                dosage: 500,
                scheduledAt: .now,
                status: nil
            )
        ]
        store.lastUpdatedAt = .now
        return store
    }
}

struct WatchCopy {
    let languageCode: String
    private var language: String { languageCode.lowercased() }

    var today: String { choose("Today", "今日", "今日", "今日", "Hoje") }
    var noPlan: String { choose("No doses today", "今天没有用药计划", "今天沒有用藥計劃", "今日冇用藥計劃", "Sem doses hoje") }
    var openPhone: String { choose("Add medicines on iPhone.", "请在 iPhone 上添加药品。", "請在 iPhone 上加入藥品。", "請喺 iPhone 加入藥物。", "Adicione medicamentos no iPhone.") }
    var taken: String { choose("Taken", "已服用", "已服用", "食咗", "Tomado") }
    var snooze: String { choose("Snooze", "延后", "稍後提醒", "遲啲提醒", "Adiar") }
    var skip: String { choose("Skip", "跳过", "略過", "略過", "Ignorar") }
    var cancel: String { choose("Cancel", "取消", "取消", "取消", "Cancelar") }
    var recordDose: String { choose("Record Dose", "记录服药", "記錄服藥", "記錄服藥", "Registar dose") }
    var confirmSkip: String { choose("Skip this dose?", "跳过本次用药？", "略過今次服藥？", "略過今次服藥？", "Ignorar esta dose?") }
    var connected: String { choose("iPhone connected", "iPhone 已连接", "iPhone 已連線", "iPhone 已連線", "iPhone ligado") }
    var offline: String { choose("Works offline", "离线可用", "離線可用", "離線可用", "Funciona offline") }
    var lastSynced: String { choose("Last synced", "最后同步", "最後同步", "最後同步", "Última sincronização") }
    var settings: String { choose("Settings", "设置", "設定", "設定", "Definições") }
    var reminders: String { choose("Reminders", "提醒", "提醒", "提醒", "Lembretes") }
    var enableReminders: String { choose("Enable Reminders", "启用提醒", "啟用提醒", "開啟提醒", "Ativar lembretes") }
    var remindersEnabled: String { choose("Enabled", "已启用", "已啟用", "已開啟", "Ativados") }
    var remindersDenied: String { choose("Permission denied", "权限已关闭", "權限已關閉", "權限已關閉", "Permissão recusada") }
    var remindersNotRequested: String { choose("Not enabled", "尚未启用", "尚未啟用", "未開啟", "Não ativados") }
    var reminderExplanation: String { choose("Get dose alerts directly on Apple Watch.", "直接在 Apple Watch 上接收用药提醒。", "直接在 Apple Watch 上接收用藥提醒。", "直接喺 Apple Watch 收到食藥提醒。", "Receba alertas de dose diretamente no Apple Watch.") }
    var nextDose: String { choose("Next dose", "下一次用药", "下一次用藥", "下一次食藥", "Próxima dose") }
    var morningBriefing: String { choose("Good morning", "早上好", "早晨好", "早晨", "Bom dia") }
    var eveningBriefing: String { choose("Evening check", "睡前检查", "睡前檢查", "瞓前檢查", "Revisão noturna") }
    var allDone: String { choose("All planned doses are complete.", "今天的计划用药已完成。", "今天的計劃用藥已完成。", "今日計劃食嘅藥已完成。", "Todas as doses planeadas estão concluídas.") }

    func morningPlan(_ count: Int) -> String {
        choose("\(count) planned dose(s) today.", "今天有 \(count) 次计划用药。", "今天有 \(count) 次計劃用藥。", "今日有 \(count) 次計劃食藥。", "\(count) dose(s) planeada(s) hoje.")
    }

    func eveningProgress(completed: Int, total: Int) -> String {
        choose("Completed \(completed) of \(total) doses.", "已完成 \(completed)/\(total) 次用药。", "已完成 \(completed)/\(total) 次用藥。", "已完成 \(completed)/\(total) 次食藥。", "Concluídas \(completed) de \(total) doses.")
    }

    func pendingSync(_ count: Int) -> String {
        choose("\(count) pending", "\(count) 项待同步", "\(count) 項待同步", "\(count) 項等緊同步", "\(count) pendente(s)")
    }

    func reminderBody(dosage: Double, unit: String, mealNote: String) -> String {
        let base = choose("Take \(dosage.formatted()) \(unit)", "服用 \(dosage.formatted()) \(unit)", "服用 \(dosage.formatted()) \(unit)", "服用 \(dosage.formatted()) \(unit)", "Tomar \(dosage.formatted()) \(unit)")
        return mealNote.isEmpty ? base : "\(base) · \(mealNote)"
    }

    func status(_ value: WatchDoseStatus) -> String {
        switch value {
        case .taken: taken
        case .snoozed: snooze
        case .skipped: choose("Skipped", "已跳过", "已略過", "已略過", "Ignorado")
        case .missed: choose("Missed", "漏服", "漏服", "漏食", "Em falta")
        }
    }

    private func choose(_ en: String, _ zhHans: String, _ zhHant: String, _ yue: String, _ pt: String) -> String {
        if language.hasPrefix("yue") { return yue }
        if language.hasPrefix("zh-hant") { return zhHant }
        if language.hasPrefix("zh") { return zhHans }
        if language.hasPrefix("pt") { return pt }
        return en
    }
}
