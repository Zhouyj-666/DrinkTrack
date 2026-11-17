import XCTest
@testable import DrinkTrack

@MainActor
final class AppLaunchFlowTests: XCTestCase {
    func testSplashDismissDoesNotAwaitRestore() async throws {
        var dismissed = false
        var watchStarted = false
        var restoreFinished = false
        let holder = ContinuationHolder()

        AppLaunchFlow.start(
            showSplash: true,
            restore: {
                await withCheckedContinuation { continuation in
                    holder.continuation = continuation
                }
                restoreFinished = true
            },
            startWatch: { watchStarted = true },
            sleep: { _ in },
            onDismissSplash: { dismissed = true }
        )

        let deadline = Date().addingTimeInterval(1)
        while !dismissed && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(dismissed, "Splash should hide even while restore is still running")
        XCTAssertFalse(restoreFinished, "Restore must not be a precondition for dismissing the splash")
        XCTAssertFalse(watchStarted, "Watch start stays behind restore and must not block the splash")
        let resumeDeadline = Date().addingTimeInterval(1)
        while holder.continuation == nil && Date() < resumeDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        holder.resume()
    }

    func testSkippedSplashDoesNotCallDismiss() async throws {
        var dismissed = false
        var restored = false
        var watchStarted = false

        AppLaunchFlow.start(
            showSplash: false,
            restore: { restored = true },
            startWatch: { watchStarted = true },
            sleep: { _ in XCTFail("Sleep should not run when the splash is skipped") },
            onDismissSplash: { dismissed = true }
        )

        let deadline = Date().addingTimeInterval(1)
        while !(restored && watchStarted) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(dismissed)
        XCTAssertTrue(restored)
        XCTAssertTrue(watchStarted)
    }
}

/// Holds a continuation so a hanging restore can be released in tear-down.
final class ContinuationHolder: @unchecked Sendable {
    var continuation: CheckedContinuation<Void, Never>?

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
