import SwiftUI

/// 健康数据连接状态展示（FR-HK-06）。
///
/// 设计原则：**如实告诉用户 App 到底知道什么**。
/// HealthKit 不允许 App 查询读取权限是否被授予，所以「读不到数据」有两种可能：
/// ① 用户在授权弹窗里拒绝了；② 确实没有数据（没戴手表、新手表、模拟器）。
/// App 分不清这两种，就不能显示一个笃定的「已连接」或「未授权」——
/// 必须把歧义摊开讲，并告诉用户怎么自查。
struct HealthConnectionStatusView: View {
    let state: HealthConnectionState
    var onRequestAuthorization: (() -> Void)?
    var onRefresh: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if case .connected = state {
                    Button {
                        onRefresh?()
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                }
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(DesignSystem.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if let action = primaryAction {
                Button(action.title) {
                    switch action.kind {
                    case .request: onRequestAuthorization?()
                    case .refresh: onRefresh?()
                    }
                }
                .font(.footnote)
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var icon: String {
        switch state {
        case .connected: return "heart.fill"
        case .requestedButNoData: return "questionmark.circle.fill"
        case .notRequested: return "heart.slash"
        case .unavailable: return "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .connected: return DesignSystem.statusGood
        case .requestedButNoData: return DesignSystem.statusWarning
        case .notRequested: return DesignSystem.mutedInk
        case .unavailable: return DesignSystem.statusCritical
        }
    }

    private var title: String {
        switch state {
        case .connected: return "已连接 Apple 健康"
        case .requestedButNoData: return "读不到健康数据"
        case .notRequested: return "尚未连接 Apple 健康"
        case .unavailable: return "此设备不支持健康数据"
        }
    }

    private var detail: String {
        switch state {
        case .connected(let lastSampleAt):
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            let rel = formatter.localizedString(for: lastSampleAt, relativeTo: Date())
            return "最近一条心率数据：\(rel)。数据来自 Apple 健康，由 Apple Watch 采集。"
        case .requestedButNoData:
            // 这段文案是本页最重要的部分：把 App 真正的认知边界讲清楚
            return """
            已经向你请求过授权，但最近 7 天里一条心率数据都没读到。可能是：
            ① 授权时没有勾选「心率」等项目；
            ② Apple Watch 最近没有佩戴过。

            自查：打开「健康」App → 右上角头像 → 隐私 →「App」→ DrinkTrack，\
            确认心率、血氧、心率变异性、睡眠都是打开的。
            """
        case .notRequested:
            return "连接后可以在饮酒时看到实时心率和血氧变化。我们只读取数据，不会修改或删除你的健康记录。"
        case .unavailable:
            return "健康数据需要 iPhone（iPad 和部分模拟器不支持 HealthKit）。你仍然可以手动记录饮酒。"
        }
    }

    private struct ActionSpec {
        enum Kind { case request, refresh }
        let title: String
        let kind: Kind
    }

    private var primaryAction: ActionSpec? {
        switch state {
        case .notRequested: return ActionSpec(title: "连接 Apple 健康", kind: .request)
        case .requestedButNoData: return ActionSpec(title: "重新检测", kind: .refresh)
        case .connected, .unavailable: return nil
        }
    }
}
