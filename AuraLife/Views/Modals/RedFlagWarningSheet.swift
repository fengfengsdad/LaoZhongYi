import SwiftUI

struct RedFlagWarningSheet: View {
    @Environment(\.dismiss) private var dismiss

    let assessment: RedFlagAssessment
    let onPauseAndLog: () -> Void
    let onOverrideFalsePositive: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    alertHeroCard
                    guidanceCard
                    falsePositiveCard
                }
                .padding(16)
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("安全红线熔断提示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(AuraTheme.secondaryText)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        HapticFeedback.notify(.warning)
                        onPauseAndLog()
                        dismiss()
                    } label: {
                        Text("暂缓今日食疗运动并记录观察")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.86), in: Capsule())
                    }

                    if assessment.allowsOverrideAsMild {
                        Button {
                            dismiss()
                            onOverrideFalsePositive()
                        } label: {
                            Text("已确认是食物/药物染色（如猪血、铁剂），按温和调理继续")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AuraTheme.secondaryText)
                                .padding(.vertical, 6)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(AuraTheme.canvasBackground.opacity(0.96))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var alertHeroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.title2)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text(assessment.category.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                    Text(assessment.headline)
                        .font(.headline)
                        .foregroundStyle(AuraTheme.primaryText)
                }
            }

            Text("「\(assessment.userInput)」")
                .font(.subheadline)
                .foregroundStyle(AuraTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !assessment.matchedKeywords.isEmpty {
                HStack(spacing: 6) {
                    Text("触发信号：")
                        .font(.caption2)
                        .foregroundStyle(AuraTheme.secondaryText)
                    ForEach(assessment.matchedKeywords, id: \.self) { kw in
                        Text(kw)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.11), in: Capsule())
                    }
                }
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.45), lineWidth: 1.2)
        )
    }

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("医疗边界与建议", systemImage: "cross.case.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AuraTheme.primaryText)

            Text(assessment.medicalGuidance)
                .font(.subheadline)
                .foregroundStyle(AuraTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(assessment.suggestedDepartment)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var falsePositiveCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AuraTheme.warmGinger)
                .padding(.top, 2)

            Text(assessment.falsePositiveHint)
                .font(.caption)
                .foregroundStyle(AuraTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraTheme.subtleSurface.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    RedFlagWarningSheet(
        assessment: RedFlagDetector.evaluate(input: "昨晚吃坏肚子了，今天大便黑黏")!,
        onPauseAndLog: {},
        onOverrideFalsePositive: {}
    )
}
