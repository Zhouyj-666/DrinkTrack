import Foundation
import Combine
import WatchConnectivity

/// iPhone side of the Apple Watch link.
///
/// Sends a session snapshot through `updateApplicationContext` (latest state
/// always wins) and accepts start / end / log commands from the Watch.
/// `sendMessage` is used when the phone is reachable; otherwise the Watch
/// queues the same payload with `transferUserInfo`, which is delivered when
/// the iPhone app is next running.
///
/// Manual logging on the phone keeps working if the Watch is missing, unpaired,
/// or the companion was stripped by a sideload resign.
@MainActor
final class PhoneWatchBridge: NSObject, ObservableObject {
    static let shared = PhoneWatchBridge()

    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isWatchReachable = false
    @Published private(set) var lastError: String?

    private var session: WCSession?
    private var drinkRepository: DrinkRepository?
    private var healthKitManager: HealthKitManager?
    private var cancellables = Set<AnyCancellable>()
    private var lastPublished: SessionSyncPayload?
    private var publishWork: DispatchWorkItem?

    override init() {
        super.init()
    }

    func start(repository: DrinkRepository, health: HealthKitManager) {
        drinkRepository = repository
        healthKitManager = health
        guard WCSession.isSupported() else { return }
        if session == nil {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            self.session = session
        }
        bindObservers(health: health)
        schedulePublish()
    }

    func publishSnapshot() {
        schedulePublish(immediate: true)
    }

    // MARK: - Snapshot

    private func bindObservers(health: HealthKitManager) {
        cancellables.removeAll()
        NotificationCenter.default.publisher(for: .drinkTrackDataDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        health.$latestInSessionHeartRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        health.$latestInSessionSpO2
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        health.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
    }

    private func schedulePublish(immediate: Bool = false) {
        publishWork?.cancel()
        if immediate {
            flushSnapshot()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.flushSnapshot() }
        }
        publishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func flushSnapshot() {
        guard let session, session.activationState == .activated else { return }
        refreshStatus(session)
        let payload = makePayload()
        guard payload != lastPublished else { return }
        lastPublished = payload
        let context = payload.plistDictionary()
        do {
            try session.updateApplicationContext(context)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        if session.isReachable {
            session.sendMessage(
                [WatchCommandKey.snapshot: context],
                replyHandler: nil,
                errorHandler: { _ in }
            )
        }
    }

    private func makePayload() -> SessionSyncPayload {
        let repo = drinkRepository
        let health = healthKitManager
        let session = repo?.fetchActiveSession()
        let logs = session.flatMap { $0.logs as? Set<DrinkLogEntity> } ?? []
        let volume = logs.reduce(0.0) { $0 + $1.volumeMl }
        let standard = logs.reduce(0.0) { $0 + $1.standardDrinks }
        return SessionSyncPayload(
            isSessionActive: session != nil,
            startedAt: session?.startedAt,
            cupCount: logs.count,
            volumeML: volume,
            standardDrinks: standard,
            latestHeartRate: health?.latestInSessionHeartRate,
            latestHeartRateAt: health?.latestInSessionHeartRateAt,
            latestSpO2: health?.latestInSessionSpO2,
            latestSpO2At: health?.latestInSessionSpO2At,
            lastCategoryRaw: UserPreferences.lastDrinkCategory.rawValue,
            lastCategoryDisplayName: UserPreferences.lastDrinkCategory.displayName,
            lastVolumeML: UserPreferences.lastDrinkVolumeML,
            healthStatusText: health?.watchHealthStatusText ?? "还没有收到手机上的会话信息，请在手机上打开小酌场。",
            updatedAt: Date()
        )
    }

    private func refreshStatus(_ session: WCSession) {
        isWatchAppInstalled = session.isWatchAppInstalled
        isWatchReachable = session.isReachable
    }

    // MARK: - Commands from the Watch

    @discardableResult
    private func handleCommand(_ message: [String: Any]) -> [String: Any] {
        guard let repo = drinkRepository else {
            return [WatchCommandKey.ok: false, WatchCommandKey.error: "手机还没准备好，请先打开小酌场。"]
        }
        let command = message[WatchCommandKey.command] as? String
        switch command {
        case WatchCommandKey.startSession:
            if repo.fetchActiveSession() == nil {
                repo.startNewSession()
            }
        case WatchCommandKey.startQuickLog:
            if repo.fetchActiveSession() == nil {
                repo.startSessionWithQuickLog()
            } else {
                logDrink(
                    on: repo,
                    categoryRaw: UserPreferences.lastDrinkCategory.rawValue,
                    volumeML: UserPreferences.lastDrinkVolumeML
                )
            }
        case WatchCommandKey.endSession:
            if let active = repo.fetchActiveSession() {
                repo.endSession(active)
            }
        case WatchCommandKey.logDrink:
            logDrink(
                on: repo,
                categoryRaw: message[WatchCommandKey.category] as? String,
                volumeML: (message[WatchCommandKey.volumeML] as? NSNumber)?.doubleValue
                    ?? message[WatchCommandKey.volumeML] as? Double
            )
        case WatchCommandKey.requestSnapshot:
            break
        default:
            return [WatchCommandKey.ok: false, WatchCommandKey.error: "手表发来的操作无法识别。"]
        }
        let payload = makePayload()
        lastPublished = payload
        if let session, session.activationState == .activated {
            try? session.updateApplicationContext(payload.plistDictionary())
        }
        return [WatchCommandKey.ok: true, WatchCommandKey.snapshot: payload.plistDictionary()]
    }

    private func logDrink(on repo: DrinkRepository, categoryRaw: String?, volumeML: Double?) {
        let session = repo.fetchActiveSession() ?? repo.startNewSession()
        let category = categoryRaw.flatMap(DrinkCategory.init(rawValue:)) ?? UserPreferences.lastDrinkCategory
        let volume: Double
        if let volumeML, volumeML > 0 {
            volume = volumeML
        } else {
            volume = UserPreferences.lastDrinkVolumeML
        }
        repo.addDrinkLog(to: session, category: category, brand: nil, volumeML: volume)
    }
}

extension PhoneWatchBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.refreshStatus(session)
            if let error {
                self.lastError = error.localizedDescription
            }
            self.flushSnapshot()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshStatus(session)
            self.flushSnapshot()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshStatus(session)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            replyHandler(self.handleCommand(message))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            _ = self.handleCommand(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            _ = self.handleCommand(userInfo)
        }
    }
}
