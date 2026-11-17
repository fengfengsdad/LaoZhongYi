import SwiftData
import SwiftUI

struct AdjustmentHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ConstitutionEvolutionRecord.date, order: .reverse) private var evolutionRecords: [ConstitutionEvolutionRecord]
    @Query(sort: \ChatAdjustmentLog.timestamp, order: .reverse) private var logs: [ChatAdjustmentLog]

    @State private var selectedTab: HistoryTab = .caseArchive

    private enum HistoryTab: String, CaseIterable, Identifiable {
        case caseArchive = "调理医案"
        case adjustmentLogs = "微调流水"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("档案视图", selection: $selectedTab) {
                    ForEach(HistoryTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Group {
                    switch selectedTab {
                    case .caseArchive:
                        caseArchiveContent
                    case .adjustmentLogs:
                        adjustmentLogsContent
                    }
                }
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("调理医案档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(AuraTheme.sageGreen)
                }
            }
        }
    }

    @ViewBuilder
    private var caseArchiveContent: some View {
        if evolutionRecords.isEmpty {
            ContentUnavailableView(
                "暂无调理医案",
                systemImage: "book.pages",
                description: Text("每次完成阶段复诊转段后，证型演变、治法总则与耐受反馈会按周期沉淀在这里。")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(evolutionRecords) { record in
                        caseRecordCard(record)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    private func caseRecordCard(_ record: ConstitutionEvolutionRecord) -> some View {
        let accent = record.stageKind.accentColor

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(record.phaseName, systemImage: record.stageKind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.13), in: Capsule())

                Text(record.outcomeTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AuraTheme.secondaryText)

                Spacer()

                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(AuraTheme.secondaryText)
            }

            Text(record.clinicalNote)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AuraTheme.primaryText)

            Text("治则：\(record.therapeuticPrinciple)")
                .font(.caption)
                .foregroundStyle(accent)

            if !record.constitutionSnapshotTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(record.constitutionSnapshotTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(AuraTheme.primaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AuraTheme.subtleSurface, in: Capsule())
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("演化：\(record.deltaSummary)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AuraTheme.sageGreen)

                Text("耐受：\(record.toleranceNote)")
                    .font(.caption2)
                    .foregroundStyle(AuraTheme.secondaryText)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AuraTheme.subtleSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(14)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AuraTheme.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var adjustmentLogsContent: some View {
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
}

#Preview {
    let container = PreviewSupport.makeContainer()
    return AdjustmentHistorySheet()
        .modelContainer(container)
}
