import SwiftUI

/// FR-LEGAL-01：首次启动全屏免责声明，不可跳过，必须点击「我已了解」。
struct DisclaimerView: View {
    let onAccepted: () -> Void
    @State private var hasScrolledToEnd = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(DesignSystem.statusWarning)
                    Text("使用须知").font(.title.bold())
                    Text(DisclaimerStrings.firstLaunchDisclaimer)
                        .font(.body)
                        .foregroundStyle(DesignSystem.primaryInk)

                    Color.clear.frame(height: 1)
                        .onAppear { hasScrolledToEnd = true }
                }
                .padding()
            }

            Divider()

            Button {
                onAccepted()
            } label: {
                Text("我已了解").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasScrolledToEnd)
            .padding()
        }
        .navigationBarBackButtonHidden(true)
    }
}
