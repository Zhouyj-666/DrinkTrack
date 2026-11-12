import HealthKit
import Combine

/// HealthKit 数据采集模块（§5.1）。
///
/// 采样频率说明（对应 FR-HK-01/02）：这里用 `startObserving` + `HKAnchoredObjectQuery`
/// 在前台做准实时轮询；App 退到后台之后，iOS 系统会按自己的策略限制后台唤醒频率
/// （文档里写的"每 10-15 分钟 1 次"是系统行为，不是我们能控制的下限，代码里不假装能绕过）。
@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var authorizationError: String?

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

    // MARK: - FR-HK-06 权限管理

    func requestAuthorization() async {
        guard isHealthDataAvailable else {
            authorizationError = "此设备不支持 HealthKit（需要 iPhone，模拟器上部分健康数据查询也会返回空结果）"
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: HealthKitTypes.readTypes)
            isAuthorized = true
            authorizationError = nil
            startForegroundSampling()
        } catch {
            isAuthorized = false
            authorizationError = error.localizedDescription
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
        startHeartRateObserving()
        startSpO2Observing()
    }

    func stopForegroundSampling() {
        if let q = heartRateQuery { healthStore.stop(q) }
        if let q = spo2Query { healthStore.stop(q) }
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

    private func handleHeartRateSamples(_ samples: [HKSample]?, error: Error?) {
        guard let quantitySamples = samples as? [HKQuantitySample], error == nil else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let points = quantitySamples.map {
            HealthSamplePoint(timestamp: $0.endDate, value: $0.quantity.doubleValue(for: unit))
        }.sorted { $0.timestamp < $1.timestamp }

        recentHeartRatePoints = points
        latestHeartRate = points.last?.value
        watchSeemsConnected = (points.last?.timestamp ?? .distantPast).timeIntervalSinceNow > -900
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
        let points = quantitySamples.map {
            HealthSamplePoint(timestamp: $0.endDate, value: $0.quantity.doubleValue(for: .percent()) * 100)
        }.sorted { $0.timestamp < $1.timestamp }

        recentSpO2Points = points
        latestSpO2 = points.last?.value
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
