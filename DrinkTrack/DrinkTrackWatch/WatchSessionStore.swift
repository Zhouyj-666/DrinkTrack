import Foundation
import Combine
import WatchConnectivity

/// Watch side of the phone link. Holds the latest session snapshot and sends
/// start / end / log commands to the iPhone via WatchConnectivity.
@MainActor
final class WatchSessionStore: NSObject, ObservableObject {
    static let shared = WatchSessionStore()

    @Published var snapshot: SessionSyncPayload = .empty
    @Published var isReachable = false
    @Published var statusMessage = "还没有收到手机上的会话信息，请在手机上打开小酌场。"
    @Published var confirmation: String?
    @Published var isSending = false

    private var session: WCSession?
    private var confirmationWork: DispatchWorkItem?

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            statusMessage = "这只手表无法连接 iPhone。"
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
        applyContext(session.receivedApplicationContext)
    }

    var canUseLastPreset: Bool {
        snapshot.lastVolumeML > 0 && !snapshot.lastCategoryDisplayName.isEmpty
    }

    func startSession() {
        send(command: WatchCommandKey.startSession)
    }

    func startWithQuickLog() {
        send(command: WatchCommandKey.startQuickLog)
    }

    func endSession() {
        send(command: WatchCommandKey.endSession)
    }

    func logLastPreset() {
        send(
            command: WatchCommandKey.logDrink,
            category: snapshot.lastCategoryRaw,
            volumeML: snapshot.lastVolumeML
        )
    }

    func log(preset: WatchDrinkPreset) {
        send(command: WatchCommandKey.logDrink, category: preset.rawValue, volumeML: preset.defaultVolumeML)
    }

    func requestSnapshot() {
        send(command: WatchCommandKey.requestSnapshot, showsConfirmation: false)
    }

    private func send(
        command: String,
        category: String? = nil,
        volumeML: Double? = nil,
        showsConfirmation: Bool = true
    ) {
        guard let session else {
            statusMessage = "这只手表无法连接 iPhone。"
            return
        }
        var message: [String: Any] = [WatchCommandKey.command: command]
        if let category { message[WatchCommandKey.category] = category }
        if let volumeML { message[WatchCommandKey.volumeML] = volumeML }

        isSending = true
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    self?.isSending = false
                    self?.applyReply(reply, command: command, category: category, volumeML: volumeML, showsConfirmation: showsConfirmation)
                }
            }, errorHandler: { [weak self] _ in
                session.transferUserInfo(message)
                Task { @MainActor in
                    self?.isSending = false
                    self?.markQueued(command: command, category: category, volumeML: volumeML, showsConfirmation: showsConfirmation)
                }
            })
        } else {
            session.transferUserInfo(message)
            isSending = false
            markQueued(command: command, category: category, volumeML: volumeML, showsConfirmation: showsConfirmation)
        }
    }

    private func applyReply(
        _ reply: [String: Any],
        command: String,
        category: String?,
        volumeML: Double?,
        showsConfirmation: Bool
    ) {
        if let snapshotDict = reply[WatchCommandKey.snapshot] as? [String: Any],
           let payload = SessionSyncPayload.fromPlist(snapshotDict) {
            snapshot = payload
        }
        if let error = reply[WatchCommandKey.error] as? String, !error.isEmpty {
            statusMessage = error
            return
        }
        if showsConfirmation {
            confirmation = confirmationText(command: command, category: category, volumeML: volumeML, queued: false)
            flashConfirmation()
        }
        refreshStatusMessage()
    }

    private func markQueued(command: String, category: String?, volumeML: Double?, showsConfirmation: Bool) {
        statusMessage = "手机现在连不上。这个操作会先排队，等手机上的小酌场打开后再同步。"
        applyOptimistic(command: command, category: category, volumeML: volumeML)
        if showsConfirmation {
            confirmation = confirmationText(command: command, category: category, volumeML: volumeML, queued: true)
            flashConfirmation()
        }
    }

    private func applyOptimistic(command: String, category: String?, volumeML: Double?) {
        switch command {
        case WatchCommandKey.startSession:
            if !snapshot.isSessionActive {
                snapshot.isSessionActive = true
                snapshot.startedAt = Date()
            }
        case WatchCommandKey.startQuickLog:
            if !snapshot.isSessionActive {
                snapshot.isSessionActive = true
                snapshot.startedAt = Date()
            }
            snapshot.cupCount += 1
            snapshot.volumeML += volumeML ?? snapshot.lastVolumeML
        case WatchCommandKey.endSession:
            snapshot.isSessionActive = false
        case WatchCommandKey.logDrink:
            if !snapshot.isSessionActive {
                snapshot.isSessionActive = true
                snapshot.startedAt = Date()
            }
            snapshot.cupCount += 1
            snapshot.volumeML += volumeML ?? snapshot.lastVolumeML
            if let category, let preset = WatchDrinkPreset(rawValue: category) {
                snapshot.lastCategoryRaw = preset.rawValue
                snapshot.lastCategoryDisplayName = preset.displayName
                snapshot.lastVolumeML = volumeML ?? preset.defaultVolumeML
            }
        default:
            break
        }
    }

    private func confirmationText(command: String, category: String?, volumeML: Double?, queued: Bool) -> String {
        let suffix = queued ? "（待同步到手机）" : ""
        switch command {
        case WatchCommandKey.startSession:
            return "已开始本场" + suffix
        case WatchCommandKey.startQuickLog:
            return "已开始并记下 \(snapshot.presetLabel)" + suffix
        case WatchCommandKey.endSession:
            return "已结束本场" + suffix
        case WatchCommandKey.logDrink:
            if let category, let preset = WatchDrinkPreset(rawValue: category) {
                let volume = Int((volumeML ?? preset.defaultVolumeML).rounded())
                return "已记下 \(preset.displayName) \(volume)ml" + suffix
            }
            return "已记下 \(snapshot.presetLabel)" + suffix
        default:
            return queued ? "已排队，等手机同步" : "已同步"
        }
    }

    private func flashConfirmation() {
        confirmationWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.confirmation = nil }
        }
        confirmationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    private func applyContext(_ context: [String: Any]) {
        guard let payload = SessionSyncPayload.fromPlist(context) else { return }
        snapshot = payload
        refreshStatusMessage()
    }

    private func refreshStatusMessage() {
        if !snapshot.hasRealSnapshot {
            statusMessage = isReachable
                ? "正在向手机请求本场信息…"
                : "还没有收到手机上的会话信息，请在手机上打开小酌场。"
            return
        }
        if isReachable {
            statusMessage = snapshot.healthStatusText
        } else {
            statusMessage = "手机现在连不上。上面是上次同步到的内容。可继续记一杯，会在手机打开小酌场后同步。"
        }
    }
}

extension WatchSessionStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.applyContext(session.receivedApplicationContext)
            if self.snapshot.hasRealSnapshot == false {
                self.requestSnapshot()
            }
            self.refreshStatusMessage()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.refreshStatusMessage()
            if session.isReachable {
                self.requestSnapshot()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyContext(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let dict = message[WatchCommandKey.snapshot] as? [String: Any] {
                self.applyContext(dict)
            } else {
                self.applyContext(message)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            if let dict = message[WatchCommandKey.snapshot] as? [String: Any] {
                self.applyContext(dict)
            } else {
                self.applyContext(message)
            }
            replyHandler([WatchCommandKey.ok: true])
        }
    }
}
