import SwiftUI

/// FR-SOC-01：好友添加（邀请制，不可主动搜）——展示自己的好友码 + 输入好友码发起请求。
struct FriendCodeView: View {
    let repository: FriendRepository
    @Environment(\.dismiss) private var dismiss

    @State private var myCode = "------"
    @State private var inputCode = ""
    @State private var statusMessage: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("我的好友码") {
                    HStack {
                        Text(myCode).font(.system(.title3, design: .monospaced).bold())
                        Spacer()
                        ShareLink(item: "我在用 DrinkTrack，我的好友码是 \(myCode)，扫码或输入好友码加我吧！") {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }

                Section("添加好友") {
                    TextField("输入对方的 6 位好友码", text: $inputCode)
                        .keyboardType(.numberPad)
                    Button("发送好友请求") {
                        Task { await sendRequest() }
                    }
                    .disabled(inputCode.count != 6)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(isError ? DesignSystem.statusCritical : DesignSystem.statusGood)
                    }
                }

                Section {
                    Text("禁止按手机号主动搜索陌生人；好友关系需要双向确认，未确认前对方看不到你的任何动态（§5.5 FR-SOC-01）。")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.mutedInk)
                }
            }
            .navigationTitle("好友码")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .task { myCode = await repository.myFriendCode() }
        }
    }

    private func sendRequest() async {
        let result = await repository.sendFriendRequest(code: inputCode)
        switch result {
        case .success(let friend):
            statusMessage = "已向 \(friend.displayName) 发送好友请求，等待对方确认"
            isError = false
            inputCode = ""
        case .failure(let error):
            statusMessage = error.localizedDescription
            isError = true
        }
    }
}
