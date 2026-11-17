import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("auralife.onboarding.completed") private var hasCompletedOnboarding: Bool = true
    @Bindable var profile: UserConstitutionProfile
    @Query(sort: \ConstitutionEvolutionRecord.date, order: .forward) private var evolutionRecords: [ConstitutionEvolutionRecord]

    @State private var reportText: String = ""
    @State private var selectedReportImage: PhotosPickerItem?
    @State private var isRecognizingImage: Bool = false
    @State private var parseBannerMessage: String?

    @State private var newDietTag: String = ""
    @State private var newFitnessTag: String = ""

    private let diningOptions = ["居家做饭", "外卖", "食堂"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    bodyMetricsSection
                    constitutionTagsSection
                    evolutionTrendSection
                    preferencesSection
                    reportImportSection
                    reopenOnboardingButton
                }
                .padding(16)
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("长期体质与目标画像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        profile.updatedAt = .now
                        dismiss()
                    }
                    .foregroundStyle(AuraTheme.sageGreen)
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedReportImage) { _, newItem in
                guard let newItem else { return }
                Task {
                    await handleReportImageSelection(newItem)
                }
            }
        }
    }

    private var bodyMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("基础体征与减重目标")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)
                Spacer()
                Text(String(format: "BMI %.1f", profile.bmi))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AuraTheme.sageGreen)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AuraTheme.sageGreen.opacity(0.14), in: Capsule())
            }

            HStack(spacing: 12) {
                metricBox(title: "身高 (cm)", value: $profile.heightCM)
                metricBox(title: "当前体重 (kg)", value: $profile.weightKG)
                metricBox(title: "目标体重 (kg)", value: $profile.targetWeightKG)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("日常就餐场景")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)

                Picker("就餐场景", selection: $profile.diningEnvironment) {
                    ForEach(diningOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private func metricBox(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AuraTheme.secondaryText)
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AuraTheme.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var constitutionTagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("体质辨识标签")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)

                Spacer()

                HStack(spacing: 6) {
                    Text("\(profile.assessmentMethod) · 置信度 \(profile.constitutionConfidencePercent)%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(profile.constitutionConfidencePercent >= 80 ? AuraTheme.sageGreen : AuraTheme.warmGinger)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (profile.constitutionConfidencePercent >= 80 ? AuraTheme.sageGreen : AuraTheme.warmGinger).opacity(0.13),
                            in: Capsule()
                        )

                    if profile.needsCalibrationTrial {
                        Text("校准中")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(AuraTheme.warmGinger, in: Capsule())
                    }
                }
            }

            FlowTagsView(tags: profile.constitutionTags, tint: AuraTheme.warmGinger) { tag in
                profile.constitutionTags.removeAll { $0 == tag }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var evolutionTrendSection: some View {
        let scoredRecords = evolutionRecords.filter { $0.primaryConstitutionScore != nil }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("体质演化轨迹 & 耐受记忆", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)
                Spacer()
                Text("共 \(evolutionRecords.count) 次节点")
                    .font(.caption2)
                    .foregroundStyle(AuraTheme.secondaryText)
            }

            if !scoredRecords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("主体质偏颇分值走势（越低越趋于平和）")
                        .font(.caption2)
                        .foregroundStyle(AuraTheme.secondaryText)

                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Array(scoredRecords.suffix(6).enumerated()), id: \.element.id) { _, item in
                            let score = item.primaryConstitutionScore ?? 75
                            let normalizedHeight = max(20.0, min(68.0, Double(score) * 0.78))

                            VStack(spacing: 4) {
                                Text("\(score)")
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(AuraTheme.sageGreen)

                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(AuraTheme.sageGreen.opacity(0.75))
                                    .frame(width: 24, height: normalizedHeight)

                                Text(item.date.formatted(.dateTime.month().day()))
                                    .font(.caption2)
                                    .foregroundStyle(AuraTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .padding(10)
                .background(AuraTheme.subtleSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let latest = evolutionRecords.last {
                Text("最近演化：\(latest.deltaSummary)")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.primaryText)
            }

            if !profile.toleranceNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("个人食养与导引耐受反馈（自动注入 AI 规划）")
                        .font(.caption2)
                        .foregroundStyle(AuraTheme.secondaryText)

                    FlowTagsView(tags: profile.toleranceNotes, tint: AuraTheme.sageGreen) { note in
                        profile.toleranceNotes.removeAll { $0 == note }
                    }
                }
            } else {
                Text("每次完成阶段复诊转段后，系统会自动沉淀你的体质变化与食材/运动耐受反馈。")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("饮食忌口与运动偏好")
                .font(.headline)
                .foregroundStyle(AuraTheme.primaryText)

            VStack(alignment: .leading, spacing: 8) {
                Text("饮食偏好 / 忌口")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)

                FlowTagsView(tags: profile.dietaryPreferences, tint: AuraTheme.sageGreen) { tag in
                    profile.dietaryPreferences.removeAll { $0 == tag }
                }

                HStack {
                    TextField("添加忌口或偏好（如：忌冰饮）", text: $newDietTag)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button("添加") {
                        let trimmed = newDietTag.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, !profile.dietaryPreferences.contains(trimmed) else { return }
                        profile.dietaryPreferences.append(trimmed)
                        newDietTag = ""
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AuraTheme.sageGreen)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("运动习惯与限制")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)

                FlowTagsView(tags: profile.fitnessPreferences, tint: AuraTheme.inkSlate) { tag in
                    profile.fitnessPreferences.removeAll { $0 == tag }
                }

                HStack {
                    TextField("添加运动偏好（如：居家轻抗阻）", text: $newFitnessTag)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button("添加") {
                        let trimmed = newFitnessTag.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, !profile.fitnessPreferences.contains(trimmed) else { return }
                        profile.fitnessPreferences.append(trimmed)
                        newFitnessTag = ""
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AuraTheme.inkSlate)
                }
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var reportImportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("导入第三方体质报告", systemImage: "doc.text.viewfinder")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)

                Spacer()

                let recognizing = isRecognizingImage
                PhotosPicker(selection: $selectedReportImage, matching: .images) {
                    Label(recognizing ? "识别中…" : "截图识别", systemImage: "photo.on.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AuraTheme.sageGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AuraTheme.sageGreen.opacity(0.14), in: Capsule())
                }
                .disabled(recognizing)
            }

            Text("粘贴中医体质测试结果或体检摘要，或上传截图自动提取体质标签与饮食运动建议。")
                .font(.caption)
                .foregroundStyle(AuraTheme.secondaryText)

            TextEditor(text: $reportText)
                .font(.subheadline)
                .frame(minHeight: 96)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if reportText.isEmpty {
                        Text("示例：身高176.5cm，体重85kg，目标75kg，痰湿质78分，轻微气虚，忌生冷海鲜，偏好游泳和抗阻。")
                            .font(.caption)
                            .foregroundStyle(AuraTheme.secondaryText.opacity(0.6))
                            .padding(14)
                            .allowsHitTesting(false)
                    }
                }

            if let parseBannerMessage {
                Text(parseBannerMessage)
                    .font(.caption)
                    .foregroundStyle(AuraTheme.sageGreen)
            }

            HStack(spacing: 10) {
                Button {
                    reportText = "身高176.5cm，体重85kg，目标体重75kg，中医辨识：痰湿质78分，轻微气虚，肠胃敏感；忌生冷油腻与寒凉海鲜；适合室外游泳、居家轻抗阻。"
                } label: {
                    Text("填入示例文本")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AuraTheme.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AuraTheme.subtleSurface, in: Capsule())
                }

                Button {
                    applyParsedReport()
                } label: {
                    Text("解析并更新画像")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            reportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AuraTheme.secondaryText.opacity(0.35)
                            : AuraTheme.warmGinger,
                            in: Capsule()
                        )
                }
                .disabled(reportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private func handleReportImageSelection(_ item: PhotosPickerItem) async {
        isRecognizingImage = true
        defer { isRecognizingImage = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                parseBannerMessage = "未能读取所选图片，请重试。"
                return
            }
            let text = try await ConstitutionReportParser.recognizeText(from: image)
            if text.isEmpty {
                parseBannerMessage = "未在截图中识别到有效文字，可直接粘贴文本。"
            } else {
                reportText = text
                parseBannerMessage = "已完成本地 OCR 识别，点击「解析并更新画像」即可同步。"
            }
        } catch {
            parseBannerMessage = "截图识别失败：\(error.localizedDescription)"
        }
    }

    private func applyParsedReport() {
        let parsed = ConstitutionReportParser.parse(text: reportText)

        if let h = parsed.heightCM { profile.heightCM = h }
        if let w = parsed.weightKG { profile.weightKG = w }
        if let tw = parsed.targetWeightKG { profile.targetWeightKG = tw }

        if !parsed.constitutionTags.isEmpty {
            profile.constitutionTags = parsed.constitutionTags
        }
        for item in parsed.dietaryPreferences where !profile.dietaryPreferences.contains(item) {
            profile.dietaryPreferences.append(item)
        }
        for item in parsed.fitnessPreferences where !profile.fitnessPreferences.contains(item) {
            profile.fitnessPreferences.append(item)
        }

        profile.rawReportSummary = parsed.extractedText
        profile.constitutionConfidencePercent = max(profile.constitutionConfidencePercent, 84)
        profile.assessmentMethod = "报告解析"
        profile.needsCalibrationTrial = false
        profile.updatedAt = .now
        HapticFeedback.notify(.success)
        parseBannerMessage = "已更新画像：识别到 \(parsed.constitutionTags.count) 项体质特征。"
    }

    private var reopenOnboardingButton: some View {
        Button {
            dismiss()
            hasCompletedOnboarding = false
        } label: {
            Label("重新运行首次四诊合参建档引导", systemImage: "arrow.counterclockwise")
                .font(.caption.weight(.medium))
                .foregroundStyle(AuraTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AuraTheme.subtleSurface.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FlowTagsView: View {
    let tags: [String]
    let tint: Color
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(.caption.weight(.medium))
                    Button {
                        onRemove(tag)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint.opacity(0.13), in: Capsule())
            }
        }
    }
}

#Preview {
    let container = PreviewSupport.makeContainer()
    let profiles = (try? container.mainContext.fetch(FetchDescriptor<UserConstitutionProfile>())) ?? []
    return ProfileSheetView(profile: profiles.first!)
        .modelContainer(container)
}
