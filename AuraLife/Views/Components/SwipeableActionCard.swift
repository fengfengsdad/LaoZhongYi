import SwiftData
import SwiftUI

struct SwipeableActionCard: View {
    let card: ActionCard
    let isLast: Bool
    let isSwapping: Bool
    let isCurrentFocus: Bool
    let onToggleComplete: () -> Void
    let onSwap: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isExpanded: Bool = false
    @State private var hasTriggeredThresholdHaptic = false

    private let triggerThreshold: CGFloat = 76
    private let maxSwipeOffset: CGFloat = 104

    private var accentColor: Color {
        AuraTheme.accent(for: card.category)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            timelineRail
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if isCurrentFocus && !card.isCompleted {
                        Circle()
                            .fill(AuraTheme.warmGinger)
                            .frame(width: 6, height: 6)
                    }

                    Text(card.timeSlot)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCurrentFocus && !card.isCompleted ? AuraTheme.primaryText : AuraTheme.secondaryText)

                    if isCurrentFocus && !card.isCompleted {
                        Text("当下顺时")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AuraTheme.warmGinger)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AuraTheme.warmGinger.opacity(0.14), in: Capsule())
                    }

                    Spacer()

                    Text(
                        isSwapping
                        ? "AI 正在换一换…"
                        : (card.isCompleted ? "已完成" : "左滑完成 · 右滑换一换")
                    )
                    .font(.caption2)
                    .foregroundStyle(isSwapping ? AuraTheme.warmGinger : AuraTheme.secondaryText.opacity(0.72))
                }

                ZStack {
                    swipeBackdrop
                    cardContent
                        .offset(x: dragOffset)
                        .gesture(swipeGesture)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var timelineRail: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(card.isCompleted ? AuraTheme.sageGreen : AuraTheme.cardSurface)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(card.isCompleted ? AuraTheme.sageGreen : accentColor, lineWidth: 2)
                    )

                if card.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            if !isLast {
                Rectangle()
                    .fill(AuraTheme.hairline)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 4)
            }
        }
        .frame(width: 18)
    }

    private var swipeBackdrop: some View {
        ZStack {
            if dragOffset > 6 {
                HStack {
                    Label("换一换", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.leading, 20)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AuraTheme.warmGinger)
            } else if dragOffset < -6 {
                HStack {
                    Spacer()
                    Label(
                        card.isCompleted ? "撤销完成" : "标记完成",
                        systemImage: card.isCompleted ? "arrow.uturn.backward" : "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.trailing, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AuraTheme.sageGreen)
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Label(card.category.displayName, systemImage: card.category.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.13), in: Capsule())

                if card.category == .diet {
                    Text("参考示范")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AuraTheme.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AuraTheme.subtleSurface, in: Capsule())
                }

                Spacer()

                Button {
                    onSwap()
                } label: {
                    Group {
                        if isSwapping {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(AuraTheme.warmGinger)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AuraTheme.secondaryText)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .background(AuraTheme.subtleSurface, in: Circle())
                }
                .disabled(isSwapping)
                .buttonStyle(.plain)
                .accessibilityLabel("换一换此项安排")

                Button {
                    HapticFeedback.impact(.medium)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        onToggleComplete()
                    }
                } label: {
                    Image(systemName: card.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(card.isCompleted ? AuraTheme.sageGreen : AuraTheme.secondaryText.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.isCompleted ? "取消完成" : "标记完成")
            }

            Text(card.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(card.isCompleted ? AuraTheme.secondaryText : AuraTheme.primaryText)
                .strikethrough(card.isCompleted, color: AuraTheme.secondaryText.opacity(0.6))

            Text(card.actionDetail)
                .font(.subheadline)
                .foregroundStyle(AuraTheme.secondaryText)
                .lineLimit(isExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(accentColor)
                    .padding(.top, 2)

                Text(card.reasoning)
                    .font(.caption)
                    .foregroundStyle(AuraTheme.primaryText.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AuraTheme.subtleSurface.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("核心原则：\(resolvedCorePrinciple)")
                        .font(.caption)
                        .foregroundStyle(AuraTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("弹性/加餐：\(resolvedFlexibleSwapHint)")
                        .font(.caption2)
                        .foregroundStyle(AuraTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if card.category == .diet {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                    Text("轻点卡片看核心原则与饿了怎么加餐")
                        .font(.caption2)
                }
                .foregroundStyle(AuraTheme.secondaryText.opacity(0.75))
            }
        }
        .padding(14)
        .background(AuraTheme.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isSwapping
                    ? AuraTheme.warmGinger.opacity(0.5)
                    : (isCurrentFocus && !card.isCompleted
                       ? AuraTheme.warmGinger.opacity(0.38)
                       : (card.isCompleted ? AuraTheme.sageGreen.opacity(0.32) : AuraTheme.hairline)),
                    lineWidth: isCurrentFocus && !card.isCompleted ? 1.4 : 1
                )
        )
        .opacity(card.isCompleted ? 0.78 : (isSwapping ? 0.85 : 1.0))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private var resolvedCorePrinciple: String {
        if !card.corePrinciple.isEmpty { return card.corePrinciple }
        switch card.category {
        case .diet:
            return "温热 + 优质蛋白 + 少油少甜，吃七八分饱即算达标"
        case .fitness:
            return "护膝低冲击、微汗通络不透支"
        case .lifestyle:
            return "顺应夜间阴血潜藏节奏，助次日精力恢复"
        }
    }

    private var resolvedFlexibleSwapHint: String {
        if !card.flexibleSwapHint.isEmpty { return card.flexibleSwapHint }
        switch card.category {
        case .diet:
            return "不必死守菜名！吃不惯可换同类清炖/白灼蛋白；真饿了从「调养」页绿灯区加餐，不必硬扛。"
        case .fitness:
            return "太忙或天冷时，改成室内 15 分钟八段锦或靠墙静蹲同样有效。"
        case .lifestyle:
            return "太累时简化成热水泡脚 10 分钟后早睡即可。"
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard !isSwapping, abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                let clamped = max(-maxSwipeOffset, min(maxSwipeOffset, value.translation.width))
                dragOffset = clamped

                if abs(clamped) >= triggerThreshold && !hasTriggeredThresholdHaptic {
                    HapticFeedback.impact(.soft)
                    hasTriggeredThresholdHaptic = true
                } else if abs(clamped) < triggerThreshold {
                    hasTriggeredThresholdHaptic = false
                }
            }
            .onEnded { value in
                guard !isSwapping else { return }
                let finalOffset = value.translation.width
                if finalOffset <= -triggerThreshold {
                    HapticFeedback.impact(.medium)
                    onToggleComplete()
                } else if finalOffset >= triggerThreshold {
                    HapticFeedback.impact(.light)
                    onSwap()
                }

                hasTriggeredThresholdHaptic = false
                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                    dragOffset = 0
                }
            }
    }
}

#Preview {
    let container = PreviewSupport.makeContainer()
    let cards = (try? container.mainContext.fetch(FetchDescriptor<ActionCard>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []

    return ZStack {
        AuraTheme.canvasBackground.ignoresSafeArea()
        VStack(spacing: 16) {
            ForEach(Array(cards.prefix(2).enumerated()), id: \.element.id) { index, card in
                SwipeableActionCard(
                    card: card,
                    isLast: index == 1,
                    isSwapping: index == 1,
                    isCurrentFocus: index == 0,
                    onToggleComplete: { card.isCompleted.toggle() },
                    onSwap: {}
                )
            }
        }
        .padding()
    }
}
