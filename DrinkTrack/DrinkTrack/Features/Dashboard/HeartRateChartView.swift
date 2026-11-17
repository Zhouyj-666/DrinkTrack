import SwiftUI
import Charts

/// FR-DASH-01：心率曲线 + 饮酒标记。
/// 配色遵循 dataviz skill：心率是单一数值的幅度编码 → 用 Sequential 单色线（见 DesignSystem.heartRateLine），
/// 不使用渐变彩虹色；饮酒标记点用独立的符号+直接标签，不额外引入新的分类色。
///
/// The card starts collapsed as a single status row. Expanding reveals the
/// recent (or in-session) line. The line updates when new HealthKit samples
/// arrive or when sampling is resumed on foreground / expand — not a
/// continuous clinical-grade live stream.
struct HeartRateChartView: View {
    let points: [HealthSamplePoint]
    let drinkMarks: [Date]
    let watchConnected: Bool
    var isInSession: Bool = false
    var onRefresh: (() -> Void)? = nil

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggleExpanded) {
                HStack(spacing: 8) {
                    Text(isInSession ? "心率（本场）" : "心率（最近 2 小时）")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    trailingStatus
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.mutedInk)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("heart-rate-toggle")
            .accessibilityLabel(isInSession ? "心率（本场）" : "心率（最近 2 小时）")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("轻点展开或收起心率折线图")

            if isExpanded {
                if points.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                        .accessibilityIdentifier("heart-rate-empty")
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
                    .accessibilityIdentifier("heart-rate-chart")
                }
            }
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if !watchConnected {
            Label("手表未连接", systemImage: "applewatch.slash")
                .font(.caption)
                .foregroundStyle(DesignSystem.statusWarning)
        } else if let latest = points.last {
            Text("\(Int(latest.value.rounded())) bpm")
                .font(.caption)
                .foregroundStyle(DesignSystem.mutedInk)
                .accessibilityLabel("最近心率 \(Int(latest.value.rounded())) bpm")
        }
    }

    private var emptyMessage: String {
        if !watchConnected {
            return "手表未连接，暂无心率曲线"
        }
        return isInSession ? "本场还没有心率读数" : "暂无心率数据"
    }

    private var accessibilityValue: String {
        let state = isExpanded ? "已展开" : "已收起"
        if !watchConnected {
            return "\(state)，手表未连接"
        }
        if let latest = points.last {
            return "\(state)，最近 \(Int(latest.value.rounded())) bpm"
        }
        return "\(state)，暂无读数"
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
        if isExpanded {
            onRefresh?()
        }
    }
}
