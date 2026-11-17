import SwiftData
import SwiftUI

struct PhaseFollowUpSheet: View {
    @Environment(\.dismiss) private var dismiss

    let currentPhase: RegimenPhase
    let snapshot: DailyContextSnapshot
    let profile: UserConstitutionProfile?
    let onApplyTransition: (FollowUpOutcome, String, AIPhaseTransitionResponse, AIServiceSource) -> Void

    @State private var selectedOutcome: FollowUpOutcome = .improved
    @State private var userNote: String = ""
    @State private var isEvaluating: Bool = false
    @State private var progressStatus: String?
    @State private var errorMessage: String?
    @State private var evaluationResult: (response: AIPhaseTransitionResponse, source: AIServiceSource)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    currentPhaseSummaryCard

                    if let result = evaluationResult {
                        transitionPreviewSection(result.response, source: result.source)
                    } else {
                        outcomeSelectionSection
                        noteInputSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle(evaluationResult == nil ? "阶段复诊评估" : "复诊转段方案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if evaluationResult != nil {
                        Button("重选") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                evaluationResult = nil
                            }
                        }
                        .foregroundStyle(AuraTheme.secondaryText)
                    } else {
                        Button("取消") { dismiss() }
                            .foregroundStyle(AuraTheme.secondaryText)
                            .disabled(isEvaluating)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let result = evaluationResult {
                    Button {
                        HapticFeedback.notify(.success)
                        onApplyTransition(selectedOutcome, userNote, result.response, result.source)
                        dismiss()
                    } label: {
                        Text("确认转段并刷新今日时间轴")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(AuraTheme.sageGreen, in: Capsule())
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(AuraTheme.canvasBackground.opacity(0.95))
                } else {
                    Button {
                        Task {
                            await runEvaluation()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isEvaluating {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(isEvaluating ? (progressStatus ?? "正在复诊评估…") : "评估转归并生成今日方案")
                                .font(.headline)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            isEvaluating ? AuraTheme.secondaryText.opacity(0.45) : AuraTheme.warmGinger,
                            in: Capsule()
                        )
                    }
                    .disabled(isEvaluating)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(AuraTheme.canvasBackground.opacity(0.95))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var currentPhaseSummaryCard: some View {
        let accent = currentPhase.stageKind.accentColor

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(currentPhase.phaseName, systemImage: currentPhase.stageKind.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)

                Spacer()

                Text(currentPhase.progressText(for: snapshot.date))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AuraTheme.secondaryText)
            }

            Text("当前治则：\(currentPhase.therapeuticPrinciple)")
                .font(.caption)
                .foregroundStyle(AuraTheme.primaryText)

            Text("转段标准：\(currentPhase.exitCriteria)")
                .font(.caption)
                .foregroundStyle(AuraTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AuraTheme.hairline, lineWidth: 1)
        )
    }

    private var outcomeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("对照上方标准，目前体感如何？")
                .font(.headline)
                .foregroundStyle(AuraTheme.primaryText)

            ForEach(FollowUpOutcome.allCases) { outcome in
                let isSelected = selectedOutcome == outcome
                Button {
                    HapticFeedback.impact(.light)
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedOutcome = outcome
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: outcome.systemImage)
                            .font(.title3)
                            .foregroundStyle(isSelected ? outcome.tintColor : AuraTheme.secondaryText)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(outcome.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AuraTheme.primaryText)

                            Text(outcome.subtitle)
                                .font(.caption)
                                .foregroundStyle(AuraTheme.secondaryText)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? outcome.tintColor : AuraTheme.secondaryText.opacity(0.45))
                    }
                    .padding(14)
                    .background(
                        isSelected ? outcome.tintColor.opacity(0.10) : AuraTheme.cardSurface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? outcome.tintColor.opacity(0.55) : AuraTheme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isEvaluating)
            }
        }
    }

    private var noteInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("补充今日变化（可选）")
                .font(.caption.weight(.medium))
                .foregroundStyle(AuraTheme.secondaryText)

            TextField("例如：大便成形了、胃不胀了，今天想恢复轻量运动", text: $userNote, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...4)
                .padding(10)
                .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AuraTheme.hairline, lineWidth: 1)
                )
                .disabled(isEvaluating)
        }
    }

    private func transitionPreviewSection(_ response: AIPhaseTransitionResponse, source: AIServiceSource) -> some View {
        let newStage = response.newPhaseSpec.resolvedStageKind

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("复诊转归结论", systemImage: "arrow.triangle.branch")
                        .font(.headline)
                        .foregroundStyle(AuraTheme.primaryText)
                    Spacer()
                    Text(source.rawValue)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AuraTheme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AuraTheme.subtleSurface, in: Capsule())
                }

                HStack(spacing: 8) {
                    Text(currentPhase.stageKind.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AuraTheme.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(AuraTheme.subtleSurface, in: Capsule())

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(newStage.accentColor)

                    Text("\(response.newPhaseSpec.phaseName)（\(response.newPhaseSpec.normalizedPlannedDays)天）")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(newStage.accentColor, in: Capsule())
                }

                Text(response.clinicalAssessment)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AuraTheme.primaryText)

                Text("新治法总则：\(response.newPhaseSpec.therapeuticPrinciple)")
                    .font(.caption)
                    .foregroundStyle(newStage.accentColor)

                Text(response.summary)
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.caption2)
                            .foregroundStyle(AuraTheme.sageGreen)
                        Text("体质演化：\(response.evolutionSpec.deltaSummary)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AuraTheme.primaryText)
                    }

                    Text("耐受沉淀：\(response.evolutionSpec.toleranceNote)")
                        .font(.caption2)
                        .foregroundStyle(AuraTheme.secondaryText)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AuraTheme.subtleSurface.opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(14)
            .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(newStage.accentColor.opacity(0.35), lineWidth: 1)
            )

            Text("今日更新后的 \(response.cards.count) 项顺时安排")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AuraTheme.primaryText)

            ForEach(Array(response.cards.enumerated()), id: \.offset) { _, card in
                let category = card.resolvedCategory
                let accent = AuraTheme.accent(for: category)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(category.displayName, systemImage: category.systemImage)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(accent.opacity(0.12), in: Capsule())

                        Text(card.timeSlot)
                            .font(.caption2)
                            .foregroundStyle(AuraTheme.secondaryText)

                        Spacer()
                    }

                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AuraTheme.primaryText)

                    Text(card.actionDetail)
                        .font(.caption)
                        .foregroundStyle(AuraTheme.secondaryText)

                    Text("理由：\(card.clampedReasoning)")
                        .font(.caption2)
                        .foregroundStyle(accent)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AuraTheme.hairline, lineWidth: 1)
                )
            }
        }
    }

    private func runEvaluation() async {
        isEvaluating = true
        errorMessage = nil
        progressStatus = "正在进行复诊评估…"
        defer {
            isEvaluating = false
            progressStatus = nil
        }

        let profileContext = profile.map(AIProfileContext.init(profile:))
        let snapshotContext = AISnapshotContext(snapshot: snapshot)

        do {
            let result = try await AIService.shared.evaluatePhaseFollowUp(
                outcome: selectedOutcome,
                userNote: userNote,
                profile: profileContext,
                snapshot: snapshotContext,
                onStreamProgress: { status in
                    Task { @MainActor in
                        progressStatus = status
                    }
                }
            )
            withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                evaluationResult = (result.payload, result.source)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let container = PreviewSupport.makeContainer()
    let snapshots = (try? container.mainContext.fetch(FetchDescriptor<DailyContextSnapshot>())) ?? []
    let profiles = (try? container.mainContext.fetch(FetchDescriptor<UserConstitutionProfile>())) ?? []
    let phase = RegimenPhase(
        stageKind: .acuteRelief,
        phaseName: "急性祛湿恢复期",
        therapeuticPrinciple: "温中散寒、先护胃气，暂缓减重与生冷",
        exitCriteria: "排便成形不黏腻、胃脘温暖无胀闷且精神恢复",
        startDate: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
        plannedDays: 3
    )

    return PhaseFollowUpSheet(
        currentPhase: phase,
        snapshot: snapshots.first!,
        profile: profiles.first,
        onApplyTransition: { _, _, _, _ in }
    )
}
