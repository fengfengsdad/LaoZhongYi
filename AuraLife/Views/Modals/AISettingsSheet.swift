import SwiftUI

struct AISettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var config: AIConfiguration = AIConfiguration.load()
    @State private var showAPIKey: Bool = false
    @State private var statusBanner: String?
    @State private var isTestingConnection: Bool = false
    @State private var testResultMessage: String?
    @State private var testResultIsError: Bool = false
    @State private var isShowingLogs: Bool = false

    let onConfigurationUpdated: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    engineStatusCard
                    providerPickerCard
                    endpointAndKeyCard
                    proxySettingsCard
                    diagnosticsCard
                    streamingInfoCard
                }
                .padding(16)
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("AI 动态引擎配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(AuraTheme.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        config.save()
                        HapticFeedback.notify(.success)
                        onConfigurationUpdated()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AuraTheme.sageGreen)
                }
            }
            .sheet(isPresented: $isShowingLogs) {
                AILogSheet()
            }
        }
    }

    private var engineStatusCard: some View {
        let isLive = config.hasValidKey

        return HStack(spacing: 12) {
            Image(systemName: isLive ? "sparkles.rectangle.stack.fill" : "cpu")
                .font(.title2)
                .foregroundStyle(isLive ? AuraTheme.sageGreen : AuraTheme.warmGinger)

            VStack(alignment: .leading, spacing: 4) {
                Text(isLive ? "已就绪：云端 Structured Outputs 模式" : "当前为离线演示引擎（未填写 API Key）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AuraTheme.primaryText)

                Text(
                    isLive
                    ? "将使用 \(config.provider.displayName)（\(config.model)）强制 JSON Schema 输出。"
                    : "未填写 Key 时仍可体验完整 SSE 进度、3 日方案生成、状态打卡 Diff 与换一换。"
                )
                .font(.caption)
                .foregroundStyle(AuraTheme.secondaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AuraTheme.hairline, lineWidth: 1)
        )
    }

    private var providerPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("模型服务商")
                .font(.headline)
                .foregroundStyle(AuraTheme.primaryText)

            Picker("服务商", selection: $config.provider) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: config.provider) { _, newProvider in
                let savedForProvider = KeychainHelper.read(account: newProvider.keychainAccount)
                config.apiKey = savedForProvider
                config.baseURL = UserDefaults.standard.string(forKey: "auralife.ai.baseURL.\(newProvider.rawValue)")
                    ?? newProvider.defaultBaseURL
                config.model = UserDefaults.standard.string(forKey: "auralife.ai.model.\(newProvider.rawValue)")
                    ?? newProvider.defaultModel
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var endpointAndKeyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("接口与密钥（Keychain 安全存储）")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)

                Spacer()

                Button("恢复默认") {
                    config.baseURL = config.provider.defaultBaseURL
                    config.model = config.provider.defaultModel
                    statusBanner = "已重置为 \(config.provider.displayName) 默认地址与模型"
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AuraTheme.sageGreen)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Base URL")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)
                TextField(config.provider.defaultBaseURL, text: $config.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.subheadline)
                    .padding(10)
                    .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("模型名称 (Model)")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)
                TextField(config.provider.defaultModel, text: $config.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .padding(10)
                    .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("API Key")
                        .font(.caption)
                        .foregroundStyle(AuraTheme.secondaryText)
                    Spacer()
                    Button(showAPIKey ? "隐藏" : "显示") {
                        showAPIKey.toggle()
                    }
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)
                }

                Group {
                    if showAPIKey {
                        TextField("sk-... / AIza...", text: $config.apiKey)
                    } else {
                        SecureField("sk-... / AIza...（留空则使用离线演示引擎）", text: $config.apiKey)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .padding(10)
                .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Toggle("启用 SSE 流式输出 (Server-Sent Events)", isOn: $config.enableStreaming)
                .font(.subheadline)
                .tint(AuraTheme.sageGreen)

            if let statusBanner {
                Text(statusBanner)
                    .font(.caption)
                    .foregroundStyle(AuraTheme.sageGreen)
            }

            Button {
                Task {
                    await runConnectionTest()
                }
            } label: {
                HStack(spacing: 8) {
                    if isTestingConnection {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "bolt.horizontal.circle.fill")
                    }
                    Text(isTestingConnection ? "正在测试连通性…" : "测试当前配置连通性")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    config.hasValidKey ? AuraTheme.sageGreen : AuraTheme.secondaryText.opacity(0.35),
                    in: Capsule()
                )
            }
            .disabled(!config.hasValidKey || isTestingConnection)

            if let testResultMessage {
                Text(testResultMessage)
                    .font(.caption)
                    .foregroundStyle(testResultIsError ? Color.red : AuraTheme.sageGreen)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var proxySettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("启用 HTTP 代理（用于模拟器/局域网代理）", isOn: $config.enableProxy)
                .font(.subheadline.weight(.semibold))
                .tint(AuraTheme.warmGinger)

            if config.enableProxy {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("代理主机 (Host)")
                            .font(.caption)
                            .foregroundStyle(AuraTheme.secondaryText)
                        TextField("127.0.0.1", text: $config.proxyHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .font(.subheadline)
                            .padding(10)
                            .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("端口 (Port)")
                            .font(.caption)
                            .foregroundStyle(AuraTheme.secondaryText)
                        TextField("7890", text: $config.proxyPort)
                            .keyboardType(.numberPad)
                            .font(.subheadline)
                            .padding(10)
                            .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .frame(width: 96)
                }

                HStack {
                    Text("iOS 模拟器可直接填 Mac 本地代理端口（如 127.0.0.1:7890）；真机请填 Mac 局域网 IP 并开启允许局域网连接。")
                        .font(.caption2)
                        .foregroundStyle(AuraTheme.secondaryText)

                    Spacer(minLength: 8)

                    Button("填 127.0.0.1:7890") {
                        config.proxyHost = "127.0.0.1"
                        config.proxyPort = "7890"
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AuraTheme.warmGinger)
                }
            } else {
                Text("若直连 Google / OpenAI 超时（URLError -1001），可开启此处代理或填写中转 Base URL。")
                    .font(.caption2)
                    .foregroundStyle(AuraTheme.secondaryText)
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var diagnosticsCard: some View {
        Button {
            isShowingLogs = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.inkSlate)
                    .frame(width: 34, height: 34)
                    .background(AuraTheme.subtleSurface, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("查看 AI 请求诊断日志")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AuraTheme.primaryText)
                    Text("实时查看请求 URL、HTTP 状态码、SSE 分片与报错详情")
                        .font(.caption)
                        .foregroundStyle(AuraTheme.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AuraTheme.secondaryText)
            }
            .padding(14)
            .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var streamingInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("三层决策漏斗 + JSON Schema 约束", systemImage: "shield.checkered")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AuraTheme.primaryText)

            Text("1. 安全与急症优先：突发肠胃不适、受寒或熬夜自动覆盖长期减重/进补目标。\n2. 环境与约束适配：结合天气与就餐/运动偏好自动切换方案。\n3. 循证可解释性：每张卡片强制输出 ≤30 字的 reasoning 理由。")
                .font(.caption)
                .foregroundStyle(AuraTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraTheme.subtleSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func runConnectionTest() async {
        isTestingConnection = true
        testResultMessage = nil
        defer { isTestingConnection = false }

        let snapshotConfig = config
        do {
            let result = try await AIService.shared.testConnection(config: snapshotConfig)
            testResultIsError = false
            testResultMessage = result
            HapticFeedback.notify(.success)
        } catch {
            testResultIsError = true
            testResultMessage = error.localizedDescription
            HapticFeedback.notify(.error)
        }
    }
}

#Preview {
    AISettingsSheet(onConfigurationUpdated: {})
}
