import SwiftUI

/// 当前账号：查看资料并退出登录。退出不会删除本机记录。
struct AccountView: View {
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.dismiss) private var dismiss

    @State private var isLoggingOut = false
    @State private var confirmLogout = false
    @State private var serverURL = AuthAPIConfiguration.baseURLString
    @State private var route: AccountViewRoute?

    var body: some View {
        List {
            if let user = authSession.user {
                Section {
                    LabeledContent("称呼", value: user.displayName)
                    LabeledContent("邮箱", value: user.email)
                    if authSession.phase == .signedInOffline {
                        Text("暂时连不上服务器，你仍保持登录。连上之后会自动核对会话。")
                            .font(.caption)
                            .foregroundStyle(AuthPalette.muted)
                    } else {
                        Text("新记的酒会挂到这个账号上，方便以后同步。心率、血氧和精确位置只留在这台手机里。")
                            .font(.caption)
                            .foregroundStyle(AuthPalette.muted)
                    }
                } header: {
                    Text("当前账号")
                }
            } else {
                Section {
                    Text("你现在没有登录。先不登录也可以继续用小酌场。")
                        .foregroundStyle(AuthPalette.secondary)
                    Button("登录") { route = .login }
                    Button("注册") { route = .register }
                }
            }

            Section {
                TextField(AuthAPIConfiguration.defaultBaseURLString, text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: serverURL) { _, newValue in
                        AuthAPIConfiguration.baseURLString = newValue
                    }
                Text("仅开发阶段使用。模拟器用 127.0.0.1，真机改成电脑的局域网 IP。正式版会改用 HTTPS。")
                    .font(.caption)
                    .foregroundStyle(AuthPalette.muted)
            } header: {
                Text("开发服务器")
            }

            if authSession.user != nil {
                Section {
                    Button(role: .destructive) {
                        confirmLogout = true
                    } label: {
                        HStack {
                            Text("退出登录")
                            if isLoggingOut { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isLoggingOut)
                } footer: {
                    Text("退出后，新的记录不再挂到这个账号上。这台手机里已经记下的酒不会被删除。")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .sipScreenBackground()
        .navigationTitle("账号")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { route in
            switch route {
            case .login:
                LoginView()
            case .register:
                RegisterView()
            }
        }
        .alert("退出登录？", isPresented: $confirmLogout) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) {
                Task { await performLogout() }
            }
        } message: {
            Text("不会删除这台手机上的饮酒记录，只是把账号会话清掉。")
        }
    }

    private func performLogout() async {
        isLoggingOut = true
        await authSession.logout()
        isLoggingOut = false
        dismiss()
    }
}

private enum AccountViewRoute: Hashable {
    case login
    case register
}
