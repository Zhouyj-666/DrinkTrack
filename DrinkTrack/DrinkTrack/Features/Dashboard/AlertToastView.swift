import SwiftUI

/// FR-DASH-03：被动预警弹窗。
///
/// PRD 原文写的是"2 秒后自动消失"，我们给用户的建议③认为健康类提示 2 秒太快、免责文案很容易没读完
/// 就消失，这里按建议改成 **6 秒**（仍可手动关闭）。不触发系统通知推送，只在 APP 前台展示。
struct AlertToastView: View {
    let message: String
    let onDismiss: () -> Void

    @State private var isVisible = true

    var body: some View {
        if isVisible {
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(DesignSystem.statusWarning)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(DesignSystem.primaryInk)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.mutedInk)
                    }
                }
            }
            .padding()
            .background(DesignSystem.chartSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 8)
            .padding(.horizontal)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                dismiss()
            }
        }
    }

    private func dismiss() {
        isVisible = false
        onDismiss()
    }
}
