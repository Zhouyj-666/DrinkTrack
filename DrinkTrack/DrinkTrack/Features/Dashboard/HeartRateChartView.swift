import SwiftUI
import Charts

/// FR-DASH-01：心率曲线 + 饮酒标记。
/// 配色遵循 dataviz skill：心率是单一数值的幅度编码 → 用 Sequential 单色线（见 DesignSystem.heartRateLine），
/// 不使用渐变彩虹色；饮酒标记点用独立的符号+直接标签，不额外引入新的分类色。
struct HeartRateChartView: View {
    let points: [HealthSamplePoint]
    let drinkMarks: [Date]
    let watchConnected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("心率（最近 2 小时）").font(.headline)
                Spacer()
                if !watchConnected {
                    Label("手表未连接", systemImage: "applewatch.slash")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.statusWarning)
                }
            }

            if points.isEmpty {
                placeholderChart
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("时间", point.timestamp), y: .value("心率", point.value))
                            .foregroundStyle(DesignSystem.heartRateLine)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                    }
                    ForEach(drinkMarks, id: \.self) { mark in
                        RuleMark(x: .value("饮酒", mark))
                            .foregroundStyle(DesignSystem.mutedInk)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top) {
                                Text("🍷").font(.caption)
                            }
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(DesignSystem.gridline)
                        AxisValueLabel().foregroundStyle(DesignSystem.mutedInk)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel().foregroundStyle(DesignSystem.mutedInk)
                    }
                }
                .frame(height: 180)
            }
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 无数据时的虚线占位（FR-DASH-01：手表未佩戴时展示虚线 + 提示）。
    private var placeholderChart: some View {
        VStack {
            Rectangle()
                .fill(DesignSystem.gridline)
                .frame(height: 1)
                .overlay(
                    Rectangle().fill(DesignSystem.mutedInk)
                        .frame(height: 1)
                        .mask(DashedLine())
                )
            Text("暂无心率数据").font(.caption).foregroundStyle(DesignSystem.mutedInk)
        }
        .frame(height: 180)
    }
}

private struct DashedLine: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
}
