import SwiftUI

/// Drop-in account card for the redesigned 「我的」 page.
///
/// AUTH-HOOK: embed this under a `sectionHeader("账号")` in ProfileView.
/// Keep the insertion small so later Me tweaks can rebase around it:
///
///     sectionHeader("账号")
///     AccountSectionView()
struct AccountSectionView: View {
    @EnvironmentObject private var authSession: AuthSession

    var body: some View {
        Group {
            if let user = authSession.user {
                NavigationLink {
                    AccountView()
                } label: {
                    HStack(spacing: 12) {
                        iconBadge("person.crop.circle.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(DesignSystem.primaryInk)
                            Text(user.email)
                                .font(.system(size: 13))
                                .foregroundStyle(DesignSystem.mutedInk)
                            if authSession.phase == .signedInOffline {
                                Text("暂时连不上服务器，你仍保持登录")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DesignSystem.muted2)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignSystem.muted2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .sipCardChromeLike()
                .accessibilityLabel("当前账号")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("登录后，这台手机上已有的记录会挂到你的账号上，方便以后换机同步。健康数据仍然只留在这台手机里。")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("先不登录也可以继续用。")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.muted2)
                    HStack(spacing: 10) {
                        NavigationLink {
                            LoginView()
                        } label: {
                            Text("登录")
                        }
                        .buttonStyle(SipPrimaryButtonStyle())
                        NavigationLink {
                            RegisterView()
                        } label: {
                            Text("注册")
                        }
                        .buttonStyle(SipOutlineButtonStyle())
                    }
                }
                .sipCard()
            }
        }
    }

    private func iconBadge(_ systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignSystem.burgundySoft)
                .frame(width: 36, height: 36)
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignSystem.burgundy)
        }
    }
}

private extension View {
    func sipCardChromeLike() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCorner, style: .continuous))
            .shadow(color: Color(red: 90 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.04), radius: 2, y: 1)
    }
}
