import SwiftUI
import CoreData

/// §7 首次启动个人基础数据采集：强制填写，无「跳过」按钮。
/// 用于：① HRV 基线计算排除年龄/性别影响 ② 心率偏离阈值的个性化基线 ③ 不对外展示，好友不可见。
struct BasicInfoView: View {
    let onSaved: () -> Void

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var healthKitManager: HealthKitManager

    @State private var gender = "other"
    @State private var birthYear = 1995
    @State private var weightKg = 65
    @State private var restingHeartRate = 65
    @State private var restingHRSource = "manual"
    @State private var isLoadingHRFromHealthKit = false

    private let genders = [("male", "男"), ("female", "女"), ("other", "其他")]
    private let years = Array(1950...2010).reversed()

    var body: some View {
        Form {
            Section("基础信息") {
                Picker("性别", selection: $gender) {
                    ForEach(genders, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("出生年份", selection: $birthYear) {
                    ForEach(years, id: \.self) { Text("\($0)").tag($0) }
                }
                Stepper("体重：\(weightKg) kg", value: $weightKg, in: 30...200)
            }

            Section {
                Stepper("安静心率：\(restingHeartRate) bpm", value: $restingHeartRate, in: 40...120)
                Button {
                    isLoadingHRFromHealthKit = true
                    Task {
                        if let avg = await healthKitManager.fetchRestingHeartRateAverage() {
                            restingHeartRate = Int(avg.rounded())
                            restingHRSource = "healthKit"
                        }
                        isLoadingHRFromHealthKit = false
                    }
                } label: {
                    if isLoadingHRFromHealthKit {
                        ProgressView()
                    } else {
                        Text("从 Apple Health 自动读取")
                    }
                }
            } header: {
                Text("安静心率")
            } footer: {
                Text("优先从 HealthKit 读取最近 7 天静息心率均值，读取成功后自动填入；你也可以手动修改。此数据用于心率预警的个性化基线计算，不会分享给好友。")
            }

            Section {
                Button {
                    saveAndContinue()
                } label: {
                    Text("保存并继续").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("基础信息")
        .navigationBarBackButtonHidden(true)
    }

    private func saveAndContinue() {
        let profile = UserProfileEntity(context: context)
        profile.id = UUID()
        profile.gender = gender
        profile.birthYear = Int32(birthYear)
        profile.weightKg = Int32(weightKg)
        profile.restingHeartRate = Int32(restingHeartRate)
        profile.restingHRSource = restingHRSource
        profile.friendCode = String(format: "%06d", Int.random(in: 0...999999))
        profile.afibDisplayEnabled = FeatureFlags.afibDisplayDefaultEnabled
        profile.iCloudSyncEnabled = false
        profile.disclaimerAcceptedAt = Date()
        profile.privacyPolicyAcceptedAt = Date()
        profile.createdAt = Date()
        try? context.save()
        onSaved()
    }
}
