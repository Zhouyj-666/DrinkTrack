import SwiftUI
import Charts

/// FR-DASH-02：血氧展示。当前数值 + 过去 1 小时折线，低于 95% 变色提醒。
/// 不支持血氧的设备（Series 5 及更早）应该直接隐藏本模块，不展示空态——
/// 由调用方（DashboardView）决定是否渲染这个 View，这里不做"无数据"兜底文案。
struct SpO2View: View {
    let points: [HealthSamplePoint]
    let current: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("血氧饱和度").font(.headline)
                Spacer()
                if let current {
                    Text(String(format: "%.0f%%", current))
                        .font(.title3.bold())
                        .foregroundStyle(current < 95 ? DesignSystem.statusWarning : DesignSystem.primaryInk)
                }
            }

            if !points.isEmpty {
                Chart(points) { point in
                    LineMark(x: .value("时间", point.timestamp), y: .value("血氧", point.value))
                        .foregroundStyle(point.value < 95 ? DesignSystem.statusWarning : DesignSystem.spo2Line)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartYScale(domain: 85...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel().foregroundStyle(DesignSystem.mutedInk) }
                }
                .frame(height: 100)
            }

            Text("Apple Watch 血氧读数受皮肤温度、肤色、肢体位置影响，可能有误差")
                .font(.caption2)
                .foregroundStyle(DesignSystem.mutedInk)
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
