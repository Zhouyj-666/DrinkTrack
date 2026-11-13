import SwiftUI

/// §6.1 数据存储与隐私：导出备份，以及一键清除本机数据。
struct DataManagementView: View {
    @State private var showConfirm = false
    @State private var resultMessage: String?
    @State private var resultIsError = false
    @State private var shareURL: URL?
    @State private var isExporting = false

    var body: some View {
        Form {
            Section {
                Text("饮酒记录和个人信息默认只存在这台手机上，不会上传到任何服务器。建议在清除数据或换机之前先导出一份备份。")
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.secondaryInk)
            }

            Section {
                Button {
                    export(.json)
                } label: {
                    Label("导出 JSON 备份", systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting)

                Button {
                    export(.csv)
                } label: {
                    Label("导出 CSV 表格", systemImage: "tablecells")
                }
                .disabled(isExporting)

                if isExporting {
                    ProgressView("正在准备文件…")
                }
            } header: {
                Text("导出")
            } footer: {
                Text("JSON 适合完整备份，CSV 可用表格软件打开。导出内容包括饮酒记录、会话、可选花费和地点、本场提示、个人基础信息和本机好友名单，不包含 Apple 健康里的原始心率或血氧样本。文件通过系统分享面板发出，DrinkTrack 不会自行上传。")
            }

            Section {
                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    Text("清除所有数据").frame(maxWidth: .infinity)
                }
            } header: {
                Text("清除")
            } footer: {
                Text("会删除：本机所有饮酒记录和会话、本场提示、个人信息、本机好友名单，以及最近用过的地点、上次的酒种和杯型。不会删除：Apple 健康里的原始数据、你已经导出并保存到别处的文件。清除后不会重新显示使用须知和隐私政策。此操作不可恢复。")
            }

            if let resultMessage {
                Text(resultMessage)
                    .font(.footnote)
                    .foregroundStyle(resultIsError ? DesignSystem.statusCritical : DesignSystem.statusGood)
            }
        }
        .navigationTitle("数据管理")
        .confirmationDialog("确认清除所有本地数据？此操作不可恢复。建议先导出一份备份。", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("清除", role: .destructive, action: eraseAll)
            Button("取消", role: .cancel) {}
        }
        .sheet(item: Binding(
            get: { shareURL.map(ExportURL.init) },
            set: { shareURL = $0?.url }
        )) { item in
            ActivityShareView(url: item.url)
        }
    }

    private func export(_ format: DataExporter.Format) {
        isExporting = true
        resultMessage = nil
        do {
            let result = try DataExporter.export(format: format)
            shareURL = result.url
            resultIsError = false
            resultMessage = "已准备 \(result.fileName)，请选择保存位置。"
        } catch {
            resultIsError = true
            resultMessage = "导出失败：\(error.localizedDescription)"
        }
        isExporting = false
    }

    private func eraseAll() {
        do {
            try PersistenceController.shared.eraseAllLocalData()
            UserPreferences.clearLocalPreferences()
            resultIsError = false
            resultMessage = "已清除本机所有数据"
        } catch {
            resultIsError = true
            resultMessage = "清除失败：\(error.localizedDescription)"
        }
    }
}

private struct ExportURL: Identifiable {
    let url: URL
    var id: String { url.path }
}
