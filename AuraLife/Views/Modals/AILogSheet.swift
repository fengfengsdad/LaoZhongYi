import SwiftUI
import UIKit

struct AILogSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var store = AILogStore.shared

    @State private var copiedToast: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView(
                        "暂无 AI 请求日志",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("发起「生成3日计划」、状态打卡或「换一换」后，这里会实时显示请求地址、HTTP 状态、SSE 流式分片与报错详情。")
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(store.entries) { entry in
                                    logRow(entry)
                                        .id(entry.id)
                                }
                            }
                            .padding(12)
                        }
                        .onChange(of: store.entries.count) { _, _ in
                            if let lastID = store.entries.last?.id {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("AI 诊断日志 (\(store.entries.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button("清空") {
                            store.clear()
                        }
                        .foregroundStyle(AuraTheme.secondaryText)
                        .disabled(store.entries.isEmpty)

                        Button(copiedToast ? "已复制" : "复制全部") {
                            UIPasteboard.general.string = store.exportText()
                            HapticFeedback.impact(.light)
                            copiedToast = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                copiedToast = false
                            }
                        }
                        .foregroundStyle(AuraTheme.sageGreen)
                        .disabled(store.entries.isEmpty)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(AuraTheme.sageGreen)
                }
            }
        }
    }

    private func logRow(_ entry: AILogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.level.rawValue)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(color(for: entry.level))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color(for: entry.level).opacity(0.14), in: Capsule())

                Text(entry.category)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(AuraTheme.secondaryText)

                Spacer()

                Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AuraTheme.secondaryText)
            }

            Text(entry.message)
                .font(.caption.monospaced())
                .foregroundStyle(AuraTheme.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(entry.level == .error ? Color.red.opacity(0.35) : AuraTheme.hairline, lineWidth: 1)
        )
    }

    private func color(for level: AILogLevel) -> Color {
        switch level {
        case .debug:
            return AuraTheme.inkSlate
        case .info:
            return AuraTheme.sageGreen
        case .warning:
            return AuraTheme.warmGinger
        case .error:
            return .red
        }
    }
}

#Preview {
    AILogSheet()
}
