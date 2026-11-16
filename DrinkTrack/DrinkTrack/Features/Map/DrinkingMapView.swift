import SwiftUI
import MapKit

/// 路书：上方始终是可交互地图，按时间串起走过的地方；下方是时间线 + 地点目录。
/// 只有用户明确标记（当前位置 / 长按选点 / 补点）的坐标才会上图；不会按地名估点，打开本页也不申请定位。
struct DrinkingMapView: View {
    @EnvironmentObject private var drinkRepository: DrinkRepository

    @State private var allStops: [RouteStop] = []
    @State private var places: [PlaceSummary] = []
    @State private var timeRange: RouteTimeRange = .all
    @State private var cameraPosition: MapCameraPosition = .region(RouteJournal.chinaOverviewRegion)
    @State private var selectedPinName: String?
    @State private var mapExpanded = false
    @State private var listMode: ListMode = .timeline
    @State private var showMarkSheet = false
    @State private var markCoordinate: CLLocationCoordinate2D?
    @State private var markInitialName = ""
    @State private var fillPlaceName: String?
    @State private var didFitCamera = false
    @State private var showExportSheet = false
    @State private var showExportEmptyHint = false

    private enum ListMode: String, CaseIterable, Identifiable {
        case timeline
        case places

        var id: String { rawValue }
        var title: String {
            switch self {
            case .timeline: return "时间线"
            case .places: return "地点"
            }
        }
    }

    private var filteredStops: [RouteStop] {
        RouteJournal.filter(allStops, range: timeRange)
    }

    private var pins: [(number: Int, stop: RouteStop)] {
        RouteJournal.numberedPins(from: filteredStops)
    }

    private var selectedPin: (number: Int, stop: RouteStop)? {
        guard let selectedPinName else { return nil }
        return pins.first { $0.stop.name == selectedPinName }
    }

    private var nameOnlyPlaces: [RouteJournalNameOnlyPlace] {
        places.filter { !$0.hasCoordinate }.map {
            RouteJournalNameOnlyPlace(name: $0.name, lastAt: $0.lastAt)
        }
    }

    private var exportPayload: RouteJournalExport {
        RouteJournalExport.build(
            stops: allStops,
            nameOnlyPlaces: nameOnlyPlaces,
            range: timeRange
        )
    }

    private var hasAnyRouteData: Bool {
        !allStops.isEmpty || places.contains { !$0.hasCoordinate }
    }


    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mapBlock
                if !mapExpanded {
                    controls
                    if let selected = selectedPin {
                        selectedRecap(selected)
                    }
                    listBlock
                }
            }
            .background(DesignSystem.pagePlane)
            .navigationTitle("路书")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if exportPayload.canExport {
                            showExportSheet = true
                        } else {
                            showExportEmptyHint = true
                        }
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("分享路书")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        markCoordinate = nil
                        markInitialName = ""
                        fillPlaceName = nil
                        showMarkSheet = true
                    } label: {
                        Label("标记地点", systemImage: "mappin.and.ellipse")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mapExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: mapExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(mapExpanded ? "缩小地图" : "放大地图")
                }
            }
            .sheet(isPresented: $showMarkSheet, onDismiss: { reload() }) {
                if let fillPlaceName {
                    MarkPlaceSheet(
                        initialCoordinate: markCoordinate,
                        initialName: fillPlaceName,
                        mode: .fillExisting
                    )
                    .environmentObject(drinkRepository)
                } else {
                    MarkPlaceSheet(
                        initialCoordinate: markCoordinate,
                        initialName: markInitialName,
                        mode: .newMark
                    )
                    .environmentObject(drinkRepository)
                }
            }
            .alert("还没有可导出的路书", isPresented: $showExportEmptyHint) {
                Button("好", role: .cancel) {}
            } message: {
                Text(RouteJournalExport.emptyHint(hasAnyData: hasAnyRouteData, range: timeRange))
            }
            .sheet(isPresented: $showExportSheet) {
                RouteJournalExportSheet(
                    payload: exportPayload,
                    mappedStops: RouteJournal.filter(allStops, range: timeRange)
                )
            }
            .task { reload(fit: true) }
            .onReceive(NotificationCenter.default.publisher(for: .drinkTrackDataDidChange)) { _ in
                reload(fit: false)
            }
            .onChange(of: timeRange) { _, _ in
                selectedPinName = nil
                fitMap(animated: true)
            }
        }
    }

    // MARK: - Map

    private var mapBlock: some View {
        ZStack(alignment: .bottom) {
            MapReader { proxy in
                Map(position: $cameraPosition, selection: $selectedPinName) {
                    if filteredStops.count >= 2 {
                        MapPolyline(coordinates: RouteJournal.polylineCoordinates(from: filteredStops))
                            .stroke(Color("AccentColor").opacity(0.75), lineWidth: 3)
                    }
                    ForEach(pins, id: \.stop.name) { item in
                        Annotation(item.stop.name, coordinate: item.stop.coordinate, anchor: .bottom) {
                            RoutePinBadge(number: item.number, selected: item.stop.name == selectedPinName)
                        }
                        .tag(item.stop.name)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onEnded { value in
                            guard case .second(true, let drag) = value,
                                  let point = drag?.location,
                                  let coordinate = proxy.convert(point, from: .local) else { return }
                            markCoordinate = coordinate
                            markInitialName = ""
                            fillPlaceName = nil
                            showMarkSheet = true
                        }
                )
            }
            .accessibilityLabel("路书地图")

            if pins.isEmpty {
                emptyMapHint
                    .padding()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: mapExpanded ? 520 : 320, idealHeight: mapExpanded ? 640 : 380)
        .clipShape(RoundedRectangle(cornerRadius: mapExpanded ? 0 : 0))
    }

    private var emptyMapHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(allStops.isEmpty ? "还没有可以画在地图上的地点" : "这个时间范围里还没有坐标")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.primaryInk)
            Text("记酒时点「用当前位置」，或在这里点「标记地点」/长按地图选点。只输入名称的地点会出现在下方列表里，不会自动估坐标。打开本页不会申请定位。")
                .font(.caption)
                .foregroundStyle(DesignSystem.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Controls / list

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("时间范围", selection: $timeRange) {
                ForEach(RouteTimeRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 10)

            Picker("列表", selection: $listMode) {
                ForEach(ListMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack {
                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.secondaryInk)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
        .background(DesignSystem.pagePlane)
    }

    private var summaryLine: String {
        let placeCount = RouteJournal.uniquePlaceCount(in: filteredStops)
        let stopCount = filteredStops.count
        if stopCount == 0 {
            let nameOnly = places.filter { !$0.hasCoordinate }.count
            if nameOnly > 0 {
                return "地图上还没有点 · 列表里有 \(nameOnly) 个仅名称地点"
            }
            return "还没有路书足迹"
        }
        return "走过 \(placeCount) 个地方 · \(stopCount) 次停留"
    }

    private func selectedRecap(_ item: (number: Int, stop: RouteStop)) -> some View {
        let place = places.first { $0.name == item.stop.name }
        return Group {
            if let place {
                NavigationLink {
                    PlaceDetailView(place: place)
                } label: {
                    recapLabel(number: item.number, stop: item.stop, place: place)
                }
                .buttonStyle(.plain)
            } else {
                recapLabel(number: item.number, stop: item.stop, place: nil)
            }
        }
    }

    private func recapLabel(number: Int, stop: RouteStop, place: PlaceSummary?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoutePinBadge(number: number, selected: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(.headline)
                    .foregroundStyle(DesignSystem.primaryInk)
                Text(stopRecapLine(stop, place: place))
                    .font(.caption)
                    .foregroundStyle(DesignSystem.secondaryInk)
                if let place, !place.categoryMix.isEmpty {
                    Text(PlaceRecap.mixLine(for: place))
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.mutedInk)
                }
                if place != nil {
                    Text("查看地点详情")
                        .font(.caption)
                        .foregroundStyle(Color("AccentColor"))
                }
            }
            Spacer()
            if place != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.mutedInk)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(DesignSystem.chartSurface)
    }

    private var listBlock: some View {
        List {
            if listMode == .timeline {
                Section {
                    if filteredStops.isEmpty {
                        Text(timelineEmptyText)
                            .font(.footnote)
                            .foregroundStyle(DesignSystem.secondaryInk)
                            .listRowBackground(DesignSystem.chartSurface)
                    } else {
                        ForEach(Array(filteredStops.reversed())) { stop in
                            let number = pins.first(where: { $0.stop.name == stop.name })?.number
                            timelineRow(stop: stop, number: number)
                                .listRowBackground(
                                    stop.name == selectedPinName
                                        ? Color("AccentColor").opacity(0.08)
                                        : DesignSystem.chartSurface
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedPinName = stop.name
                                }
                        }
                    }
                } header: {
                    Text("时间线")
                } footer: {
                    Text("按时间排列每一次停留；再次去过的地方会再出现一次。仅名称、没有坐标的地点请看「地点」。")
                }
            } else {
                Section {
                    if places.isEmpty {
                        Text("还没有地点。记酒时填写地点，或点右上角「标记地点」。")
                            .font(.footnote)
                            .foregroundStyle(DesignSystem.secondaryInk)
                            .listRowBackground(DesignSystem.chartSurface)
                    } else {
                        ForEach(places) { place in
                            NavigationLink {
                                PlaceDetailView(place: place)
                            } label: {
                                PlaceRow(place: place, isSelected: place.name == selectedPinName)
                            }
                            .listRowBackground(
                                place.name == selectedPinName
                                    ? Color("AccentColor").opacity(0.08)
                                    : DesignSystem.chartSurface
                            )
                        }
                    }
                } header: {
                    Text("全部地点")
                } footer: {
                    if places.contains(where: { !$0.hasCoordinate }) {
                        Text("没有坐标的地点只出现在列表里，不会在地图上估一个位置。可在地点详情里点「用当前位置补点」。")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var timelineEmptyText: String {
        if allStops.isEmpty {
            return "还没有带坐标的停留。可用「标记地点」、长按地图，或在记酒时点「用当前位置」。"
        }
        return "这个时间范围里还没有停留，可切换到「全部」看看。"
    }

    @ViewBuilder
    private func timelineRow(stop: RouteStop, number: Int?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let number {
                RoutePinBadge(number: number, selected: stop.name == selectedPinName)
            } else {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(Color("AccentColor"))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(.body)
                    .foregroundStyle(DesignSystem.primaryInk)
                Text(stopRecapLine(stop, place: places.first { $0.name == stop.name }))
                    .font(.caption)
                    .foregroundStyle(DesignSystem.secondaryInk)
                Text(stop.kind == .placeMark ? "地点标记" : "饮酒场次")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.mutedInk)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func stopRecapLine(_ stop: RouteStop, place: PlaceSummary?) -> String {
        var parts: [String] = [PlaceRecap.formatDate(stop.at)]
        if stop.kind == .session {
            if let place {
                parts.append("\(place.sessionCount) 场")
            }
            if stop.volumeML > 0 {
                parts.append(PlaceRecap.formatML(stop.volumeML))
            }
        } else {
            parts.append("标记")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Data

    private func reload(fit: Bool = false) {
        allStops = drinkRepository.routeStops()
        places = drinkRepository.placeSummaries()
        if let selectedPinName, pins.contains(where: { $0.stop.name == selectedPinName }) == false {
            self.selectedPinName = nil
        }
        if fit || !didFitCamera {
            fitMap(animated: false)
            didFitCamera = true
        }
    }

    private func fitMap(animated: Bool) {
        let coords = RouteJournal.polylineCoordinates(from: filteredStops)
        let region = RouteJournal.fitRegion(for: coords)
        let next: MapCameraPosition = .region(region)
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                cameraPosition = next
            }
        } else {
            cameraPosition = next
        }
    }
}

private struct RoutePinBadge: View {
    let number: Int
    var selected = false

    var body: some View {
        ZStack {
            Circle()
                .fill(selected ? Color("AccentColor") : Color("AccentColor").opacity(0.92))
                .frame(width: selected ? 30 : 26, height: selected ? 30 : 26)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .accessibilityLabel("路书第 \(number) 站")
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
    @EnvironmentObject private var drinkRepository: DrinkRepository
    let place: PlaceSummary

    @State private var showFillSheet = false

    var body: some View {
        List {
            Section {
                recap
            }

            if !place.hasCoordinate {
                Section {
                    Text("这个地点目前只有名称，还没有坐标，所以不会出现在地图上。可以点「用当前位置补点」，或下次记酒时点「用当前位置」。小酌场不会按地名自动估点。")
                        .font(.footnote)
                        .foregroundStyle(DesignSystem.secondaryInk)
                    Button {
                        showFillSheet = true
                    } label: {
                        Label("用当前位置补点", systemImage: "location")
                    }
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
                    Text(place.hasCoordinate
                        ? "还没有关联的饮酒场次。若这是路书标记，它不会算成一场酒。"
                        : "还没有可以打开的场次。")
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
        .sheet(isPresented: $showFillSheet) {
            MarkPlaceSheet(
                initialCoordinate: nil,
                initialName: place.name,
                mode: .fillExisting
            )
            .environmentObject(drinkRepository)
        }
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
        formatter.timeStyle = .short
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
