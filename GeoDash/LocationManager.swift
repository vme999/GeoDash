import CoreLocation
import CoreMotion
import Foundation
import MapKit
import Observation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    var latitude: Double = 0
    var longitude: Double = 0
    var altitude: Double = 0
    var speed: Double = -1
    var course: Double = -1
    var horizontalAccuracy: Double = -1
    var verticalAccuracy: Double = -1
    var pressurePascals: Double = -1
    var address: String = "... ..."
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var hasLocation: Bool = false
    var lastUpdatedAt: Date?

    private let manager = CLLocationManager()
    private let altimeter = CMAltimeter()
    private let isForPreviewsOnly: Bool
    private var activeGeocodeRequest: MKReverseGeocodingRequest?
    private var isBarometerUpdating: Bool = false

    /// When `true`, skips Core Location delegate wiring and barometer updates (for SwiftUI previews).
    init(forPreviewsOnly: Bool = false) {
        isForPreviewsOnly = forPreviewsOnly
        super.init()
        guard !forPreviewsOnly else { return }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = kCLHeadingFilterNone
        authorizationStatus = manager.authorizationStatus
    }

    deinit {
        stopBarometerUpdates()
        manager.stopUpdatingHeading()
    }

    func start() {
        guard !isForPreviewsOnly else { return }
        let status = manager.authorizationStatus
        authorizationStatus = status
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationAndHeadingUpdates()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func setBarometerUpdatesEnabled(_ isEnabled: Bool) {
        guard !isForPreviewsOnly else { return }
        if isEnabled {
            startBarometerUpdatesIfAvailable()
        } else {
            stopBarometerUpdates()
        }
    }

    private func startBarometerUpdatesIfAvailable() {
        guard !isBarometerUpdating else { return }
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        isBarometerUpdating = true
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            guard let pa = Self.pascals(fromPressure: data.pressure) else { return }
            Task { @MainActor in
                self.pressurePascals = pa
            }
        }
    }

    private func stopBarometerUpdates() {
        guard isBarometerUpdating else { return }
        altimeter.stopRelativeAltitudeUpdates()
        isBarometerUpdating = false
    }

    private func startHeadingUpdatesIfAvailable() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    private func startLocationAndHeadingUpdates() {
        manager.startUpdatingLocation()
        startHeadingUpdatesIfAvailable()
    }

    private static func pascals(fromPressure pressure: Any) -> Double? {
        if let pressureKPa = pressure as? NSNumber {
            return pressureKPa.doubleValue * 1_000
        }
        if let measurement = pressure as? Measurement<UnitPressure> {
            return measurement.converted(to: UnitPressure.newtonsPerMetersSquared).value
        }
        return nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startLocationAndHeadingUpdates()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        let coord = location.coordinate
        guard CLLocationCoordinate2DIsValid(coord) else { return }

        let alt = location.altitude
        let spd = location.speed
        let crs = location.course
        let hAcc = location.horizontalAccuracy
        let vAcc = location.verticalAccuracy

        Task { @MainActor in
            self.latitude = coord.latitude
            self.longitude = coord.longitude
            self.altitude = alt
            self.speed = spd
            if crs >= 0 {
                self.course = crs
            }
            self.horizontalAccuracy = hAcc
            self.verticalAccuracy = vAcc
            self.hasLocation = true
            self.lastUpdatedAt = location.timestamp
            self.reverseGeocode(location)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard heading >= 0 else { return }
        Task { @MainActor in
            self.course = heading
        }
    }

    private func reverseGeocode(_ location: CLLocation) {
        activeGeocodeRequest?.cancel()
        guard let request = MKReverseGeocodingRequest(location: location) else { return }
        request.preferredLocale = Locale(identifier: "en_US")
        activeGeocodeRequest = request

        Task { @MainActor in
            defer {
                if activeGeocodeRequest === request {
                    activeGeocodeRequest = nil
                }
            }
            do {
                let mapItems = try await request.mapItems
                guard let item = mapItems.first else { return }
                let line = systemFormattedAddress(from: item)
                address = line.isEmpty ? "—" : line
            } catch {}
        }
    }

    private func systemFormattedAddress(from item: MKMapItem) -> String {
        let raw = item.address?.fullAddress ?? item.address?.shortAddress ?? ""
        return raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

#if DEBUG
extension LocationManager {
    /// Sample data for Canvas; does not start location updates or the barometer.
    @MainActor
    static var previewMock: LocationManager {
        let m = LocationManager(forPreviewsOnly: true)
        m.authorizationStatus = .authorizedWhenInUse
        m.hasLocation = true
        m.latitude = 37.334_886
        m.longitude = -122.008_996
        m.altitude = 55
        m.speed = 4.5
        m.course = 315
        m.horizontalAccuracy = 8
        m.verticalAccuracy = 12
        m.pressurePascals = 101_125
        m.address = "1 Apple Park Way, Cupertino, CA 95014, USA"
        m.lastUpdatedAt = Date()
        return m
    }

    @MainActor
    static var previewDenied: LocationManager {
        let m = LocationManager(forPreviewsOnly: true)
        m.authorizationStatus = .denied
        return m
    }
}
#endif
