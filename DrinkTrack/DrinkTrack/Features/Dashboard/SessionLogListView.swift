import SwiftUI
import CoreData

/// 当前会话的饮酒记录列表。
///
/// 修复的 bug：之前录入的饮酒记录**在界面上完全看不到**——
/// 仪表盘只把记录当成 🍷 标记画在心率曲线上，而没有手表数据时图表走占位分支，
/// 标记根本不会渲染；「趋势」页又只查已归档的会话，进行中会话里的记录被过滤掉了。
/// 结果就是：录入成功了，但用户哪里都看不见。
///
/// 这里用 @FetchRequest 直接绑定 Core Data，录入后会自动刷新——
/// 这也顺带修了第三个问题：原先 activeSession 是 @State 持有的托管对象，
/// 往它的 logs 关系里插数据不会触发 SwiftUI 重绘。
struct SessionLogListView: View {
    @FetchRequest private var logs: FetchedResults<DrinkLogEntity>
    private let sessionIsActive: Bool
    var onDelete: ((DrinkLogEntity) -> Void)?

    init(session: DrinkSessionEntity?, sessionIsActive: Bool = true, onDelete: ((DrinkLogEntity) -> Void)? = nil) {
        self.sessionIsActive = sessionIsActive
        self.onDelete = onDelete
        let request = NSFetchRequest<DrinkLogEntity>(entityName: "DrinkLog")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DrinkLogEntity.timestamp, ascending: false)]
        if let session {
            request.predicate = NSPredicate(format: "session == %@", session)
        } else {
            // 没有进行中的会话时不显示任何记录（而不是显示全部）
            request.predicate = NSPredicate(value: false)
        }
        _logs = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本次记录").font(.headline)
                Spacer()
                if !logs.isEmpty {
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.secondaryInk)
                }
            }

            if logs.isEmpty {
                Text(sessionIsActive ? "还没有记录。点上方「+ 添加记录」记下你喝的第一杯。" : "这次会话没有记录任何饮品。")
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(logs, id: \.objectID) { log in
                    DrinkLogRow(log: log)
                    if log.objectID != logs.last?.objectID {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var summaryText: String {
        let totalML = logs.reduce(0.0) { $0 + $1.volumeMl }
        let totalStandard = logs.reduce(0.0) { $0 + $1.standardDrinks }
        return String(format: "共 %d 杯 · %.0f ml · ≈%.1f 标准饮品", logs.count, totalML, totalStandard)
    }
}

struct DrinkLogRow: View {
    @ObservedObject var log: DrinkLogEntity

    var body: some View {
        HStack(spacing: 12) {
            Text(category?.emoji ?? "🍹")
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category?.displayName ?? "其他")
                        .font(.subheadline.weight(.medium))
                    if let brand = log.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.secondaryInk)
                    }
                }
                if let note = log.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.mutedInk)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(log.volumeMl)) ml")
                    .font(.subheadline)
                    .monospacedDigit()
                if log.standardDrinks > 0 {
                    Text(String(format: "≈%.1f 标准饮品", log.standardDrinks))
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.mutedInk)
                }
                if let timestamp = log.timestamp {
                    Text(timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.mutedInk)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var category: DrinkCategory? {
        guard let raw = log.category else { return nil }
        return DrinkCategory(rawValue: raw)
    }
}
