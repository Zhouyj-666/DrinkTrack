import SwiftUI

/// FR-DR-04：剂量输入，支持① 直接输入 ml 数值（0-5000）② 杯数 × 单杯容量（预设常见杯型）。
struct VolumeInputView: View {
    let category: DrinkCategory
    @Binding var volumeML: Double

    @State private var mode: Mode = .cups
    @State private var cupCount: Int = 1
    @State private var selectedCupIndex: Int = 0

    enum Mode: String, CaseIterable { case cups = "按杯数", direct = "直接输入 ml" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("输入方式", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .cups:
                if category.presetVolumesML.isEmpty {
                    Text("「其他」类目请直接输入 ml").font(.caption).foregroundStyle(DesignSystem.mutedInk)
                } else {
                    Picker("杯型", selection: $selectedCupIndex) {
                        ForEach(category.presetVolumesML.indices, id: \.self) { i in
                            Text(category.presetVolumesML[i].label).tag(i)
                        }
                    }
                    Stepper("杯数：\(cupCount)", value: $cupCount, in: 1...20)
                    Text("合计 \(Int(totalFromCups)) ml").font(.footnote).foregroundStyle(DesignSystem.secondaryInk)
                }
            case .direct:
                HStack {
                    Slider(value: $volumeML, in: 0...2000, step: 10)
                    TextField("ml", value: $volumeML, format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .onAppear { syncVolume() }
        .onChange(of: cupCount) { _ in syncVolume() }
        .onChange(of: selectedCupIndex) { _ in syncVolume() }
        .onChange(of: mode) { _ in syncVolume() }
    }

    private var totalFromCups: Double {
        guard !category.presetVolumesML.isEmpty, selectedCupIndex < category.presetVolumesML.count else { return 0 }
        return category.presetVolumesML[selectedCupIndex].ml * Double(cupCount)
    }

    private func syncVolume() {
        if mode == .cups, !category.presetVolumesML.isEmpty {
            volumeML = totalFromCups
        }
    }
}
