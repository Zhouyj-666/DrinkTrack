import SwiftUI

/// 功能介绍页：在要任何个人信息之前，先让用户知道这是个什么 App。
///
/// 这一页是试用反馈直接催生的——原来的流程一上来就让人填体重、安静心率，
/// 但用户此时还不知道这些数据是干什么用的，体验上像在填表而不是在用产品。
struct AppIntroView: View {
    let onFinished: () -> Void

    private struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let tint: Color
    }

    private var features: [Feature] {
        [
            Feature(
                icon: "wineglass.fill",
                title: "记录你喝了什么",
                detail: "选酒种、填杯数，自动换算成标准饮品数，8 种常见酒类都有预设杯型。",
                tint: DesignSystem.categorical[1]
            ),
            Feature(
                icon: "waveform.path.ecg",
                title: "看身体正在发生什么",
                detail: "连上 Apple 健康后，饮酒时的心率、血氧变化会实时画在同一条时间轴上。",
                tint: DesignSystem.heartRateLine
            ),
            Feature(
                icon: "chart.xyaxis.line",
                title: "发现长期规律",
                detail: "饮酒日和非饮酒日的心率、HRV、睡眠对比，做你自己的量化实验。",
                tint: DesignSystem.categorical[2]
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DrinkTrack")
                            .font(.largeTitle.bold())
                        Text("把每一次喝酒，变成一次可以回看的身体记录。")
                            .font(.subheadline)
                            .foregroundStyle(DesignSystem.secondaryInk)
                    }
                    .padding(.top, 32)

                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(features) { feature in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: feature.icon)
                                    .font(.title2)
                                    .foregroundStyle(feature.tint)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(feature.title)
                                        .font(.headline)
                                    Text(feature.detail)
                                        .font(.footnote)
                                        .foregroundStyle(DesignSystem.secondaryInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    // 明确告诉用户后面还需要什么，但不在这里就要
                    VStack(alignment: .leading, spacing: 6) {
                        Label("随时可选，不填也能用", systemImage: "info.circle")
                            .font(.footnote.weight(.medium))
                        Text("连接 Apple 健康、填写身高体重等基础信息，都可以之后在「我的」页里完成。基础信息只用来让会话提示更贴合你本人，不会分享给任何人。")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignSystem.chartSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }

            Divider()

            Button {
                onFinished()
            } label: {
                Text("开始使用").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
        .navigationBarBackButtonHidden(true)
    }
}
