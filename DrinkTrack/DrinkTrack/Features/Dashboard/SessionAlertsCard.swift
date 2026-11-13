import SwiftUI

/// 本场已经出现过的身体提示列表，会话进行中和详情页都能用。
/// 只陈述当时的原因，不做评价。
struct SessionAlertsCard: View {
    let alerts: [AlertThresholdEngine.AlertResult]
    var title: String = "本场提示"

    var body: some View {
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                ForEach(alerts) { alert in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: alert.kind.symbolName)
                            .foregroundStyle(DesignSystem.statusWarning)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(alert.title).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(alert.triggeredAt, format: .dateTime.hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(DesignSystem.mutedInk)
                            }
                            Text(alert.reason)
                                .font(.footnote)
                                .foregroundStyle(DesignSystem.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if alert.id != alerts.last?.id {
                        Divider()
                    }
                }
                Text(alerts.last?.disclaimer ?? DisclaimerStrings.passiveAlertDisclaimer)
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.mutedInk)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.chartSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// 把一条结构化提示画成底部横幅：标题、原因、免责，可手动关掉，约 8 秒后自动收起。
struct AlertBannerView: View {
    let alert: AlertThresholdEngine.AlertResult
    let onDismiss: () -> Void

    @State private var isVisible = true

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: alert.kind.symbolName)
                        .foregroundStyle(DesignSystem.statusWarning)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alert.title)
                            .font(.subheadline.weight(.semibold))
                        Text(alert.reason)
                            .font(.footnote)
                            .foregroundStyle(DesignSystem.primaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(alert.disclaimer)
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.mutedInk)
                    }
                    Spacer(minLength: 8)
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.mutedInk)
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .padding()
            .background(DesignSystem.chartSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 8)
            .padding(.horizontal)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                dismiss()
            }
        }
    }

    private func dismiss() {
        isVisible = false
        onDismiss()
    }
}
