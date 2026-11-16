import SwiftUI

/// Wrist UI for 小酌场: current session, a one-tap log, and start/end.
/// Heart rate and SpO2 are shown only when the phone has sent a real
/// in-session reading. Nothing is invented on the Watch.
struct WatchRootView: View {
    @EnvironmentObject private var store: WatchSessionStore
    @State private var showPresets = false

    private let accent = Color(red: 168 / 255, green: 42 / 255, blue: 36 / 255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if store.snapshot.isSessionActive {
                        sessionMetrics
                        logButtons
                        Button("结束本场") { store.endSession() }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(store.isSending)
                    } else {
                        Text("当前没有进行中的会话")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("开始本场") { store.startSession() }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            .disabled(store.isSending)
                        Button("一键开始 · \(store.snapshot.presetLabel)") {
                            store.startWithQuickLog()
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isSending)
                    }

                    if let confirmation = store.confirmation {
                        Text(confirmation)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(accent)
                    }

                    Text(store.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("小酌场")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPresets) {
                presetSheet
            }
        }
        .tint(accent)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text("小酌场")
                    .font(.headline)
                Text("SipSession")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(store.isReachable ? Color.green : Color.yellow)
                .frame(width: 8, height: 8)
                .accessibilityLabel(store.isReachable ? "手机已连接" : "手机未连接")
        }
    }

    private var sessionMetrics: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("进行中")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let startedAt = store.snapshot.startedAt {
                Text(startedAt, style: .timer)
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
            metricRow(title: "杯数", value: "\(store.snapshot.cupCount)")
            metricRow(
                title: "容量",
                value: store.snapshot.volumeML == 0 ? "—" : "\(Int(store.snapshot.volumeML.rounded())) ml"
            )
            metricRow(
                title: "标准饮品",
                value: store.snapshot.volumeML == 0 ? "—" : String(format: "≈%.1f", store.snapshot.standardDrinks)
            )
            if let bpm = store.snapshot.latestHeartRate {
                metricRow(title: "本场心率", value: "\(Int(bpm.rounded()))")
            }
            if let spo2 = store.snapshot.latestSpO2 {
                metricRow(title: "本场血氧", value: String(format: "%.0f%%", spo2))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.footnote)
    }

    private var logButtons: some View {
        VStack(spacing: 6) {
            Button("记一杯 · \(store.snapshot.presetLabel)") {
                store.logLastPreset()
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(store.isSending)

            Button("换一种") { showPresets = true }
                .buttonStyle(.bordered)
                .disabled(store.isSending)
        }
    }

    private var presetSheet: some View {
        NavigationStack {
            List(WatchDrinkPreset.allCases) { preset in
                Button {
                    store.log(preset: preset)
                    showPresets = false
                } label: {
                    HStack {
                        Text(preset.displayName)
                        Spacer()
                        Text("\(Int(preset.defaultVolumeML))ml")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("记一杯")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showPresets = false }
                }
            }
        }
    }
}
