import SwiftUI

/// §7 首次启动引导流程：免责声明 → 隐私政策 → HealthKit 授权 → 基础信息采集 → 好友码展示 → 主界面
struct OnboardingCoordinator: View {
    enum Step: Int, CaseIterable {
        case disclaimer, privacyPolicy, healthKitAuth, basicInfo, friendCode
    }

    @State private var step: Step = .disclaimer
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Environment(\.managedObjectContext) private var context
    let onFinished: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .disclaimer:
                    DisclaimerView { step = .privacyPolicy }
                case .privacyPolicy:
                    PrivacyPolicyView(mode: .onboarding) { step = .healthKitAuth }
                case .healthKitAuth:
                    HealthKitAuthView { step = .basicInfo }
                case .basicInfo:
                    BasicInfoView(onSaved: { step = .friendCode })
                case .friendCode:
                    FriendCodeIntroView(onFinished: onFinished)
                }
            }
            .animation(.default, value: step)
        }
    }
}

/// Apple Health 授权引导（FR-HK-06）。
private struct HealthKitAuthView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    let onNext: () -> Void
    @State private var isRequesting = false

    private let neededTypes = [
        ("心率", "heart.fill"),
        ("血氧饱和度", "lungs.fill"),
        ("心率变异性 (HRV)", "waveform.path.ecg"),
        ("睡眠分析", "bed.double.fill"),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Text("需要访问的健康数据").font(.title2.bold())
            Text("DrinkTrack 需要读取以下 Apple Health 数据，用来在饮酒时展示你的实时身体状态。我们只读取数据，不会修改或删除你的健康记录。")
                .font(.footnote)
                .foregroundStyle(DesignSystem.secondaryInk)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(neededTypes, id: \.0) { item in
                    Label(item.0, systemImage: item.1)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.chartSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let error = healthKitManager.authorizationError {
                Text(error).font(.caption).foregroundStyle(DesignSystem.statusCritical)
            }

            Spacer()

            Button {
                isRequesting = true
                Task {
                    await healthKitManager.requestAuthorization()
                    isRequesting = false
                    onNext()
                }
            } label: {
                if isRequesting {
                    ProgressView()
                } else {
                    Text("前往系统授权").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)

            // FR-HK-06 / §3.1 Recovery path：未授权也允许继续，后续仅能手动录入饮酒信息
            Button("暂不授权，仅手动记录") { onNext() }
                .font(.footnote)
        }
        .padding()
    }
}
