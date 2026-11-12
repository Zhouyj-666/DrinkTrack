import SwiftUI
import CoreData

/// §7 首次启动流程最后一步：展示个人好友码（邀请制社交入口，不可跳过，首次生成）。
struct FriendCodeIntroView: View {
    let onFinished: () -> Void
    @Environment(\.managedObjectContext) private var context
    @State private var friendCode: String = "------"

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "qrcode")
                .font(.system(size: 64))
                .foregroundStyle(DesignSystem.heartRateLine)

            Text("这是你的好友码").font(.title2.bold())
            Text(friendCode)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .tracking(4)

            Text("好友只能通过扫描二维码或手动输入好友码添加你，DrinkTrack 不支持按手机号搜索陌生人，避免被陌生人骚扰（§5.5 FR-SOC-01）。")
                .font(.footnote)
                .foregroundStyle(DesignSystem.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button {
                onFinished()
            } label: {
                Text("进入 DrinkTrack").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: loadFriendCode)
    }

    private func loadFriendCode() {
        let request = NSFetchRequest<UserProfileEntity>(entityName: "UserProfile")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \UserProfileEntity.createdAt, ascending: false)]
        request.fetchLimit = 1
        if let profile = try? context.fetch(request).first {
            friendCode = profile.friendCode ?? "------"
        }
    }
}
