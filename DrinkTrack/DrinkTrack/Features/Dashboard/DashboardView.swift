import SwiftUI
import CoreData

/// §5.3 实时状态仪表盘：饮酒记录列表、心率曲线、血氧展示、被动预警、会话开始/结束控制。
struct DashboardView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var drinkRepository: DrinkRepository
    @EnvironmentObject private var calendarDay: CalendarDayContext
    @Environment(\.managedObjectContext) private var context

    @State private var activeSession: DrinkSessionEntity?
    /// 最近一场已结束的会话，用于小结卡片（查看详情 / 生成分享卡）。12 小时内仍显示「上一场已结束」。
    @State private var lastEndedSession: DrinkSessionEntity?
    @State private var showQuickLog = false
    @State private var activeAlert: AlertThresholdEngine.AlertResult?
    @State private var sessionAlerts: [AlertThresholdEngine.AlertResult] = []
    @State private var hrvBaseline: Double?
    @State private var restingHeartRate: Double = 65
    /// 录入后自增，用来强制刷新依赖会话关系的派生数据（Core Data 关系变更不会自动发布）
    @State private var logRevision = 0
    @State private var glanceTodayVolume: Double = 0
    @State private var glanceTodayStandard: Double = 0
    @State private var glanceWeekVolume: Double = 0
    @State private var glanceWeekStandard: Double = 0
    @State private var glanceWeekSessions: Int = 0
    @State private var glanceLastWeekVolume: Double = 0
    @State private var glanceLastWeekStandard: Double = 0
    @State private var glanceMonthSessions: Int = 0
    @State private var glanceMonthPlaces: Int = 0
    @State private var glanceMonthSpendFen: Int = 0
    @State private var glanceMonthSpendCount: Int = 0
    @State private var glanceTopCategory: DrinkCategory?
    @State private var glanceTopBrand: String?
    @State private var glanceMix: [(DrinkCategory, Double)] = []
    @State private var routeStops: [RouteStop] = []
    @State private var routePlaceCount: Int = 0
    @State private var routeLatestPlace: String?
    @State private var bodyRestingHR: Double?
    @State private var bodyHRV: Double?
    @State private var bodySleepMinutes: Double?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        SessionControlView(
                            drinkRepository: drinkRepository,
                            activeSession: $activeSession,
                            showQuickLog: $showQuickLog,
                            latestHeartRate: healthKitManager.latestInSessionHeartRate,
                            latestSpO2: healthKitManager.latestInSessionSpO2
                        )
                        .id(logRevision)

                        // 健康数据没连上时，把状态和自查方法摆在显眼处，
                        // 而不是让用户对着一张空图表猜为什么没数据
                        if !healthKitManager.connectionState.isUsable {
                            HealthConnectionStatusView(
                                state: healthKitManager.connectionState,
                                authorizationError: healthKitManager.authorizationError,
                                isRequesting: healthKitManager.isRequestingAuthorization,
                                onRequestAuthorization: {
                                    Task { await healthKitManager.requestAuthorization() }
                                },
                                onRefresh: {
                                    Task { await healthKitManager.refreshConnectionState() }
                                }
                            )
                        }

                        HeartRateChartView(
                            points: healthKitManager.chartHeartRatePoints,
                            drinkMarks: drinkMarkTimestamps,
                            watchConnected: healthKitManager.watchSeemsConnected,
                            isInSession: healthKitManager.isChartInSession
                        )

                        if !healthKitManager.chartSpO2Points.isEmpty || healthKitManager.latestInSessionSpO2 != nil {
                            SpO2View(
                                points: healthKitManager.chartSpO2Points,
                                current: healthKitManager.isChartInSession
                                    ? healthKitManager.latestInSessionSpO2
                                    : healthKitManager.latestSpO2
                            )
                        }

                        DashboardGlanceView(
                            todayVolumeML: glanceTodayVolume,
                            todayStandard: glanceTodayStandard,
                            weekVolumeML: glanceWeekVolume,
                            weekStandard: glanceWeekStandard,
                            weekSessionCount: glanceWeekSessions,
                            lastWeekVolumeML: glanceLastWeekVolume,
                            lastWeekStandard: glanceLastWeekStandard,
                            monthSessionCount: glanceMonthSessions,
                            monthPlaceCount: glanceMonthPlaces,
                            monthSpendFen: glanceMonthSpendFen,
                            monthSpendCount: glanceMonthSpendCount,
                            showSpend: UserPreferences.spendTrackingEnabled,
                            topCategory: glanceTopCategory,
                            topBrand: glanceTopBrand,
                            mix: glanceMix
                        )

                        DashboardRoutePreviewCard(
                            stops: routeStops,
                            placeCount: routePlaceCount,
                            latestPlaceName: routeLatestPlace,
                            onOpenMap: { selectedTab = .map }
                        )

                        DashboardBodySnapshotCard(
                            restingHeartRate: bodyRestingHR,
                            hrvSDNN: bodyHRV,
                            sleepMinutes: bodySleepMinutes
                        )

                        if activeSession == nil, let last = lastEndedSession {
                            NavigationLink {
                                SessionDetailView(session: last)
                            } label: {
                                LastSessionCard(session: last)
                            }
                            .buttonStyle(.plain)
                        }

                        // 录入的记录现在第一时间可见（修复「记录不显示」）
                        if activeSession != nil {
                            SessionLogListView(session: activeSession)
                                .id(logRevision)
                            SessionAlertsCard(alerts: sessionAlerts)
                        }

                    }
                    .padding()
                }

                if let alert = activeAlert {
                    AlertBannerView(alert: alert) { activeAlert = nil }
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("仪表盘")
            .task {
                activeSession = drinkRepository.fetchActiveSession()
                healthKitManager.setActiveSessionWindow(startedAt: activeSession?.startedAt)
                loadSessionAlerts()
                loadLastEndedSession()
                loadGlance()
                loadRoutePreview()
                loadRestingHeartRate()
                await healthKitManager.resumeIfPossible()
                await refreshHRVBaseline()
                await refreshRestingHeartRateFromHealth()
                await refreshBodySnapshot()
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
                loadRoutePreview()
            }
            .onChange(of: calendarDay.todayStart) { _, _ in
                loadGlance()
                loadRoutePreview()
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
                // 录入面板关掉后刷新列表和图表标记
                logRevision += 1
                loadGlance()
                loadRoutePreview()
                loadLastEndedSession()
            }) {
                if let session = activeSession {
                    QuickLogSheet(session: session, drinkRepository: drinkRepository)
                }
            }
        }
    }

    private var drinkMarkTimestamps: [Date] {
        _ = logRevision // 建立依赖，录入后重新计算
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
        glanceLastWeekVolume = result.lastWeekVolumeML
        glanceLastWeekStandard = result.lastWeekStandard
        glanceMonthSessions = result.monthSessionCount
        glanceMonthPlaces = result.monthPlaceCount
        glanceMonthSpendFen = result.monthSpendFen
        glanceMonthSpendCount = result.monthSpendCount
        glanceTopCategory = result.topCategory
        glanceTopBrand = result.topBrand
        glanceMix = result.mix
    }

    private func loadRoutePreview() {
        let stops = drinkRepository.routeStops()
        routeStops = stops
        routePlaceCount = RouteJournal.uniquePlaceCount(in: stops)
        routeLatestPlace = stops.last?.name
    }

    private func refreshBodySnapshot() async {
        guard healthKitManager.connectionState.isUsable else {
            bodyRestingHR = nil
            bodyHRV = nil
            bodySleepMinutes = nil
            return
        }
        if let avg = await healthKitManager.fetchRestingHeartRateAverage(), avg > 0 {
            bodyRestingHR = avg
        } else {
            bodyRestingHR = nil
        }
        if let hrv = await healthKitManager.fetchLatestHRV(), hrv > 0 {
            bodyHRV = hrv
        } else {
            bodyHRV = healthKitManager.latestHRV
        }
        if let sleep = await healthKitManager.fetchLastNightSleep(), sleep.totalMinutes > 0 {
            bodySleepMinutes = sleep.totalMinutes
        } else {
            bodySleepMinutes = nil
        }
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

    /// Prefer a real HealthKit resting-HR average when one exists, without
    /// inventing a value when Health is off or has no samples.
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

/// 仪表盘上的「上一场」小结：结束会话后马上能看到本场摘要，点进去生成分享卡。
private struct LastSessionCard: View {
    @ObservedObject var session: DrinkSessionEntity

    private var logs: [DrinkLogEntity] {
        Array((session.logs as? Set<DrinkLogEntity>) ?? [])
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.title2)
                .foregroundStyle(DesignSystem.statusGood)
            VStack(alignment: .leading, spacing: 2) {
                Text(isRecent ? "上一场已结束" : "最近一场").font(.subheadline.weight(.medium))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.secondaryInk)
                    .lineLimit(1)
            }
            Spacer()
            Text("查看 / 分享")
                .font(.caption)
                .foregroundStyle(DesignSystem.heartRateLine)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(DesignSystem.mutedInk)
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var isRecent: Bool {
        guard let endedAt = session.endedAt else { return false }
        return Date().timeIntervalSince(endedAt) < 12 * 3600
    }

    private var summary: String {
        let start = session.startedAt ?? Date()
        let end = session.endedAt ?? start
        let volume = logs.reduce(0.0) { $0 + $1.volumeMl }
        let standard = logs.reduce(0.0) { $0 + $1.standardDrinks }
        var text = ""
        if !isRecent {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            text += formatter.string(from: end) + " · "
        }
        text += String(format: "%d 杯 · %.0f ml · ≈%.1f 标准饮品 · ", logs.count, volume, standard)
        text += UserPreferences.formatDuration(end.timeIntervalSince(start))
        if let place = session.locationName, !place.isEmpty {
            text += " · " + place
        }
        let alertCount = AlertThresholdEngine.decode(session.value(forKey: "alertsJSON") as? String).count
        if alertCount > 0 {
            text += " · \(alertCount) 条提示"
        }
        return text
    }
}
