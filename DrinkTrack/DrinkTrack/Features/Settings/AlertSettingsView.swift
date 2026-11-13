import SwiftUI
import CoreData

/// 会话中的身体提示：开关 + 规则说明。
/// 文案只陈述规则和当前参考线，不做评价、不建议怎么喝。
struct AlertSettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var healthKitManager: HealthKitManager

    @State private var masterEnabled = UserPreferences.sessionAlertsEnabled
    @State private var heartRateEnabled = UserPreferences.heartRateAlertsEnabled
    @State private var spo2Enabled = UserPreferences.spo2AlertsEnabled
    @State private var hrvEnabled = UserPreferences.hrvAlertsEnabled
    @State private var storedResting: Double?
    @State private var hrvBaseline: Double?

    var body: some View {
        Form {
            Section {
                Toggle("在会话中显示提示", isOn: $masterEnabled)
                    .onChange(of: masterEnabled) { _, value in
                        UserPreferences.sessionAlertsEnabled = value
                    }
            } footer: {
                Text("只在 App 打开、并且有一场进行中的会话时出现，不会发送系统通知。关闭后，下面三项都不再提示。")
            }

            Section {
                Toggle("心率持续偏高", isOn: $heartRateEnabled)
                    .onChange(of: heartRateEnabled) { _, value in
                        UserPreferences.heartRateAlertsEnabled = value
                    }
                    .disabled(!masterEnabled)
                Toggle("血氧持续偏低", isOn: $spo2Enabled)
                    .onChange(of: spo2Enabled) { _, value in
                        UserPreferences.spo2AlertsEnabled = value
                    }
                    .disabled(!masterEnabled)
                Toggle("心率变异偏低", isOn: $hrvEnabled)
                    .onChange(of: hrvEnabled) { _, value in
                        UserPreferences.hrvAlertsEnabled = value
                    }
                    .disabled(!masterEnabled)
            } header: {
                Text("提示项目")
            } footer: {
                Text("默认都开着。异常心律相关的提示在「实验性功能」里，默认关闭。")
            }

            Section("当前规则") {
                ruleRow(
                    title: "心率",
                    detail: heartRateRuleText
                )
                ruleRow(
                    title: "血氧",
                    detail: String(format: "低于 %.0f%%，并持续 %.0f 分钟以上。", AlertThresholdEngine.spo2PercentThreshold, AlertThresholdEngine.spo2SustainedMinutes)
                )
                ruleRow(
                    title: "心率变异（SDNN）",
                    detail: hrvRuleText
                )
            }

            Section {
                Text(DisclaimerStrings.passiveAlertDisclaimer)
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.secondaryInk)
            }
        }
        .navigationTitle("会话提示")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadBaselines() }
    }

    private var resting: Double {
        AlertThresholdEngine.resolvedRestingHeartRate(from: storedResting)
    }

    private var usingDefaultResting: Bool {
        storedResting == nil
    }

    private var heartRateRuleText: String {
        let threshold = AlertThresholdEngine.heartRateThreshold(restingHeartRate: storedResting)
        var text = String(
            format: "超过安静心率 + %.0f bpm（现在是 %.0f bpm），并持续 %.0f 分钟以上。",
            AlertThresholdEngine.heartRateOffset,
            threshold,
            AlertThresholdEngine.heartRateSustainedMinutes
        )
        if usingDefaultResting {
            text += " 尚未填写安静心率，目前按通用值 \(Int(AlertThresholdEngine.defaultRestingHeartRate)) bpm 计算，可在「我的」里补充。"
        } else {
            text += " 你的安静心率是 \(Int(resting)) bpm。"
        }
        return text
    }

    private var hrvRuleText: String {
        var text = "当前 SDNN 低于近 7 天均值的一半。"
        if let hrvBaseline, hrvBaseline > 0 {
            text += String(format: " 最近 7 天均值约 %.0f ms，参考线约 %.0f ms。", hrvBaseline, hrvBaseline * AlertThresholdEngine.hrvBaselineFraction)
        } else if !healthKitManager.connectionState.isUsable {
            text += " 连接 Apple 健康并有足够数据后，才会出现这项提示。"
        } else {
            text += " 暂时还没有足够的近 7 天数据，这项暂不会出现。"
        }
        return text
    }

    private func ruleRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.medium))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(DesignSystem.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func loadBaselines() async {
        let request = NSFetchRequest<UserProfileEntity>(entityName: "UserProfile")
        request.fetchLimit = 1
        if let profile = try? context.fetch(request).first, profile.restingHeartRate > 0 {
            storedResting = Double(profile.restingHeartRate)
        } else {
            storedResting = nil
        }
        if healthKitManager.connectionState.isUsable {
            hrvBaseline = await healthKitManager.fetchSevenDayHRVAverage()
        }
    }
}
