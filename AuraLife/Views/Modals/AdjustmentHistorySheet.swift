import SwiftData
import SwiftUI

struct AdjustmentHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ChatAdjustmentLog.timestamp, order: .reverse) private var logs: [ChatAdjustmentLog]

    var body: some View {
        NavigationStack {
            Group {
                if logs.isEmpty {
                    ContentUnavailableView(
                        "暂无动态微调记录",
                        systemImage: "sparkles",
                        description: Text("在首页底部输入状态，或右滑卡片「换一换」后，调整记录会保存在这里。")
                    )
                } else {
                    List(logs) { log in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(log.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(AuraTheme.secondaryText)

                                Spacer()

                                Text(log.wasApplied ? "已应用" : "未应用")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(log.wasApplied ? AuraTheme.sageGreen : AuraTheme.secondaryText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        (log.wasApplied ? AuraTheme.sageGreen : AuraTheme.secondaryText).opacity(0.13),
                                        in: Capsule()
                                    )
                            }

                            Text("「\(log.userInput)」")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AuraTheme.primaryText)

                            Text(log.aiSummary)
                                .font(.caption)
                                .foregroundStyle(AuraTheme.secondaryText)

                            if !log.affectedCardTitles.isEmpty {
                                Text("涉及卡片：\(log.affectedCardTitles.joined(separator: "、"))")
                                    .font(.caption2)
                                    .foregroundStyle(AuraTheme.warmGinger)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(AuraTheme.cardSurface)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("动态调整记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(AuraTheme.sageGreen)
                }
            }
        }
    }
}

#Preview {
    let container = PreviewSupport.makeContainer()
    return AdjustmentHistorySheet()
        .modelContainer(container)
}
