import CoreLocation
import Observation
import WeatherKit

enum WeatherLoadState: Equatable {
    case idle
    case requestingLocation
    case loaded
    case unavailable(String)
}

@MainActor
@Observable
final class WeatherAdvisoryService: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherAdvisoryService()

    private(set) var state = WeatherLoadState.idle
    private(set) var temperatureCelsius: Double?
    private(set) var conditionSymbol = "cloud.sun.fill"
    private(set) var conditionText = ""
    private(set) var clothingAdvice = ""

    private let locationManager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() async {
        guard state != .requestingLocation else { return }
        state = .requestingLocation
        do {
            let location = try await requestLocation()
            let weather = try await WeatherService.shared.weather(for: location)
            let current = weather.currentWeather
            let celsius = current.apparentTemperature.converted(to: .celsius).value
            temperatureCelsius = celsius
            conditionSymbol = current.symbolName
            conditionText = current.condition.description
            clothingAdvice = Self.advice(for: celsius)
            state = .loaded
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            continuation?.resume(throwing: WeatherError.locationDenied)
            continuation = nil
        } else if manager.authorizationStatus == .authorizedWhenInUse ||
                    manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                locationManager.requestLocation()
            case .denied, .restricted:
                continuation.resume(throwing: WeatherError.locationDenied)
                self.continuation = nil
            @unknown default:
                continuation.resume(throwing: WeatherError.locationUnavailable)
                self.continuation = nil
            }
        }
    }

    private static func advice(for celsius: Double) -> String {
        switch celsius {
        case ..<5: String(localized: "天气较冷，建议穿保暖外套并注意防风。")
        case 5..<12: String(localized: "建议穿外套或毛衣，早晚注意保暖。")
        case 12..<20: String(localized: "建议穿薄外套，可根据活动量增减衣物。")
        case 20..<28: String(localized: "体感舒适，建议穿轻薄透气衣物。")
        default: String(localized: "天气炎热，建议穿透气衣物并注意补水防晒。")
        }
    }
}

private enum WeatherError: LocalizedError {
    case locationDenied
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .locationDenied: String(localized: "位置权限未开启")
        case .locationUnavailable: String(localized: "暂时无法获取位置")
        }
    }
}
