import SwiftUI

/// FR-DR-01：新建 DrinkLog 快速录入表单，3 步完成（选种类 → 选剂量 → 确认）。
struct QuickLogSheet: View {
    let session: DrinkSessionEntity
    @ObservedObject var drinkRepository: DrinkRepository
    @Environment(\.dismiss) private var dismiss

    @State private var category: DrinkCategory = .beer
    @State private var brand: String = ""
    @State private var volumeML: Double = 500
    @State private var customABVPercent: Double = 15 // 仅「其他」类目使用，展示层用整数百分比，换算前除以 100
    @State private var timestamp = Date()
    @State private var note: String = ""
    @State private var addedCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("酒种类") {
                    DrinkCategoryPicker(selection: $category)
                }

                Section("品牌（可选）") {
                    BrandPickerField(category: category, brand: $brand)
                }

                Section("剂量") {
                    VolumeInputView(category: category, volumeML: $volumeML)
                    if category == .other {
                        HStack {
                            Text("酒精含量")
                            Slider(value: $customABVPercent, in: 0...70, step: 1)
                            Text("\(Int(customABVPercent))%").frame(width: 48)
                        }
                    }
                    if let standard = StandardDrinkConverter.standardDrinks(
                        volumeML: volumeML, category: category,
                        customABVFraction: category == .other ? customABVPercent / 100 : nil
                    ) {
                        Text(StandardDrinkConverter.formatted(standard))
                            .font(.footnote)
                            .foregroundStyle(DesignSystem.secondaryInk)
                    }
                    if volumeML > 1000 {
                        Label("单条记录超过 1000ml，请确认数值正确", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.statusWarning)
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
        }
    }

    private func addLogAndContinue() {
        drinkRepository.addDrinkLog(
            to: session,
            category: category,
            brand: brand.isEmpty ? nil : brand,
            volumeML: volumeML,
            timestamp: timestamp,
            note: note.isEmpty ? nil : note,
            customABVFraction: category == .other ? customABVPercent / 100 : nil
        )
        addedCount += 1
        timestamp = Date()
        note = ""
    }
}

/// FR-DR-03：品牌搜索/自由输入。
private struct BrandPickerField: View {
    let category: DrinkCategory
    @Binding var brand: String

    var body: some View {
        VStack(alignment: .leading) {
            TextField("搜索或输入品牌", text: $brand)
            if !category.presetBrands.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(category.presetBrands.filter {
                            brand.isEmpty || $0.localizedCaseInsensitiveContains(brand)
                        }, id: \.self) { preset in
                            Button(preset) { brand = preset }
                                .font(.caption)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
}
