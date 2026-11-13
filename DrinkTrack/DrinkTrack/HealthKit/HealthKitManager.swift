import HealthKit
import Combine

/// HealthKit 数据采集模块（§5.1）。
///
/// 采样频率说明（对应 FR-HK-01/02）：这里用 `startObserving` + `HKAnchoredObjectQuery`
/// 在前台做准实时轮询；App 退到后台之后，iOS 系统会按自己的策略限制后台唤醒频率
/// （文档里写的"每 10-15 分钟 1 次"是系统行为，不是我们能控制的下限，代码里不假装能绕过）。
/// 健康数据连接状态。
///
/// ⚠️ 为什么不是简单的 `isAuthorized: Bool`：
/// HealthKit **故意不告诉 App 读取权限是否被授予**（这是 Apple 的隐私设计——如果 App 能知道
/// 「用户拒绝了心率权限」，本身就泄露了用户的健康信息）。
/// `requestAuthorization(toShare:read:)` 即使用户在弹窗里全部点了「不允许」也会正常返回成功。
///
/// 所以唯一可靠的判断方式是：**实际跑一次查询，看能不能读到数据**。
/// 读到了 → 一定有权限；读不到 → 可能没权限，也可能只是没有数据（没戴表 / 新手表 / 模拟器）。
/// 这两种情况 App 无法区分，所以 UI 必须如实告诉用户这个歧义，而不是假装「已连接」。
enum HealthConnectionState: Equatable {
    /// 设备不支持 HealthKit（如 iPad、部分模拟器）
    case unavailable
    /// 还没弹过授权窗
    case notRequested
    /// 弹过授权窗，且确实读到了数据 —— 唯一能确认「真的连上了」的状态
    case connected(lastSampleAt: Date)
    /// 弹过授权窗，但一条数据都读不到。可能是被拒绝，也可能是真的没数据
    case requestedButNoData

    var isUsable: Bool {
        if case .connected = self { return true }
        return false
    }
}

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    /// 真实的连接状态（取代原来那个永远为 true 的 isAuthorized）
    @Published private(set) var connectionState: HealthConnectionState = .notRequested
    @Published var authorizationError: String?
    @Published private(set) var isRequestingAuthorization = false

    /// 手表是否在近期有数据写入（用于 FR-HK-01「手表未佩戴」提示判断的粗略依据）。
    @Published var watchSeemsConnected = false

    @Published var latestHeartRate: Double?
    @Published var latestSpO2: Double?
    @Published var latestHRV: Double?
    @Published var recentHeartRatePoints: [HealthSamplePoint] = []
    @Published var recentSpO2Points: [HealthSamplePoint] = []

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var heartRateQuery: HKQuery?
    private var spo2Query: HKQuery?
    private var isSampling = false

    /// 是否已经向用户弹过授权窗。HealthKit 不提供这个信息，只能自己记。
    private var hasRequestedAuthorization: Bool {
        get { UserDefaults.standard.bool(forKey: "hasRequestedHealthKitAuthorization") }
        set { UserDefaults.standard.set(newValue, forKey: "hasRequestedHealthKitAuthorization") }
    }

    private init() {
        if !isHealthDataAvailable {
            connectionState = .unavailable
        } else if hasRequestedAuthorization {
            connectionState = .requestedButNoData // 等 refreshConnectionState() 探测后再更新
        }
    }

    // MARK: - FR-HK-06 权限管理

    func requestAuthorization() async {
        guard !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }

        guard isHealthDataAvailable else {
            connectionState = .unavailable
            authorizationError = "此设备不支持 HealthKit（iPad 和部分模拟器不支持）。你仍然可以手动记录饮酒。"
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: HealthKitTypes.readTypes)
            hasRequestedAuthorization = true
            authorizationError = nil
            // 注意：走到这里**不代表用户同意了**，只代表弹窗流程走完了。
            // 真实状态要靠下面的探测查询来确定。
            startForegroundSampling()
            await refreshConnectionState()
        } catch {
            authorizationError = Self.friendlyAuthorizationMessage(for: error)
            if !hasRequestedAuthorization {
                connectionState = .notRequested
            }
        }
    }

    /// Turn a HealthKit / signing failure into a message the user can actually act on.
    /// Sideloaded builds often lose the HealthKit entitlement; the system sheet
    /// never appears and the error used to be stored but never shown.
    private static func friendlyAuthorizationMessage(for error: Error) -> String {
        let nsError = error as NSError
        let reason = nsError.localizedFailureReason ?? ""
        let haystack = (error.localizedDescription + " " + reason + " " + String(describing: error)).lowercased()
        if haystack.contains("entitlement") || haystack.contains("missing com.apple.developer.healthkit") {
            return "这次安装没有带上「健康」权限，所以系统授权窗口不会出现。用个人 Apple ID 侧载重签时经常会这样。你仍然可以手动记录饮酒；若要读取心率和血氧，需要用带 HealthKit 权限的签名方式重新安装。"
        }
        if let hkError = error as? HKError {
            switch hkError.code {
            case .errorHealthDataUnavailable:
                return "此设备当前无法使用健康数据。你仍然可以手动记录饮酒。"
            case .errorHealthDataRestricted:
                return "健康数据受到系统限制（例如屏幕使用时间或设备管理），无法授权。"
            case .errorAuthorizationDenied:
                return "系统拒绝了健康数据授权。请打开「健康」App → 头像 → 隐私 → App → DrinkTrack，打开心率、血氧、心率变异性和睡眠。"
            case .errorUserCanceled:
                return "你取消了授权。需要连接时可以再点一次「连接 Apple 健康」。"
            default:
                break
            }
        }
        return "无法完成健康授权：\(error.localizedDescription)"
    }

    /// App 每次进入前台时调用：恢复采样 + 重新探测连接状态。
    ///
    /// 修复的 bug：原来 `startForegroundSampling()` 只在 `requestAuthorization()` 里调用一次，
    /// App 重启后采样永远不会启动，仪表盘因此一直是空的。
    func resumeIfPossible() async {
        guard isHealthDataAvailable else {
            connectionState = .unavailable
            return
        }
        guard hasRequestedAuthorization else {
            connectionState = .notRequested
            return
        }
        startForegroundSampling()
        await refreshConnectionState()
    }

    /// 用一次真实查询来探测「到底能不能读到数据」，这是唯一可靠的连接性判断。
    func refreshConnectionState() async {
        guard isHealthDataAvailable else {
            connectionState = .unavailable
            return
        }
        guard hasRequestedAuthorization else {
            connectionState = .notRequested
            return
        }
        // 查最近 7 天任意一条心率样本。窗口开大是故意的：
        // 只要用户戴过表，7 天内一定有数据；查不到就说明大概率没授权。
        if let latest = await fetchMostRecentSampleDate(
            for: .heartRate, within: 7 * 24 * 3600
        ) {
            connectionState = .connected(lastSampleAt: latest)
        } else {
            connectionState = .requestedButNoData
        }
    }

    private func fetchMostRecentSampleDate(
        for identifier: HKQuantityTypeIdentifier, within seconds: TimeInterval
    ) async -> Date? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-seconds), end: nil
        )
        let store = healthStore
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first?.endDate)
            }
            store.execute(query)
        }
    }

    /// 用户主动在 Settings 里打开 AFib 实验性功能后，补充请求那一类权限（FR-HK-05）。
    func requestAFibAuthorizationIfNeeded() async {
        guard let type = HealthKitTypes.afibRelatedType else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [type])
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    // MARK: - FR-HK-01 心率实时采集

    func startForegroundSampling() {
        guard !isSampling else { return } // 避免重复 execute 同一个 query
        isSampling = true
        startHeartRateObserving()
        startSpO2Observing()
    }

    func stopForegroundSampling() {
        if let q = heartRateQuery { healthStore.stop(q) }
        if let q = spo2Query { healthStore.stop(q) }
        heartRateQuery = nil
        spo2Query = nil
        isSampling = false
    }

    private func startHeartRateObserving() {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-2 * 3600), end: nil)
        let query = HKAnchoredObjectQuery(
            type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            Task { @MainActor in
                self?.handleHeartRateSamples(samples, error: error)
            }
        }
        query.updateHandler = { [weak self] _, samples, _, _, error in
            Task { @MainActor in
                self?.handleHeartRateSamples(samples, error: error)
            }
        }
        healthStore.execute(query)
        heartRateQuery = query
    }

    /// 心率曲线展示窗口：最近 2 小时（对应 FR-DASH-01）
    private static let heartRateWindow: TimeInterval = 2 * 3600
    /// 血氧曲线展示窗口：最近 1 小时（对应 FR-DASH-02）
    private static let spo2Window: TimeInterval = 3600

    private func handleHeartRateSamples(_ samples: [HKSample]?, error: Error?) {
        guard let quantitySamples = samples as? [HKQuantitySample], error == nil else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let newPoints = quantitySamples.map {
            HealthSamplePoint(timestamp: $0.endDate, value: $0.quantity.doubleValue(for: unit))
        }

        // ⚠️ 必须「累加」而不是「替换」：
        // HKAnchoredObjectQuery 的 updateHandler 只回传**自上次锚点以来的新样本**，
        // 不是全量。原来写成 `recentHeartRatePoints = points` 会导致第一次更新之后
        // 整条曲线塌缩成只剩新来的那一两个点。
        recentHeartRatePoints = Self.merged(
            existing: recentHeartRatePoints, incoming: newPoints, window: Self.heartRateWindow
        )
        latestHeartRate = recentHeartRatePoints.last?.value
        watchSeemsConnected = (recentHeartRatePoints.last?.timestamp ?? .distantPast)
            .timeIntervalSinceNow > -900

        if let latest = recentHeartRatePoints.last?.timestamp {
            connectionState = .connected(lastSampleAt: latest)
        }
    }

    /// 合并新旧样本：按时间戳去重、排序，并丢掉窗口之外的旧数据（防止无限增长）。
    private static func merged(
        existing: [HealthSamplePoint], incoming: [HealthSamplePoint], window: TimeInterval
    ) -> [HealthSamplePoint] {
        let cutoff = Date().addingTimeInterval(-window)
        var byTimestamp: [Date: HealthSamplePoint] = [:]
        for point in existing + incoming where point.timestamp >= cutoff {
            byTimestamp[point.timestamp] = point
        }
        return byTimestamp.values.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - FR-HK-02 血氧采集

    private func startSpO2Observing() {
        let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-3600), end: nil)
        let query = HKAnchoredObjectQuery(
            type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            Task { @MainActor in
                self?.handleSpO2Samples(samples, error: error)
            }
        }
        query.updateHandler = { [weak self] _, samples, _, _, error in
            Task { @MainActor in
                self?.handleSpO2Samples(samples, error: error)
            }
        }
        healthStore.execute(query)
        spo2Query = query
    }

    private func handleSpO2Samples(_ samples: [HKSample]?, error: Error?) {
        guard let quantitySamples = samples as? [HKQuantitySample], error == nil else { return }
        let newPoints = quantitySamples.map {
            HealthSamplePoint(timestamp: $0.endDate, value: $0.quantity.doubleValue(for: .percent()) * 100)
        }
        // 同心率：累加而非替换，见 handleHeartRateSamples 的注释
        recentSpO2Points = Self.merged(
            existing: recentSpO2Points, incoming: newPoints, window: Self.spo2Window
        )
        latestSpO2 = recentSpO2Points.last?.value
    }

    // MARK: - FR-HK-03 HRV 采集（直接读取原生 SDNN，不做换算）

    func fetchLatestHRV() async -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let store = healthStore
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let ms = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
                Task { @MainActor in self?.latestHRV = ms }
                continuation.resume(returning: ms)
            }
            store.execute(query)
        }
    }

    /// 用于 §6.2 HRV 阈值判断：健康状态（无饮酒）下最近 7 天 SDNN 均值。
    /// 本轮实现为简化版——取最近 7 天全部样本均值，不特别排除饮酒当天
    /// （更精确的"排除饮酒日"逻辑依赖 DrinkRepository 的会话数据，留到趋势报告模块里做交叉计算）。
    func fetchSevenDayHRVAverage() async -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-7 * 24 * 3600), end: nil)
        let store = healthStore
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
                let ms = stats?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli))
                continuation.resume(returning: ms)
            }
            store.execute(query)
        }
    }

    /// §7 基础信息采集页"从 Apple Health 自动读取安静心率"用的是这个方法，
    /// 不要和上面的 HRV 查询搞混——两者是不同的 HealthKit 类型。
    func fetchRestingHeartRateAverage() async -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-7 * 24 * 3600), end: nil)
        let store = healthStore
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                let bpm = stats?.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: bpm)
            }
            store.execute(query)
        }
    }

    // MARK: - FR-HK-04 睡眠数据读取

    func fetchLastNightSleep() async -> (totalMinutes: Double, efficiency: Double)? {
        let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let start = Calendar.current.date(byAdding: .hour, value: -18, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let store = healthStore
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let categorySamples = samples as? [HKCategorySample], !categorySamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let asleep = categorySamples.filter {
                    $0.value != HKCategoryValueSleepAnalysis.awake.rawValue &&
                    $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue
                }
                let totalAsleep = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60
                let totalInBed = categorySamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60
                let efficiency = totalInBed > 0 ? totalAsleep / totalInBed : 0
                continuation.resume(returning: (totalAsleep, efficiency))
            }
            store.execute(query)
        }
    }

    // MARK: - FR-TREND-03 饮酒日 vs 非饮酒日对比

    /// 简化说明：PRD §4.2 时间轴模型里"酒后 2-4 小时"是相对单次会话开始时间的窗口，
    /// 但趋势报告是跨多天的统计，这里按天粒度做近似——取"饮酒日全天心率/HRV 均值"
    /// 与"非饮酒日同范围内全天均值"对比，而不是精确到每次会话的 2-4 小时窗口。
    /// 这是本轮的已知简化，比假装做了精确的会话级对齐更诚实；
    /// 后续轮次如果要做到 PRD 原文的精确窗口，需要把 DrinkSession 的 startedAt 传进来逐会话计算。
    func fetchDrinkVsNonDrinkComparison(drinkDays: [Date], withinLast days: Int = 60) async -> DrinkDayComparisonResult? {
        let calendar = Calendar.current
        let drinkDaySet = Set(drinkDays.map { calendar.startOfDay(for: $0) })
        guard drinkDaySet.count >= 5 else { return nil }

        let rangeStart = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var allDays: [Date] = []
        var cursor = calendar.startOfDay(for: rangeStart)
        let today = calendar.startOfDay(for: Date())
        while cursor <= today {
            allDays.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? today.addingTimeInterval(86400)
        }
        let nonDrinkDays = allDays.filter { !drinkDaySet.contains($0) }
        guard nonDrinkDays.count >= 5 else { return nil }

        let drinkHR = await averageQuantity(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), on: Array(drinkDaySet))
        let nonDrinkHR = await averageQuantity(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), on: nonDrinkDays)
        let drinkHRV = await averageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), on: Array(drinkDaySet))
        let nonDrinkHRV = await averageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), on: nonDrinkDays)

        return DrinkDayComparisonResult(
            drinkDayCount: drinkDaySet.count, nonDrinkDayCount: nonDrinkDays.count,
            drinkDayAvgHR: drinkHR, nonDrinkDayAvgHR: nonDrinkHR,
            drinkDayAvgHRV: drinkHRV, nonDrinkDayAvgHRV: nonDrinkHRV
        )
    }

    private func averageQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, on days: [Date]) async -> Double? {
        guard !days.isEmpty else { return nil }
        let calendar = Calendar.current
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!
        let store = healthStore
        var total = 0.0
        var count = 0
        for day in days {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let predicate = HKQuery.predicateForSamples(withStart: day, end: dayEnd)
            let value: Double? = await withCheckedContinuation { continuation in
                let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
                    continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
                }
                store.execute(query)
            }
            if let value {
                total += value
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : nil
    }

    // MARK: - FR-HK-05 异常心律事件（受 FeatureFlags 门控，默认不调用）
    //
    // ⚠️ 合规风险最高的查询，必须配合 FR-LEGAL-04 的额外免责弹窗一起展示，
    // 且只在用户于 Settings 主动打开"实验性功能"开关后才会被调用。

    func fetchAFibEvents(afterEnabledByUser enabled: Bool) async -> [Date] {
        guard enabled else { return [] }
        guard #available(iOS 16.0, *) else { return [] }
        let type = HKObjectType.electrocardiogramType()
        let store = healthStore
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-24 * 3600), end: nil)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let dates = (samples as? [HKElectrocardiogram])?.compactMap { sample -> Date? in
                    sample.classification == .atrialFibrillation ? sample.startDate : nil
                } ?? []
                continuation.resume(returning: dates)
            }
            store.execute(query)
        }
    }
}
