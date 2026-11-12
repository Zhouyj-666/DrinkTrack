import SwiftUI

/// FR-LEGAL-02：隐私政策 / 用户协议。首次启动需要显式勾选同意；设置页可随时查阅（无需再勾选）。
struct PrivacyPolicyView: View {
    enum Mode { case onboarding, readOnly }
    let mode: Mode
    var onAgreed: (() -> Void)? = nil

    @State private var hasAgreed = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("隐私政策").font(.title.bold())
                    Text(DisclaimerStrings.privacyPolicySummary)
                        .font(.body)
                        .foregroundStyle(DesignSystem.primaryInk)
                }
                .padding()
            }

            if mode == .onboarding {
                Divider()
                VStack(spacing: 12) {
                    Toggle(isOn: $hasAgreed) {
                        Text("我已阅读并同意《隐私政策》与《用户协议》")
                            .font(.footnote)
                    }
                    Button {
                        onAgreed?()
                    } label: {
                        Text("同意并继续").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasAgreed)
                }
                .padding()
            }
        }
        .navigationBarBackButtonHidden(mode == .onboarding)
        .navigationTitle(mode == .readOnly ? "隐私政策" : "")
    }
}
