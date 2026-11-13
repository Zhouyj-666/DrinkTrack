import SwiftUI

/// FR-DR-03：完整品牌库浏览 / 搜索页（录入页「浏览品牌库」进入）。
/// 不搜索时按酒种类分组列出；搜索时支持中文、全拼和拼音首字母。
struct BrandLibraryView: View {
    let initialCategory: DrinkCategory
    let onPick: (BrandItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filterCategory: DrinkCategory?

    init(initialCategory: DrinkCategory, onPick: @escaping (BrandItem) -> Void) {
        self.initialCategory = initialCategory
        self.onPick = onPick
        _filterCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(title: "全部", selected: filterCategory == nil) { filterCategory = nil }
                        ForEach(DrinkCategory.allCases) { category in
                            chip(title: "\(category.emoji) \(category.displayName)", selected: filterCategory == category) {
                                filterCategory = category
                            }
                        }
                    }
                }
            }

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(visibleCategories) { category in
                    let items = BrandLibrary.items(in: category)
                    if !items.isEmpty {
                        Section("\(category.displayName)（\(items.count)）") {
                            ForEach(items) { item in
                                row(item)
                            }
                        }
                    }
                }
            } else {
                let results = searchResults
                if results.isEmpty {
                    Section {
                        Text("没有找到「\(query)」。可以返回直接输入这个名称记录。")
                            .font(.footnote)
                            .foregroundStyle(DesignSystem.mutedInk)
                    }
                } else {
                    Section("搜索结果（\(results.count)）") {
                        ForEach(results) { item in
                            row(item)
                        }
                    }
                }
            }

            Section {
                Text("酒精度为常见规格的参考值，不同规格、批次可能不同，录入时可手动调整。")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.mutedInk)
            }
        }
        .navigationTitle("品牌库")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "名称 / 拼音 / 首字母")
    }

    private var visibleCategories: [DrinkCategory] {
        if let filterCategory { return [filterCategory] }
        return DrinkCategory.allCases
    }

    private var searchResults: [BrandItem] {
        let results = BrandLibrary.search(query, preferredCategory: filterCategory ?? initialCategory, limit: 80)
        guard let filterCategory else { return results }
        return results.filter { $0.category == filterCategory }
    }

    private func row(_ item: BrandItem) -> some View {
        Button {
            onPick(item)
            dismiss()
        } label: {
            BrandResultRow(item: item, highlightCategory: filterCategory == nil)
        }
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? DesignSystem.heartRateLine.opacity(0.15) : DesignSystem.chartSurface)
                .overlay(Capsule().stroke(selected ? DesignSystem.heartRateLine : DesignSystem.gridline))
                .clipShape(Capsule())
        }
        .buttonStyle(.borderless)
    }
}
