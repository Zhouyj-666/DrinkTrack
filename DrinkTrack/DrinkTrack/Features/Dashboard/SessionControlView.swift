import SwiftUI

/// FR-DASH-04：会话开始/结束控制。
struct SessionControlView: View {
    @ObservedObject var drinkRepository: DrinkRepository
    @Binding var activeSession: DrinkSessionEntity?
    @Binding var showQuickLog: Bool

    var body: some View {
        HStack {
            if let session = activeSession {
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
            } else {
                Text("当前没有进行中的会话").foregroundStyle(DesignSystem.secondaryInk)
                Spacer()
                Button("开始新会话") {
                    activeSession = drinkRepository.startNewSession()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
