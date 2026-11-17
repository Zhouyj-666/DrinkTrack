import SwiftUI

/// 邮箱 + 密码登录。没有做不了的 Apple / 手机号按钮。
struct LoginView: View {
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var serverURL = AuthAPIConfiguration.baseURLString
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showServerField = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("欢迎回来")
                    .font(.title.bold())
                    .foregroundStyle(AuthPalette.ink)
                Text("用邮箱登录小酌场。登录后，这台手机上还没有挂账号的记录会附到你名下。健康数据不会上传。")
                    .font(.subheadline)
                    .foregroundStyle(AuthPalette.secondary)

                field(title: "邮箱") {
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                field(title: "密码") {
                    SecureField("至少 8 位", text: $password)
                        .textContentType(.password)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(AuthPalette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: submit) {
                    HStack {
                        if isWorking { ProgressView().tint(.white) }
                        Text(isWorking ? "正在登录…" : "登录")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SipPrimaryButtonStyle())
                .disabled(isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)

                NavigationLink("还没有账号？注册一个") {
                    RegisterView()
                }
                .font(.subheadline)
                .foregroundStyle(AuthPalette.burgundySoft)

                DisclosureGroup("开发服务器地址", isExpanded: $showServerField) {
                    Text("模拟器可用默认的 127.0.0.1。真机请改成电脑的局域网 IP，例如 http://192.168.1.12:8000。")
                        .font(.caption)
                        .foregroundStyle(AuthPalette.muted)
                    TextField(AuthAPIConfiguration.defaultBaseURLString, text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: serverURL) { _, newValue in
                            AuthAPIConfiguration.baseURLString = newValue
                        }
                }
                .font(.subheadline)
                .foregroundStyle(AuthPalette.secondary)
            }
            .padding(24)
        }
        .sipScreenBackground()
        .navigationTitle("登录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AuthPalette.muted)
            content()
                .padding(12)
                .background(AuthPalette.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func submit() {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@") else {
            errorMessage = AuthAPIError.invalidEmail.userMessage
            return
        }
        isWorking = true
        AuthAPIConfiguration.baseURLString = serverURL
        Task {
            do {
                try await authSession.login(email: trimmedEmail, password: password)
                dismiss()
            } catch let error as AuthAPIError {
                errorMessage = error.userMessage
            } catch {
                errorMessage = AuthAPIError.unexpected.userMessage
            }
            isWorking = false
        }
    }
}
