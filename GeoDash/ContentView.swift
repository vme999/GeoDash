import SwiftUI
import MapKit
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var locationManager: LocationManager
    @State private var isPageVisible: Bool = false
    /// Brief nav-title dim pulse when location `lastUpdatedAt` advances (user-visible refresh cue).
    @State private var isTitleUpdateFlashActive: Bool = false
    /// When false, skips `requestWhenInUseAuthorization` (used for SwiftUI previews with a mock manager).
    private let startsLiveLocationWhenAppeared: Bool

    /// Prefer MapKit's user location so basemap tiles align with the blue dot (matches Apple Maps); CL-only pins can show the wrong area in some regions.
    @State private var mapCameraPosition: MapCameraPosition = .userLocation(
        followsHeading: false,
        fallback: .automatic
    )

    init(
        locationManager: LocationManager = LocationManager(),
        startsLiveLocationWhenAppeared: Bool = true
    ) {
        _locationManager = State(initialValue: locationManager)
        self.startsLiveLocationWhenAppeared = startsLiveLocationWhenAppeared
    }

    private var isDenied: Bool {
        locationManager.authorizationStatus == .denied
            || locationManager.authorizationStatus == .restricted
    }

    private enum GPSSignalStrength {
        case unknown
        case excellent
        case good
        case poor
    }

    private var gpsSignalStrength: GPSSignalStrength {
        guard locationManager.hasLocation else { return .unknown }
        let accuracy = locationManager.horizontalAccuracy
        guard accuracy >= 0 else { return .unknown }
        if accuracy <= 10 { return .excellent }
        if accuracy <= 30 { return .good }
        return .poor
    }

    private var gpsSignalColor: Color {
        switch gpsSignalStrength {
            case .unknown:
                return Color(uiColor: .secondaryLabel)
            case .excellent:
                return Color(uiColor: .systemGreen)
            case .good:
                return Color(uiColor: .systemBlue)
            case .poor:
                return Color(uiColor: .systemOrange)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isDenied {
                    deniedView
                } else {
                    locationView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            // Empty system title avoids duplicating the principal label (duplicate inflates bar height vs Dynamic Island).
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("GeoDash")
                        .font(.headline)
                        .foregroundStyle(gpsSignalColor)
                        .opacity(isTitleUpdateFlashActive ? 0.38 : 1)
                        // Nudge toward the status bar / Dynamic Island without overlapping side items (time, indicators).
                        .offset(y: 0)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .onChange(of: locationManager.lastUpdatedAt) { _, newValue in
                guard newValue != nil else { return }
                withAnimation(.easeOut(duration: 0.10)) {
                    isTitleUpdateFlashActive = true
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    withAnimation(.easeIn(duration: 0.25)) {
                        isTitleUpdateFlashActive = false
                    }
                }
            }
        }
        .onAppear {
            isPageVisible = true
            if startsLiveLocationWhenAppeared {
                locationManager.start()
            }
            syncBarometerUpdateState()
        }
        .onDisappear {
            isPageVisible = false
            syncBarometerUpdateState()
        }
        .onChange(of: scenePhase) { _, _ in
            syncBarometerUpdateState()
        }
    }

    private func syncBarometerUpdateState() {
        let shouldEnableBarometer = isPageVisible && scenePhase != .background
        locationManager.setBarometerUpdatesEnabled(shouldEnableBarometer)
    }

    /// Fills the safe area: top cards use intrinsic height; metrics + map share the rest (SwiftUI constraints, UIKit Auto Layout under the hood).
    private var locationView: some View {
        ViewThatFits(in: .vertical) {
            locationColumnFillingScreen
            locationColumnScrollable
        }
        .padding(.horizontal)
        .padding(.vertical, interCardSpacing)
    }

    /// Address, coordinates, and metrics — shared by fill and scroll layouts so vertical spacing stays identical.
    private var topLocationCards: some View {
        VStack(spacing: interCardSpacing) {
            addressCard
            coordinatesCard
            metricsTwoByTwo
        }
    }

    /// One `VStack` spacing value for every card edge gap; map absorbs remaining height (no stretched metric rows).
    private var locationColumnFillingScreen: some View {
        VStack(spacing: interCardSpacing) {
            topLocationCards
            mapPreviewCard
                .frame(minHeight: 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            lastUpdatedFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var locationColumnScrollable: some View {
        ScrollView {
            VStack(spacing: interCardSpacing) {
                topLocationCards
                mapPreviewCard
                    .frame(height: mapFallbackHeight)
                lastUpdatedFooter
            }
        }
    }

    private var metricsTwoByTwo: some View {
        let courseDisplay = formatCourseDisplay()
        return VStack(spacing: interCardSpacing) {
            HStack(spacing: interCardSpacing) {
                altitudeWithAccuracyCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                infoCard(title: "Pressure", value: formatPressure(), unit: "kPa")
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            HStack(spacing: interCardSpacing) {
                infoCard(title: "Speed", value: formatSpeed(), unit: "km/h")
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                infoCard(
                    title: "Course",
                    value: courseDisplay.value,
                    unit: courseDisplay.unit,
                    suffix: courseDisplay.direction
                )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    /// Vertical gap between adjacent cards (and stack top/bottom padding in `locationView`).
    private let interCardSpacing: CGFloat = 10
    private let cardTitleToValueSpacing: CGFloat = 12

    /// Minimum height for address text (two body lines at current Dynamic Type) so it is not vertically squeezed.
    private var addressBodyMinHeightForLines: CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .body)
        return ceil(font.lineHeight * 2.6)
    }

    /// Grouped-style section header: subordinate to content, matches Settings / Health hierarchy.
    private func cardSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    /// Primary numeric (or coordinate) value on cards — same text style everywhere; avoid `minimumScaleFactor`
    /// so half-width metric cells don’t render smaller than full-width rows (layout gives each value fair width).
    private func cardValueText(_ string: String) -> some View {
        Text(string)
            .font(.title2)
            .fontWeight(.semibold)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.25), value: string)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.primary)
    }

    private func cardUnitText(_ string: String) -> some View {
        Text(string)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: cardTitleToValueSpacing) {
            cardSectionTitle("Address")

            Text(locationManager.address)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: addressBodyMinHeightForLines, alignment: .topLeading)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var coordinatesCard: some View {
        VStack(alignment: .leading, spacing: cardTitleToValueSpacing) {
            cardSectionTitle("Coordinates")

            HStack(spacing: interCardSpacing) {
                coordinateColumn(
                    value: formatCoordinateValue(locationManager.latitude),
                    direction: formatCoordinateDirection(locationManager.latitude, isLatitude: true)
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 40)

                coordinateColumn(
                    value: formatCoordinateValue(locationManager.longitude),
                    direction: formatCoordinateDirection(locationManager.longitude, isLatitude: false)
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Scroll fallback map height when `ViewThatFits` chooses the scroll column (e.g. very large Dynamic Type).
    private let mapFallbackHeight: CGFloat = 200
    /// Camera distance (meters) chosen to match roughly the previous ~600 m region footprint.
    private let mapLookAtDistanceMeters: CLLocationDistance = 520

    private var mapPreviewCard: some View {
        readOnlyLocationMap
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Map")
            .onAppear { syncMapCameraWithLocation() }
            .onChange(of: locationManager.latitude) { _, _ in syncMapCameraWithLocation() }
            .onChange(of: locationManager.longitude) { _, _ in syncMapCameraWithLocation() }
    }

    private var readOnlyLocationMap: some View {
        Map(position: $mapCameraPosition) {
            // Uses the same user fix MapKit applies to Apple Maps tiles (not raw CL coordinates on the map).
            UserAnnotation()
        }
        // Satellite base with road and place labels (hybrid); flat elevation reduces parallax vs the user dot.
        .mapStyle(.hybrid(elevation: .flat))
        .allowsHitTesting(false)
    }

    private func syncMapCameraWithLocation() {
        guard locationManager.hasLocation else { return }
        let coord = CLLocationCoordinate2D(
            latitude: locationManager.latitude,
            longitude: locationManager.longitude
        )
        guard CLLocationCoordinate2DIsValid(coord) else { return }

        let fallback = MapCamera(
            centerCoordinate: coord,
            distance: mapLookAtDistanceMeters,
            heading: 0,
            pitch: 0
        )
        mapCameraPosition = .userLocation(
            followsHeading: false,
            fallback: .camera(fallback)
        )
    }

    private func coordinateColumn(
        value: String,
        direction: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            cardValueText(value)
            cardUnitText("°\(direction)")
        }
    }

    private var altitudeWithAccuracyCard: some View {
        VStack(alignment: .leading, spacing: cardTitleToValueSpacing) {
            cardSectionTitle("Altitude")

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                cardValueText(formatAltitude())
                Text("m")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(altitudeAccuracyCaption())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func altitudeAccuracyCaption() -> String {
        let v = locationManager.verticalAccuracy
        if v >= 0 {
            return String(format: "(±%.0f m)", v)
        }
        return "(—)"
    }

    private func infoCard(title: String, value: String, unit: String, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: cardTitleToValueSpacing) {
            cardSectionTitle(title)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                cardValueText(value)
                let unitText = unit + suffix
                if !unitText.isEmpty {
                    cardUnitText(unitText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var lastUpdatedFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.clockwise")
            Text(formatLastUpdatedAt())
                .monospacedDigit()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Location Access Denied", systemImage: "location.slash")
        } description: {
            Text("Please enable location access in Settings to use GeoDash.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func formatCoordinateValue(_ value: Double) -> String {
        String(format: "%.5f", abs(value))
    }

    private func formatCoordinateDirection(_ value: Double, isLatitude: Bool) -> String {
        isLatitude
            ? (value >= 0 ? "N" : "S")
            : (value >= 0 ? "E" : "W")
    }

    private func formatAltitude() -> String {
        guard locationManager.verticalAccuracy >= 0 else { return "--" }
        return String(format: "%.0f", locationManager.altitude)
    }

    private func formatSpeed() -> String {
        guard locationManager.speed >= 0 else { return "0" }
        return String(format: "%.0f", locationManager.speed * 3.6)
    }

    /// Snaps true course/heading to the nearest 10° so the Course card does not update on small sensor noise.
    private static func displayCourseDegreesStep10(_ degrees: Double) -> Double {
        let stepped = (degrees / 10.0).rounded() * 10.0
        var normalized = stepped.truncatingRemainder(dividingBy: 360.0)
        if normalized < 0 { normalized += 360.0 }
        return normalized
    }

    private func formatCourseDisplay() -> (value: String, unit: String, direction: String) {
        let course = locationManager.course
        guard course >= 0 else { return ("--", "", "") }
        let display = Self.displayCourseDegreesStep10(course)
        return (String(format: "%.0f", display), "°", courseDirection(from: display))
    }

    private func formatPressure() -> String {
        guard locationManager.pressurePascals >= 0 else { return "--" }
        let kPa = locationManager.pressurePascals / 1_000.0
        return String(format: "%.0f", kPa)
    }

    private func formatLastUpdatedAt() -> String {
        guard let lastUpdatedAt = locationManager.lastUpdatedAt else { return "--" }
        return Self.lastUpdatedAtFormatter.string(from: lastUpdatedAt)
    }

    private static let lastUpdatedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private func courseDirection(from degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return directions[index]
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView(
                locationManager: LocationManager.previewMock,
                startsLiveLocationWhenAppeared: false
            )
            .previewDisplayName("Filled (mock)")

            ContentView(
                locationManager: LocationManager.previewDenied,
                startsLiveLocationWhenAppeared: false
            )
            .previewDisplayName("Denied")
        }
    }
}
#endif
