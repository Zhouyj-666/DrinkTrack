import SwiftUI

/// FR-DR-02：酒种类选择，横向滑动选择（8 种预设）。
struct DrinkCategoryPicker: View {
    @Binding var selection: DrinkCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DrinkCategory.allCases) { category in
                    VStack {
                        Text(category.emoji).font(.system(size: 28))
                        Text(category.displayName).font(.caption)
                    }
                    .padding(10)
                    .background(
                        selection == category
                            ? DesignSystem.color(for: category).opacity(0.18)
                            : DesignSystem.chartSurface
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selection == category ? DesignSystem.color(for: category) : DesignSystem.gridline, lineWidth: selection == category ? 2 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { selection = category }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
