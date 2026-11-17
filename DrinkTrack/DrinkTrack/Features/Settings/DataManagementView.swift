import SwiftUI
import UniformTypeIdentifiers

/// §6.1 数据存储与隐私：导出备份、导入备份，以及一键清除本机数据。
struct DataManagementView: View {
    @Environment(\.managedObjectContext) private var context

    @State private var showConfirmErase = false
    @State private var showImporter = false
    @State private var showReplaceConfirm = false
    @State private var resultMessage: String?
    @State private var resultIsError = false
    @State private var shareURL: URL?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var preview: DataImporter.Preview?

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
                .disabled(isExporting || isImporting)

                Button {
                    export(.csv)
                } label: {
                    Label("导出 CSV 表格", systemImage: "tablecells")
                }
                .disabled(isExporting || isImporting)

                if isExporting {
                    ProgressView("正在准备文件…")
                }
            } header: {
                Text("导出")
            } footer: {
                Text("JSON 适合完整备份，CSV 可用表格软件打开。导出内容包括饮酒记录、会话、可选花费和地点（若你曾用「用当前位置」，JSON 和 CSV 里还会带上对应的经纬度）、本场提示、个人基础信息和本机好友名单，不包含 Apple 健康里的原始心率或血氧样本。文件通过系统分享面板发出，小酌场不会自行上传。分享卡片不会带上坐标。")
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("导入 JSON 备份", systemImage: "square.and.arrow.down")
                }
                .disabled(isExporting || isImporting)

                if isImporting {
                    ProgressView("正在读取备份…")
                }
            } header: {
                Text("导入")
            } footer: {
                Text("从「文件」或之前通过分享面板保存的 JSON 备份里恢复。导入前会先预览将要写入的内容。备份里没有 Apple 健康的原始心率或血氧样本，导入也不会改动健康数据。")
            }

            Section {
                Button(role: .destructive) {
                    showConfirmErase = true
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
        .confirmationDialog("确认清除所有本地数据？此操作不可恢复。建议先导出一份备份。", isPresented: $showConfirmErase, titleVisibility: .visible) {
            Button("清除", role: .destructive, action: eraseAll)
            Button("取消", role: .cancel) {}
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                openBackup(url)
            case .failure(let error):
                resultIsError = true
                resultMessage = "无法打开文件：\(error.localizedDescription)"
            }
        }
        .sheet(item: $preview) { item in
            ImportPreviewSheet(
                preview: item,
                isWorking: $isImporting,
                onMerge: { applyImport(.merge, preview: item) },
                onReplace: { showReplaceConfirm = true },
                onCancel: { preview = nil }
            )
            .confirmationDialog(
                "替换会先删除这台手机上现有的饮酒记录、会话、好友和个人基础信息，再用备份里的内容写入。此操作不可恢复。建议确认这份备份是你想要的那一份。",
                isPresented: $showReplaceConfirm,
                titleVisibility: .visible
            ) {
                Button("删除本机数据并导入", role: .destructive) {
                    applyImport(.replace, preview: item)
                }
                Button("取消", role: .cancel) {}
            }
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

    private func openBackup(_ url: URL) {
        resultMessage = nil
        isImporting = true
        defer { isImporting = false }
        do {
            preview = try DataImporter.preview(from: url, context: context)
        } catch {
            resultIsError = true
            resultMessage = "无法导入：\(error.localizedDescription)"
        }
    }

    private func applyImport(_ mode: DataImporter.Mode, preview item: DataImporter.Preview) {
        isImporting = true
        resultMessage = nil
        defer { isImporting = false }
        do {
            let outcome = try DataImporter.apply(item, mode: mode, context: context)
            preview = nil
            resultIsError = false
            resultMessage = successMessage(outcome, mode: mode)
            NotificationCenter.default.post(name: .drinkTrackDataDidChange, object: nil)
        } catch {
            resultIsError = true
            resultMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func successMessage(_ outcome: DataImporter.Outcome, mode: DataImporter.Mode) -> String {
        let modeText = mode == .merge ? "已合并导入" : "已替换并导入"
        var parts = [
            "\(outcome.sessionsAdded) 场会话",
            "\(outcome.logsAdded) 条饮酒记录"
        ]
        if outcome.friendsAdded > 0 {
            parts.append("\(outcome.friendsAdded) 位好友")
        }
        if outcome.placesAdded > 0 {
            parts.append("\(outcome.placesAdded) 个地点")
        }
        if outcome.placeMarksAdded > 0 {
            parts.append("\(outcome.placeMarksAdded) 个饮酒地图标记")
        }
        if outcome.profileImported {
            parts.append("个人基础信息")
        }
        var text = "\(modeText)：\(parts.joined(separator: "、"))。"
        if outcome.sessionsSkipped > 0 {
            text += " 另有 \(outcome.sessionsSkipped) 场因本机已有而跳过。"
        }
        if outcome.archivedImportedActive {
            text += " 备份里有进行中的会话，本机已有一场进行中，已把导入的那场记为已结束，避免同时开着两场。"
        }
        text += " 备份不含 Apple 健康样本，健康数据没有改动。"
        return text
    }

    private func eraseAll() {
        do {
            try PersistenceController.shared.eraseAllLocalData()
            UserPreferences.clearLocalPreferences()
            resultIsError = false
            resultMessage = "已清除本机所有数据"
            NotificationCenter.default.post(name: .drinkTrackDataDidChange, object: nil)
        } catch {
            resultIsError = true
            resultMessage = "清除失败：\(error.localizedDescription)"
        }
    }
}

private struct ImportPreviewSheet: View {
    let preview: DataImporter.Preview
    @Binding var isWorking: Bool
    let onMerge: () -> Void
    let onReplace: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("文件", value: preview.fileName)
                    if let exportedAt = preview.exportedAt {
                        LabeledContent("导出时间", value: format(exportedAt))
                    }
                    LabeledContent("格式版本", value: "\(preview.schemaVersion)")
                } header: {
                    Text("备份信息")
                }

                Section {
                    row("会话", "\(preview.sessionCount) 场" + (preview.activeSessionCount > 0 ? "（其中 \(preview.activeSessionCount) 场进行中）" : ""))
                    row("饮酒记录", "\(preview.logCount) 条")
                    row("花费", preview.spendCount > 0 ? "\(preview.spendCount) 条，共 \(UserPreferences.formatYuan(fen: preview.spendFen))" : "没有记录花费")
                    row("地点", preview.placeCount > 0 ? "\(preview.placeCount) 个" : "没有地点")
                    row("饮酒地图标记", preview.placeMarkCount > 0 ? "\(preview.placeMarkCount) 个" : "没有标记")
                    row("本场提示", preview.alertCount > 0 ? "\(preview.alertCount) 条" : "没有提示")
                    row("个人基础信息", preview.hasProfile ? "有" : "没有")
                    row("本机好友", preview.friendCount > 0 ? "\(preview.friendCount) 人" : "没有")
                } header: {
                    Text("将要导入的内容")
                } footer: {
                    Text("会导入饮酒记录、会话、可选花费和地点（若备份里有经纬度也会一并恢复，供本机地图使用）、本场提示、个人基础信息和本机好友名单。不会导入 Apple 健康里的原始心率、血氧等样本，因为备份文件里没有这些数据。")
                }

                Section {
                    if preview.duplicateSessionCount > 0 || preview.duplicateLogCount > 0 || preview.duplicateFriendCount > 0 {
                        Text("合并时会跳过本机已经存在的 \(preview.duplicateSessionCount) 场会话、\(preview.duplicateLogCount) 条记录、\(preview.duplicateFriendCount) 位好友，避免重复。合并不会覆盖你现在的个人基础信息。")
                    } else {
                        Text("合并会把备份里还没有的记录加进来，不会覆盖你现在的个人基础信息，也不会改已经在本机的同一条记录。")
                    }
                    if preview.localHasActiveSession && preview.activeSessionCount > 0 {
                        Text("本机已有进行中的会话。合并时，备份里进行中的会话会记为已结束，避免同时开着两场。")
                    }
                    Text("替换会先删除这台手机上现有的饮酒记录、会话、好友和个人基础信息，再用备份写入。请先确认这是你想恢复的那份备份。")
                        .foregroundStyle(DesignSystem.statusSerious)
                } header: {
                    Text("合并或替换")
                }

                Section {
                    Button(action: onMerge) {
                        Label("合并导入", systemImage: "square.and.arrow.down.on.square")
                    }
                    .disabled(isWorking)

                    Button(role: .destructive, action: onReplace) {
                        Label("替换全部数据…", systemImage: "exclamationmark.triangle")
                    }
                    .disabled(isWorking)

                    if isWorking {
                        ProgressView("正在导入…")
                    }
                }
            }
            .navigationTitle("导入备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                        .disabled(isWorking)
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct ExportURL: Identifiable {
    let url: URL
    var id: String { url.path }
}

extension DataImporter.Preview: Identifiable {
    var id: String { fileName + "|" + (exportedAt?.timeIntervalSince1970.description ?? "na") }
}
