import SwiftUI

/// FR-TREND-03：饮酒日 vs 非饮酒日对比（心率均值、HRV 均值）。
/// 至少需要 5 个饮酒日和 5 个非饮酒日数据才展示对比图，数据不足时提示"继续记录以生成对比报告"。
struct DrinkVsNonDrinkComparisonView: View {
    let logs: [DrinkLogEntity]
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @State private var result: DrinkDayComparisonResult?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("饮酒日 vs 非饮酒日").font(.headline)

            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let result {
                comparisonRow(title: "静息心率均值", drink: result.drinkDayAvgHR, nonDrink: result.nonDrinkDayAvgHR, unit: "bpm")
                comparisonRow(title: "HRV (SDNN) 均值", drink: result.drinkDayAvgHRV, nonDrink: result.nonDrinkDayAvgHRV, unit: "ms")
                Text("样本：\(result.drinkDayCount) 个饮酒日 / \(result.nonDrinkDayCount) 个非饮酒日（近 60 天）")
                    .font(.caption2).foregroundStyle(DesignSystem.mutedInk)
            } else {
                Text("继续记录以生成对比报告（需要至少 5 个饮酒日和 5 个非饮酒日的数据）")
                    .font(.footnote).foregroundStyle(DesignSystem.secondaryInk)
            }
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: logs.count) { await load() }
    }

    private func load() async {
        isLoading = true
        let drinkDays = Array(Set(logs.compactMap(\.timestamp)))
        result = await healthKitManager.fetchDrinkVsNonDrinkComparison(drinkDays: drinkDays)
        isLoading = false
    }

    @ViewBuilder
    private func comparisonRow(title: String, drink: Double?, nonDrink: Double?, unit: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            if let drink {
                Text("饮酒日 \(String(format: "%.0f", drink))\(unit)")
                    .font(.footnote).foregroundStyle(DesignSystem.statusWarning)
            }
            if let nonDrink {
                Text("非饮酒日 \(String(format: "%.0f", nonDrink))\(unit)")
                    .font(.footnote).foregroundStyle(DesignSystem.statusGood)
            }
        }
    }
}
