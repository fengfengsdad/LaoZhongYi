import CoreLocation
import Foundation
import WeatherKit

struct WeatherContextSnapshot: Sendable {
    let city: String
    let tempC: Double
    let condition: String
    let humidityPercent: Double
    let windSpeedKmh: Double
    let symbolName: String
    let source: String
}

@MainActor
final class WeatherContextService: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherContextService()

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorizationStatusDescription: String {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return "未授权定位"
        case .restricted, .denied:
            return "定位已关闭"
        case .authorizedAlways, .authorizedWhenInUse:
            return "定位已授权"
        @unknown default:
            return "定位未知"
        }
    }

    func fetchCurrentWeather() async -> WeatherContextSnapshot? {
        let location = await requestSingleLocation()

        let targetLocation: CLLocation
        let fallbackCity: String
        if let location {
            targetLocation = location
            fallbackCity = await reverseGeocodeCity(for: location) ?? "当前位置"
            AILog.info("Weather", "定位成功: \(fallbackCity) (\(String(format: "%.3f", location.coordinate.latitude)), \(String(format: "%.3f", location.coordinate.longitude)))")
        } else {
            // 定位未授权或模拟器未配置位置时，默认以深圳经纬度拉取实时天气
            targetLocation = CLLocation(latitude: 22.5431, longitude: 114.0579)
            fallbackCity = "深圳"
            AILog.warning("Weather", "未获取到系统定位（\(authorizationStatusDescription)），使用默认城市深圳坐标拉取气象")
        }

        // 1. 优先尝试 Apple WeatherKit
        do {
            let weather = try await WeatherService.shared.weather(for: targetLocation)
            let current = weather.currentWeather
            let tempC = current.temperature.converted(to: .celsius).value
            let windKmh = current.wind.speed.converted(to: .kilometersPerHour).value
            let humidityPercent = current.humidity * 100.0
            let conditionText = localizeCondition(current.condition)

            AILog.info("Weather", "WeatherKit 获取成功: \(fallbackCity) \(Int(tempC.rounded()))°C \(conditionText) 湿度\(Int(humidityPercent.rounded()))% 风速\(Int(windKmh.rounded()))km/h")

            return WeatherContextSnapshot(
                city: fallbackCity,
                tempC: tempC,
                condition: conditionText,
                humidityPercent: humidityPercent,
                windSpeedKmh: windKmh,
                symbolName: current.symbolName,
                source: "WeatherKit"
            )
        } catch {
            AILog.warning("Weather", "WeatherKit 不可用（可能未配置签名 Entitlement），切换 Open-Meteo 气象兜底: \(error.localizedDescription)")
        }

        // 2. 兜底使用 Open-Meteo（免 Key 实时气象接口）
        if let openMeteo = await fetchOpenMeteoWeather(for: targetLocation, city: fallbackCity) {
            return openMeteo
        }

        return nil
    }

    // MARK: - CoreLocation

    private func requestSingleLocation() async -> CLLocation? {
        let status = locationManager.authorizationStatus
        if status == .restricted || status == .denied {
            return nil
        }

        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            try? await Task.sleep(for: .milliseconds(500))
        }

        let updatedStatus = locationManager.authorizationStatus
        guard updatedStatus == .authorizedWhenInUse || updatedStatus == .authorizedAlways else {
            return nil
        }

        if let cached = locationManager.location,
           abs(cached.timestamp.timeIntervalSinceNow) < 600 {
            return cached
        }

        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(6))
                if let pending = self?.locationContinuation {
                    self?.locationContinuation = nil
                    pending.resume(returning: self?.locationManager.location)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in
            if let continuation = self.locationContinuation {
                self.locationContinuation = nil
                continuation.resume(returning: latest)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            AILog.warning("Location", "定位回调失败: \(error.localizedDescription)")
            if let continuation = self.locationContinuation {
                self.locationContinuation = nil
                continuation.resume(returning: nil)
            }
        }
    }

    private func reverseGeocodeCity(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let place = placemarks.first {
                return place.locality ?? place.administrativeArea ?? place.name
            }
        } catch {
            AILog.warning("Location", "反地理编码失败: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Open-Meteo Fallback

    private func fetchOpenMeteoWeather(for location: CLLocation, city: String) async -> WeatherContextSnapshot? {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
        guard let url = URL(string: urlString) else { return nil }

        let config = AIConfiguration.load()
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10
        sessionConfig.waitsForConnectivity = false

        let session = URLSession(configuration: sessionConfig)
        defer { session.finishTasksAndInvalidate() }
        _ = config

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let tempC = current["temperature_2m"] as? Double else {
                return nil
            }

            let humidity = current["relative_humidity_2m"] as? Double ?? 65.0
            let wind = current["wind_speed_10m"] as? Double ?? 8.0
            let code = current["weather_code"] as? Int ?? 0
            let mapped = mapWMOWeatherCode(code)

            AILog.info("Weather", "Open-Meteo 获取成功: \(city) \(Int(tempC.rounded()))°C \(mapped.text) 湿度\(Int(humidity.rounded()))%")

            return WeatherContextSnapshot(
                city: city,
                tempC: tempC,
                condition: mapped.text,
                humidityPercent: humidity,
                windSpeedKmh: wind,
                symbolName: mapped.symbol,
                source: "Open-Meteo"
            )
        } catch {
            AILog.warning("Weather", "Open-Meteo 请求失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func localizeCondition(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear:
            return "晴"
        case .partlyCloudy:
            return "多云"
        case .cloudy, .foggy, .haze, .smoky:
            return "阴"
        case .drizzle, .rain, .sunShowers:
            return "小雨"
        case .heavyRain, .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms:
            return "大雨"
        case .windy, .breezy:
            return "大风"
        case .snow, .heavySnow, .flurries, .sleet, .freezingRain, .freezingDrizzle, .blizzard, .wintryMix, .hail:
            return "雨雪降温"
        default:
            return condition.description
        }
    }

    private func mapWMOWeatherCode(_ code: Int) -> (text: String, symbol: String) {
        switch code {
        case 0, 1:
            return ("晴", "sun.max.fill")
        case 2:
            return ("多云", "cloud.sun.fill")
        case 3, 45, 48:
            return ("阴", "cloud.fill")
        case 51...67, 80...82:
            return ("小雨", "cloud.rain.fill")
        case 71...77, 85, 86:
            return ("雨雪降温", "cloud.snow.fill")
        case 95...99:
            return ("雷阵雨", "cloud.bolt.rain.fill")
        default:
            return ("多云", "cloud.sun.fill")
        }
    }
}
