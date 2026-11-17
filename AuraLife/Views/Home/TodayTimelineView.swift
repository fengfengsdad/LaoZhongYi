import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct TodayTimelineView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserConstitutionProfile]
    @Query(sort: \RegimenPhase.startDate, order: .reverse) private var phases: [RegimenPhase]
    @Query(sort: \DailyContextSnapshot.date, order: .forward) private var snapshots: [DailyContextSnapshot]

    @State private var selectedDayIndex: Int = 0
    @State private var checkInText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?
    @State private var photoIntent: PhotoCheckInIntent = .auto
    @State private var recognizedPhotoText: String?

    @State private var isProcessingCheckIn: Bool = false
    @State private var isGeneratingMultiDay: Bool = false
    @State private var streamingStatus: String?
    @State private var swappingCardIDs: Set<UUID> = []
    @State private var isAILiveConfigured: Bool = AIConfiguration.load().hasValidKey
    @State private var isNotificationsEnabled: Bool = NotificationPreferences.load().isEnabled
    @State private var hasSyncedInitialEnvironment: Bool = false

    @State private var pendingProposal: AdjustmentProposal?
    @State private var pendingTriageSession: SymptomTriageSession?
    @State private var isSubmittingTriage: Bool = false
    @State private var isShowingProfile: Bool = false
    @State private var isShowingHistory: Bool = false
    @State private var isShowingAISettings: Bool = false
    @State private var isShowingAILogs: Bool = false
    @State private var isShowingWeatherContext: Bool = false
    @State private var isShowingNotifications: Bool = false
    @State private var isShowingPhaseRoadmap: Bool = false
    @State private var isShowingPhaseFollowUp: Bool = false
    @State private var errorAlertMessage: String?
    @State private var toastMessage: String?

    private var activeProfile: UserConstitutionProfile? {
        profiles.first
    }

    private var activeRegimenPhase: RegimenPhase? {
        phases.first(where: { $0.status == .active }) ?? phases.first
    }

    private var orderedSnapshots: [DailyContextSnapshot] {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let upcoming = snapshots.filter { Calendar.current.startOfDay(for: $0.date) >= startOfToday }
        return upcoming.isEmpty ? snapshots : upcoming
    }

    private var activeSnapshot: DailyContextSnapshot? {
        let list = orderedSnapshots
        guard !list.isEmpty else { return nil }
        let safeIndex = min(max(0, selectedDayIndex), list.count - 1)
        return list[safeIndex]
    }

    private var timelineCards: [ActionCard] {
        activeSnapshot?.sortedCards ?? []
    }

    private var focusedCardID: UUID? {
        guard let snapshot = activeSnapshot else { return nil }
        let pending = timelineCards.filter { !$0.isCompleted }
        if let activeWindow = pending.first(where: {
            TimeSlotParser.isCurrentOrNextWindow(timeSlot: $0.timeSlot, on: snapshot.date)
        }) {
            return activeWindow.id
        }
        return pending.first?.id
    }

    private var isAllTodayCompleted: Bool {
        !timelineCards.isEmpty && timelineCards.allSatisfy(\.isCompleted)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AuraTheme.canvasBackground.ignoresSafeArea()

            if let snapshot = activeSnapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if orderedSnapshots.count > 1 {
                            daySelectorBar
                        }

                        RecoveryBannerView(
                            snapshot: snapshot,
                            dayTitle: dayHeadline(for: selectedDayIndex),
                            profile: activeProfile,
                            activePhase: activeRegimenPhase,
                            completedCount: timelineCards.filter(\.isCompleted).count,
                            totalCount: timelineCards.count,
                            isGeneratingMultiDay: isGeneratingMultiDay,
                            isAILiveConfigured: isAILiveConfigured,
                            isNotificationsEnabled: isNotificationsEnabled,
                            onTapWeatherContext: { isShowingWeatherContext = true },
                            onTapPhaseRoadmap: { isShowingPhaseRoadmap = true },
                            onTapNotifications: { isShowingNotifications = true },
                            onTapProfile: { isShowingProfile = true },
                            onTapHistory: { isShowingHistory = true },
                            onTapAISettings: { isShowingAISettings = true },
                            onGenerateMultiDay: {
                                Task {
                                    await generateMultiDayPlan(baseSnapshot: snapshot)
                                }
                            }
                        )

                        if selectedDayIndex == 0,
                           let currentPhase = snapshot.regimenPhase ?? activeRegimenPhase,
                           currentPhase.shouldSuggestFollowUp(on: snapshot.date) {
                            PhaseFollowUpBannerCard(
                                phase: currentPhase,
                                referenceDate: snapshot.date,
                                onStartFollowUp: {
                                    isShowingPhaseFollowUp = true
                                },
                                onDismissToday: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        currentPhase.lastFollowUpDate = .now
                                        try? modelContext.save()
                                    }
                                    showToast("今日先按当前方案继续调理")
                                }
                            )
                        }

                        VStack(spacing: 16) {
                            ForEach(Array(timelineCards.enumerated()), id: \.element.id) { index, card in
                                SwipeableActionCard(
                                    card: card,
                                    isLast: index == timelineCards.count - 1,
                                    isSwapping: swappingCardIDs.contains(card.id),
                                    isCurrentFocus: card.id == focusedCardID,
                                    onToggleComplete: {
                                        card.isCompleted.toggle()
                                        try? modelContext.save()
                                        Task {
                                            await syncGentleNotifications()
                                        }
                                    },
                                    onSwap: {
                                        Task {
                                            await swapSingleCard(card, in: snapshot)
                                        }
                                    }
                                )
                            }
                        }

                        if isAllTodayCompleted {
                            sereneCompletionFooter
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    QuickCheckInBar(
                        inputText: $checkInText,
                        selectedPhotoItem: $selectedPhotoItem,
                        photoIntent: $photoIntent,
                        attachedImage: attachedImage,
                        recognizedPhotoText: recognizedPhotoText,
                        isProcessing: isProcessingCheckIn || isGeneratingMultiDay,
                        streamingStatus: streamingStatus,
                        onClearAttachment: {
                            attachedImage = nil
                            selectedPhotoItem = nil
                            recognizedPhotoText = nil
                            photoIntent = .auto
                        },
                        onTapLogs: {
                            isShowingAILogs = true
                        },
                        onSubmit: {
                            Task {
                                await submitCheckIn()
                            }
                        }
                    )
                }
            } else {
                ProgressView("正在准备今日顺时方案…")
                    .tint(AuraTheme.sageGreen)
            }

            if let toastMessage {
                Text(toastMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AuraTheme.primaryText.opacity(0.88), in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            MockDataSeeder.seedIfNeeded(in: modelContext)
            isAILiveConfigured = AIConfiguration.load().hasValidKey
            isNotificationsEnabled = NotificationPreferences.load().isEnabled
            if !hasSyncedInitialEnvironment {
                hasSyncedInitialEnvironment = true
                _ = await refreshWeatherContext()
                _ = await syncGentleNotifications()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .auraLifeCompleteCardFromNotification)) { notification in
            guard let cardID = notification.userInfo?["cardID"] as? UUID else { return }
            markCardCompletedFromNotification(cardID)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await handleAttachedPhotoSelection(newItem)
            }
        }
        .sheet(item: $pendingTriageSession) { session in
            SymptomTriageSheet(
                session: session,
                isSubmitting: isSubmittingTriage,
                onSubmitAnswers: { answers, extraNote in
                    Task {
                        await submitTriageClarification(
                            originalInput: session.userInput,
                            answers: answers,
                            extraNote: extraNote
                        )
                    }
                },
                onCancel: {
                    pendingTriageSession = nil
                }
            )
        }
        .sheet(item: $pendingProposal) { proposal in
            AdjustmentDiffSheet(
                proposal: proposal,
                onApply: {
                    applyProposal(proposal)
                },
                onCancel: {
                    let log = ChatAdjustmentLog(
                        userInput: proposal.userInput,
                        aiSummary: proposal.summary,
                        affectedCardTitles: proposal.diffs.map(\.updatedTitle),
                        wasApplied: false
                    )
                    modelContext.insert(log)
                    try? modelContext.save()
                    pendingProposal = nil
                }
            )
        }
        .sheet(isPresented: $isShowingProfile) {
            if let profile = activeProfile {
                ProfileSheetView(profile: profile)
            }
        }
        .sheet(isPresented: $isShowingHistory) {
            AdjustmentHistorySheet()
        }
        .sheet(isPresented: $isShowingAISettings) {
            AISettingsSheet {
                isAILiveConfigured = AIConfiguration.load().hasValidKey
                showToast(isAILiveConfigured ? "已切换至云端 LLM 引擎" : "当前使用离线演示引擎")
            }
        }
        .sheet(isPresented: $isShowingAILogs) {
            AILogSheet()
        }
        .sheet(isPresented: $isShowingWeatherContext) {
            if let snapshot = activeSnapshot {
                ContextEnvironmentSheet(
                    snapshot: snapshot,
                    profile: activeProfile,
                    onRefreshWeather: {
                        await refreshWeatherContext()
                    },
                    onSyncHealthKit: {
                        await syncHealthKitMetrics()
                    },
                    onApplyWeatherToPlan: {
                        Task {
                            await triggerWeatherAdaptation(for: snapshot)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingNotifications) {
            NotificationSettingsSheet(
                snapshots: orderedSnapshots,
                onPreferencesChanged: {
                    isNotificationsEnabled = NotificationPreferences.load().isEnabled
                    return await syncGentleNotifications()
                }
            )
        }
        .sheet(isPresented: $isShowingPhaseRoadmap) {
            RegimenPhaseRoadmapSheet(
                currentPhase: activeSnapshot?.regimenPhase ?? activeRegimenPhase,
                referenceDate: activeSnapshot?.date ?? .now,
                onStartFollowUp: {
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        await MainActor.run {
                            isShowingPhaseFollowUp = true
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $isShowingPhaseFollowUp) {
            if let snapshot = activeSnapshot,
               let currentPhase = snapshot.regimenPhase ?? activeRegimenPhase {
                PhaseFollowUpSheet(
                    currentPhase: currentPhase,
                    snapshot: snapshot,
                    profile: activeProfile,
                    onApplyTransition: { outcome, note, response, source in
                        applyPhaseTransition(
                            currentPhase: currentPhase,
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
        .alert("AI 请求未成功", isPresented: Binding(
            get: { errorAlertMessage != nil },
            set: { if !$0 { errorAlertMessage = nil } }
        )) {
            Button("查看诊断日志") {
                isShowingAILogs = true
            }
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorAlertMessage ?? "")
        }
    }

    private var daySelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(orderedSnapshots.enumerated()), id: \.element.id) { index, snap in
                    let isSelected = index == min(selectedDayIndex, orderedSnapshots.count - 1)
                    Button {
                        HapticFeedback.impact(.light)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDayIndex = index
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(dayChipLabel(for: index, date: snap.date))
                                .font(.caption.weight(.semibold))
                            if snap.isAcuteRecovery {
                                Circle()
                                    .fill(AuraTheme.warmGinger)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .foregroundStyle(isSelected ? .white : AuraTheme.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? AuraTheme.sageGreen : AuraTheme.cardSurface,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(isSelected ? Color.clear : AuraTheme.hairline, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private func dayChipLabel(for index: Int, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        let dateStr = formatter.string(from: date)
        switch index {
        case 0: return "今日 · \(dateStr)"
        case 1: return "明日 · \(dateStr)"
        case 2: return "后日 · \(dateStr)"
        default: return "第\(index + 1)天 · \(dateStr)"
        }
    }

    private func dayHeadline(for index: Int) -> String {
        switch index {
        case 0: return "今日顺时调理"
        case 1: return "明日顺时调理"
        case 2: return "后日顺时调理"
        default: return "第\(index + 1)日调理"
        }
    }

    // MARK: - Phase 3 Ecological Context & Multimodal

    private func refreshWeatherContext() async -> String? {
        guard let weather = await WeatherContextService.shared.fetchCurrentWeather(),
              let todaySnapshot = orderedSnapshots.first else {
            return nil
        }

        for snap in orderedSnapshots {
            snap.city = weather.city
            snap.weatherTempC = weather.tempC
            snap.weatherCondition = weather.condition
            snap.weatherHumidity = weather.humidityPercent
            snap.weatherWindSpeedKmh = weather.windSpeedKmh
            snap.weatherSource = weather.source
            snap.solarTermName = SolarTermCalculator.term(for: snap.date).name
        }
        try? modelContext.save()

        let summary = "已更新气象（\(weather.source)）：\(todaySnapshot.city) \(Int(weather.tempC.rounded()))°C \(weather.condition) · 湿度 \(Int(weather.humidityPercent.rounded()))%"
        return summary
    }

    private func syncHealthKitMetrics() async -> String {
        let health = await HealthKitSyncService.shared.syncTodayMetrics()
        if let todaySnapshot = orderedSnapshots.first {
            todaySnapshot.healthStepCount = health.stepsToday
            todaySnapshot.healthSleepHours = health.sleepHoursLastNight
            todaySnapshot.healthLatestWeightKG = health.latestWeightKG
        }
        if let weight = health.latestWeightKG, let profile = activeProfile {
            profile.weightKG = weight
            profile.updatedAt = .now
        }
        try? modelContext.save()
        return health.statusMessage
    }

    private func handleAttachedPhotoSelection(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }
        attachedImage = image
        recognizedPhotoText = nil

        if let text = try? await ConstitutionReportParser.recognizeText(from: image),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recognizedPhotoText = text
            let parsed = ConstitutionReportParser.parse(text: text)
            if !parsed.constitutionTags.isEmpty || parsed.weightKG != nil || parsed.heightCM != nil {
                photoIntent = .report
                if let profile = activeProfile {
                    if let h = parsed.heightCM { profile.heightCM = h }
                    if let w = parsed.weightKG { profile.weightKG = w }
                    if let tw = parsed.targetWeightKG { profile.targetWeightKG = tw }
                    if !parsed.constitutionTags.isEmpty {
                        profile.constitutionTags = parsed.constitutionTags
                    }
                    profile.rawReportSummary = parsed.extractedText
                    profile.updatedAt = .now
                    try? modelContext.save()
                    showToast("已从报告图片提取 \(parsed.constitutionTags.count) 项体质标签并同步画像")
                }
            }
        }
    }

    private func triggerWeatherAdaptation(for snapshot: DailyContextSnapshot) async {
        let weatherInput = "请结合当前\(snapshot.city) \(Int(snapshot.weatherTempC.rounded()))°C \(snapshot.weatherCondition)（湿度\(Int(snapshot.weatherHumidity.rounded()))%、风速\(Int(snapshot.weatherWindSpeedKmh.rounded()))km/h）与\(snapshot.resolvedSolarTerm.name)节气，评估并调整今日运动与饮食计划"
        await submitCheckIn(overrideInput: weatherInput)
    }

    // MARK: - Phase 2 & 3 AI Actions

    private func submitCheckIn(overrideInput: String? = nil) async {
        let snapshotsList = orderedSnapshots
        guard !snapshotsList.isEmpty else { return }

        let trimmed = (overrideInput ?? checkInText).trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveInput = trimmed.isEmpty && attachedImage != nil ? photoIntent.defaultPromptHint : trimmed

        isProcessingCheckIn = true
        streamingStatus = "正在唤醒动态规划引擎…"

        defer {
            isProcessingCheckIn = false
            streamingStatus = nil
        }

        let profileContext = activeProfile.map(AIProfileContext.init(profile:))
        let snapshotContexts = snapshotsList.map(AISnapshotContext.init(snapshot:))
        let attachedSnapshot = attachedImage
        let intentSnapshot = photoIntent
        let ocrSnapshot = recognizedPhotoText

        do {
            let result = try await AIService.shared.proposeContextualAdjustment(
                userInput: effectiveInput,
                attachedImage: attachedSnapshot,
                photoIntent: intentSnapshot,
                recognizedPhotoText: ocrSnapshot,
                profile: profileContext,
                snapshots: snapshotContexts,
                onStreamProgress: { progress in
                    Task { @MainActor in
                        streamingStatus = progress
                    }
                }
            )

            var byOffset: [Int: DailyContextSnapshot] = [:]
            for (idx, snap) in snapshotsList.enumerated() {
                byOffset[idx] = snap
            }

            let outcome = LocalContextPlanner.makeEvaluationOutcome(
                from: result.payload,
                userInput: effectiveInput,
                source: result.source,
                snapshotsByOffset: byOffset
            )

            switch outcome {
            case let .needsClarification(session):
                pendingTriageSession = session
            case let .ready(proposal):
                pendingProposal = proposal
            }
        } catch {
            AILog.error("UI", "状态打卡微调失败: \(error.localizedDescription)")
            errorAlertMessage = error.localizedDescription
        }
    }

    private func submitTriageClarification(
        originalInput: String,
        answers: [AITriageAnswer],
        extraNote: String
    ) async {
        let snapshotsList = orderedSnapshots
        guard !snapshotsList.isEmpty else { return }

        isSubmittingTriage = true
        streamingStatus = "正在结合辨证结果生成调理方案…"
        defer {
            isSubmittingTriage = false
            streamingStatus = nil
        }

        let profileContext = activeProfile.map(AIProfileContext.init(profile:))
        let snapshotContexts = snapshotsList.map(AISnapshotContext.init(snapshot:))
        let attachedSnapshot = attachedImage
        let intentSnapshot = photoIntent
        let ocrSnapshot = recognizedPhotoText

        do {
            let result = try await AIService.shared.proposeContextualAdjustment(
                userInput: originalInput,
                triageAnswers: answers,
                extraTriageNote: extraNote,
                attachedImage: attachedSnapshot,
                photoIntent: intentSnapshot,
                recognizedPhotoText: ocrSnapshot,
                profile: profileContext,
                snapshots: snapshotContexts,
                onStreamProgress: { progress in
                    Task { @MainActor in
                        streamingStatus = progress
                    }
                }
            )

            var byOffset: [Int: DailyContextSnapshot] = [:]
            for (idx, snap) in snapshotsList.enumerated() {
                byOffset[idx] = snap
            }

            let outcome = LocalContextPlanner.makeEvaluationOutcome(
                from: result.payload,
                userInput: originalInput,
                triageAnswers: answers,
                source: result.source,
                snapshotsByOffset: byOffset
            )

            pendingTriageSession = nil
            switch outcome {
            case let .ready(proposal):
                pendingProposal = proposal
            case let .needsClarification(nextSession):
                pendingTriageSession = nextSession
            }
        } catch {
            AILog.error("UI", "轻问诊二次辨证失败: \(error.localizedDescription)")
            pendingTriageSession = nil
            errorAlertMessage = error.localizedDescription
        }
    }

    private func generateMultiDayPlan(baseSnapshot: DailyContextSnapshot) async {
        isGeneratingMultiDay = true
        streamingStatus = "正在生成未来 3 日顺时计划…"

        defer {
            isGeneratingMultiDay = false
            streamingStatus = nil
        }

        let profileContext = activeProfile.map(AIProfileContext.init(profile:))
        let snapshotContext = AISnapshotContext(snapshot: baseSnapshot)

        do {
            let result = try await AIService.shared.generateMultiDayPlan(
                daysCount: 3,
                profile: profileContext,
                snapshot: snapshotContext,
                onStreamProgress: { progress in
                    Task { @MainActor in
                        streamingStatus = progress
                    }
                }
            )

            let calendar = Calendar.current
            let baseDay = calendar.startOfDay(for: baseSnapshot.date)

            withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) {
                let updatedPhase = upsertActivePhase(
                    from: result.payload.phaseSpec,
                    startDate: baseDay,
                    triggerSummary: "生成未来 \(result.payload.days.count) 日动态规划"
                )

                for dayPlan in result.payload.days {
                    let targetDate = calendar.date(byAdding: .day, value: dayPlan.dayOffset, to: baseDay) ?? baseDay
                    let targetSnapshot = findOrCreateSnapshot(
                        for: targetDate,
                        template: baseSnapshot,
                        in: calendar
                    )

                    targetSnapshot.regimenPhase = updatedPhase
                    targetSnapshot.therapeuticPrinciple = updatedPhase.therapeuticPrinciple
                    targetSnapshot.recoveryPhase = updatedPhase.badgeText(for: targetDate)
                    if !dayPlan.detectedSymptoms.isEmpty {
                        targetSnapshot.userReportedSymptoms = dayPlan.detectedSymptoms
                    }

                    for existingCard in targetSnapshot.actionCards {
                        modelContext.delete(existingCard)
                    }
                    targetSnapshot.actionCards.removeAll()

                    var newCards: [ActionCard] = []
                    for (index, cardPayload) in dayPlan.cards.enumerated() {
                        let card = ActionCard(
                            category: cardPayload.resolvedCategory,
                            timeSlot: cardPayload.timeSlot,
                            title: cardPayload.title,
                            actionDetail: cardPayload.actionDetail,
                            reasoning: cardPayload.clampedReasoning,
                            isCompleted: false,
                            sortOrder: index,
                            snapshot: targetSnapshot
                        )
                        modelContext.insert(card)
                        newCards.append(card)
                    }
                    targetSnapshot.actionCards = newCards
                }

                let log = ChatAdjustmentLog(
                    userInput: "生成未来 3 日动态生活规划",
                    aiSummary: "[\(result.source.rawValue)] \(result.payload.summary)",
                    affectedCardTitles: result.payload.days.flatMap { $0.cards.map(\.title) },
                    wasApplied: true
                )
                modelContext.insert(log)
                try? modelContext.save()
            }

            selectedDayIndex = 0
            HapticFeedback.notify(.success)
            showToast("已生成未来 \(result.payload.days.count) 日方案（\(result.source.rawValue)）")
            _ = await syncGentleNotifications()
        } catch {
            AILog.error("UI", "生成3日计划失败: \(error.localizedDescription)")
            errorAlertMessage = error.localizedDescription
        }
    }

    private func applyProposal(_ proposal: AdjustmentProposal) {
        let snapshotsList = orderedSnapshots
        guard let todaySnapshot = snapshotsList.first else { return }

        let calendar = Calendar.current
        let baseDay = calendar.startOfDay(for: todaySnapshot.date)

        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            let updatedPhase = upsertActivePhase(
                from: proposal.phaseSpec,
                startDate: baseDay,
                triggerSummary: proposal.userInput
            )

            todaySnapshot.regimenPhase = updatedPhase
            todaySnapshot.therapeuticPrinciple = updatedPhase.therapeuticPrinciple
            todaySnapshot.recoveryPhase = updatedPhase.badgeText(for: todaySnapshot.date)
            todaySnapshot.userReportedSymptoms = proposal.detectedSymptoms

            for diff in proposal.diffs {
                let targetDate = calendar.date(byAdding: .day, value: diff.dayOffset, to: baseDay) ?? baseDay
                let targetSnapshot: DailyContextSnapshot
                if diff.dayOffset < snapshotsList.count {
                    targetSnapshot = snapshotsList[diff.dayOffset]
                } else {
                    targetSnapshot = findOrCreateSnapshot(
                        for: targetDate,
                        template: todaySnapshot,
                        in: calendar
                    )
                }

                targetSnapshot.regimenPhase = updatedPhase
                targetSnapshot.therapeuticPrinciple = updatedPhase.therapeuticPrinciple
                targetSnapshot.recoveryPhase = updatedPhase.badgeText(for: targetDate)
                targetSnapshot.userReportedSymptoms = proposal.detectedSymptoms

                if let targetID = diff.targetCardID,
                   let card = targetSnapshot.actionCards.first(where: { $0.id == targetID }) {
                    card.category = diff.category
                    card.timeSlot = diff.timeSlot
                    card.title = diff.updatedTitle
                    card.actionDetail = diff.updatedDetail
                    card.reasoning = diff.updatedReasoning
                    card.isCompleted = false
                } else {
                    let newCard = ActionCard(
                        category: diff.category,
                        timeSlot: diff.timeSlot,
                        title: diff.updatedTitle,
                        actionDetail: diff.updatedDetail,
                        reasoning: diff.updatedReasoning,
                        isCompleted: false,
                        sortOrder: diff.sortOrder,
                        snapshot: targetSnapshot
                    )
                    modelContext.insert(newCard)
                    targetSnapshot.actionCards.append(newCard)
                }
            }

            let triageDetail = proposal.triageSummary.map { " [辨证：\($0)]" } ?? ""
            let log = ChatAdjustmentLog(
                userInput: "\(proposal.userInput)\(triageDetail)",
                aiSummary: "[\(proposal.source.rawValue)] \(proposal.summary)",
                affectedCardTitles: proposal.diffs.map(\.updatedTitle),
                wasApplied: true
            )
            modelContext.insert(log)
            try? modelContext.save()
        }

        checkInText = ""
        attachedImage = nil
        selectedPhotoItem = nil
        recognizedPhotoText = nil
        photoIntent = .auto
        pendingProposal = nil
        showToast("已刷新动态时间轴")
        Task {
            _ = await syncGentleNotifications()
        }
    }

    private func swapSingleCard(_ card: ActionCard, in snapshot: DailyContextSnapshot) async {
        guard !swappingCardIDs.contains(card.id) else { return }
        swappingCardIDs.insert(card.id)
        defer { swappingCardIDs.remove(card.id) }

        let previousTitle = card.title
        let cardContext = AIActionCardContext(card: card)
        let profileContext = activeProfile.map(AIProfileContext.init(profile:))
        let snapshotContext = AISnapshotContext(snapshot: snapshot)

        do {
            let result = try await AIService.shared.swapSingleCard(
                card: cardContext,
                profile: profileContext,
                snapshot: snapshotContext,
                onStreamProgress: { _ in }
            )

            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                card.title = result.payload.title
                card.actionDetail = result.payload.actionDetail
                card.reasoning = result.payload.clampedReasoning
                card.isCompleted = false
            }

            let log = ChatAdjustmentLog(
                userInput: "卡片换一换：\(previousTitle)",
                aiSummary: "[\(result.source.rawValue)] 局部替换为「\(result.payload.title)」",
                affectedCardTitles: [result.payload.title],
                wasApplied: true
            )
            modelContext.insert(log)
            try? modelContext.save()

            HapticFeedback.impact(.light)
            showToast("已换一换「\(card.category.displayName)」建议（\(result.source.rawValue)）")
            _ = await syncGentleNotifications()
        } catch {
            AILog.error("UI", "单卡换一换失败: \(error.localizedDescription)")
            errorAlertMessage = error.localizedDescription
        }
    }

    private func findOrCreateSnapshot(
        for date: Date,
        template: DailyContextSnapshot,
        in calendar: Calendar
    ) -> DailyContextSnapshot {
        if let existing = snapshots.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return existing
        }
        let created = DailyContextSnapshot(
            date: date,
            weatherTempC: template.weatherTempC,
            weatherCondition: template.weatherCondition,
            city: template.city,
            weatherHumidity: template.weatherHumidity,
            weatherWindSpeedKmh: template.weatherWindSpeedKmh,
            weatherSource: template.weatherSource,
            solarTermName: SolarTermCalculator.term(for: date).name,
            healthStepCount: template.healthStepCount,
            healthSleepHours: template.healthSleepHours,
            healthLatestWeightKG: template.healthLatestWeightKG,
            userReportedSymptoms: template.userReportedSymptoms,
            recoveryPhase: template.recoveryPhase,
            therapeuticPrinciple: template.therapeuticPrinciple,
            regimenPhase: template.regimenPhase
        )
        modelContext.insert(created)
        return created
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

        withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) {
            let targetPhase: RegimenPhase
            if response.transitionDecision == "extendCurrentStage" {
                currentPhase.therapeuticPrinciple = response.newPhaseSpec.therapeuticPrinciple
                currentPhase.exitCriteria = response.newPhaseSpec.exitCriteria
                currentPhase.nextStageHint = response.newPhaseSpec.nextStageHint
                currentPhase.plannedDays = max(currentPhase.plannedDays, response.newPhaseSpec.normalizedPlannedDays)
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
                    triggerSummary: "复诊评估（\(outcome.title)）"
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

            var newCards: [ActionCard] = []
            for (index, payload) in response.cards.enumerated() {
                let card = ActionCard(
                    category: payload.resolvedCategory,
                    timeSlot: payload.timeSlot,
                    title: payload.title,
                    actionDetail: payload.actionDetail,
                    reasoning: payload.clampedReasoning,
                    isCompleted: false,
                    sortOrder: index,
                    snapshot: snapshot
                )
                modelContext.insert(card)
                newCards.append(card)
            }
            snapshot.actionCards = newCards

            let noteSuffix = userNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " · \(userNote)"
            let log = ChatAdjustmentLog(
                userInput: "阶段复诊：\(outcome.title)\(noteSuffix)",
                aiSummary: "[\(source.rawValue)] \(response.clinicalAssessment)",
                affectedCardTitles: newCards.map(\.title),
                wasApplied: true
            )
            modelContext.insert(log)

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

            let snapshotTags = evolution.updatedConstitutionTags.isEmpty
                ? (activeProfile?.constitutionTags ?? [])
                : evolution.updatedConstitutionTags

            let record = ConstitutionEvolutionRecord(
                date: .now,
                phaseName: targetPhase.phaseName,
                stageKind: targetPhase.stageKind,
                therapeuticPrinciple: targetPhase.therapeuticPrinciple,
                outcomeTitle: outcome.title,
                clinicalNote: response.clinicalAssessment,
                constitutionSnapshotTags: snapshotTags,
                deltaSummary: evolution.deltaSummary,
                toleranceNote: evolution.toleranceNote
            )
            modelContext.insert(record)

            try? modelContext.save()
        }

        showToast("已完成复诊转段，进入「\(response.newPhaseSpec.phaseName)」")
        Task {
            _ = await syncGentleNotifications()
        }
    }

    private func upsertActivePhase(
        from spec: AIRegimenPhasePayload,
        startDate: Date,
        triggerSummary: String
    ) -> RegimenPhase {
        let resolvedStage = spec.resolvedStageKind
        if let existing = activeRegimenPhase,
           existing.stageKind == resolvedStage && existing.phaseName == spec.phaseName {
            existing.therapeuticPrinciple = spec.therapeuticPrinciple
            existing.exitCriteria = spec.exitCriteria
            existing.nextStageHint = spec.nextStageHint
            existing.plannedDays = spec.normalizedPlannedDays
            existing.updatedAt = .now
            return existing
        }

        for item in phases where item.status != .completed {
            item.status = .completed
            item.updatedAt = .now
        }

        let created = RegimenPhase(
            stageKind: resolvedStage,
            phaseName: spec.phaseName,
            therapeuticPrinciple: spec.therapeuticPrinciple,
            exitCriteria: spec.exitCriteria,
            nextStageHint: spec.nextStageHint,
            startDate: startDate,
            plannedDays: spec.normalizedPlannedDays,
            status: .active,
            triggerSummary: triggerSummary
        )
        modelContext.insert(created)
        return created
    }

    private var sereneCompletionFooter: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.circle.fill")
                .font(.title2)
                .foregroundStyle(AuraTheme.sageGreen)

            VStack(alignment: .leading, spacing: 3) {
                Text("今日顺时调理已圆满")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AuraTheme.primaryText)
                Text("脾胃安和，夜间减少进食与大量饮水，早些安歇。")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AuraTheme.sageGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AuraTheme.sageGreen.opacity(0.25), lineWidth: 1)
        )
    }

    private func syncGentleNotifications() async -> Int {
        isNotificationsEnabled = NotificationPreferences.load().isEnabled
        return await GentleNotificationService.shared.syncNotifications(for: orderedSnapshots)
    }

    private func markCardCompletedFromNotification(_ cardID: UUID) {
        for snap in snapshots {
            if let card = snap.actionCards.first(where: { $0.id == cardID }) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    card.isCompleted = true
                }
                try? modelContext.save()
                showToast("已在通知中完成「\(card.title)」")
                Task {
                    _ = await syncGentleNotifications()
                }
                return
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.22)) {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if toastMessage == message {
                        toastMessage = nil
                    }
                }
            }
        }
    }
}

#Preview("浅色模式") {
    TodayTimelineView()
        .modelContainer(PreviewSupport.makeContainer())
}

#Preview("深色模式") {
    TodayTimelineView()
        .modelContainer(PreviewSupport.makeContainer())
        .preferredColorScheme(.dark)
}
