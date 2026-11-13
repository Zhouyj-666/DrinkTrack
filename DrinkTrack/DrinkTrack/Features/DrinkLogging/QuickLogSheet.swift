import SwiftUI

/// FR-DR-01：新建 DrinkLog 快速录入表单，3 步完成（选种类 → 选剂量 → 确认）。
/// 品牌、酒精度、地点、花费、备注都是可选项，不填也能直接记。
struct QuickLogSheet: View {
    let session: DrinkSessionEntity
    @ObservedObject var drinkRepository: DrinkRepository
    @Environment(\.dismiss) private var dismiss

    @State private var category: DrinkCategory = UserPreferences.lastDrinkCategory
    @State private var brand: String = ""
    /// 从品牌库选中的酒款；用户手动改了品牌文字后清空。
    @State private var selectedBrandItem: BrandItem?
    @State private var volumeML: Double = UserPreferences.lastDrinkVolumeML
    /// 本条记录用于换算的酒精度（百分比数值）。默认取酒种类的典型值，选品牌后取品牌参考值。
    @State private var abvPercent: Double = QuickLogSheet.defaultABVPercent(for: UserPreferences.lastDrinkCategory)
    @State private var timestamp = Date()
    @State private var note: String = ""
    @State private var amountYuanText: String = ""
    @State private var locationName: String = ""
    @State private var addedCount = 0
    @StateObject private var locationProvider = LocationProvider()

    var body: some View {
        NavigationStack {
            Form {
                Section("酒种类") {
                    DrinkCategoryPicker(selection: $category)
                }

                Section {
                    BrandPickerField(
                        category: category,
                        brand: $brand,
                        onPick: pickBrand
                    )
                    // Own row: a NavigationLink inside a multi-control row would make
                    // the whole row (including the text field) act as the link.
                    NavigationLink {
                        BrandLibraryView(initialCategory: category) { item in
                            pickBrand(item)
                        }
                    } label: {
                        Label("浏览品牌库（\(BrandLibrary.all.count) 款）", systemImage: "books.vertical")
                            .font(.footnote)
                    }
                } header: {
                    Text("品牌 / 酒款（可选）")
                } footer: {
                    Text("支持中文、拼音或首字母搜索，例如「maotai」「qd」。选中后会自动带出参考酒精度。")
                }

                Section("剂量") {
                    VolumeInputView(category: category, volumeML: $volumeML)
                    ABVRow(abvPercent: $abvPercent, fromBrand: selectedBrandItem != nil)
                    Text(StandardDrinkConverter.formatted(standardDrinks))
                        .font(.footnote)
                        .foregroundStyle(DesignSystem.secondaryInk)
                    if volumeML > 1000 {
                        Label("单条记录超过 1000ml，请确认数值正确", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.statusWarning)
                    }
                }

                Section {
                    LocationInputField(locationName: $locationName, provider: locationProvider)
                } header: {
                    Text("地点（可选）")
                } footer: {
                    Text("只保存地名文字，不保存经纬度，也不会出现在好友动态里。分享卡片默认不显示地点。")
                }

                if UserPreferences.spendTrackingEnabled {
                    Section {
                        HStack {
                            Text("金额")
                            TextField("未填写", text: $amountYuanText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("元")
                                .foregroundStyle(DesignSystem.secondaryInk)
                        }
                    } header: {
                        Text("花费（可选）")
                    } footer: {
                        Text("可不填。花费只保存在本机，只有你自己能看到，不会出现在好友动态或分享卡片里。")
                    }
                }

                Section("时间") {
                    // FR-DR-01：时间戳默认取当前时间，允许手动调整 ±15 分钟
                    DatePicker("时间", selection: $timestamp,
                               in: Date().addingTimeInterval(-900)...Date().addingTimeInterval(900))
                }

                Section("备注（可选）") {
                    TextField("口感 / 心情", text: $note)
                }

                Section {
                    Button {
                        addLogAndContinue()
                    } label: {
                        Text(addedCount == 0 ? "+1 继续" : "再添加一条（已记录 \(addedCount) 条）")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        dismiss()
                    } label: {
                        Text("完成").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("添加饮酒记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                if locationName.isEmpty, let existing = session.locationName {
                    locationName = existing
                }
            }
            .onChange(of: category) { _, newCategory in
                // 切换酒种类时，如果当前品牌不属于新类目，酒精度回到新类目的典型值。
                if selectedBrandItem?.category != newCategory {
                    selectedBrandItem = nil
                    abvPercent = Self.defaultABVPercent(for: newCategory)
                }
            }
            .onChange(of: brand) { _, newValue in
                if let item = selectedBrandItem, item.name != newValue {
                    selectedBrandItem = nil
                }
            }
        }
    }

    private var standardDrinks: Double {
        StandardDrinkConverter.standardDrinks(volumeML: volumeML, abvFraction: abvPercent / 100)
    }

    private func pickBrand(_ item: BrandItem) {
        selectedBrandItem = item
        brand = item.name
        abvPercent = item.abvPercent
        category = item.category
    }

    static func defaultABVPercent(for category: DrinkCategory) -> Double {
        (category.typicalABVFraction ?? 0.15) * 100
    }

    private func addLogAndContinue() {
        drinkRepository.addDrinkLog(
            to: session,
            category: category,
            brand: brand.isEmpty ? nil : brand,
            volumeML: volumeML,
            timestamp: timestamp,
            note: note.isEmpty ? nil : note,
            customABVFraction: abvPercent / 100,
            amountFen: UserPreferences.parseYuanToFen(amountYuanText),
            locationName: locationName
        )
        addedCount += 1
        timestamp = Date()
        note = ""
        amountYuanText = ""
        // 地点和品牌保留：同一场里连着记几杯，通常是同一个地方、同一款酒。
    }
}

/// 酒精度：默认典型值，选品牌后带出参考值，都可以手动调。
private struct ABVRow: View {
    @Binding var abvPercent: Double
    let fromBrand: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("酒精度")
                Slider(value: $abvPercent, in: 0...70, step: 0.5)
                Text(abvLabel)
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
            Text(fromBrand ? "已按所选酒款的参考酒精度计算，可拖动调整" : "默认按该酒种的常见酒精度估算，可拖动调整")
                .font(.caption2)
                .foregroundStyle(DesignSystem.mutedInk)
        }
    }

    private var abvLabel: String {
        abvPercent == abvPercent.rounded()
            ? String(format: "%.0f%%", abvPercent)
            : String(format: "%.1f%%", abvPercent)
    }
}

/// FR-DR-03：品牌搜索 / 自由输入。没输入时给出当前类目的常见酒款；
/// 输入后搜索整个品牌库（含拼音），也可以进入完整列表浏览。
private struct BrandPickerField: View {
    let category: DrinkCategory
    @Binding var brand: String
    let onPick: (BrandItem) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("搜索或输入品牌", text: $brand)
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if showsSearchResults {
                if searchResults.isEmpty {
                    Text("品牌库里没找到，会按你输入的名称记录。")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.mutedInk)
                } else {
                    ForEach(searchResults) { item in
                        Button {
                            onPick(item)
                            focused = false
                        } label: {
                            BrandResultRow(item: item, highlightCategory: item.category != category)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } else {
                let suggestions = BrandLibrary.items(in: category).prefix(8)
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(suggestions)) { item in
                                Button(item.name) { onPick(item) }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 输入内容正好是已选中的酒款名时，不再展开搜索结果。
    private var showsSearchResults: Bool {
        let trimmed = brand.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return BrandLibrary.item(named: trimmed) == nil || focused
    }

    private var searchResults: [BrandItem] {
        BrandLibrary.search(brand, preferredCategory: category, limit: 6)
    }
}

struct BrandResultRow: View {
    let item: BrandItem
    var highlightCategory = false

    var body: some View {
        HStack {
            Text(item.category.emoji)
            Text(item.name)
                .foregroundStyle(DesignSystem.primaryInk)
            if highlightCategory {
                Text(item.category.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(DesignSystem.color(for: item.category).opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(DesignSystem.secondaryInk)
            }
            Spacer()
            Text(item.abvText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(DesignSystem.secondaryInk)
        }
        .contentShape(Rectangle())
    }
}

/// FR-DR-05：地点输入。手动输入、点「用当前位置」或点最近用过的地点。
private struct LocationInputField: View {
    @Binding var locationName: String
    @ObservedObject var provider: LocationProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(DesignSystem.secondaryInk)
                TextField("例如：家里、三里屯某酒吧", text: $locationName)
                if !locationName.isEmpty {
                    Button {
                        locationName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignSystem.mutedInk)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("清除地点")
                }
            }

            HStack {
                Button {
                    provider.fillCurrentPlace { name in
                        locationName = name
                    }
                } label: {
                    if provider.state == .locating {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("正在定位…")
                        }
                    } else {
                        Label("用当前位置", systemImage: "location")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(provider.state == .locating)
                .font(.footnote)

                Spacer()
            }

            if case .failed(let message) = provider.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.statusWarning)
            }

            let recents = UserPreferences.recentLocations.filter { $0 != locationName }
            if !recents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(recents, id: \.self) { name in
                            Button(name) { locationName = name }
                                .font(.caption)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
}
