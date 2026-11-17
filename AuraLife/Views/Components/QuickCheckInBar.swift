import PhotosUI
import SwiftUI
import UIKit

struct QuickCheckInBar: View {
    @Binding var inputText: String
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var photoIntent: PhotoCheckInIntent
    let attachedImage: UIImage?
    let recognizedPhotoText: String?
    let isProcessing: Bool
    let streamingStatus: String?
    let onClearAttachment: () -> Void
    let onTapLogs: () -> Void
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool
    @State private var showQuickChips: Bool = false

    private let quickPrompts = [
        "昨晚熬夜吃了螃蟹、大便发黏",
        "今天不想室外游泳，想改到室内",
        "晨起腰酸没胃口"
    ]

    private var canSubmit: Bool {
        !isProcessing && (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImage != nil)
    }

    var body: some View {
        VStack(spacing: 8) {
            if isProcessing, let streamingStatus {
                Button(action: onTapLogs) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(AuraTheme.sageGreen)
                        Text(streamingStatus)
                            .font(.caption)
                            .foregroundStyle(AuraTheme.primaryText)
                            .lineLimit(1)
                        Spacer()
                        Text("日志")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AuraTheme.sageGreen)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AuraTheme.cardSurface, in: Capsule())
                    .overlay(Capsule().stroke(AuraTheme.sageGreen.opacity(0.35), lineWidth: 1))
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if (isFocused || showQuickChips) && !isProcessing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPrompts, id: \.self) { prompt in
                            Button {
                                HapticFeedback.impact(.light)
                                inputText = prompt
                                onSubmit()
                                isFocused = false
                            } label: {
                                Text(prompt)
                                    .font(.caption)
                                    .foregroundStyle(AuraTheme.primaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(AuraTheme.cardSurface, in: Capsule())
                                    .overlay(
                                        Capsule().stroke(AuraTheme.hairline, lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let attachedImage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(uiImage: attachedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("已附照片 · \(photoIntent.rawValue)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AuraTheme.primaryText)

                            if let recognizedPhotoText, !recognizedPhotoText.isEmpty {
                                Text("已提取文字：\(recognizedPhotoText.replacingOccurrences(of: "\n", with: " "))")
                                    .font(.caption2)
                                    .foregroundStyle(AuraTheme.sageGreen)
                                    .lineLimit(1)
                            } else {
                                Text("发送后将结合气象与体质动态评估")
                                    .font(.caption2)
                                    .foregroundStyle(AuraTheme.secondaryText)
                            }
                        }

                        Spacer()

                        Button(action: onClearAttachment) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AuraTheme.secondaryText)
                        }
                        .disabled(isProcessing)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(PhotoCheckInIntent.allCases) { intent in
                                let selected = intent == photoIntent
                                Button {
                                    HapticFeedback.impact(.light)
                                    photoIntent = intent
                                } label: {
                                    Label(intent.rawValue, systemImage: intent.systemImage)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(selected ? .white : AuraTheme.secondaryText)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(selected ? AuraTheme.sageGreen : AuraTheme.subtleSurface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AuraTheme.hairline, lineWidth: 1)
                )
                .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "camera")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AuraTheme.secondaryText)
                        .frame(width: 34, height: 34)
                        .background(AuraTheme.subtleSurface, in: Circle())
                }
                .disabled(isProcessing)
                .accessibilityLabel("拍摄或选择舌象餐食报告照片")

                TextField("一句话状态打卡（如：昨晚熬夜吃了螃蟹）", text: $inputText, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(AuraTheme.primaryText)
                    .lineLimit(1...3)
                    .focused($isFocused)
                    .disabled(isProcessing)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSubmit {
                            onSubmit()
                            isFocused = false
                        }
                    }

                Button {
                    HapticFeedback.impact(.light)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        showQuickChips.toggle()
                    }
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(showQuickChips ? AuraTheme.warmGinger : AuraTheme.secondaryText)
                        .frame(width: 32, height: 32)
                }
                .disabled(isProcessing)
                .accessibilityLabel("展开常用状态快捷词")

                Button {
                    HapticFeedback.impact(.medium)
                    onSubmit()
                    isFocused = false
                } label: {
                    Group {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(
                        (canSubmit || isProcessing) ? AuraTheme.sageGreen : AuraTheme.secondaryText.opacity(0.35),
                        in: Circle()
                    )
                }
                .disabled(!canSubmit)
                .accessibilityLabel("发送状态并动态调整计划")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AuraTheme.cardSurface, in: Capsule())
            .overlay(
                Capsule().stroke(AuraTheme.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 16)
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [
                    AuraTheme.canvasBackground.opacity(0),
                    AuraTheme.canvasBackground.opacity(0.95),
                    AuraTheme.canvasBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        AuraTheme.canvasBackground.ignoresSafeArea()
        QuickCheckInBar(
            inputText: .constant(""),
            selectedPhotoItem: .constant(nil),
            photoIntent: .constant(.meal),
            attachedImage: nil,
            recognizedPhotoText: nil,
            isProcessing: true,
            streamingStatus: "正在流式生成结构化方案（已接收 128 字符）…",
            onClearAttachment: {},
            onTapLogs: {},
            onSubmit: {}
        )
    }
}
