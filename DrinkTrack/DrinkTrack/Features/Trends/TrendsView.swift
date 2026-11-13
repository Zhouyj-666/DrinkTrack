import SwiftUI

/// §5.4 长期趋势报告模块。
struct TrendsView: View {
    @EnvironmentObject private var drinkRepository: DrinkRepository
    @State private var logs: [DrinkLogEntity] = []
    @State private var sessions: [DrinkSessionEntity] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if logs.isEmpty {
                        ContentUnavailableView(
                            "暂无数据",
                            systemImage: "chart.bar",
                            description: Text("记录至少一次饮酒后，这里会展示你的饮酒频率、饮酒量趋势和健康对比报告")
                        )
                        .padding(.top, 60)
                    } else {
                        FrequencyChart(logs: logs)
                        VolumeTrendChart(logs: logs)
                        DrinkVsNonDrinkComparisonView(logs: logs)
                        historySection
                    }
                }
                .padding()
            }
            .navigationTitle("趋势报告")
            .task { load() }
            .refreshable { load() }
        }
    }

    /// FR-SOC-03 分享打卡的入口：从历史会话列表进入单次会话详情，再点右上角分享。
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("历史记录").font(.headline)
            ForEach(sessions.prefix(10), id: \.objectID) { session in
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    HStack {
                        if let startedAt = session.startedAt {
                            Text(startedAt, style: .date)
                        }
                        if session.status == "active" {
                            Text("进行中")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(DesignSystem.statusGood.opacity(0.15))
                                .foregroundStyle(DesignSystem.statusGood)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        let count = (session.logs as? Set<DrinkLogEntity>)?.count ?? 0
                        Text("\(count) 条记录").font(.caption).foregroundStyle(DesignSystem.secondaryInk)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(DesignSystem.mutedInk)
                    }
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func load() {
        let since = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? .distantPast
        logs = drinkRepository.allLogs(since: since)
        sessions = drinkRepository.fetchAllSessions()
    }
}
