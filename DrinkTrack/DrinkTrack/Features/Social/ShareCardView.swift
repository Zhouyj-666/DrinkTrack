import SwiftUI

/// FR-SOC-03：分享饮酒打卡。生成可分享卡片：会话摘要 + 可选心率曲线截图。
/// §6.1 分享的边界：分享卡片上的心率曲线仅展示时间趋势，不展示精确数值（下面的图表特意不画坐标轴刻度）。
struct ShareCardView: View {
    let session: DrinkSessionEntity
    let includeHeartRateCurve: Bool
    @EnvironmentObject private var healthKitManager: HealthKitManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wineglass.fill").foregroundStyle(DesignSystem.heartRateLine)
                Text("DrinkTrack 饮酒打卡").font(.headline)
                Spacer()
                if let startedAt = session.startedAt {
                    Text(startedAt, style: .date).font(.caption).foregroundStyle(DesignSystem.secondaryInk)
                }
            }

            let logs = (session.logs as? Set<DrinkLogEntity> ?? []).sorted {
                ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
            }
            ForEach(logs, id: \.objectID) { log in
                if let rawCategory = log.category, let category = DrinkCategory(rawValue: rawCategory) {
                    HStack {
                        Text(category.emoji)
                        Text("\(category.displayName) \(Int(log.volumeMl))ml")
                        Spacer()
                        Text(StandardDrinkConverter.formatted(log.standardDrinks)).font(.caption)
                    }
                    .font(.footnote)
                }
            }

            if includeHeartRateCurve, !healthKitManager.recentHeartRatePoints.isEmpty {
                TrendOnlySparkline(points: healthKitManager.recentHeartRatePoints.map(\.value))
                    .frame(height: 50)
                Text("心率趋势（仅展示走势，不展示精确数值）")
                    .font(.caption2).foregroundStyle(DesignSystem.mutedInk)
            }

            Text(DisclaimerStrings.passiveAlertDisclaimer)
                .font(.caption2)
                .foregroundStyle(DesignSystem.mutedInk)
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

/// 不带坐标轴/刻度的纯趋势折线，专用于分享卡片（故意不暴露精确数值）。
private struct TrendOnlySparkline: View {
    let points: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxV = points.max() ?? 1
            let minV = points.min() ?? 0
            let span = max(maxV - minV, 1)
            Path { path in
                for (index, value) in points.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                    let y = geo.size.height * (1 - CGFloat((value - minV) / span))
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(DesignSystem.heartRateLine, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}
