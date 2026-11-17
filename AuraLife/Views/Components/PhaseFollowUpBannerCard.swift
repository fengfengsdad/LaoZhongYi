import SwiftData
import SwiftUI

struct PhaseFollowUpBannerCard: View {
    let phase: RegimenPhase
    let referenceDate: Date
    let onStartFollowUp: () -> Void
    let onDismissToday: () -> Void

    var body: some View {
        let accent = phase.stageKind.accentColor

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg.text.clipboard")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)

                Text("阶段复诊节点 · \(phase.progressText(for: referenceDate))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AuraTheme.primaryText)

                Spacer()

                Button("今日先继续", action: onDismissToday)
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)
            }

            Text("对照转段标准：\(phase.exitCriteria)")
                .font(.caption)
                .foregroundStyle(AuraTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                HapticFeedback.impact(.light)
                onStartFollowUp()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stethoscope")
                        .font(.caption.weight(.semibold))
                    Text("记录今日体感并评估转段")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(accent, in: Capsule())
            }
        }
        .padding(14)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 1)
        )
    }
}

#Preview {
    let container = PreviewSupport.makeContainer()
    let phase = RegimenPhase(
        stageKind: .acuteRelief,
        phaseName: "急性祛湿恢复期",
        therapeuticPrinciple: "温中散寒、先护胃气，暂缓减重与生冷",
        exitCriteria: "排便成形不黏腻、胃脘温暖无胀闷且精神恢复",
        startDate: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
        plannedDays: 3
    )

    return ZStack {
        AuraTheme.canvasBackground.ignoresSafeArea()
        PhaseFollowUpBannerCard(
            phase: phase,
            referenceDate: .now,
            onStartFollowUp: {},
            onDismissToday: {}
        )
        .padding()
    }
    .modelContainer(container)
}
