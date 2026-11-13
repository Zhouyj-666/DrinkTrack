import SwiftUI

/// 可直接用键盘输入的数值输入框，同时保留 +/- 微调按钮。
///
/// 试用反馈：原来的身体数据全用 `Stepper`，改体重要一下一下点几十次。
/// 现在主输入方式是键盘，步进按钮只作为微调补充。
struct NumericField: View {
    let title: String
    let unit: String
    let range: ClosedRange<Int>
    @Binding var value: Int
    /// 为空时表示「未填写」，用于区分"没填"和"填了个默认值"
    var placeholder: String = "未填写"

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()

            TextField(placeholder, text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .frame(maxWidth: 90)
                .onChange(of: text) { _, newValue in
                    // 只保留数字，防止粘贴进非法字符
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue { text = digits }
                    if let parsed = Int(digits) { value = parsed }
                }
                .onChange(of: isFocused) { _, focused in
                    // 失焦时才做范围钳制：输入过程中不打断用户
                    // （否则输入 "7" 想打 "70" 时会被立刻纠正成最小值）
                    if !focused { clampAndSync() }
                }

            Text(unit)
                .foregroundStyle(DesignSystem.secondaryInk)

            Stepper("") {
                value = min(value + 1, range.upperBound)
                text = String(value)
            } onDecrement: {
                value = max(value - 1, range.lowerBound)
                text = String(value)
            }
            .labelsHidden()
        }
        .onAppear { text = value > 0 ? String(value) : "" }
    }

    private func clampAndSync() {
        guard let parsed = Int(text), !text.isEmpty else {
            text = value > 0 ? String(value) : ""
            return
        }
        value = min(max(parsed, range.lowerBound), range.upperBound)
        text = String(value)
    }
}
