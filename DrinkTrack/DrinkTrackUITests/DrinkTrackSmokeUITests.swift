import XCTest

/// DrinkTrack simulator smoke test (CI only).
///
/// Walks through onboarding and the four main tabs, saving a screenshot at every
/// step. It deliberately skips the HealthKit system permission prompt by tapping
/// the in-app "skip" button, because the simulator has no real Health data and the
/// Health permission sheet is not something CI can reliably drive. Any missing
/// control, unexpected alert, or crash is captured as a screenshot + note.
///
/// Screenshots are written two ways:
///  1. XCTAttachment (keepAlways) inside the .xcresult bundle
///  2. PNG files in $SCREENSHOT_DIR (set via TEST_RUNNER_SCREENSHOT_DIR in CI)
final class DrinkTrackSmokeUITests: XCTestCase {

    private var app: XCUIApplication!
    private var shotIndex = 0
    private var notes: [String] = []

    // MARK: - Helpers

    @MainActor
    private func snap(_ name: String) {
        shotIndex += 1
        let shot = XCUIScreen.main.screenshot()
        let fileName = String(format: "%02d-%@", shotIndex, name)
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let url = URL(fileURLWithPath: dir).appendingPathComponent(fileName + ".png")
            try? shot.pngRepresentation.write(to: url)
        }
    }

    private func note(_ text: String) {
        notes.append(text)
        print("[SMOKE] " + text)
    }

    /// Returns false (and records a screenshot) if the app is no longer in the foreground.
    @MainActor
    @discardableResult
    private func checkAlive(_ step: String) -> Bool {
        if app.state == .runningForeground { return true }
        snap("CRASH-or-background-after-" + step)
        note("App not in foreground after step '\(step)' (state=\(app.state.rawValue)). Possible crash.")
        XCTFail("App left foreground after step: \(step)")
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
        return false
    }

    /// Waits for an element and taps it. On failure records a screenshot + note.
    @MainActor
    @discardableResult
    private func tap(_ element: XCUIElement, _ step: String, timeout: TimeInterval = 8, required: Bool = true) -> Bool {
        if !element.waitForExistence(timeout: timeout / 2) {
            // Lazy Form/List rows only exist once scrolled near; swipe to reveal.
            for _ in 0..<5 where !element.exists { app.swipeUp(); _ = element.waitForExistence(timeout: 1) }
        }
        guard element.exists else {
            snap("MISSING-" + step)
            note("Could not find control for step '\(step)'.")
            if required { XCTFail("Missing control: \(step)") }
            return false
        }
        if !element.isHittable {
            // Try scrolling it into view.
            for _ in 0..<4 where !element.isHittable { app.swipeUp() }
        }
        guard element.isEnabled else {
            snap("DISABLED-" + step)
            note("Control for step '\(step)' exists but is disabled.")
            if required { XCTFail("Disabled control: \(step)") }
            return false
        }
        guard element.isHittable else {
            snap("NOT-HITTABLE-" + step)
            note("Control for step '\(step)' exists but is not hittable (covered or off-screen).")
            if required { XCTFail("Not hittable: \(step)") }
            return false
        }
        element.tap()
        checkAlive(step)
        return true
    }

    @MainActor
    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 3) { back.tap() }
    }

    // MARK: - Test

    @MainActor
    func testSmokeWalkthrough() throws {
        continueAfterFailure = true
        app = XCUIApplication()

        addUIInterruptionMonitor(withDescription: "System alerts") { [weak self] alert in
            self?.note("System alert appeared: \(alert.label)")
            for label in ["Don\u{2019}t Allow", "Don't Allow", "Not Now", "Cancel", "OK", "Allow", "\u{4E0D}\u{5141}\u{8BB8}", "\u{597D}"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }

        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "App did not reach foreground")
        sleep(2)
        snap("launch")
        checkAlive("launch")

        // ---------- Onboarding ----------
        let disclaimerButton = app.buttons["我已了解"]
        if disclaimerButton.waitForExistence(timeout: 10) {
            snap("onboarding-1-disclaimer")
            for _ in 0..<3 { app.swipeUp() }
            tap(disclaimerButton, "onboarding-accept-disclaimer")

            // Privacy policy: must flip the agree toggle first.
            let agreeToggle = app.switches.firstMatch
            if agreeToggle.waitForExistence(timeout: 8) {
                snap("onboarding-2-privacy-policy")
                // SwiftUI Toggle: tap the switch knob on the right edge, not the label.
                agreeToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
                if (agreeToggle.value as? String) != "1" {
                    let inner = agreeToggle.switches.firstMatch
                    if inner.exists { inner.tap() }
                }
                snap("onboarding-2b-privacy-agreed")
            } else {
                snap("MISSING-privacy-toggle")
                note("Privacy policy agree toggle not found.")
                XCTFail("Privacy toggle missing")
            }
            tap(app.buttons["同意并继续"], "onboarding-accept-privacy")

            // App intro screen. The onboarding flow was deliberately shortened after
            // on-device testing: it used to force HealthKit authorization and a
            // mandatory body-metrics form here. Both are now optional and live in the
            // "我的" tab, so the intro screen is the last onboarding step.
            let startButton = app.buttons["开始使用"]
            if startButton.waitForExistence(timeout: 8) {
                snap("onboarding-3-app-intro")
                tap(startButton, "onboarding-start-using")
            } else {
                snap("MISSING-app-intro")
                note("App intro screen not found.")
                XCTFail("App intro screen missing")
            }
        } else {
            note("Onboarding disclaimer not shown at launch (already onboarded, or onboarding broken).")
            snap("no-onboarding-at-launch")
        }

        // ---------- Main tabs ----------
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 15) else {
            snap("MISSING-tab-bar")
            note("Main tab bar never appeared; stopping walkthrough.")
            XCTFail("Main tab bar missing")
            attachNotes()
            return
        }
        sleep(1)

        // Dashboard + drink logging
        snap("tab-1-dashboard")
        if tap(app.buttons["开始新会话"], "dashboard-start-session", required: false) {
            sleep(1)
            snap("dashboard-session-started")
            if tap(app.buttons["+ 添加记录"], "dashboard-open-quicklog") {
                if app.navigationBars["添加饮酒记录"].waitForExistence(timeout: 8) {
                    snap("quicklog-sheet")
                } else {
                    snap("MISSING-quicklog-sheet")
                    note("Quick-log sheet did not open.")
                }
                if tap(app.buttons["+1 继续"], "quicklog-add-one") {
                    sleep(1)
                    snap("quicklog-after-add")
                }
                tap(app.buttons["完成"], "quicklog-done")
                sleep(1)
                let cancel = app.navigationBars.buttons["取消"]
                if cancel.exists { note("Quick-log sheet still open; dismissing via Cancel."); cancel.tap(); sleep(1) }
                snap("dashboard-after-log")

                // REGRESSION GUARD: on-device testing found that a logged drink was
                // invisible everywhere in the UI. The dashboard only drew logs as wine
                // markers on the heart-rate chart, which renders a placeholder (and no
                // markers) when there is no health data -- exactly the simulator case.
                // The dashboard now carries a real "本次记录" list; assert it shows up.
                let logList = app.staticTexts["本次记录"]
                if logList.waitForExistence(timeout: 8) {
                    snap("dashboard-log-list-visible")
                    // The summary line proves at least one record was actually rendered.
                    let summaryShown = app.staticTexts.containing(
                        NSPredicate(format: "label CONTAINS %@", "标准饮品")
                    ).firstMatch.waitForExistence(timeout: 5)
                    if !summaryShown {
                        snap("MISSING-log-summary")
                        note("'本次记录' header is present but no logged drink row rendered.")
                        XCTFail("Logged drink did not appear in the session list")
                    }
                } else {
                    snap("MISSING-log-list")
                    note("Dashboard session log list ('本次记录') not found after logging a drink.")
                    XCTFail("Logged drink is not visible on the dashboard")
                }
            }
            if tap(app.buttons["结束会话"], "dashboard-end-session", required: false) {
                sleep(1)
                snap("dashboard-session-ended")
            }
        }

        // Trends
        if tap(tabBar.buttons["趋势"], "tab-trends") {
            sleep(1)
            snap("tab-2-trends")
            app.swipeUp()
            snap("tab-2-trends-scrolled")
        }

        // Friends
        if tap(tabBar.buttons["好友"], "tab-friends") {
            sleep(2)
            snap("tab-3-friends")
            let navBar = app.navigationBars["好友"]
            var qr = navBar.buttons["qrcode"]
            if !qr.exists { qr = navBar.buttons["QR Code"] }
            if !qr.exists, navBar.exists, navBar.buttons.count > 0 {
                qr = navBar.buttons.element(boundBy: navBar.buttons.count - 1)
            }
            if tap(qr, "friends-open-friend-code", required: false) {
                sleep(1)
                snap("friend-code-sheet")
                tap(app.buttons["关闭"], "friend-code-close", required: false)
            }
        }

        // Profile ("我的") — this tab replaced the old "设置" tab. Body metrics and the
        // health-connection status now live here; 设置 is a page pushed from inside it.
        if tap(tabBar.buttons["我的"], "tab-profile") {
            sleep(1)
            snap("tab-4-profile")

            // Body metrics are keyboard-editable now (they used to be Stepper-only).
            let weightField = app.textFields.element(boundBy: 1)
            if weightField.exists && weightField.isHittable {
                weightField.tap()
                weightField.typeText("72")
                snap("profile-weight-typed")
                // Dismiss the number pad so later taps are not blocked by it.
                app.toolbars.buttons.firstMatch.tap()
                if app.keyboards.count > 0 { app.swipeDown() }
            } else {
                note("Weight text field not hittable; skipped keyboard-input check.")
            }

            if tap(app.buttons["保存"], "profile-save", required: false) {
                sleep(1)
                snap("profile-saved")
            }

            app.swipeUp()
            snap("tab-4-profile-scrolled")

            if tap(app.buttons["设置与隐私"], "profile-open-settings", required: false) {
                sleep(1)
                snap("settings-root")
                if tap(app.buttons["隐私政策"], "settings-privacy-policy", required: false) {
                    sleep(1)
                    snap("settings-privacy-policy")
                    goBack()
                }
                if tap(app.buttons["免责声明"], "settings-disclaimer", required: false) {
                    sleep(1)
                    snap("settings-disclaimer")
                    goBack()
                }
                app.swipeUp()
                snap("settings-scrolled")
                if tap(app.buttons["数据管理"], "settings-data-management", required: false) {
                    sleep(1)
                    snap("settings-data-management")
                    goBack()
                }
                goBack()
            }
        }

        // Back to dashboard for a final state check.
        tap(tabBar.buttons["仪表盘"], "tab-dashboard-final", required: false)
        sleep(1)
        snap("final-dashboard")
        checkAlive("final")
        attachNotes()
    }

    @MainActor
    private func attachNotes() {
        let text = notes.isEmpty ? "No issues noted." : notes.joined(separator: "\n")
        let attachment = XCTAttachment(string: text)
        attachment.name = "smoke-notes"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? text.write(toFile: dir + "/smoke-notes.txt", atomically: true, encoding: .utf8)
        }
    }
}
