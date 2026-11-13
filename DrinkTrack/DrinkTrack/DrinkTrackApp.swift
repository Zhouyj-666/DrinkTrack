import SwiftUI

@main
struct DrinkTrackApp: App {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var drinkRepository = DrinkRepository()
    private let persistence = PersistenceController.shared
    private let friendRepository: FriendRepository = MockFriendRepository()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    RootView(friendRepository: friendRepository)
                } else {
                    OnboardingCoordinator(onFinished: { hasCompletedOnboarding = true })
                }
            }
            .environment(\.managedObjectContext, persistence.viewContext)
            .environmentObject(healthKitManager)
            .environmentObject(drinkRepository)
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
            }
        }
    }
}
