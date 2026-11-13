import Foundation
import CoreLocation

/// FR-DR-05：录入时「用当前位置」一键填地点。
///
/// - 只在用户点按钮时才申请「使用 App 期间」定位权限，不在启动时弹窗。
/// - 只取一次位置（requestLocation），反查成「区 + 街道/地标」这样的文字后就丢掉坐标，
///   不保存经纬度，也不在后台定位。
/// - 失败（拒绝授权、无信号、反查失败）时给出中文原因，手动输入不受影响。
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        case locating
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var completion: ((String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 请求一次当前位置，成功后把地名回调给调用方。
    func fillCurrentPlace(_ completion: @escaping (String) -> Void) {
        self.completion = completion
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .locating
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .failed("定位权限已关闭，可在「设置 > 隐私与安全性 > 定位服务」里给 DrinkTrack 打开，或直接手动输入地点。")
        default:
            state = .locating
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.state == .locating else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.state = .failed("没有获得定位权限，可以直接手动输入地点。")
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await self.reverseGeocode(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.state = .failed("暂时没能获取到位置，可以直接手动输入地点。")
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN"))
            if let name = placemarks.first.map(Self.displayName(for:)), !name.isEmpty {
                state = .idle
                completion?(name)
            } else {
                state = .failed("没能识别出这个位置的地名，可以直接手动输入。")
            }
        } catch {
            state = .failed("没能识别出这个位置的地名，可以直接手动输入。")
        }
        completion = nil
    }

    /// 「朝阳区 三里屯路」这种粒度：区/县 + 地标名或街道，不带门牌号。
    private static func displayName(for placemark: CLPlacemark) -> String {
        var parts: [String] = []
        if let district = placemark.subLocality ?? placemark.locality {
            parts.append(district)
        }
        if let name = placemark.areasOfInterest?.first ?? placemark.thoroughfare ?? placemark.name,
           !parts.contains(name) {
            parts.append(name)
        }
        return parts.joined(separator: " ")
    }
}
