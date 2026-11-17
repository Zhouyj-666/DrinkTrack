import SwiftUI
import MapKit

/// Compact 饮酒地图 teaser on the dashboard. Tapping switches to the Map tab.
struct DashboardRoutePreviewCard: View {
    let stops: [RouteStop]
    let placeCount: Int
    let latestPlaceName: String?
    let onOpenMap: () -> Void

    private var pins: [(number: Int, stop: RouteStop)] {
        RouteJournal.numberedPins(from: stops)
    }

    var body: some View {
        Button(action: onOpenMap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("饮酒地图", systemImage: "map")
                        .font(.headline)
                        .foregroundStyle(DesignSystem.primaryInk)
                    Spacer()
                    Text("查看")
                        .font(.caption)
                        .foregroundStyle(Color("AccentColor"))
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.mutedInk)
                }

                if pins.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Color("AccentColor"))
                        Text("还没有画在地图上的地点。记酒时点「用当前位置」，或去地图页标记地点。")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                } else {
                    Map(initialPosition: .region(RouteJournal.fitRegion(for: pins.map(\.stop.coordinate)))) {
                        if stops.count >= 2 {
                            MapPolyline(coordinates: RouteJournal.polylineCoordinates(from: stops))
                                .stroke(Color("AccentColor").opacity(0.7), lineWidth: 2)
                        }
                        ForEach(pins, id: \.stop.name) { item in
                            Annotation(item.stop.name, coordinate: item.stop.coordinate, anchor: .bottom) {
                                ZStack {
                                    Circle()
                                        .fill(Color("AccentColor"))
                                        .frame(width: 20, height: 20)
                                    Text("\(item.number)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .allowsHitTesting(false)
                    .mapControls { }

                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.secondaryInk)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.chartSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开饮酒地图")
    }

    private var caption: String {
        var parts = ["走过 \(placeCount) 个地方"]
        if let latestPlaceName, !latestPlaceName.isEmpty {
            parts.append("最近：\(latestPlaceName)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Optional body snapshot. Only shows rows with real HealthKit values.
struct DashboardBodySnapshotCard: View {
    let restingHeartRate: Double?
    let hrvSDNN: Double?
    let sleepMinutes: Double?

    private var hasAny: Bool {
        restingHeartRate != nil || hrvSDNN != nil || sleepMinutes != nil
    }

    var body: some View {
        if hasAny {
            VStack(alignment: .leading, spacing: 10) {
                Text("身体快照")
                    .font(.headline)
                if let restingHeartRate {
                    row(icon: "heart.fill", title: "静息心率", value: String(format: "%.0f bpm", restingHeartRate))
                }
                if let hrvSDNN {
                    row(icon: "waveform.path.ecg", title: "HRV (SDNN)", value: String(format: "%.0f ms", hrvSDNN))
                }
                if let sleepMinutes {
                    row(icon: "bed.double.fill", title: "昨晚睡眠", value: formatSleep(sleepMinutes))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.chartSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color("AccentColor"))
                .frame(width: 22)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(DesignSystem.secondaryInk)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(DesignSystem.primaryInk)
        }
    }

    private func formatSleep(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let hours = total / 60
        let mins = total % 60
        if hours > 0 {
            return "\(hours) 小时 \(mins) 分"
        }
        return "\(mins) 分"
    }
}