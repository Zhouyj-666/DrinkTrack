import SwiftUI

/// FR-SOC-01：展示自己的好友码（含二维码）、复制/分享，以及把对方的码存到本机。
struct FriendCodeView: View {
    var repository: FriendRepository
    @Environment(\.dismiss) private var dismiss

    @State private var myCode = "------"
    @State private var inputCode = ""
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        Text(myCode)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityLabel("我的好友码 \(myCode)")

                        if myCode.count == 6 {
                            QRCodeView(value: myCode, side: 180)
                        }

                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = myCode
                                copied = true
                            } label: {
                                Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)

                            ShareLink(item: shareText) {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text("我的好友码")
                } footer: {
                    Text("把这串 6 位数字或二维码发给朋友。本版本名单只存在这台手机上，还不能在两台设备之间同步动态。")
                }

                Section("保存对方的好友码") {
                    TextField("输入对方的 6 位好友码", text: $inputCode)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                    Button("保存到本机") {
                        Task { await saveCode() }
                    }
                    .disabled(inputCode.trimmingCharacters(in: .whitespaces).count != 6)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(isError ? DesignSystem.statusCritical : DesignSystem.statusGood)
                    }
                }

                Section {
                    Text("不会按手机号搜索陌生人。名单保存在本机，清除本机数据时会一起删除。对方设备上看不到这里的状态，因为本版本还没有互通。")
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

    private var shareText: String {
        "我的 DrinkTrack 好友码是 \(myCode)。本版本先把码存到手机上，设备之间的动态互通还在后续。"
    }

    private func saveCode() async {
        let result = await repository.sendFriendRequest(code: inputCode)
        switch result {
        case .success(let friend):
            statusMessage = "已把 \(friend.displayName)（\(friend.friendCode)）保存到本机"
            isError = false
            inputCode = ""
        case .failure(let error):
            statusMessage = error.localizedDescription
            isError = true
        }
    }
}
