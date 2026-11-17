import Foundation

/// Coordinates the branded splash and launch-time session restore.
///
/// The splash fade is scheduled on its own and must never wait for network,
/// Keychain, or Watch startup. Session restore and Watch start run in the
/// background; the app stays usable without a completed login.
@MainActor
enum AppLaunchFlow {
    static let splashDuration: Duration = .milliseconds(1200)

    static func start(
        showSplash: Bool,
        restore: @escaping @MainActor () async -> Void,
        startWatch: @escaping @MainActor () -> Void,
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onDismissSplash: @escaping @MainActor () -> Void
    ) {
        if showSplash {
            Task { @MainActor in
                try? await sleep(Self.splashDuration)
                onDismissSplash()
            }
        }
        Task { @MainActor in
            await restore()
            startWatch()
        }
    }
}
