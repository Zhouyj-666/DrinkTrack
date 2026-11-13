import SwiftUI
import CoreData

/// 「我的」页：个人基础信息 + 健康连接状态 + 好友码。
///
/// 这一页承接了原来塞在首次启动流程里的基础数据采集（PRD §7）。
/// 改动理由见 OnboardingCoordinator 的注释：强制在首次启动填身体数据，
/// 用户此时还不知道这些数据干什么用，体验像填表。
/// 现在全部改成可选、可随时修改，不填也能正常用 App。
/// 个人信息收成一个默认折叠的集合，需要填写时再点开。
struct ProfileView: View {
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
    @State private var isPersonalInfoExpanded = false

    private let genders = [("male", "男"), ("female", "女"), ("other", "其他")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HealthConnectionStatusView(
                        state: healthKitManager.connectionState,
                        authorizationError: healthKitManager.authorizationError,
                        isRequesting: healthKitManager.isRequestingAuthorization,
                        onRequestAuthorization: {
                            Task {
                                await healthKitManager.requestAuthorization()
                                await autoFillRestingHRIfEmpty()
                            }
                        },
                        onRefresh: {
                            Task { await healthKitManager.refreshConnectionState() }
                        }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    DisclosureGroup(isExpanded: $isPersonalInfoExpanded) {
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
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("个人信息")
                            Text(personalInfoSummary)
                                .font(.caption)
                                .foregroundStyle(DesignSystem.secondaryInk)
                        }
                    }
                    .accessibilityIdentifier("personal-info-group")
                } footer: {
                    Text("点开后可以填写或修改。这些信息只用来让会话提示的参考线更贴合你本人，不会展示给好友，也不会上传到任何服务器。不填也能正常使用。安静心率不填时，心率提示按 65 bpm 的通用值计算。")
                }

                Section {
                    HStack {
                        Text("我的好友码")
                        Spacer()
                        Text(profile?.friendCode ?? "—")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(DesignSystem.secondaryInk)
                        if let code = profile?.friendCode, !code.isEmpty {
                            Button {
                                UIPasteboard.general.string = code
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("复制好友码")
                        }
                    }
                } header: {
                    Text("好友")
                } footer: {
                    Text("可在「好友」页查看二维码、分享，或把对方的码保存到本机。本版本名单只存在这台手机上。")
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("设置与隐私", systemImage: "gearshape")
                    }
                }

                Section {
                    Button {
                        saveProfile()
                    } label: {
                        Text("保存").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    if let saveConfirmation {
                        Text(saveConfirmation)
                            .font(.footnote)
                            .foregroundStyle(DesignSystem.statusGood)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("我的")
            .task { loadProfile() }
        }
    }

    private var personalInfoSummary: String {
        var parts: [String] = []
        if gender == "male" { parts.append("男") }
        else if gender == "female" { parts.append("女") }
        if birthYear > 0 { parts.append("\(birthYear)年") }
        if weightKg > 0 { parts.append("\(weightKg)kg") }
        if restingHeartRate > 0 { parts.append("安静心率 \(restingHeartRate)bpm") }
        if parts.isEmpty { return "未填写，需要时点开补充" }
        return parts.joined(separator: " · ")
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

    private func autoFillRestingHRIfEmpty() async {
        guard restingHeartRate == 0 else { return }
        await loadRestingHRFromHealth(force: false)
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
