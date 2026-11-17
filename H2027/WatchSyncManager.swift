import Foundation
import SwiftData
import WatchConnectivity

struct WatchDosePayload: Codable {
    let id: String
    let medicationID: UUID
    let scheduleID: UUID
    let name: String
    let dosage: Double
    let unit: String
    let scheduledAt: Date
    let mealNote: String
    let status: String?
}

struct WatchSnapshot: Codable {
    let generatedAt: Date
    let languageCode: String
    let doses: [WatchDosePayload]
}

struct WatchDoseAction: Codable {
    let id: UUID
    let medicationID: UUID
    let scheduleID: UUID
    let scheduledAt: Date
    let recordedAt: Date
    let dosage: Double
    let unit: String
    let status: String
}

@MainActor
final class WatchSyncManager: NSObject, WCSessionDelegate {
    static let shared = WatchSyncManager()
    private var modelContainer: ModelContainer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var latestSnapshotData: Data?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func configure(modelContainer: ModelContainer) { self.modelContainer = modelContainer }

    func send(doses: [ScheduledDose], languageCode: String) {
        let snapshot = WatchSnapshot(generatedAt: .now, languageCode: languageCode, doses: doses.map {
            WatchDosePayload(id: $0.id, medicationID: $0.medicationID, scheduleID: $0.scheduleID,
                             name: $0.medicationName, dosage: $0.dosage, unit: $0.unit,
                             scheduledAt: $0.scheduledAt, mealNote: $0.mealNote,
                             status: $0.recordedStatus?.rawValue)
        })
        guard let data = try? encoder.encode(snapshot) else { return }
        latestSnapshotData = data
        transmitLatestSnapshot()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.transmitLatestSnapshot() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { receive(userInfo) }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["requestSnapshot"] as? Bool == true {
            Task { @MainActor in self.transmitLatestSnapshot(immediately: true) }
        } else {
            receive(message)
        }
    }
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let data = message["doseAction"] as? Data else {
            replyHandler(["accepted": false])
            return
        }
        Task { @MainActor in
            replyHandler(["accepted": self.importAction(data)])
        }
    }

    private func transmitLatestSnapshot(immediately: Bool = false) {
        guard let latestSnapshotData, WCSession.isSupported(),
              WCSession.default.activationState == .activated else { return }
#if os(iOS)
        guard WCSession.default.isWatchAppInstalled else { return }
#endif
        try? WCSession.default.updateApplicationContext(["snapshot": latestSnapshotData])
        if immediately, WCSession.default.isReachable {
            WCSession.default.sendMessage(["snapshot": latestSnapshotData], replyHandler: nil)
        }
    }

    nonisolated private func receive(_ message: [String: Any]) {
        guard let data = message["doseAction"] as? Data else { return }
        Task { @MainActor in self.importAction(data) }
    }

    @discardableResult
    private func importAction(_ data: Data) -> Bool {
        guard let action = try? decoder.decode(WatchDoseAction.self, from: data),
              let status = DoseStatus(rawValue: action.status), let modelContainer else { return false }
        let context = ModelContext(modelContainer)
        let actionID = action.id
        let descriptor = FetchDescriptor<DoseEvent>(predicate: #Predicate { $0.id == actionID })
        guard (try? context.fetchCount(descriptor)) == 0 else { return true }
        context.insert(DoseEvent(id: action.id, medicationID: action.medicationID,
                                 scheduleID: action.scheduleID, scheduledAt: action.scheduledAt,
                                 recordedAt: action.recordedAt, dosage: action.dosage, unit: action.unit,
                                 status: status, source: .watch))
        do {
            try context.save()
            return true
        } catch {
            return false
        }
    }
}
