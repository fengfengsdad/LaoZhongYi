import SwiftData
import SwiftUI

struct RegimenProgressView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserConstitutionProfile]
    @Query(sort: \RegimenPhase.startDate, order: .reverse) private var phases: [RegimenPhase]
    @Query(sort: \DailyContextSnapshot.date, order: .forward) private var snapshots: [DailyContextSnapshot]
    @Query(sort: \ConstitutionEvolutionRecord.date, order: .reverse) private var evolutionRecords: [ConstitutionEvolutionRecord]
    @Query(sort: \ChatAdjustmentLog.timestamp, order: .reverse) private var logs: [ChatAdjustmentLog]

    @State private var selectedHistoryTab: HistoryTab = .caseArchive
    @State private var isShowingPhaseFollowUp: Bool = false
    @State private var toastMessage: String?

    private enum HistoryTab: String, CaseIterable, Identifiable {
        case caseArchive = "调理医案"
        case adjustmentLogs = "微调流水"

        var id: String { rawValue }
    }

    private var activeProfile: UserConstitutionProfile? {
        profiles.first
    }

    private var activePhase: RegimenPhase? {
        phases.first(where: { $0.status == .active }) ?? phases.first
    }

    private var todaySnapshot: DailyContextSnapshot? {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return snapshots.first(where: { Calendar.current.startOfDay(for: $0.date) >= startOfToday }) ?? snapshots.first
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let phase = activePhase {
                            currentPhaseHeroCard(phase)
                            dietaryBoundaryCard(phase)
                            fourStageRoadmapCard(activeStage: phase.stageKind)
                        } else {
                            ContentUnavailableView(
                                "暂无调理分期",
                                systemImage: "leaf.arrow.circlepath",
                                description: Text("在「今日」打卡或生成 3 日计划后，会在这里呈现完整阶段进度与调养路线。")
                            )
                        }

                        evolutionTrendCard
                        archiveSection
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .background(AuraTheme.canvasBackground.ignoresSafeArea())

                if let toastMessage {
                    Text(toastMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AuraTheme.primaryText.opacity(0.88), in: Capsule())
                        .padding(.top, 8)
                }
            }
            .navigationTitle("整体调养进度")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $isShowingPhaseFollowUp) {
                if let phase = activePhase, let snapshot = todaySnapshot {
                    PhaseFollowUpSheet(
                        currentPhase: phase,
                        snapshot: snapshot,
                        profile: activeProfile,
                        onApplyTransition: { outcome, note, response, source in
                            applyPhaseTransition(
                                currentPhase: phase,
                                snapshot: snapshot,
                                outcome: outcome,
                                userNote: note,
                                response: response,
                                source: source
                            )
                        }
                    )
                }
            }
        }
    }

    private func currentPhaseHeroCard(_ phase: RegimenPhase) -> some View {
        let accent = phase.stageKind.accentColor
        let refDate = todaySnapshot?.date ?? .now

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

                Text(phase.progressText(for: refDate))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent)
            }

            Text(phase.phaseName)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(AuraTheme.primaryText)

            ProgressView(value: phase.progressFraction(for: refDate))
                .tint(accent)

            VStack(alignment: .leading, spacing: 8) {
                badgeLine(label: "治法总则", value: phase.therapeuticPrinciple, tint: accent)
                badgeLine(label: "转段标准", value: phase.exitCriteria, tint: AuraTheme.sageGreen)
                badgeLine(label: "下一阶段", value: phase.nextStageHint, tint: AuraTheme.inkSlate)
            }

            if todaySnapshot != nil {
                Button {
                    HapticFeedback.impact(.light)
                    isShowingPhaseFollowUp = true
                } label: {
                    Label("发起阶段复诊 / 评估转段", systemImage: "stethoscope")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(accent, in: Capsule())
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.32), lineWidth: 1)
        )
    }

    private func badgeLine(label: String, value: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(tint.opacity(0.13), in: Capsule())

            Text(value)
                .font(.caption)
                .foregroundStyle(AuraTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dietaryBoundaryCard(_ phase: RegimenPhase) -> some View {
        let boundary = phase.resolvedDietaryBoundary

        return VStack(alignment: .leading, spacing: 12) {
            Label("本阶段饮食红绿灯（防焦虑指南）", systemImage: "leaf.circle.fill")
                .font(.headline)
                .foregroundStyle(AuraTheme.primaryText)

            Text(boundary.flexibility)
                .font(.caption)
                .foregroundStyle(AuraTheme.primaryText)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AuraTheme.sageGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            boundaryChipGroup(title: "绿灯 · 放心吃 / 饿了可加餐", items: boundary.green, tint: AuraTheme.sageGreen)
            boundaryChipGroup(title: "黄灯 · 适量减半", items: boundary.yellow, tint: AuraTheme.warmGinger)
            boundaryChipGroup(title: "红灯 · 本阶段尽量避开", items: boundary.red, tint: .red.opacity(0.82))
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private func boundaryChipGroup(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.11), in: Capsule())
                }
            }
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
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var evolutionTrendCard: some View {
        let scored = evolutionRecords.reversed().filter { $0.primaryConstitutionScore != nil }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("体质偏颇走势 & 置信度", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)

                Spacer()

                if let profile = activeProfile {
                    Text("置信度 \(profile.constitutionConfidencePercent)%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AuraTheme.sageGreen)
                }
            }

            if !scored.isEmpty {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(scored.suffix(6)), id: \.id) { item in
                        let score = item.primaryConstitutionScore ?? 75
                        let height = max(20.0, min(64.0, Double(score) * 0.75))

                        VStack(spacing: 4) {
                            Text("\(score)")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(AuraTheme.sageGreen)

                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(AuraTheme.sageGreen.opacity(0.75))
                                .frame(width: 24, height: height)

                            Text(item.date.formatted(.dateTime.month().day()))
                                .font(.caption2)
                                .foregroundStyle(AuraTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(10)
                .background(AuraTheme.subtleSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let latest = evolutionRecords.first {
                Text("最新进展：\(latest.deltaSummary)")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("个人医案与微调记录")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)
                Spacer()
            }

            Picker("档案类型", selection: $selectedHistoryTab) {
                ForEach(HistoryTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if selectedHistoryTab == .caseArchive {
                if evolutionRecords.isEmpty {
                    Text("暂无调理医案记录。")
                        .font(.caption)
                        .foregroundStyle(AuraTheme.secondaryText)
                } else {
                    ForEach(evolutionRecords) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(record.phaseName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(record.stageKind.accentColor)
                                Text("· \(record.outcomeTitle)")
                                    .font(.caption2)
                                    .foregroundStyle(AuraTheme.secondaryText)
                                Spacer()
                                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(AuraTheme.secondaryText)
                            }
                            Text(record.clinicalNote)
                                .font(.subheadline)
                                .foregroundStyle(AuraTheme.primaryText)
                            Text("耐受：\(record.toleranceNote)")
                                .font(.caption2)
                                .foregroundStyle(AuraTheme.secondaryText)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
                    }
                }
            } else {
                if logs.isEmpty {
                    Text("暂无状态打卡或卡片换一换记录。")
                        .font(.caption)
                        .foregroundStyle(AuraTheme.secondaryText)
                } else {
                    ForEach(logs) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("「\(log.userInput)」")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AuraTheme.primaryText)
                                Spacer()
                                Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(AuraTheme.secondaryText)
                            }
                            Text(log.aiSummary)
                                .font(.caption)
                                .foregroundStyle(AuraTheme.secondaryText)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func applyPhaseTransition(
        currentPhase: RegimenPhase,
        snapshot: DailyContextSnapshot,
        outcome: FollowUpOutcome,
        userNote: String,
        response: AIPhaseTransitionResponse,
        source: AIServiceSource
    ) {
        let baseDay = Calendar.current.startOfDay(for: snapshot.date)
        let boundary = response.newPhaseSpec.dietaryBoundary

        withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) {
            let targetPhase: RegimenPhase
            if response.transitionDecision == "extendCurrentStage" {
                currentPhase.therapeuticPrinciple = response.newPhaseSpec.therapeuticPrinciple
                currentPhase.exitCriteria = response.newPhaseSpec.exitCriteria
                currentPhase.nextStageHint = response.newPhaseSpec.nextStageHint
                currentPhase.plannedDays = max(currentPhase.plannedDays, response.newPhaseSpec.normalizedPlannedDays)
                currentPhase.greenLightFoods = boundary.greenLightFoods
                currentPhase.yellowLightFoods = boundary.yellowLightLimit
                currentPhase.redLightFoods = boundary.redLightAvoid
                currentPhase.dietaryFlexibilityNote = boundary.flexibilityNote
                currentPhase.status = .active
                currentPhase.lastFollowUpDate = .now
                currentPhase.updatedAt = .now
                targetPhase = currentPhase
            } else {
                currentPhase.status = .completed
                currentPhase.lastFollowUpDate = .now
                currentPhase.updatedAt = .now

                let newPhase = RegimenPhase(
                    stageKind: response.newPhaseSpec.resolvedStageKind,
                    phaseName: response.newPhaseSpec.phaseName,
                    therapeuticPrinciple: response.newPhaseSpec.therapeuticPrinciple,
                    exitCriteria: response.newPhaseSpec.exitCriteria,
                    nextStageHint: response.newPhaseSpec.nextStageHint,
                    startDate: baseDay,
                    plannedDays: response.newPhaseSpec.normalizedPlannedDays,
                    status: .active,
                    triggerSummary: "复诊评估（\(outcome.title)）",
                    greenLightFoods: boundary.greenLightFoods,
                    yellowLightFoods: boundary.yellowLightLimit,
                    redLightFoods: boundary.redLightAvoid,
                    dietaryFlexibilityNote: boundary.flexibilityNote
                )
                modelContext.insert(newPhase)
                targetPhase = newPhase
            }

            snapshot.regimenPhase = targetPhase
            snapshot.therapeuticPrinciple = targetPhase.therapeuticPrinciple
            snapshot.recoveryPhase = targetPhase.badgeText(for: snapshot.date)
            snapshot.userReportedSymptoms = response.remainingSymptoms

            for existingCard in snapshot.actionCards {
                modelContext.delete(existingCard)
            }
            snapshot.actionCards.removeAll()

            let diningEnv = activeProfile?.diningEnvironment ?? "居家做饭"
            let dietPrefs = activeProfile?.dietaryPreferences ?? []

            var newCards: [ActionCard] = []
            for (index, rawPayload) in response.cards.enumerated() {
                let payload = DietaryAdaptationHelper.adaptPayload(rawPayload, diningEnvironment: diningEnv, dietaryPreferences: dietPrefs)
                let card = ActionCard(
                    category: payload.resolvedCategory,
                    timeSlot: payload.timeSlot,
                    title: payload.title,
                    actionDetail: payload.actionDetail,
                    reasoning: payload.clampedReasoning,
                    corePrinciple: payload.corePrinciple,
                    flexibleSwapHint: payload.flexibleSwapHint,
                    isCompleted: false,
                    sortOrder: index,
                    snapshot: snapshot
                )
                modelContext.insert(card)
                newCards.append(card)
            }
            snapshot.actionCards = newCards

            let evolution = response.evolutionSpec
            if let profile = activeProfile {
                if evolution.shouldUpdateProfile && !evolution.updatedConstitutionTags.isEmpty {
                    profile.constitutionTags = evolution.updatedConstitutionTags
                }
                if outcome == .improved {
                    profile.constitutionConfidencePercent = min(95, profile.constitutionConfidencePercent + 12)
                    if profile.constitutionConfidencePercent >= 82 {
                        profile.needsCalibrationTrial = false
                    }
                } else if outcome == .persistingOrWorse {
                    profile.constitutionConfidencePercent = max(55, profile.constitutionConfidencePercent - 4)
                    profile.needsCalibrationTrial = true
                }
                let trimmedTolerance = evolution.toleranceNote.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedTolerance.isEmpty && !profile.toleranceNotes.contains(trimmedTolerance) {
                    profile.toleranceNotes.append(trimmedTolerance)
                    if profile.toleranceNotes.count > 6 {
                        profile.toleranceNotes.removeFirst(profile.toleranceNotes.count - 6)
                    }
                }
                profile.updatedAt = .now
            }

            let record = ConstitutionEvolutionRecord(
                date: .now,
                phaseName: targetPhase.phaseName,
                stageKind: targetPhase.stageKind,
                therapeuticPrinciple: targetPhase.therapeuticPrinciple,
                outcomeTitle: outcome.title,
                clinicalNote: response.clinicalAssessment,
                constitutionSnapshotTags: evolution.updatedConstitutionTags.isEmpty ? (activeProfile?.constitutionTags ?? []) : evolution.updatedConstitutionTags,
                deltaSummary: evolution.deltaSummary,
                toleranceNote: evolution.toleranceNote
            )
            modelContext.insert(record)

            let log = ChatAdjustmentLog(
                userInput: "阶段复诊：\(outcome.title)\(userNote.isEmpty ? "" : " · \(userNote)")",
                aiSummary: "[\(source.rawValue)] \(response.clinicalAssessment)",
                affectedCardTitles: newCards.map(\.title),
                wasApplied: true
            )
            modelContext.insert(log)
            try? modelContext.save()
        }

        toastMessage = "已转入「\(response.newPhaseSpec.phaseName)」并刷新今日安排"
        Task {
            _ = await GentleNotificationService.shared.syncNotifications(for: snapshots)
            try? await Task.sleep(for: .seconds(2.4))
            await MainActor.run { toastMessage = nil }
        }
    }
}

#Preview {
    RegimenProgressView()
        .modelContainer(PreviewSupport.makeContainer())
}
