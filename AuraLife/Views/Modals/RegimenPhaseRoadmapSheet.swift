import SwiftData
import SwiftUI

struct RegimenPhaseRoadmapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RegimenPhase.startDate, order: .reverse) private var phases: [RegimenPhase]

    let currentPhase: RegimenPhase?
    let referenceDate: Date

    private var activePhase: RegimenPhase? {
        currentPhase ?? phases.first(where: { $0.status == .active }) ?? phases.first
    }

    private var archivedPhases: [RegimenPhase] {
        guard let activeID = activePhase?.id else { return phases }
        return phases.filter { $0.id != activeID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let active = activePhase {
                        activePhaseCard(active)
                        fourStageRoadmapCard(activeStage: active.stageKind)
                    } else {
                        ContentUnavailableView(
                            "暂无调理分期",
                            systemImage: "leaf.arrow.circlepath",
                            description: Text("发起状态打卡或生成 3 日计划后，会自动建立中医分期与治法总则。")
                        )
                    }

                    if !archivedPhases.isEmpty {
                        archivedHistoryCard
                    }
                }
                .padding(16)
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("中医分期与治法路线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AuraTheme.sageGreen)
                }
            }
        }
    }

    private func activePhaseCard(_ phase: RegimenPhase) -> some View {
        let accent = phase.stageKind.accentColor

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(phase.stageKind.displayName, systemImage: phase.stageKind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.14), in: Capsule())

                Text(phase.stageKind.clinicalAxiom)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AuraTheme.secondaryText)

                Spacer()

                Text(phase.progressText(for: referenceDate))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent)
            }

            Text(phase.phaseName)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(AuraTheme.primaryText)

            ProgressView(value: phase.progressFraction(for: referenceDate))
                .tint(accent)

            VStack(alignment: .leading, spacing: 8) {
                infoBlock(title: "治法总则", content: phase.therapeuticPrinciple, tint: accent)
                infoBlock(title: "转段标准", content: phase.exitCriteria, tint: AuraTheme.sageGreen)
                infoBlock(title: "下一阶段", content: phase.nextStageHint, tint: AuraTheme.inkSlate)
            }

            Text("开启缘由：\(phase.triggerSummary)（起始于 \(phase.startDate.formatted(date: .abbreviated, time: .omitted))）")
                .font(.caption2)
                .foregroundStyle(AuraTheme.secondaryText)
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.32), lineWidth: 1)
        )
    }

    private func infoBlock(title: String, content: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(tint.opacity(0.13), in: Capsule())

            Text(content)
                .font(.caption)
                .foregroundStyle(AuraTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fourStageRoadmapCard(activeStage: RegimenStageKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("临床四阶段演进路径")
                .font(.headline)
                .foregroundStyle(AuraTheme.primaryText)

            VStack(spacing: 0) {
                ForEach(Array(RegimenStageKind.allCases.enumerated()), id: \.element) { index, stage in
                    let isCurrent = stage == activeStage
                    let isLast = index == RegimenStageKind.allCases.count - 1

                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(isCurrent ? stage.accentColor : AuraTheme.subtleSurface)
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle()
                                        .stroke(isCurrent ? stage.accentColor : AuraTheme.hairline, lineWidth: 1.5)
                                )
                                .padding(.top, 3)

                            if !isLast {
                                Rectangle()
                                    .fill(AuraTheme.hairline)
                                    .frame(width: 1.5, height: 34)
                                    .padding(.vertical, 3)
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(stage.displayName)
                                    .font(.subheadline.weight(isCurrent ? .semibold : .medium))
                                    .foregroundStyle(isCurrent ? AuraTheme.primaryText : AuraTheme.secondaryText)

                                Text("· \(stage.clinicalAxiom)")
                                    .font(.caption2)
                                    .foregroundStyle(isCurrent ? stage.accentColor : AuraTheme.secondaryText.opacity(0.8))

                                if isCurrent {
                                    Text("当前")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(stage.accentColor, in: Capsule())
                                }
                            }

                            Text(stage.defaultSummary)
                                .font(.caption)
                                .foregroundStyle(AuraTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, isLast ? 0 : 10)
                    }
                }
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AuraTheme.hairline, lineWidth: 1)
        )
    }

    private var archivedHistoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("历史阶段记录")
                .font(.headline)
                .foregroundStyle(AuraTheme.primaryText)

            ForEach(archivedPhases) { phase in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: phase.stageKind.systemImage)
                        .font(.caption)
                        .foregroundStyle(phase.stageKind.accentColor)
                        .frame(width: 24, height: 24)
                        .background(phase.stageKind.accentColor.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(phase.phaseName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AuraTheme.primaryText)
                            Spacer()
                            Text(phase.status.displayName)
                                .font(.caption2)
                                .foregroundStyle(AuraTheme.secondaryText)
                        }

                        Text("治则：\(phase.therapeuticPrinciple)")
                            .font(.caption)
                            .foregroundStyle(AuraTheme.secondaryText)

                        Text(phase.startDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(AuraTheme.secondaryText.opacity(0.8))
                    }
                }
                .padding(10)
                .background(AuraTheme.subtleSurface.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AuraTheme.hairline, lineWidth: 1)
        )
    }
}

#Preview {
    let container = PreviewSupport.makeContainer()
    let phases = (try? container.mainContext.fetch(FetchDescriptor<RegimenPhase>())) ?? []
    return RegimenPhaseRoadmapSheet(currentPhase: phases.first, referenceDate: .now)
        .modelContainer(container)
}
