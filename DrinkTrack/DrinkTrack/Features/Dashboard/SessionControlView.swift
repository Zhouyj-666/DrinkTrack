import SwiftUI

/// FR-DASH-04：会话开始/结束控制。也提供 FR-DR-06 一键开始：一次点击创建会话并写入第一条记录。
struct SessionControlView: View {
    @ObservedObject var drinkRepository: DrinkRepository
    @Binding var activeSession: DrinkSessionEntity?
    @Binding var showQuickLog: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let session = activeSession {
                HStack {
                    VStack(alignment: .leading) {
                        Text("进行中的饮酒会话").font(.caption).foregroundStyle(DesignSystem.secondaryInk)
                        if let startedAt = session.startedAt {
                            Text(startedAt, style: .relative).font(.headline) + Text(" 前开始")
                        }
                    }
                    Spacer()
                    Button("+ 添加记录") { showQuickLog = true }
                        .buttonStyle(.bordered)
                    Button("结束会话") {
                        drinkRepository.endSession(session)
                        activeSession = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.statusCritical)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前没有进行中的会话")
                        .foregroundStyle(DesignSystem.secondaryInk)
                    Text("一键开始会按上次的种类和杯型直接记第一杯，之后还可以改。")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.mutedInk)
                }
                HStack(spacing: 10) {
                    Button("开始新会话") {
                        activeSession = drinkRepository.startNewSession()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        activeSession = drinkRepository.startSessionWithQuickLog()
                    } label: {
                        VStack(spacing: 2) {
                            Text("一键开始")
                            Text(UserPreferences.oneTapPresetLabel)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("one-tap-start")
                }
            }
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
