import SwiftUI

struct SymptomTriageSheet: View {
    let session: SymptomTriageSession
    let isSubmitting: Bool
    let onSubmitAnswers: ([AITriageAnswer], String) -> Void
    let onCancel: () -> Void

    @State private var selectedOptions: [String: String] = [:]
    @State private var extraNote: String = ""

    private var allQuestionsAnswered: Bool {
        session.questions.allSatisfy { selectedOptions[$0.id] != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    ForEach(Array(session.questions.enumerated()), id: \.element.id) { index, item in
                        questionCard(index: index + 1, item: item)
                    }

                    extraNoteCard
                }
                .padding(16)
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("轻问诊 · 辨证追问")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                        .foregroundStyle(AuraTheme.secondaryText)
                        .disabled(isSubmitting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let answers = session.questions.compactMap { q -> AITriageAnswer? in
                        guard let picked = selectedOptions[q.id] else { return nil }
                        return AITriageAnswer(id: q.id, question: q.question, selectedOption: picked)
                    }
                    HapticFeedback.impact(.medium)
                    onSubmitAnswers(answers, extraNote)
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(isSubmitting ? "正在依据辨证生成方案…" : "确认辨证并生成调整方案")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        (allQuestionsAnswered && !isSubmitting)
                        ? AuraTheme.sageGreen
                        : AuraTheme.secondaryText.opacity(0.35),
                        in: Capsule()
                    )
                }
                .disabled(!allQuestionsAnswered || isSubmitting)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(AuraTheme.canvasBackground.opacity(0.95))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "stethoscope")
                    .foregroundStyle(AuraTheme.warmGinger)
                Text("先辨寒热虚实，再定饮食方案")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)

                Spacer()

                Text(session.source.rawValue)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AuraTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AuraTheme.subtleSurface, in: Capsule())
            }

            Text("「\(session.userInput)」")
                .font(.subheadline)
                .foregroundStyle(AuraTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(session.clarificationReason)
                .font(.footnote)
                .foregroundStyle(AuraTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AuraTheme.warmGinger.opacity(0.3), lineWidth: 1)
        )
    }

    private func questionCard(index: Int, item: AITriageQuestionPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(index). \(item.question)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AuraTheme.primaryText)

            VStack(spacing: 8) {
                ForEach(item.options, id: \.self) { option in
                    let isSelected = selectedOptions[item.id] == option
                    Button {
                        HapticFeedback.impact(.light)
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedOptions[item.id] = option
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? AuraTheme.sageGreen : AuraTheme.secondaryText.opacity(0.5))

                            Text(option)
                                .font(.subheadline)
                                .foregroundStyle(AuraTheme.primaryText)
                                .multilineTextAlignment(.leading)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            isSelected ? AuraTheme.sageGreen.opacity(0.12) : AuraTheme.subtleSurface.opacity(0.85),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? AuraTheme.sageGreen.opacity(0.55) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
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

    private var extraNoteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("补充体感（可选）")
                .font(.caption.weight(.medium))
                .foregroundStyle(AuraTheme.secondaryText)

            TextField("例如：伴有轻微恶心 / 昨晚还喝了冰镇啤酒", text: $extraNote)
                .font(.subheadline)
                .padding(10)
                .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(isSubmitting)
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
    SymptomTriageSheet(
        session: SymptomTriageSession(
            userInput: "昨晚吃坏肚子了",
            clarificationReason: "「肠胃不适」在中医里寒湿与湿热食养截然相反（姜饮只适合偏寒），先确认 2 个细节：",
            questions: [
                AITriageQuestionPayload(
                    id: "gi_stool",
                    question: "腹部与排便更偏向哪种感受？",
                    options: ["偏水样清稀 / 腹部怕凉", "偏黏腻臭秽 / 肛门灼热", "只是胃胀隐痛 / 暂无腹泻"]
                ),
                AITriageQuestionPayload(
                    id: "gi_thermal",
                    question: "伴随的口渴与寒热体感？",
                    options: ["偏怕冷手脚凉 / 喜热饮", "口干口苦 / 想喝凉水", "仅觉乏力 / 均不明显"]
                )
            ],
            source: .offlineDemo
        ),
        isSubmitting: false,
        onSubmitAnswers: { _, _ in },
        onCancel: {}
    )
}
