import SwiftUI

@main
struct DrinkTrackApp: App {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var drinkRepository = DrinkRepository()
    private let persistence = PersistenceController.shared
    @StateObject private var friendRepository = LocalFriendRepository()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showBrandSplash = !Self.shouldSkipBrandSplash
    @AppStorage("appearancePreference") private var appearanceRaw = AppearancePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if hasCompletedOnboarding {
                        RootView(friendRepository: friendRepository)
                    } else {
                        OnboardingCoordinator(onFinished: { hasCompletedOnboarding = true })
                    }
                }

                if showBrandSplash {
                    BrandSplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .environment(\.managedObjectContext, persistence.viewContext)
            .environmentObject(healthKitManager)
            .environmentObject(drinkRepository)
            .preferredColorScheme(preferredColorScheme)
            .task {
                PhoneWatchBridge.shared.start(repository: drinkRepository, health: healthKitManager)
                guard showBrandSplash else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                withAnimation(.easeOut(duration: 0.35)) {
                    showBrandSplash = false
                }
            }
        }
        // FR-DASH-04：每次 App 变为 active（冷启动或从后台回到前台）都做一次自动归档扫描，
        // 而不是只在第一次出现时跑一次（.onAppear 只在视图首次出现时触发一次，无法覆盖
        // "从后台切回前台"的场景），也不是跑一个持续运行的高频定时器。
        //
        // 同时恢复 HealthKit 采样：修复「App 重启后仪表盘永远没数据」的 bug——
        // 原来 startForegroundSampling() 只在首次授权那一刻被调用过一次。
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                SessionAutoArchiver.runAutoArchiveSweep(context: persistence.viewContext)
                Task { await healthKitManager.resumeIfPossible() }
                PhoneWatchBridge.shared.publishSnapshot()
            }
        }
    }
    private var preferredColorScheme: ColorScheme? {
        switch AppearancePreference(rawValue: appearanceRaw) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// UI tests and debug launches can skip the branded splash so walkthroughs
    /// do not wait on the animation. Also skip when running under XCTest.
    private static var shouldSkipBrandSplash: Bool {
        if CommandLine.arguments.contains("-SkipBrandSplash") { return true }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        return false
    }
}
