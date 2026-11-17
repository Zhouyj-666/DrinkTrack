import SwiftUI
import Charts

/// FR-DASH-01：可展开的心率卡片。收起只留一行状态；展开显示近 2 小时（或本场）折线。
/// 折线随新的 HealthKit 样本和回到前台/展开时的采样恢复更新，不是连续的临床级实时流。
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
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignSystem.burgundy)
                        Text("心率")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DesignSystem.primaryInk)
                    }
                    Spacer(minLength: 8)
                    trailingStatus
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.muted2)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("heart-rate-toggle")
            .accessibilityLabel("心率")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCorner, style: .continuous))
        .shadow(color: Color(red: 90 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.04), radius: 2, y: 1)
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if !watchConnected {
            Label("手表未连接", systemImage: "applewatch.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.warningGold)
                .labelStyle(.titleAndIcon)
        } else if let latest = points.last {
            Text("\(Int(latest.value.rounded())) bpm")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.warningGold)
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
