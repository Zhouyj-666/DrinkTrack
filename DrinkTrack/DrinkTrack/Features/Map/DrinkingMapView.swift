import SwiftUI
import MapKit

/// 喝酒地图：按地点查看自己记下的场次。
/// 有坐标的地点显示在地图上；只有名称的地点仍出现在列表里，不会被丢掉，也不会按地名估算图钉。
struct DrinkingMapView: View {
    @EnvironmentObject private var drinkRepository: DrinkRepository
    @State private var places: [PlaceSummary] = []
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedPlaceName: String?

    var body: some View {
        NavigationStack {
            Group {
                if places.isEmpty {
                    emptyState
                } else {
                    populated
                }
            }
            .background(DesignSystem.pagePlane)
            .navigationTitle("喝酒地图")
            .task { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .drinkTrackDataDidChange)) { _ in
                reload()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有地点记录", systemImage: "map")
        } description: {
            Text("记酒的时候可以填写地点，也可以点「用当前位置」。\n\n用当前位置会把这个地点标到地图上；只输入名称的地点会出现在列表里，不会自动估算坐标。\n\n打开这张地图不会再要定位权限，也不会在后台定位。")
        }
        .padding()
    }

    private var populated: some View {
        VStack(spacing: 0) {
            if hasPins {
                mapSection
                    .frame(minHeight: 240, idealHeight: 300, maxHeight: 340)
                if let selected = selectedPlace {
                    selectedRecap(selected)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            } else {
                nameOnlyBanner
            }
            placeList
        }
    }

    private var hasPins: Bool { places.contains(where: \.hasCoordinate) }

    private var selectedPlace: PlaceSummary? {
        guard let selectedPlaceName else { return nil }
        return places.first { $0.name == selectedPlaceName }
    }

    private var mapSection: some View {
        Map(position: $cameraPosition, selection: $selectedPlaceName) {
            ForEach(places.filter(\.hasCoordinate)) { place in
                if let coordinate = place.coordinate {
                    Marker(place.name, systemImage: "wineglass", coordinate: coordinate)
                        .tint(Color("AccentColor"))
                        .tag(place.name)
                }
            }
        }
        .mapStyle(.standard)
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .accessibilityLabel("喝酒地图")
    }

    private var nameOnlyBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mappin.slash")
                .foregroundStyle(Color("AccentColor"))
            Text("这些地点还没有坐标，所以还不能显示在地图上。下次记酒时点「用当前位置」，同一地点就会出现在地图上。")
                .font(.footnote)
                .foregroundStyle(DesignSystem.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.chartSurface)
    }

    private func selectedRecap(_ place: PlaceSummary) -> some View {
        NavigationLink {
            PlaceDetailView(place: place)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color("AccentColor"))
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.headline)
                        .foregroundStyle(DesignSystem.primaryInk)
                    Text(PlaceRecap.line(for: place))
                        .font(.caption)
                        .foregroundStyle(DesignSystem.secondaryInk)
                    if !place.categoryMix.isEmpty {
                        Text(PlaceRecap.mixLine(for: place))
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.mutedInk)
                    }
                    Text("查看这些场次")
                        .font(.caption)
                        .foregroundStyle(Color("AccentColor"))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.mutedInk)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(DesignSystem.chartSurface)
        }
        .buttonStyle(.plain)
    }

    private var placeList: some View {
        List {
            Section {
                ForEach(places) { place in
                    NavigationLink {
                        PlaceDetailView(place: place)
                    } label: {
                        PlaceRow(place: place, isSelected: place.name == selectedPlaceName)
                    }
                    .listRowBackground(
                        place.name == selectedPlaceName
                            ? Color("AccentColor").opacity(0.08)
                            : DesignSystem.chartSurface
                    )
                }
            } header: {
                Text(hasPins ? "全部地点" : "地点")
            } footer: {
                if hasPins, places.contains(where: { !$0.hasCoordinate }) {
                    Text("没有坐标的地点只出现在列表里，不会在地图上估一个位置。")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func reload() {
        let next = drinkRepository.placeSummaries()
        places = next
        if let selectedPlaceName, next.contains(where: { $0.name == selectedPlaceName }) == false {
            self.selectedPlaceName = nil
        }
        fitMap(to: next)
    }

    private func fitMap(to places: [PlaceSummary]) {
        let coords = places.compactMap(\.coordinate)
        guard !coords.isEmpty else { return }
        if coords.count == 1 {
            cameraPosition = .region(MKCoordinateRegion(
                center: coords[0],
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            ))
            return
        }
        var minLat = coords[0].latitude
        var maxLat = minLat
        var minLon = coords[0].longitude
        var maxLon = minLon
        for coord in coords {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.8, 0.02)
        let lonDelta = max((maxLon - minLon) * 1.8, 0.02)
        cameraPosition = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        ))
    }
}

private struct PlaceRow: View {
    let place: PlaceSummary
    var isSelected = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: place.hasCoordinate ? "mappin.circle.fill" : "mappin.slash.circle")
                .font(.title3)
                .foregroundStyle(place.hasCoordinate ? Color("AccentColor") : DesignSystem.mutedInk)
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.body)
                    .foregroundStyle(DesignSystem.primaryInk)
                Text(PlaceRecap.line(for: place))
                    .font(.caption)
                    .foregroundStyle(DesignSystem.secondaryInk)
                if !place.categoryMix.isEmpty {
                    Text(PlaceRecap.mixLine(for: place))
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.mutedInk)
                        .lineLimit(1)
                }
                if !place.hasCoordinate {
                    Text("还没有坐标")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.mutedInk)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// 单个地点的摘要和场次列表。
struct PlaceDetailView: View {
    let place: PlaceSummary

    var body: some View {
        List {
            Section {
                recap
            }

            if !place.hasCoordinate {
                Section {
                    Text("这个地点目前只有名称，还没有坐标，所以不会出现在地图上。下次在这里记酒时点「用当前位置」，就可以标到地图上。小酌场不会按地名自动估点。")
                        .font(.footnote)
                        .foregroundStyle(DesignSystem.secondaryInk)
                }
            } else if let coordinate = place.coordinate {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    ))) {
                        Marker(place.name, systemImage: "wineglass", coordinate: coordinate)
                            .tint(Color("AccentColor"))
                    }
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets())
                    .mapControls { }
                }
            }

            Section("场次") {
                if place.sessions.isEmpty {
                    Text("还没有可以打开的场次。")
                        .foregroundStyle(DesignSystem.mutedInk)
                } else {
                    ForEach(place.sessions, id: \.objectID) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            sessionRow(session)
                        }
                    }
                }
            }
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var recap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PlaceRecap.line(for: place))
                .font(.body)
            if place.totalVolumeML > 0 {
                Text(PlaceRecap.volumeLine(for: place))
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.secondaryInk)
            }
            if !place.categoryMix.isEmpty {
                Text(PlaceRecap.mixLine(for: place))
                    .font(.caption)
                    .foregroundStyle(DesignSystem.mutedInk)
            }
        }
        .padding(.vertical, 4)
    }

    private func sessionRow(_ session: DrinkSessionEntity) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let startedAt = session.startedAt {
                    Text(startedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "zh_CN")))
                }
                let count = (session.logs as? Set<DrinkLogEntity>)?.count ?? 0
                Text("\(count) 条记录")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.mutedInk)
            }
            if session.status == "active" {
                Text("进行中")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignSystem.statusGood.opacity(0.15))
                    .foregroundStyle(DesignSystem.statusGood)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }
}

enum PlaceRecap {
    static func line(for place: PlaceSummary) -> String {
        var parts: [String] = []
        parts.append("\(place.sessionCount) 场")
        if place.logCount > 0 {
            parts.append("\(place.logCount) 条记录")
        }
        if let lastAt = place.lastAt {
            parts.append("上次 \(formatDate(lastAt))")
        }
        return parts.joined(separator: " · ")
    }

    static func volumeLine(for place: PlaceSummary) -> String {
        "\(formatML(place.totalVolumeML)) · ≈\(formatStandard(place.totalStandardDrinks))"
    }

    static func mixLine(for place: PlaceSummary) -> String {
        place.categoryMix.map { item in
            "\(item.category.displayName) \(percent(item.fraction))"
        }.joined(separator: "  ")
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func formatML(_ ml: Double) -> String {
        ml == ml.rounded() ? "\(Int(ml)) ml" : String(format: "%.0f ml", ml)
    }

    static func formatStandard(_ value: Double) -> String {
        String(format: "%.1f 标准饮品", value)
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }
}
