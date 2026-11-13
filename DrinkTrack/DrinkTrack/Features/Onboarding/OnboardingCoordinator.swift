import SwiftUI

/// 首次启动引导。
///
/// 相比 PRD §7 的调整（基于真机试用反馈）：
/// 原设计是「免责声明 → 隐私政策 → HealthKit 授权 → **强制填写**性别/年龄/体重/安静心率 → 好友码 → 主界面」，
/// 一上来就让用户填一堆身体数据，而此时用户还不知道这是个什么 App、为什么要给这些信息。
///
/// 现在改成：**免责声明 → 隐私政策 → 功能介绍 → 直接进 App**。
/// - 免责声明和隐私政策保留且不可跳过：这是法律要求（FR-LEGAL-01/02），不是产品选择
/// - 身体基础数据移到「我的」页，随时可填、可改，不填也能正常用（只是预警用默认基线）
/// - HealthKit 授权也不在这里强求，改在用户真正需要看数据时再引导
struct OnboardingCoordinator: View {
    enum Step {
        case disclaimer, privacyPolicy, intro
    }

    @State private var step: Step = .disclaimer
    let onFinished: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .disclaimer:
                    DisclaimerView { step = .privacyPolicy }
                case .privacyPolicy:
                    PrivacyPolicyView(mode: .onboarding) { step = .intro }
                case .intro:
                    AppIntroView(onFinished: onFinished)
                }
            }
            .animation(.default, value: step)
        }
    }
}
