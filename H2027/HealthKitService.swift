import HealthKit
import Observation

enum HealthConnectionState: Equatable {
    case notRequested
    case requested
    case unavailable
    case failed(String)

    var title: String {
        switch self {
        case .notRequested: String(localized: "尚未请求")
        case .requested: String(localized: "已请求，可在健康中管理")
        case .unavailable: String(localized: "此设备不可用")
        case .failed: String(localized: "连接失败")
        }
    }
}

@MainActor
@Observable
final class HealthKitService {
    static let shared = HealthKitService()

    private(set) var state: HealthConnectionState
    private let store = HKHealthStore()
    var canRequestAccess: Bool {
        switch state {
        case .notRequested, .failed: true
        case .requested, .unavailable: false
        }
    }

    private init() {
        if !HKHealthStore.isHealthDataAvailable() {
            state = .unavailable
        } else if UserDefaults.standard.bool(forKey: "healthAccessRequested") {
            state = .requested
        } else {
            state = .notRequested
        }
    }

    func requestReadAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            UserDefaults.standard.set(true, forKey: "healthAccessRequested")
            state = .requested
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private static var readTypes: Set<HKObjectType> {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .heartRate,
            .bloodPressureSystolic,
            .bloodPressureDiastolic,
            .bloodGlucose,
        ]
        return Set(identifiers.compactMap(HKObjectType.quantityType(forIdentifier:)))
    }
}
