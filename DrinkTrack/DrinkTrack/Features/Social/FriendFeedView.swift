import SwiftUI

/// §5.5 轻量社交模块首页：本机好友名单 + 好友码入口。
/// 本版本没有跨设备动态，不再展示示例数据。
struct FriendFeedView: View {
    let repository: FriendRepository
    @State private var friends: [FriendSummary] = []
    @State private var showFriendCode = false
    @State private var renaming: FriendSummary?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("还不能查看其他设备上的好友动态")
                            .font(.subheadline.weight(.medium))
                        Text("本版本好友码和名单只保存在这台手机上。你可以先交换好友码、把对方存下来，互通能力后续再接。好友即使以后能看到摘要，也不会看到生理数据或花费。")
                            .font(.footnote)
                            .foregroundStyle(DesignSystem.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                if friends.isEmpty {
                    Section {
                        Text("还没有保存任何好友码。点右上角二维码，查看你的码或把对方的码存到本机。")
                            .font(.footnote)
                            .foregroundStyle(DesignSystem.mutedInk)
                    }
                } else {
                    Section("已保存的好友（\(friends.count)）") {
                        ForEach(friends) { friend in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.displayName)
                                    Text(friend.friendCode)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(DesignSystem.secondaryInk)
                                }
                                Spacer()
                                Text(friend.status == "confirmed" ? "已确认" : "待确认")
                                    .font(.caption)
                                    .foregroundStyle(friend.status == "confirmed" ? DesignSystem.statusGood : DesignSystem.statusWarning)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        await repository.removeFriend(id: friend.id)
                                        await load()
                                    }
                                } label: {
                                    Text("删除")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if friend.status != "confirmed" {
                                    Button {
                                        Task {
                                            await repository.confirmFriend(id: friend.id)
                                            await load()
                                        }
                                    } label: {
                                        Text("标记已确认")
                                    }
                                    .tint(DesignSystem.statusGood)
                                }
                                Button {
                                    renaming = friend
                                    renameText = friend.displayName
                                } label: {
                                    Text("改备注")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("好友")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFriendCode = true } label: {
                        Image(systemName: "qrcode")
                    }
                    .accessibilityLabel("好友码")
                    .accessibilityIdentifier("friend-code-button")
                }
            }
            .sheet(isPresented: $showFriendCode, onDismiss: { Task { await load() } }) {
                FriendCodeView(repository: repository)
            }
            .alert("改备注", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("备注名", text: $renameText)
                Button("保存") {
                    if let friend = renaming {
                        Task {
                            await repository.renameFriend(id: friend.id, displayName: renameText)
                            renaming = nil
                            await load()
                        }
                    }
                }
                Button("取消", role: .cancel) { renaming = nil }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        friends = await repository.fetchFriends()
    }
}
