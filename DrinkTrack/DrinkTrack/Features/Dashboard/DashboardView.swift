import SwiftUI
import CoreData

/// §5.3 实时状态仪表盘：心率曲线、血氧展示、被动预警、会话开始/结束控制。
struct DashboardView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var drinkRepository: DrinkRepository
    @Environment(\.managedObjectContext) private var context

    @State private var activeSession: DrinkSessionEntity?
    @State private var showQuickLog = false
    @State private var activeAlertMessage: String?
    @State private var restingHeartRate: Double = 65

    private let supportsSpO2 = true // 简化判断；真实实现应查询设备型号或 HKQuantityType 可用性

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        SessionControlView(drinkRepository: drinkRepository, activeSession: $activeSession, showQuickLog: $showQuickLog)

                        HeartRateChartView(
                            points: healthKitManager.recentHeartRatePoints,
                            drinkMarks: drinkMarkTimestamps,
                            watchConnected: healthKitManager.watchSeemsConnected
                        )

                        if supportsSpO2 {
                            SpO2View(points: healthKitManager.recentSpO2Points, current: healthKitManager.latestSpO2)
                        }
                    }
                    .padding()
                }

                if let message = activeAlertMessage {
                    AlertToastView(message: message) { activeAlertMessage = nil }
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("仪表盘")
            .onAppear {
                activeSession = drinkRepository.fetchActiveSession()
                loadRestingHeartRate()
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                evaluateAlerts()
            }
            .sheet(isPresented: $showQuickLog) {
                if let session = activeSession {
                    QuickLogSheet(session: session, drinkRepository: drinkRepository)
                }
            }
        }
    }

    private var drinkMarkTimestamps: [Date] {
        guard let session = activeSession, let logs = session.logs as? Set<DrinkLogEntity> else { return [] }
        return logs.compactMap(\.timestamp).sorted()
    }

    private func loadRestingHeartRate() {
        let request = NSFetchRequest<UserProfileEntity>(entityName: "UserProfile")
        request.fetchLimit = 1
        if let profile = try? context.fetch(request).first {
            restingHeartRate = Double(profile.restingHeartRate)
        }
    }

    /// §6.2 被动预警判定：每分钟跑一次，而不是用持续运行的高频定时器。
    private func evaluateAlerts() {
        guard activeSession != nil else { return }

        let hrSamples = healthKitManager.recentHeartRatePoints.map { (timestamp: $0.timestamp, bpm: $0.value) }
        if let alert = AlertThresholdEngine.evaluateHeartRate(recentHeartRates: hrSamples, restingHeartRate: restingHeartRate) {
            activeAlertMessage = alert.message
            return
        }

        let spo2Samples = healthKitManager.recentSpO2Points.map { (timestamp: $0.timestamp, percent: $0.value) }
        if let alert = AlertThresholdEngine.evaluateSpO2(recentSpO2: spo2Samples) {
            activeAlertMessage = alert.message
        }
    }
}
