import SwiftUI

/// §5.5 轻量社交模块首页：好友动态 feed（FR-SOC-02）。
struct FriendFeedView: View {
    let repository: FriendRepository
    @State private var feed: [FriendFeedItem] = []
    @State private var friends: [FriendSummary] = []
    @State private var showFriendCode = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(feed) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.friendDisplayName).font(.subheadline.bold())
                                Text(item.category.emoji)
                                Spacer()
                                Text(item.date, style: .relative).font(.caption).foregroundStyle(DesignSystem.mutedInk)
                            }
                            Text("\(item.category.displayName) · \(Int(item.totalVolumeML))ml")
                                .font(.footnote).foregroundStyle(DesignSystem.secondaryInk)
                            if let note = item.note {
                                Text(note).font(.footnote).foregroundStyle(DesignSystem.mutedInk)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("好友最近 7 天动态（仅摘要，不展示生理数据）")
                }

                if !friends.isEmpty {
                    Section("好友（\(friends.count)）") {
                        ForEach(friends) { friend in
                            HStack {
                                Text(friend.displayName)
                                Spacer()
                                if friend.status == "pending" {
                                    Text("待确认").font(.caption).foregroundStyle(DesignSystem.statusWarning)
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
                }
            }
            .sheet(isPresented: $showFriendCode) {
                FriendCodeView(repository: repository)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        feed = await repository.fetchFeed()
        friends = await repository.fetchFriends()
    }
}
