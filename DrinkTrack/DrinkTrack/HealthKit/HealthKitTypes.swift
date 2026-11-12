import HealthKit

/// 本 App 需要读取的 HealthKit 数据类型清单（FR-HK-06 权限管理：
/// 首次启动引导时展示的"需要的健康数据类型清单"就是这里）。
enum HealthKitTypes {

    static var readTypes: Set<HKObjectType> {
        // 用传统的 `xxxType(forIdentifier:)` API（强制解包），而不是较新的
        // `HKQuantityType(.heartRate)` 便捷构造器——后者是近几个 SDK 才加入的语法糖，
        // 在 iOS 17 部署目标下是否可用没有十足把握，这里选更保守、确定可用的写法。
        // 这几个 identifier 都是系统预置、恒定存在的类型，强制解包是安全的。
        var types: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
        ]
        // AFib 相关类型按 FeatureFlags.afibDisplayDefaultEnabled 决定要不要请求授权；
        // 即使以后打开开关，也只在用户主动开启实验性功能后才去申请，不在首次启动就强行要这个权限
        // （减少首次授权弹窗的权限数量，降低用户拒绝整体授权的概率）。
        if #available(iOS 16.0, *) {
            types.insert(HKObjectType.electrocardiogramType())
        }
        return types
    }

    /// 是否需要额外请求 AFib 历史记录类别（FR-HK-05），由 Settings 里的开关控制。
    static var afibRelatedType: HKObjectType? {
        HKObjectType.electrocardiogramType()
    }
}

/// 一次 HealthKit 查询返回的简化数据点，供 UI / Repository 层使用，
/// 不直接把 HKSample 暴露到 View 层（减少 View 对 HealthKit SDK 的直接依赖）。
struct HealthSamplePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

enum SleepStageSummary {
    case awake, light, deep, rem
}

/// FR-TREND-03 饮酒日 vs 非饮酒日对比结果。
struct DrinkDayComparisonResult {
    let drinkDayCount: Int
    let nonDrinkDayCount: Int
    let drinkDayAvgHR: Double?
    let nonDrinkDayAvgHR: Double?
    let drinkDayAvgHRV: Double?
    let nonDrinkDayAvgHRV: Double?
}
