import SwiftUI

/// §6.1 数据存储与隐私规则：一键清除本地数据。
struct DataManagementView: View {
    @State private var showConfirm = false
    @State private var resultMessage: String?

    var body: some View {
        Form {
            Section {
                Text("所有生理数据和饮酒记录默认仅存储在本机（Core Data），不会上传到任何服务器。")
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.secondaryInk)
            }

            Section {
                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    Text("清除所有数据").frame(maxWidth: .infinity)
                }
            } footer: {
                Text("清除本机所有饮酒记录、会话、健康数据缓存和基础信息。不会影响 Apple Health 里的原始健康数据——那些数据属于你，由系统管理，本 App 无权也不会删除。")
            }

            if let resultMessage {
                Text(resultMessage).font(.footnote).foregroundStyle(DesignSystem.statusGood)
            }
        }
        .navigationTitle("数据管理")
        .confirmationDialog("确认清除所有本地数据？此操作不可恢复。", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("清除", role: .destructive, action: eraseAll)
            Button("取消", role: .cancel) {}
        }
    }

    private func eraseAll() {
        do {
            try PersistenceController.shared.eraseAllLocalData()
            UserPreferences.clearRecentLocations()
            resultMessage = "已清除本机所有数据"
        } catch {
            resultMessage = "清除失败：\(error.localizedDescription)"
        }
    }
}
