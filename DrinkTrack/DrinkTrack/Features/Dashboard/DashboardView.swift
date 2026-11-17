import SwiftUI
import CoreData

/// §5.3 实时状态仪表盘：会话控制、可展开心率、今天/本周/本月摘要。
struct DashboardView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var drinkRepository: DrinkRepository
    @EnvironmentObject private var calendarDay: CalendarDayContext
    @Environment(\.managedObjectContext) private var context

    @State private var activeSession: DrinkSessionEntity?
    @State private var lastEndedSession: DrinkSessionEntity?
    @State private var showQuickLog = false
    @State private var activeAlert: AlertThresholdEngine.AlertResult?
    @State private var sessionAlerts: [AlertThresholdEngine.AlertResult] = []
    @State private var hrvBaseline: Double?
    @State private var restingHeartRate: Double = 65
    @State private var logRevision = 0
    @State private var glanceTodayVolume: Double = 0
    @State private var glanceTodayStandard: Double = 0
    @State private var glanceWeekVolume: Double = 0
    @State private var glanceWeekStandard: Double = 0
    @State private var glanceWeekSessions: Int = 0
    @State private var glanceMonthSessions: Int = 0
    @State private var glanceMonthPlaces: Int = 0
    @State private var glanceMonthSpendFen: Int = 0
    @State private var glanceTopBrand: String?
    @State private var glanceMix: [DrinkMixShare] = []

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: DesignSystem.cardSpacing) {
                        SessionControlView(
                            drinkRepository: drinkRepository,
                            activeSession: $activeSession,
                            showQuickLog: $showQuickLog,
                            latestHeartRate: healthKitManager.latestInSessionHeartRate,
                            latestSpO2: healthKitManager.latestInSessionSpO2
                        )
                        .id(logRevision)

                        HeartRateChartView(
                            points: healthKitManager.chartHeartRatePoints,
                            drinkMarks: drinkMarkTimestamps,
                            watchConnected: healthKitManager.watchSeemsConnected,
                            isInSession: healthKitManager.isChartInSession,
                            onRefresh: {
                                Task { await healthKitManager.resumeIfPossible() }
                            }
                        )

                        DashboardSummaryStack(
                            todayVolumeML: glanceTodayVolume,
                            todayStandard: glanceTodayStandard,
                            weekVolumeML: glanceWeekVolume,
                            weekStandard: glanceWeekStandard,
                            weekSessionCount: glanceWeekSessions,
                            monthSessionCount: glanceMonthSessions,
                            monthPlaceCount: glanceMonthPlaces,
                            monthSpendFen: glanceMonthSpendFen,
                            showSpend: UserPreferences.spendTrackingEnabled,
                            topBrand: glanceTopBrand,
                            mix: glanceMix,
                            lastEndedSession: lastEndedSession,
                            lastSessionIsToday: lastSessionIsToday
                        )

                        if activeSession != nil {
                            SessionLogListView(session: activeSession)
                                .id(logRevision)
                            SessionAlertsCard(alerts: sessionAlerts)
                        }
                    }
                    .padding(.horizontal, DesignSystem.screenPadding)
                    .padding(.vertical, 8)
                }
                .sipScreenBackground()

                if let alert = activeAlert {
                    AlertBannerView(alert: alert) { activeAlert = nil }
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("仪表盘")
            .background(DesignSystem.pagePlane)
            .task {
                activeSession = drinkRepository.fetchActiveSession()
                healthKitManager.setActiveSessionWindow(startedAt: activeSession?.startedAt)
                loadSessionAlerts()
                loadLastEndedSession()
                loadGlance()
                loadRestingHeartRate()
                await healthKitManager.resumeIfPossible()
                await refreshHRVBaseline()
                await refreshRestingHeartRateFromHealth()
                evaluateAlerts()
            }
            .onChange(of: activeSession) { _, session in
                healthKitManager.setActiveSessionWindow(startedAt: session?.startedAt)
                loadSessionAlerts()
                loadLastEndedSession()
                loadGlance()
                evaluateAlerts()
            }
            .onReceive(NotificationCenter.default.publisher(for: .drinkTrackDataDidChange)) { _ in
                activeSession = drinkRepository.fetchActiveSession()
                loadSessionAlerts()
                loadLastEndedSession()
                loadGlance()
            }
            .onChange(of: calendarDay.todayStart) { _, _ in
                loadGlance()
                loadLastEndedSession()
            }
            .onChange(of: healthKitManager.recentHeartRatePoints.count) { _, _ in
                evaluateAlerts()
            }
            .onChange(of: healthKitManager.recentSpO2Points.count) { _, _ in
                evaluateAlerts()
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                Task {
                    if activeSession != nil, UserPreferences.sessionAlertsEnabled, UserPreferences.hrvAlertsEnabled {
                        _ = await healthKitManager.fetchLatestHRV()
                        if hrvBaseline == nil {
                            hrvBaseline = await healthKitManager.fetchSevenDayHRVAverage()
                        }
                    }
                    evaluateAlerts()
                }
            }
            .sheet(isPresented: $showQuickLog, onDismiss: {
                logRevision += 1
                loadGlance()
                loadLastEndedSession()
            }) {
                if let session = activeSession {
                    QuickLogSheet(session: session, drinkRepository: drinkRepository)
                }
            }
        }
    }

    private var lastSessionIsToday: Bool {
        _ = selectedTab

        guard let session = lastEndedSession else { return false }
        let date = session.endedAt ?? session.startedAt ?? Date.distantPast
        return DashboardGlanceBuilder.isOnLocalDay(date, now: calendarDay.now, calendar: .current)
    }

    private var drinkMarkTimestamps: [Date] {
        _ = logRevision
        guard let session = activeSession, let logs = session.logs as? Set<DrinkLogEntity> else { return [] }
        return logs.compactMap(\.timestamp).sorted()
    }

    private func loadLastEndedSession() {
        lastEndedSession = drinkRepository.fetchArchivedSessions(limit: 1).first
    }

    private func loadGlance() {
        let calendar = Calendar.current
        let now = calendarDay.now
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let startOfLastWeek = calendar.date(byAdding: .day, value: -7, to: startOfWeek) ?? startOfWeek
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfWeek
        let logs = drinkRepository.allLogs(since: min(startOfLastWeek, startOfMonth))
        let result = DashboardGlanceBuilder.metrics(
            logs: logs,
            sessions: drinkRepository.fetchAllSessions(limit: 400),
            now: now,
            calendar: calendar
        )
        glanceTodayVolume = result.todayVolumeML
        glanceTodayStandard = result.todayStandard
        glanceWeekVolume = result.weekVolumeML
        glanceWeekStandard = result.weekStandard
        glanceWeekSessions = result.weekSessionCount
        glanceMonthSessions = result.monthSessionCount
        glanceMonthPlaces = result.monthPlaceCount
        glanceMonthSpendFen = result.monthSpendFen
        glanceTopBrand = result.topBrand
        glanceMix = result.mix
    }

    private func loadRestingHeartRate() {
        let request = NSFetchRequest<UserProfileEntity>(entityName: "UserProfile")
        request.fetchLimit = 1
        if let profile = try? context.fetch(request).first, profile.restingHeartRate > 0 {
            restingHeartRate = Double(profile.restingHeartRate)
        } else {
            restingHeartRate = AlertThresholdEngine.defaultRestingHeartRate
        }
    }

    private func refreshRestingHeartRateFromHealth() async {
        guard healthKitManager.connectionState.isUsable else { return }
        if let avg = await healthKitManager.fetchRestingHeartRateAverage(), avg > 0 {
            restingHeartRate = avg
        }
    }

    private func loadSessionAlerts() {
        if let session = activeSession {
            sessionAlerts = drinkRepository.alerts(for: session)
        } else {
            sessionAlerts = []
            activeAlert = nil
        }
    }

    private func refreshHRVBaseline() async {
        guard healthKitManager.connectionState.isUsable else { return }
        hrvBaseline = await healthKitManager.fetchSevenDayHRVAverage()
        _ = await healthKitManager.fetchLatestHRV()
    }

    /// §6.2 被动提示判定：有新采样或每 30 秒检查一次。同类提示 30 分钟内不重复弹出。
    private func evaluateAlerts() {
        guard let session = activeSession else { return }
        guard UserPreferences.sessionAlertsEnabled else { return }

        var candidates: [AlertThresholdEngine.AlertResult] = []

        if UserPreferences.heartRateAlertsEnabled {
            let hrSamples = healthKitManager.recentHeartRatePoints.map { (timestamp: $0.timestamp, bpm: $0.value) }
            if let alert = AlertThresholdEngine.evaluateHeartRate(recentHeartRates: hrSamples, restingHeartRate: restingHeartRate) {
                candidates.append(alert)
            }
        }

        if UserPreferences.spo2AlertsEnabled {
            let spo2Samples = healthKitManager.recentSpO2Points.map { (timestamp: $0.timestamp, percent: $0.value) }
            if let alert = AlertThresholdEngine.evaluateSpO2(recentSpO2: spo2Samples) {
                candidates.append(alert)
            }
        }

        if UserPreferences.hrvAlertsEnabled,
           let current = healthKitManager.latestHRV,
           let baseline = hrvBaseline,
           let alert = AlertThresholdEngine.evaluateHRV(currentSDNN: current, baseline7DayAverage: baseline) {
            candidates.append(alert)
        }

        for alert in candidates {
            if drinkRepository.appendAlert(alert, to: session) {
                sessionAlerts = drinkRepository.alerts(for: session)
                activeAlert = alert
            }
        }
    }
}
