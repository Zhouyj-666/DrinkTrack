import SwiftUI
import CoreData

/// §5.6 法律合规框架 + §6.1 数据存储隐私的设置入口。
struct SettingsView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Environment(\.managedObjectContext) private var context

    @State private var afibEnabled = false
    @State private var showAFibDisclaimer = false
    @State private var profile: UserProfileEntity?

    var body: some View {
        // 注意：这里**不能**再包一层 NavigationStack。
        // SettingsView 现在是从「我的」页 push 进来的子页面，
        // 嵌套 NavigationStack 会导致内部的 NavigationLink 无法正常跳转。
        Form {
                // 健康连接状态不在这里重复展示——它在「我的」页顶部，
                // 用 HealthConnectionStatusView 如实反映真实可读性，
                // 而不是像以前那样显示一个永远为「已授权」的假状态。
                Section {
                    Toggle("显示异常心律 (AFib) 事件", isOn: Binding(
                        get: { afibEnabled },
                        set: { newValue in
                            if newValue {
                                showAFibDisclaimer = true
                            } else {
                                afibEnabled = false
                                persistAFibFlag(false)
                            }
                        }
                    ))
                } header: {
                    Text("实验性功能")
                } footer: {
                    Text(DisclaimerStrings.afibFeatureFlagCaption)
                }

                Section("隐私与法律") {
                    NavigationLink("隐私政策") {
                        PrivacyPolicyView(mode: .readOnly)
                    }
                    NavigationLink("免责声明") {
                        ScrollView {
                            Text(DisclaimerStrings.firstLaunchDisclaimer).padding()
                        }
                        .navigationTitle("免责声明")
                    }
                }

                Section("iCloud 同步") {
                    Toggle("iCloud 同步", isOn: .constant(false)).disabled(true)
                    Text("即将推出——本版本数据仅保存在本机，不会上传到任何服务器")
                        .font(.caption2).foregroundStyle(DesignSystem.mutedInk)
                }

                NavigationLink("数据管理") {
                    DataManagementView()
                }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadProfile() }
        .alert("额外提示", isPresented: $showAFibDisclaimer) {
            Button("取消", role: .cancel) {}
            Button("我已了解，开启") {
                afibEnabled = true
                persistAFibFlag(true)
                Task { await healthKitManager.requestAFibAuthorizationIfNeeded() }
            }
        } message: {
            Text(DisclaimerStrings.afibExtraDisclaimer)
        }
    }

    private func loadProfile() {
        let request = NSFetchRequest<UserProfileEntity>(entityName: "UserProfile")
        request.fetchLimit = 1
        profile = try? context.fetch(request).first
        afibEnabled = profile?.afibDisplayEnabled ?? FeatureFlags.afibDisplayDefaultEnabled
    }

    private func persistAFibFlag(_ enabled: Bool) {
        profile?.afibDisplayEnabled = enabled
        try? context.save()
    }
}
