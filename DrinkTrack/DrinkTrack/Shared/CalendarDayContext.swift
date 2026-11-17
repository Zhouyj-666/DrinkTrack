import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Tracks the current local calendar day so "today" windows refresh after
/// midnight, when the app returns to the foreground, or when the system clock
/// or time zone changes.
///
/// Historical record timestamps are never rewritten. There is no custom
/// drinking-day cutoff (for example 04:00); a new local day begins at
/// `Calendar.startOfDay`.
@MainActor
final class CalendarDayContext: ObservableObject {
    @Published private(set) var now: Date
    @Published private(set) var todayStart: Date

    private let calendar: Calendar
    private var midnightItem: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init(now: Date = Date(), calendar: Calendar = .current, observeSystem: Bool = true) {
        self.calendar = calendar
        self.now = now
        self.todayStart = calendar.startOfDay(for: now)
        if observeSystem {
            startObserving()
            scheduleMidnightRefresh()
        }
    }

    deinit {
        midnightItem?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Re-read the system clock. Call when the scene becomes active.
    func refreshFromSystemClock() {
        apply(Date())
    }

    /// Test hook and shared update path. Does not rewrite stored records.
    func apply(_ now: Date) {
        let start = calendar.startOfDay(for: now)
        self.now = now
        if todayStart != start {
            todayStart = start
        }
        scheduleMidnightRefresh()
    }

    private func startObserving() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromSystemClock()
            }
        })
        #if canImport(UIKit)
        observers.append(center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromSystemClock()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromSystemClock()
            }
        })
        #endif
    }

    private func scheduleMidnightRefresh() {
        midnightItem?.cancel()
        let clock = Date()
        let start = calendar.startOfDay(for: clock)
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let delay = nextMidnight.timeIntervalSince(clock)
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.refreshFromSystemClock()
            }
        }
        midnightItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0.05), execute: work)
    }
}
