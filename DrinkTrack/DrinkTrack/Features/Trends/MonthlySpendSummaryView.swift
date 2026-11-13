import SwiftUI

/// FR-DR-07：本月花费摘要。花费只给用户本人看，不出现在好友动态或分享卡上。
struct MonthlySpendSummaryView: View {
    let monthTotalFen: Int
    let monthToDateFen: Int
    let sessionAverageFen: Int?
    let sessionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("花费").font(.headline)
            HStack(alignment: .top, spacing: 12) {
                spendTile(title: "本月花费", value: UserPreferences.formatYuan(fen: monthTotalFen))
                spendTile(title: "本月至今花费", value: UserPreferences.formatYuan(fen: monthToDateFen), caption: "截至今天")
                spendTile(
                    title: "单场平均花费",
                    value: sessionAverageFen.map { UserPreferences.formatYuan(fen: $0) } ?? "—",
                    caption: sessionCount > 0 ? "\(sessionCount) 场有花费记录" : "还没有记录花费"
                )
            }
            Text("花费只保存在本机，只有你自己能看到。")
                .font(.caption2)
                .foregroundStyle(DesignSystem.mutedInk)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func spendTile(title: String, value: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(DesignSystem.secondaryInk)
            Text(value)
                .font(.headline)
                .monospacedDigit()
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.mutedInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
