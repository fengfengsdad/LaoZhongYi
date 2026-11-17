import SwiftData
import SwiftUI

struct AdjustmentDiffSheet: View {
    let proposal: AdjustmentProposal
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(AuraTheme.warmGinger)
                            Text("AI 为你调整了 \(proposal.diffs.count) 项计划")
                                .font(.headline)
                                .foregroundStyle(AuraTheme.primaryText)

                            Spacer()

                            Text(proposal.source.rawValue)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(AuraTheme.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AuraTheme.subtleSurface, in: Capsule())
                        }

                        Text("「\(proposal.userInput)」")
                            .font(.subheadline)
                            .foregroundStyle(AuraTheme.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        HStack(spacing: 6) {
                            Text("判定阶段：")
                                .font(.caption)
                                .foregroundStyle(AuraTheme.secondaryText)
                            Text(proposal.proposedPhase)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AuraTheme.warmGinger)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AuraTheme.warmGinger.opacity(0.14), in: Capsule())
                        }

                        Text(proposal.summary)
                            .font(.footnote)
                            .foregroundStyle(AuraTheme.secondaryText)
                    }
                    .padding(16)
                    .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AuraTheme.hairline, lineWidth: 1)
                    )

                    ForEach(proposal.diffs) { diff in
                        diffCard(diff)
                    }
                }
                .padding(16)
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("动态微调确认")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("暂不修改", action: onCancel)
                        .foregroundStyle(AuraTheme.secondaryText)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    HapticFeedback.notify(.success)
                    onApply()
                } label: {
                    Text("应用调整并刷新时间轴")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AuraTheme.sageGreen, in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(AuraTheme.canvasBackground.opacity(0.95))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func diffCard(_ diff: CardAdjustmentDiff) -> some View {
        let accent = AuraTheme.accent(for: diff.category)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(diff.dayLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AuraTheme.primaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AuraTheme.subtleSurface, in: Capsule())

                Label(diff.category.displayName, systemImage: diff.category.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.12), in: Capsule())

                Text(diff.timeSlot)
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)

                Spacer()
            }

            if let previousTitle = diff.previousTitle {
                HStack(spacing: 6) {
                    Text("原计划")
                        .font(.caption2)
                        .foregroundStyle(AuraTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AuraTheme.subtleSurface, in: Capsule())

                    Text(previousTitle)
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundStyle(AuraTheme.secondaryText)
                }
            }

            HStack(alignment: .top, spacing: 6) {
                Text(diff.previousTitle == nil ? "新增安排" : "调整为")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AuraTheme.sageGreen, in: Capsule())

                Text(diff.updatedTitle)
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)
            }

            Text(diff.updatedDetail)
                .font(.subheadline)
                .foregroundStyle(AuraTheme.secondaryText)

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(accent)
                Text(diff.updatedReasoning)
                    .font(.caption)
                    .foregroundStyle(AuraTheme.primaryText.opacity(0.85))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(14)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AuraTheme.hairline, lineWidth: 1)
        )
    }
}

#Preview {
    let container = PreviewSupport.makeContainer()
    let snapshots = (try? container.mainContext.fetch(FetchDescriptor<DailyContextSnapshot>())) ?? []
    let profiles = (try? container.mainContext.fetch(FetchDescriptor<UserConstitutionProfile>())) ?? []
    let proposal = LocalContextPlanner.proposeAdjustment(
        input: "昨晚熬夜吃了螃蟹、大便发黏",
        hasAttachedImage: false,
        profile: profiles.first,
        snapshot: snapshots.first!
    )

    return AdjustmentDiffSheet(
        proposal: proposal,
        onApply: {},
        onCancel: {}
    )
}
