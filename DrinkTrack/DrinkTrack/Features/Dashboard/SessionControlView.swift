import SwiftUI

/// FR-DASH-04：会话开始/结束控制。也提供 FR-DR-06 一键开始：一次点击创建会话并写入第一条记录。
struct SessionControlView: View {
    @ObservedObject var drinkRepository: DrinkRepository
    @Binding var activeSession: DrinkSessionEntity?
    @Binding var showQuickLog: Bool
    var latestHeartRate: Double?
    var latestSpO2: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let session = activeSession {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("进行中的饮酒会话")
                                .font(.caption)
                                .foregroundStyle(DesignSystem.mutedInk)
                            if let startedAt = session.startedAt {
                                Text(startedAt, style: .relative).font(.headline).foregroundStyle(DesignSystem.primaryInk) + Text(" 前开始").foregroundStyle(DesignSystem.primaryInk)
                            }
                        }
                        Spacer(minLength: 8)
                    }
                    HStack(spacing: 10) {
                        Button("+ 添加记录") { showQuickLog = true }
                            .buttonStyle(SipOutlineButtonStyle())
                        Button("结束会话") {
                            drinkRepository.endSession(session)
                            activeSession = nil
                        }
                        .buttonStyle(SipPrimaryButtonStyle())
                    }
                    activeSessionMetrics(session)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前没有进行中的会话")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(DesignSystem.primaryInk)
                    Text("一键开始将按上次的\(UserPreferences.oneTapPresetLabel)记入，之后还能改。")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button("开始新会话") {
                        activeSession = drinkRepository.startNewSession()
                    }
                    .buttonStyle(SipOutlineButtonStyle())

                    Button {
                        activeSession = drinkRepository.startSessionWithQuickLog()
                    } label: {
                        VStack(spacing: 1) {
                            Text("一键开始")
                            Text(UserPreferences.oneTapPresetLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
                    .buttonStyle(SipPrimaryButtonStyle())
                    .accessibilityIdentifier("one-tap-start")
                }
            }
        }
        .sipCard()
    }

    private func activeSessionMetrics(_ session: DrinkSessionEntity) -> some View {
        let logs = Array((session.logs as? Set<DrinkLogEntity>) ?? [])
        let volume = logs.reduce(0.0) { $0 + $1.volumeMl }
        let standard = logs.reduce(0.0) { $0 + $1.standardDrinks }
        let started = session.startedAt ?? Date()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                metric(icon: "clock.fill", title: "已进行", valueView: Text(started, style: .timer))
                metric(icon: "wineglass.fill", title: "本场杯数", valueView: Text("\(logs.count)"))
                metric(icon: "drop.fill", title: "本场容量", valueView: Text(volume == 0 ? "—" : "\(Int(volume.rounded())) ml"))
                metric(icon: "equal.circle.fill", title: "标准饮品", valueView: Text(volume == 0 ? "—" : String(format: "≈%.1f", standard)))
            }
            if latestHeartRate != nil || latestSpO2 != nil {
                HStack(spacing: 10) {
                    if let bpm = latestHeartRate {
                        metric(icon: "heart.fill", title: "本场心率", valueView: Text("\(Int(bpm.rounded()))"))
                    }
                    if let spo2 = latestSpO2 {
                        metric(icon: "lungs.fill", title: "本场血氧", valueView: Text(String(format: "%.0f%%", spo2)))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func metric<V: View>(icon: String, title: String, valueView: V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.burgundy)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.mutedInk)
            }
            valueView
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.primaryInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
