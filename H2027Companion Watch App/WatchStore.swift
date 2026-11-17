import Foundation
import Observation
import WatchConnectivity

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
final class WatchStore: NSObject, WCSessionDelegate {
    var doses: [WatchDose] = []
    var languageCode = "zh-Hans"
    var isPhoneReachable = false
    var lastUpdatedAt: Date?
    private(set) var pendingActions: [WatchDoseAction] = []

    private let snapshotKey = "watchSnapshot"
    private let pendingActionsKey = "pendingWatchDoseActions"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var copy: WatchCopy { WatchCopy(languageCode: languageCode) }
    var completedCount: Int { doses.filter { $0.status == .taken }.count }
    var pendingActionCount: Int { pendingActions.count }

    override init() {
        super.init()
        restoreSnapshot()
        restorePendingActions()
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

    func pendingSync(_ count: Int) -> String {
        choose("\(count) pending", "\(count) 项待同步", "\(count) 項待同步", "\(count) 項等緊同步", "\(count) pendente(s)")
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
