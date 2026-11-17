import SwiftUI
import CoreData

/// 「我的」页：设备、个人、设置，按用户改稿分层。
///
/// 个人信息仍是可选的，不填也能用。本页不加入登录或注册入口。
struct ProfileView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var healthKitManager: HealthKitManager

    @State private var profile: UserProfileEntity?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionHeader("设备")
                    NavigationLink {
                        WatchDeviceView()
                    } label: {
                        deviceRow
                    }
                    .buttonStyle(.plain)

                    sectionHeader("个人")
                        .padding(.top, 2)
                    VStack(spacing: 0) {
                        NavigationLink {
                            PersonalInfoFormView()
                        } label: {
                            personalInfoRow
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("personal-info-group")

                        Rectangle()
                            .fill(DesignSystem.separator)
                            .frame(height: 1)
                            .padding(.leading, 16)

                        NavigationLink {
                            FriendCodeView(repository: LocalFriendRepository(context: context))
                        } label: {
                            friendCodeRow
                        }
                        .buttonStyle(.plain)
                    }
                    .background(DesignSystem.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCorner, style: .continuous))
                    .shadow(color: Color(red: 90 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.04), radius: 2, y: 1)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        settingsRow
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignSystem.screenPadding)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .sipScreenBackground()
            .navigationTitle("我的")
            .background(DesignSystem.pagePlane)
            .task { loadProfile() }
        }
    }

    private var deviceRow: some View {
        HStack(spacing: 12) {
            iconBadge("applewatch")
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Watch")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DesignSystem.primaryInk)
                Text("可在手表上记杯、开始或结束会话")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.mutedInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(watchStatusText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(watchConnected ? DesignSystem.success : DesignSystem.warningGold)
            chevron
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .sipCardChrome()
    }

    private var personalInfoRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("个人信息")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DesignSystem.primaryInk)
                Text(personalInfoSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.mutedInk)
            }
            Spacer(minLength: 8)
            chevron
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var friendCodeRow: some View {
        HStack {
            Text("我的好友码")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignSystem.primaryInk)
            Spacer(minLength: 8)
            Text(profile?.friendCode ?? "—")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignSystem.primaryInk)
                .monospacedDigit()
            chevron
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var settingsRow: some View {
        HStack(spacing: 12) {
            iconBadge("gearshape")
            Text("设置与隐私")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignSystem.primaryInk)
            Spacer()
            chevron
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .sipCardChrome()
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DesignSystem.muted2)
    }

    private func iconBadge(_ systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignSystem.burgundySoft)
                .frame(width: 36, height: 36)
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignSystem.burgundy)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DesignSystem.mutedInk)
            .padding(.horizontal, 4)
    }

    private var watchConnected: Bool {
        healthKitManager.watchSeemsConnected || PhoneWatchBridge.shared.isWatchReachable
    }

    private var watchStatusText: String {
        watchConnected ? "已连接" : "未连接"
    }

    private var personalInfoSummary: String {
        guard let profile else { return "未填写，需要时再补" }
        var parts: [String] = []
        if profile.gender == "male" { parts.append("男") }
        else if profile.gender == "female" { parts.append("女") }
        if profile.birthYear > 0 { parts.append("\(profile.birthYear)年") }
        if profile.weightKg > 0 { parts.append("\(profile.weightKg)kg") }
        if profile.restingHeartRate > 0 { parts.append("安静心率 \(profile.restingHeartRate)bpm") }
        if parts.isEmpty { return "未填写，需要时再补" }
        return parts.joined(separator: " · ")
    }

    private func loadProfile() {
        profile = UserProfileStore.ensureProfile(in: context)
    }
}

private extension View {
    func sipCardChrome() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCorner, style: .continuous))
            .shadow(color: Color(red: 90 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.04), radius: 2, y: 1)
    }
}

/// Apple Watch 与健康连接说明。保持原有授权流程，不假装已经连上。
struct WatchDeviceView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HealthConnectionStatusView(
                    state: healthKitManager.connectionState,
                    authorizationError: healthKitManager.authorizationError,
                    isRequesting: healthKitManager.isRequestingAuthorization,
                    onRequestAuthorization: {
                        Task { await healthKitManager.requestAuthorization() }
                    },
                    onRefresh: {
                        Task { await healthKitManager.refreshConnectionState() }
                    }
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text("手表上的「小酌场」可以查看本场、记一杯，也可以开始或结束会话。数据通过 iPhone 上的小酌场同步。")
                    Text("用个人 Apple ID 侧载时，手表 App 通常装不上，这是签名限制，不是功能没做。若要用手表和健康数据，需要用带正式签名的方式安装，例如加入 Apple 开发者计划后，用 Xcode 或 TestFlight 安装。")
                }
                .font(.system(size: 15))
                .foregroundStyle(DesignSystem.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignSystem.screenPadding)
        }
        .sipScreenBackground()
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 可选的个人信息表。不填也能正常使用，保存后只留在本机。
struct PersonalInfoFormView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var healthKitManager: HealthKitManager

    @State private var profile: UserProfileEntity?
    @State private var gender = "other"
    @State private var birthYear = 0
    @State private var weightKg = 0
    @State private var restingHeartRate = 0
    @State private var restingHRSource = "manual"
    @State private var isLoadingHR = false
    @State private var saveConfirmation: String?

    private let genders = [("male", "男"), ("female", "女"), ("other", "其他")]

    var body: some View {
        Form {
            Section {
                Picker("性别", selection: $gender) {
                    ForEach(genders, id: \.0) { Text($0.1).tag($0.0) }
                }
                NumericField(title: "出生年份", unit: "年", range: 1930...Calendar.current.component(.year, from: Date()), value: $birthYear)
                NumericField(title: "体重", unit: "kg", range: 30...250, value: $weightKg)
                NumericField(title: "安静心率", unit: "bpm", range: 35...140, value: $restingHeartRate)
                Button {
                    Task { await loadRestingHRFromHealth(force: true) }
                } label: {
                    HStack {
                        Text("从 Apple 健康读取安静心率")
                        if isLoadingHR {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!healthKitManager.connectionState.isUsable || isLoadingHR)

                if restingHRSource == "healthKit" {
                    Label("已从 Apple 健康读取", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.statusGood)
                }
            } footer: {
                Text("这些信息只用来让会话提示的参考线更贴合你本人，不会展示给好友，也不会上传到任何服务器。不填也能正常使用。安静心率不填时，心率提示按 65 bpm 的通用值计算。")
            }

            Section {
                Button {
                    saveProfile()
                } label: {
                    Text("保存").frame(maxWidth: .infinity)
                }
                if let saveConfirmation {
                    Text(saveConfirmation)
                        .font(.footnote)
                        .foregroundStyle(DesignSystem.statusGood)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle("个人信息")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadProfile() }
    }

    private func loadProfile() {
        let target = UserProfileStore.ensureProfile(in: context)
        profile = target
        gender = target.gender ?? "other"
        birthYear = Int(target.birthYear)
        weightKg = Int(target.weightKg)
        restingHeartRate = Int(target.restingHeartRate)
        restingHRSource = target.restingHRSource ?? "manual"
    }

    private func saveProfile() {
        guard let profile else { return }
        profile.gender = gender
        profile.birthYear = Int32(birthYear)
        profile.weightKg = Int32(weightKg)
        profile.restingHeartRate = Int32(restingHeartRate)
        profile.restingHRSource = restingHRSource
        try? context.save()
        saveConfirmation = "已保存"
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveConfirmation = nil
        }
    }

    private func loadRestingHRFromHealth(force: Bool) async {
        isLoadingHR = true
        defer { isLoadingHR = false }
        if let avg = await healthKitManager.fetchRestingHeartRateAverage() {
            restingHeartRate = Int(avg.rounded())
            restingHRSource = "healthKit"
            saveProfile()
        } else if force {
            saveConfirmation = nil
        }
    }
}
