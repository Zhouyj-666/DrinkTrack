import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var serverURL = AuthAPIConfiguration.baseURLString
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showServerField = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("给自己做一个账号")
                    .font(.title.bold())
                    .foregroundStyle(AuthPalette.ink)
                Text("这一期先用邮箱和密码。手机号和通过 Apple 登录等你开通相关资质后再接上。先不注册也可以继续记酒。")
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
                        .textContentType(.newPassword)
                }
                field(title: "怎么称呼你（可选）") {
                    TextField("例如：小酌", text: $displayName)
                        .textContentType(.name)
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
                        Text(isWorking ? "正在注册…" : "注册并登录")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SipPrimaryButtonStyle())
                .disabled(isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)

                Text("注册成功后，这台手机上还没有挂账号的记录会附到你名下。健康数据仍然只留在这台手机里。")
                    .font(.caption)
                    .foregroundStyle(AuthPalette.muted)

                DisclosureGroup("开发服务器地址", isExpanded: $showServerField) {
                    Text("模拟器可用默认的 127.0.0.1。真机请改成电脑的局域网 IP。")
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
        .navigationTitle("注册")
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
        guard password.count >= 8 else {
            errorMessage = AuthAPIError.weakPassword.userMessage
            return
        }
        isWorking = true
        AuthAPIConfiguration.baseURLString = serverURL
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await authSession.register(
                    email: trimmedEmail,
                    password: password,
                    displayName: name.isEmpty ? nil : name
                )
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
