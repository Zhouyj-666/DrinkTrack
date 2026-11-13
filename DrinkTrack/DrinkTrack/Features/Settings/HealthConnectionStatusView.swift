import SwiftUI

/// 健康数据连接状态展示（FR-HK-06）。
///
/// 设计原则：**如实告诉用户 App 到底知道什么**，并且每一次点击都不能没有反馈。
/// HealthKit 不允许 App 查询读取权限是否被授予，所以「读不到数据」有两种可能：
/// 用户拒绝了授权，或确实没有数据（没戴表 / 新手表 / 模拟器）。
/// App 分不清这两种，就不能显示一个笃定的「已连接」或「未授权」——
/// 必须把歧义摊开讲，并告诉用户怎么自查。
///
/// 真机侧载（Sideloadly + 个人/免费 Apple ID）时，重签经常会丢掉 HealthKit 权限。
/// 这时系统授权窗根本不会出现，`requestAuthorization` 会直接失败。以前失败信息
/// 只写进了 `authorizationError` 却没有画在界面上，所以用户会觉得「点了没反应」。
struct HealthConnectionStatusView: View {
    let state: HealthConnectionState
    var authorizationError: String? = nil
    var isRequesting: Bool = false
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
                if isRequesting {
                    ProgressView()
                        .controlSize(.small)
                } else if case .connected = state {
                    Button {
                        onRefresh?()
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("重新检测健康连接")
                }
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(DesignSystem.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if let authorizationError, !authorizationError.isEmpty {
                Text(authorizationError)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("health-authorization-error")
            }

            if let action = primaryAction {
                Button {
                    perform(action)
                } label: {
                    HStack(spacing: 8) {
                        if isRequesting { ProgressView().controlSize(.small) }
                        Text(isRequesting ? "正在请求授权…" : action.title)
                    }
                    .frame(maxWidth: .infinity)
                }
                .font(.footnote)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isRequesting || action.unavailable)
                .contentShape(Rectangle())
                .accessibilityIdentifier("health-connect-button")
            }

            if state == .requestedButNoData {
                Button("重新检测") {
                    onRefresh?()
                }
                .font(.footnote)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(isRequesting)
            }

            if showsOpenHealthButton {
                Button("打开健康 App 检查权限") {
                    openHealthApp()
                }
                .font(.footnote)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func perform(_ action: ActionSpec) {
        switch action.kind {
        case .request:
            if let onRequestAuthorization {
                onRequestAuthorization()
            }
        case .refresh:
            if let onRefresh {
                onRefresh()
            }
        }
    }

    private func openHealthApp() {
        // Prefer the Health app; fall back to this app's system settings page.
        let candidates = [
            URL(string: "x-apple-health://"),
            URL(string: UIApplication.openSettingsURLString)
        ].compactMap { $0 }
        for url in candidates where UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }
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
        if isRequesting { return "正在连接 Apple 健康" }
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
            return """
            已经向系统请求过授权，但最近 7 天里一条心率数据都没读到。可能是：
            · 授权时没有勾选心率、血氧等项目
            · Apple Watch 还没戴上或还没有数据
            · 当前安装方式没有带上「健康」权限（常见于侧载重签）

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
        var unavailable: Bool = false
    }

    private var primaryAction: ActionSpec? {
        if isRequesting {
            return ActionSpec(title: "正在请求授权…", kind: .request, unavailable: true)
        }
        switch state {
        case .notRequested:
            return ActionSpec(title: "连接 Apple 健康", kind: .request)
        case .requestedButNoData:
            // Offer another authorization request (the system sheet only appears
            // if the status is still "not determined") plus a refresh path via
            // the secondary button in the header. The main button retries
            // authorization so a previous silent failure can surface an error.
            return ActionSpec(title: "重新连接 / 再次请求授权", kind: .request)
        case .connected, .unavailable:
            return nil
        }
    }

    private var showsOpenHealthButton: Bool {
        switch state {
        case .requestedButNoData: return true
        case .notRequested, .connected, .unavailable: return authorizationError != nil
        }
    }
}
