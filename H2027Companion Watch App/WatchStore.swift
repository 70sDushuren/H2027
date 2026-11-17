import Foundation
import Observation
import WatchConnectivity

struct WatchDose: Codable, Identifiable {
    let id: String, name: String, unit: String, mealNote: String
    let medicationID: UUID, scheduleID: UUID
    let dosage: Double
    let scheduledAt: Date
    var status: String?
}

private struct WatchSnapshot: Codable {
    let generatedAt: Date
    let languageCode: String
    let doses: [WatchDose]
}

private struct WatchDoseAction: Codable {
    let id: UUID, medicationID: UUID, scheduleID: UUID
    let scheduledAt: Date, recordedAt: Date
    let dosage: Double
    let unit: String, status: String
}

@Observable @MainActor
final class WatchStore: NSObject, WCSessionDelegate {
    var doses: [WatchDose] = []
    var languageCode = "zh-Hans"
    var isPhoneReachable = false
    private let snapshotKey = "watchSnapshot"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    var copy: WatchCopy { WatchCopy(languageCode: languageCode) }
    var completedCount: Int { doses.filter { $0.status == "taken" }.count }

    override init() {
        super.init()
        restoreSnapshot()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func record(_ dose: WatchDose, status: String) {
        guard let index = doses.firstIndex(where: { $0.id == dose.id }) else { return }
        doses[index].status = status
        persistCurrentSnapshot()
        let action = WatchDoseAction(id: UUID(), medicationID: dose.medicationID, scheduleID: dose.scheduleID,
            scheduledAt: dose.scheduledAt, recordedAt: .now, dosage: dose.dosage, unit: dose.unit, status: status)
        guard let data = try? encoder.encode(action), WCSession.isSupported() else { return }
        let message: [String: Any] = ["doseAction": data]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in WCSession.default.transferUserInfo(message) }
        } else { WCSession.default.transferUserInfo(message) }
    }

    func requestRefresh() {
        guard WCSession.isSupported(), WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["requestSnapshot": true], replyHandler: nil)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.isPhoneReachable = session.isReachable }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isPhoneReachable = session.isReachable }
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
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }
    private func restoreSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else { return }
        applySnapshot(data)
    }
    private func persistCurrentSnapshot() {
        let snapshot = WatchSnapshot(generatedAt: .now, languageCode: languageCode, doses: doses)
        if let data = try? encoder.encode(snapshot) { UserDefaults.standard.set(data, forKey: snapshotKey) }
    }

    static var preview: WatchStore {
        let store = WatchStore()
        store.doses = [WatchDose(id: "preview", name: "Metformin", unit: "mg", mealNote: "",
            medicationID: UUID(), scheduleID: UUID(), dosage: 500, scheduledAt: .now, status: nil)]
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
    var connected: String { choose("iPhone connected", "iPhone 已连接", "iPhone 已連線", "iPhone 已連線", "iPhone ligado") }
    var offline: String { choose("Works offline", "离线可用", "離線可用", "離線可用", "Funciona offline") }
    func status(_ value: String) -> String {
        switch value {
        case "taken": taken
        case "snoozed": snooze
        case "skipped": choose("Skipped", "已跳过", "已略過", "已略過", "Ignorado")
        default: choose("Missed", "漏服", "漏服", "漏食", "Em falta")
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
