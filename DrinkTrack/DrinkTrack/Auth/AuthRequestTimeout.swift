import Foundation

/// Time limits for talking to the local auth API.
enum AuthRequestTimeout {
    /// Launch check of GET /v1/auth/me. Keep this short so a down LAN host cannot stall the UI.
    static let sessionRestore: TimeInterval = 3
    /// Login, register, and logout. Long enough for a slightly slow LAN, short enough not to hang forever.
    static let interactive: TimeInterval = 20
}

enum AuthAsyncTimeout {
    /// Runs `operation` and throws `AuthAPIError.unreachable` if it does not finish in time.
    static func run<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: Result<T, Error>.self) { group in
            group.addTask {
                do {
                    return .success(try await operation())
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                let nanos = UInt64(max(seconds, 0) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
                return .failure(AuthAPIError.unreachable)
            }
            let first = try await group.next()!
            group.cancelAll()
            while let leftover = try? await group.next() {
                _ = leftover
            }
            switch first {
            case .success(let value):
                return value
            case .failure(let error):
                throw error
            }
        }
    }
}
