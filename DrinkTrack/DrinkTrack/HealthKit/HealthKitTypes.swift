import HealthKit

/// Types 小酌场 actually requests to read (FR-HK-06).
/// The onboarding / Health connection UI lists the same set.
/// AFib / electrocardiogram is NOT in this default set; it is requested only
/// after the user turns on the experimental toggle in Settings.
enum HealthKitTypes {

    static var readTypes: Set<HKObjectType> {
        // Use the older `xxxType(forIdentifier:)` APIs (force unwrap) rather
        // than the newer `HKQuantityType(.heartRate)` sugar, which is a more
        // recent SDK convenience. These identifiers are system-defined and
        // always present, so the unwrap is safe.
        [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
        ]
    }

    /// Requested only after the user enables the experimental AFib toggle (FR-HK-05).
    static var afibRelatedType: HKObjectType? {
        HKObjectType.electrocardiogramType()
    }
}

/// A simplified HealthKit sample for the UI / repository layers,
/// so Views do not depend on HKSample directly.
struct HealthSamplePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

enum SleepStageSummary {
    case awake, light, deep, rem
}

/// FR-TREND-03 drink-day vs non-drink-day comparison.
struct DrinkDayComparisonResult {
    let drinkDayCount: Int
    let nonDrinkDayCount: Int
    let drinkDayAvgHR: Double?
    let nonDrinkDayAvgHR: Double?
    let drinkDayAvgHRV: Double?
    let nonDrinkDayAvgHRV: Double?
}
