import Foundation
import Network
import UIKit

enum AIServiceError: LocalizedError {
    case invalidURL(String)
    case missingAPIKey
    case invalidResponse(statusCode: Int, message: String)
    case emptyOutput
    case decodingFailed(rawText: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            return "AI 接口地址无效：\(url)"
        case .missingAPIKey:
            return "未配置 API Key。"
        case let .invalidResponse(statusCode, message):
            let preview = message.count > 160 ? String(message.prefix(160)) + "…" : message
            return "AI 接口返回错误 (\(statusCode))：\(preview)"
        case .emptyOutput:
            return "AI 未返回有效内容（请打开诊断日志查看原始响应）。"
        case let .decodingFailed(_, underlying):
            return "结构化 JSON 解析失败：\(underlying.localizedDescription)"
        }
    }
}

enum AIServiceSource: String, Sendable {
    case liveLLM = "云端 LLM"
    case offlineDemo = "离线演示引擎"
}

struct AIGenerationResult<T: Sendable>: Sendable {
    let payload: T
    let source: AIServiceSource
}

actor AIService {
    static let shared = AIService()

    private let customSession: URLSession?

    init(session: URLSession? = nil) {
        self.customSession = session
    }

    private func makeSession(for config: AIConfiguration) -> URLSession {
        if let customSession {
            return customSession
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false

        let trimmedHost = config.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if config.enableProxy,
           !trimmedHost.isEmpty,
           let portValue = config.resolvedProxyPort,
           let nwPort = NWEndpoint.Port(rawValue: portValue) {
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(trimmedHost), port: nwPort)
            let proxyConfig = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)
            configuration.proxyConfigurations = [proxyConfig]
            AILog.info("Proxy", "已启用 HTTP 代理 \(trimmedHost):\(portValue)")
        }

        return URLSession(configuration: configuration)
    }

    func testConnection(config: AIConfiguration) async throws -> String {
        let startedAt = Date()
        let session = makeSession(for: config)
        defer {
            if customSession == nil {
                session.finishTasksAndInvalidate()
            }
        }

        var testConfig = config
        testConfig.enableStreaming = false

        let request = try buildURLRequest(
            config: testConfig,
            systemPrompt: "你是连通性测试助手。",
            userPrompt: "请输出：{\"title\":\"连通正常\",\"actionDetail\":\"测试通过\",\"reasoning\":\"接口连通性验证成功\"}",
            encodedImages: [],
            schemaName: AIStructuredSchemas.cardSwapSchemaName,
            schema: AIStructuredSchemas.cardSwapSchema
        )

        AILog.info("Test", "开始连通性测试 -> \(request.url?.absoluteString ?? "<nil>") | key=\(AILog.maskSecret(config.apiKey))")
        let responseText = try await performNonStreamingRequest(
            request: request,
            provider: config.provider,
            session: session
        )
        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(startedAt))
        AILog.info("Test", "连通性测试成功 (耗时 \(elapsed)): \(Self.truncateForLog(responseText, limit: 200))")
        return "连接成功（耗时 \(elapsed)）"
    }

    // MARK: - Public Capabilities

    func generateMultiDayPlan(
        daysCount: Int = 3,
        profile: AIProfileContext?,
        snapshot: AISnapshotContext,
        onStreamProgress: @Sendable (String) -> Void
    ) async throws -> AIGenerationResult<AIMultiDayPlanResponse> {
        let config = AIConfiguration.load()
        AILog.info("AIService", "发起「生成\(daysCount)日计划」 provider=\(config.provider.rawValue), model=\(config.model), streaming=\(config.enableStreaming), hasKey=\(config.hasValidKey)")

        guard config.hasValidKey else {
            AILog.info("AIService", "未检测到 API Key，走离线演示引擎")
            let demo = try await simulateStreaming(
                steps: [
                    "正在分析体质画像与 \(snapshot.city) \(Int(snapshot.weatherTempC.rounded()))°C 天气…",
                    "正在执行三层决策漏斗，编排未来 \(daysCount) 日顺时方案…",
                    "正在校验 JSON Schema 与循证理由（≤30字）…"
                ],
                onStreamProgress: onStreamProgress
            ) {
                Self.offlineMultiDayPlan(daysCount: daysCount, profile: profile, snapshot: snapshot)
            }
            return AIGenerationResult(payload: demo, source: .offlineDemo)
        }

        let prompt = AIPromptBuilder.multiDayPlanPrompt(
            daysCount: daysCount,
            profile: profile,
            snapshot: snapshot
        )

        let payload: AIMultiDayPlanResponse = try await executeStructuredRequest(
            config: config,
            systemPrompt: AIPromptBuilder.systemPrompt,
            userPrompt: prompt,
            images: [],
            schemaName: AIStructuredSchemas.multiDayPlanSchemaName,
            schema: AIStructuredSchemas.multiDayPlanSchema,
            onStreamProgress: onStreamProgress
        )
        return AIGenerationResult(payload: payload, source: .liveLLM)
    }

    func proposeContextualAdjustment(
        userInput: String,
        triageAnswers: [AITriageAnswer] = [],
        extraTriageNote: String? = nil,
        bypassRedFlag: Bool = false,
        attachedImage: UIImage?,
        photoIntent: PhotoCheckInIntent = .auto,
        recognizedPhotoText: String? = nil,
        profile: AIProfileContext?,
        snapshots: [AISnapshotContext],
        onStreamProgress: @Sendable (String) -> Void
    ) async throws -> AIGenerationResult<AIAdjustmentResponse> {
        let config = AIConfiguration.load()
        AILog.info("AIService", "发起「动态微调」 input=\"\(userInput)\", triageAnswers=\(triageAnswers.count), bypassRedFlag=\(bypassRedFlag), hasImage=\(attachedImage != nil), intent=\(photoIntent.rawValue), provider=\(config.provider.rawValue), model=\(config.model), streaming=\(config.enableStreaming), hasKey=\(config.hasValidKey)")

        guard config.hasValidKey, let primarySnapshot = snapshots.first else {
            AILog.info("AIService", "未检测到 API Key（或快照为空），走离线演示引擎")
            let fallbackSnapshot = snapshots.first ?? AISnapshotContext()
            let demo = try await simulateStreaming(
                steps: [
                    "正在结合 \(fallbackSnapshot.city) \(Int(fallbackSnapshot.weatherTempC.rounded()))°C \(fallbackSnapshot.weatherCondition)与\(fallbackSnapshot.solarTermName)节气…",
                    triageAnswers.isEmpty ? "正在评估安全红线与寒热虚实…" : "正在依据轻问诊结果匹配证型与治则…",
                    "正在生成结构化评估结果…"
                ],
                onStreamProgress: onStreamProgress
            ) {
                LocalContextPlanner.evaluateOfflineAdjustment(
                    input: userInput,
                    triageAnswers: triageAnswers,
                    extraTriageNote: extraTriageNote,
                    bypassRedFlag: bypassRedFlag,
                    hasAttachedImage: attachedImage != nil,
                    photoIntent: photoIntent,
                    recognizedPhotoText: recognizedPhotoText,
                    diningEnvironment: profile?.diningEnvironment,
                    dietaryPreferences: profile?.dietaryPreferences ?? [],
                    snapshot: fallbackSnapshot
                )
            }
            return AIGenerationResult(payload: demo, source: .offlineDemo)
        }

        _ = primarySnapshot
        let prompt = AIPromptBuilder.adjustmentPrompt(
            userInput: userInput,
            triageAnswers: triageAnswers,
            extraTriageNote: extraTriageNote,
            hasAttachedImage: attachedImage != nil,
            photoIntent: photoIntent,
            recognizedPhotoText: recognizedPhotoText,
            profile: profile,
            snapshots: snapshots
        )

        let payload: AIAdjustmentResponse = try await executeStructuredRequest(
            config: config,
            systemPrompt: AIPromptBuilder.systemPrompt,
            userPrompt: prompt,
            images: attachedImage.map { [$0] } ?? [],
            schemaName: AIStructuredSchemas.adjustmentSchemaName,
            schema: AIStructuredSchemas.adjustmentSchema,
            onStreamProgress: onStreamProgress
        )
        return AIGenerationResult(payload: payload, source: .liveLLM)
    }

    func swapSingleCard(
        card: AIActionCardContext,
        profile: AIProfileContext?,
        snapshot: AISnapshotContext,
        onStreamProgress: @Sendable (String) -> Void
    ) async throws -> AIGenerationResult<AICardSwapResponse> {
        let config = AIConfiguration.load()
        AILog.info("AIService", "发起「单卡换一换」 card=\"\(card.title)\", provider=\(config.provider.rawValue), model=\(config.model), streaming=\(config.enableStreaming), hasKey=\(config.hasValidKey)")

        guard config.hasValidKey else {
            AILog.info("AIService", "未检测到 API Key，走离线演示引擎")
            let demo = try await simulateStreaming(
                steps: [
                    "正在检索「\(card.category.displayName)」替代方案…",
                    "正在校验体质禁忌与天气适配…"
                ],
                onStreamProgress: onStreamProgress
            ) {
                let fallback = LocalContextPlanner.swapAlternative(
                    category: card.category,
                    excludingTitle: card.title,
                    isAcuteRecovery: snapshot.isAcuteRecovery,
                    weatherTempC: snapshot.weatherTempC,
                    weatherCondition: snapshot.weatherCondition,
                    city: snapshot.city,
                    diningEnvironment: profile?.diningEnvironment,
                    dietaryPreferences: profile?.dietaryPreferences ?? []
                )
                return AICardSwapResponse(
                    title: fallback.title,
                    actionDetail: fallback.detail,
                    reasoning: fallback.reasoning
                )
            }
            return AIGenerationResult(payload: demo, source: .offlineDemo)
        }

        let prompt = AIPromptBuilder.swapCardPrompt(
            card: card,
            profile: profile,
            snapshot: snapshot
        )

        let payload: AICardSwapResponse = try await executeStructuredRequest(
            config: config,
            systemPrompt: AIPromptBuilder.systemPrompt,
            userPrompt: prompt,
            images: [],
            schemaName: AIStructuredSchemas.cardSwapSchemaName,
            schema: AIStructuredSchemas.cardSwapSchema,
            onStreamProgress: onStreamProgress
        )
        return AIGenerationResult(payload: payload, source: .liveLLM)
    }

    func evaluatePhaseFollowUp(
        outcome: FollowUpOutcome,
        userNote: String,
        profile: AIProfileContext?,
        snapshot: AISnapshotContext,
        onStreamProgress: @Sendable (String) -> Void
    ) async throws -> AIGenerationResult<AIPhaseTransitionResponse> {
        let config = AIConfiguration.load()
        AILog.info("AIService", "发起「复诊转段评估」 outcome=\(outcome.rawValue), currentStage=\(snapshot.activePhase?.stageKind.rawValue ?? "none"), provider=\(config.provider.rawValue)")

        guard config.hasValidKey else {
            let demo = try await simulateStreaming(
                steps: [
                    "正在对照转段标准评估当前阶段恢复度…",
                    "正在推演下一调理阶段与治法总则…",
                    "正在生成今日顺时食养与导引卡片…"
                ],
                onStreamProgress: onStreamProgress
            ) {
                LocalContextPlanner.offlinePhaseTransition(
                    outcome: outcome,
                    userNote: userNote,
                    profile: profile,
                    snapshot: snapshot
                )
            }
            return AIGenerationResult(payload: demo, source: .offlineDemo)
        }

        let prompt = AIPromptBuilder.phaseFollowUpPrompt(
            outcome: outcome,
            userNote: userNote,
            profile: profile,
            snapshot: snapshot
        )

        let payload: AIPhaseTransitionResponse = try await executeStructuredRequest(
            config: config,
            systemPrompt: AIPromptBuilder.systemPrompt,
            userPrompt: prompt,
            images: [],
            schemaName: AIStructuredSchemas.phaseTransitionSchemaName,
            schema: AIStructuredSchemas.phaseTransitionSchema,
            onStreamProgress: onStreamProgress
        )
        return AIGenerationResult(payload: payload, source: .liveLLM)
    }

    // MARK: - Phase 9: Onboarding Adaptive Assessment

    func generateAdaptiveOnboardingFollowUp(
        heightCM: Double,
        weightKG: Double,
        targetWeightKG: Double,
        baseAnswers: [OnboardingInquiryAnswer],
        voiceTranscript: String = "",
        acousticSummary: String? = nil,
        reportText: String,
        hasTongueImage: Bool,
        hasFaceImage: Bool = false,
        city: String,
        weatherTempC: Double,
        weatherCondition: String
    ) async throws -> AIGenerationResult<AIOnboardingFollowUpResponse> {
        let config = AIConfiguration.load()
        AILog.info("AIService", "发起「建档十问歌自适应追问」 baseAnswers=\(baseAnswers.count), hasVoice=\(!voiceTranscript.isEmpty), hasTongue=\(hasTongueImage), hasFace=\(hasFaceImage)")

        guard config.hasValidKey else {
            try await Task.sleep(for: .milliseconds(320))
            let demo = LocalContextPlanner.offlineOnboardingFollowUp(
                baseAnswers: baseAnswers,
                voiceTranscript: voiceTranscript,
                reportText: reportText,
                hasTongueImage: hasTongueImage,
                hasFaceImage: hasFaceImage
            )
            return AIGenerationResult(payload: demo, source: .offlineDemo)
        }

        let prompt = AIPromptBuilder.onboardingFollowUpPrompt(
            heightCM: heightCM,
            weightKG: weightKG,
            targetWeightKG: targetWeightKG,
            baseAnswers: baseAnswers,
            voiceTranscript: voiceTranscript,
            acousticSummary: acousticSummary,
            reportText: reportText,
            hasTongueImage: hasTongueImage,
            hasFaceImage: hasFaceImage,
            city: city,
            weatherTempC: weatherTempC,
            weatherCondition: weatherCondition
        )

        let payload: AIOnboardingFollowUpResponse = try await executeStructuredRequest(
            config: config,
            systemPrompt: AIPromptBuilder.systemPrompt,
            userPrompt: prompt,
            images: [],
            schemaName: AIStructuredSchemas.onboardingFollowUpSchemaName,
            schema: AIStructuredSchemas.onboardingFollowUpSchema,
            onStreamProgress: { _ in }
        )
        return AIGenerationResult(payload: payload, source: .liveLLM)
    }

    func evaluateOnboardingConstitution(
        heightCM: Double,
        weightKG: Double,
        targetWeightKG: Double,
        diningEnvironment: String,
        dietaryPreferences: [String],
        fitnessPreferences: [String],
        allAnswers: [OnboardingInquiryAnswer],
        voiceTranscript: String = "",
        acousticSummary: String? = nil,
        reportText: String,
        tongueImage: UIImage?,
        faceImage: UIImage? = nil,
        city: String,
        weatherTempC: Double,
        weatherCondition: String,
        weatherHumidity: Double,
        onStreamProgress: @Sendable (String) -> Void
    ) async throws -> AIGenerationResult<AIOnboardingConstitutionResponse> {
        let config = AIConfiguration.load()
        AILog.info("AIService", "发起「建档四诊合参综合辨证」 answers=\(allAnswers.count), hasVoice=\(!voiceTranscript.isEmpty), hasTongue=\(tongueImage != nil), hasFace=\(faceImage != nil), provider=\(config.provider.rawValue)")

        guard config.hasValidKey else {
            let demo = try await simulateStreaming(
                steps: [
                    "正在综合十问歌与语音主诉、\(city) \(Int(weatherTempC.rounded()))°C 气象基线…",
                    (tongueImage != nil || faceImage != nil) ? "正在融合自然光舌象与面色特征…" : "正在评估初筛置信度与试探校准需求…",
                    "正在整理老中医初诊医嘱总结…"
                ],
                onStreamProgress: onStreamProgress
            ) {
                LocalContextPlanner.offlineOnboardingAssessment(
                    heightCM: heightCM,
                    weightKG: weightKG,
                    targetWeightKG: targetWeightKG,
                    diningEnvironment: diningEnvironment,
                    dietaryPreferences: dietaryPreferences,
                    fitnessPreferences: fitnessPreferences,
                    allAnswers: allAnswers,
                    voiceTranscript: voiceTranscript,
                    acousticSummary: acousticSummary,
                    reportText: reportText,
                    hasTongueImage: tongueImage != nil,
                    hasFaceImage: faceImage != nil,
                    city: city,
                    weatherTempC: weatherTempC,
                    weatherCondition: weatherCondition,
                    weatherHumidity: weatherHumidity
                )
            }
            return AIGenerationResult(payload: demo, source: .offlineDemo)
        }

        let prompt = AIPromptBuilder.onboardingAssessmentPrompt(
            heightCM: heightCM,
            weightKG: weightKG,
            targetWeightKG: targetWeightKG,
            diningEnvironment: diningEnvironment,
            dietaryPreferences: dietaryPreferences,
            fitnessPreferences: fitnessPreferences,
            allAnswers: allAnswers,
            voiceTranscript: voiceTranscript,
            acousticSummary: acousticSummary,
            reportText: reportText,
            hasTongueImage: tongueImage != nil,
            hasFaceImage: faceImage != nil,
            city: city,
            weatherTempC: weatherTempC,
            weatherCondition: weatherCondition,
            weatherHumidity: weatherHumidity
        )

        let attachedImages = [tongueImage, faceImage].compactMap { $0 }
        let payload: AIOnboardingConstitutionResponse = try await executeStructuredRequest(
            config: config,
            systemPrompt: AIPromptBuilder.systemPrompt,
            userPrompt: prompt,
            images: attachedImages,
            schemaName: AIStructuredSchemas.onboardingAssessmentSchemaName,
            schema: AIStructuredSchemas.onboardingAssessmentSchema,
            onStreamProgress: onStreamProgress
        )
        return AIGenerationResult(payload: payload, source: .liveLLM)
    }

    // MARK: - Core Structured Outputs + SSE Request Executor

    private func executeStructuredRequest<T: Decodable & Sendable>(
        config: AIConfiguration,
        systemPrompt: String,
        userPrompt: String,
        images: [UIImage] = [],
        schemaName: String,
        schema: [String: Any],
        onStreamProgress: @Sendable (String) -> Void
    ) async throws -> T {
        let startedAt = Date()
        let encodedImages = images.compactMap { encodeJPEGDataURL(from: $0) }
        let request = try buildURLRequest(
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            encodedImages: encodedImages,
            schemaName: schemaName,
            schema: schema
        )

        AILog.info(
            "HTTP",
            "准备请求 \(request.httpMethod ?? "POST") \(request.url?.absoluteString ?? "<nil>") | body=\(request.httpBody?.count ?? 0) bytes | key=\(AILog.maskSecret(config.apiKey))"
        )

        let session = makeSession(for: config)
        defer {
            if customSession == nil {
                session.finishTasksAndInvalidate()
            }
        }

        let rawJSONText: String
        do {
            if config.enableStreaming {
                onStreamProgress("正在连接 \(config.provider.displayName)…")
                rawJSONText = try await performSSERequest(
                    request: request,
                    provider: config.provider,
                    session: session,
                    onStreamProgress: onStreamProgress
                )
            } else {
                onStreamProgress("正在等待 \(config.provider.displayName) 结构化响应…")
                rawJSONText = try await performNonStreamingRequest(
                    request: request,
                    provider: config.provider,
                    session: session
                )
            }
        } catch {
            let elapsed = String(format: "%.2fs", Date().timeIntervalSince(startedAt))
            if let urlError = error as? URLError {
                AILog.error("Network", "请求失败 (耗时 \(elapsed)) URLError code=\(urlError.code.rawValue): \(urlError.localizedDescription)")
            } else {
                AILog.error("Network", "请求失败 (耗时 \(elapsed)): \(error.localizedDescription)")
            }
            throw error
        }

        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(startedAt))
        AILog.info("AIService", "收到完整文本 (耗时 \(elapsed), 长度 \(rawJSONText.count)): \(Self.truncateForLog(rawJSONText, limit: 600))")

        let cleanedJSON = Self.extractJSONObject(from: rawJSONText)
        guard let data = cleanedJSON.data(using: .utf8), !cleanedJSON.isEmpty else {
            AILog.error("Decode", "提取后的 JSON 为空，原始文本：\(Self.truncateForLog(rawJSONText, limit: 400))")
            throw AIServiceError.emptyOutput
        }

        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            AILog.info("Decode", "Structured Output 解析成功 -> \(T.self)")
            return decoded
        } catch {
            AILog.error("Decode", "JSONDecoder 解析 \(T.self) 失败: \(error)\n原始 JSON: \(Self.truncateForLog(cleanedJSON, limit: 800))")
            throw AIServiceError.decodingFailed(rawText: cleanedJSON, underlying: error)
        }
    }

    private func buildURLRequest(
        config: AIConfiguration,
        systemPrompt: String,
        userPrompt: String,
        encodedImages: [(mimeType: String, base64: String)],
        schemaName: String,
        schema: [String: Any]
    ) throws -> URLRequest {
        let trimmedBase = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)

        let endpointString: String
        switch config.provider {
        case .openAICompatible:
            endpointString = "\(trimmedBase)/chat/completions"
        case .anthropicClaude:
            endpointString = "\(trimmedBase)/messages"
        case .gemini:
            let normalizedModel = trimmedModel.hasPrefix("models/")
                ? String(trimmedModel.dropFirst("models/".count))
                : trimmedModel
            let action = config.enableStreaming ? "streamGenerateContent?alt=sse" : "generateContent"
            endpointString = "\(trimmedBase)/models/\(normalizedModel):\(action)"
        }

        guard let url = URL(string: endpointString) else {
            AILog.error("HTTP", "无效 URL: \(endpointString)")
            throw AIServiceError.invalidURL(endpointString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let bodyDict: [String: Any]
        switch config.provider {
        case .openAICompatible:
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

            let userContent: Any
            if !encodedImages.isEmpty {
                var items: [[String: Any]] = [["type": "text", "text": userPrompt]]
                for img in encodedImages {
                    items.append([
                        "type": "image_url",
                        "image_url": ["url": "data:\(img.mimeType);base64,\(img.base64)"]
                    ])
                }
                userContent = items
            } else {
                userContent = userPrompt
            }

            bodyDict = [
                "model": trimmedModel,
                "stream": config.enableStreaming,
                "temperature": 0.4,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userContent]
                ],
                "response_format": [
                    "type": "json_schema",
                    "json_schema": [
                        "name": schemaName,
                        "strict": true,
                        "schema": schema
                    ]
                ]
            ]

        case .anthropicClaude:
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            var contentBlocks: [[String: Any]] = []
            for img in encodedImages {
                contentBlocks.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": img.mimeType,
                        "data": img.base64
                    ]
                ])
            }
            contentBlocks.append(["type": "text", "text": userPrompt])

            bodyDict = [
                "model": trimmedModel,
                "max_tokens": 2048,
                "stream": config.enableStreaming,
                "system": systemPrompt,
                "messages": [
                    ["role": "user", "content": contentBlocks]
                ],
                "tools": [
                    [
                        "name": schemaName,
                        "description": "输出符合 AuraLife 规范的结构化生活规划 JSON",
                        "input_schema": schema
                    ]
                ],
                "tool_choice": [
                    "type": "tool",
                    "name": schemaName
                ]
            ]

        case .gemini:
            request.setValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")

            var parts: [[String: Any]] = [["text": userPrompt]]
            for img in encodedImages {
                parts.append([
                    "inline_data": [
                        "mime_type": img.mimeType,
                        "data": img.base64
                    ]
                ])
            }

            let geminiSchema = AIStructuredSchemas.geminiCompatibleSchema(from: schema)
            if let schemaData = try? JSONSerialization.data(withJSONObject: geminiSchema, options: [.sortedKeys]),
               let schemaText = String(data: schemaData, encoding: .utf8) {
                AILog.debug("Gemini", "responseSchema: \(Self.truncateForLog(schemaText, limit: 600))")
            }

            bodyDict = [
                "system_instruction": [
                    "parts": [["text": systemPrompt]]
                ],
                "contents": [
                    ["role": "user", "parts": parts]
                ],
                "generationConfig": [
                    "temperature": 0.4,
                    "responseMimeType": "application/json",
                    "responseSchema": geminiSchema
                ]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
        return request
    }

    // MARK: - SSE Stream Reader

    private func performSSERequest(
        request: URLRequest,
        provider: AIProvider,
        session: URLSession,
        onStreamProgress: @Sendable (String) -> Void
    ) async throws -> String {
        AILog.debug("SSE", "开始建立流式连接…")
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            AILog.error("SSE", "响应不是 HTTPURLResponse")
            throw AIServiceError.emptyOutput
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "<unknown>"
        AILog.info("SSE", "收到 HTTP \(httpResponse.statusCode) | Content-Type=\(contentType)")

        guard (200..<300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count >= 4096 { break }
            }
            let errorBody = String(data: errorData, encoding: .utf8) ?? "<binary \(errorData.count) bytes>"
            AILog.error("SSE", "HTTP 错误 \(httpResponse.statusCode) 响应体: \(errorBody)")
            throw AIServiceError.invalidResponse(statusCode: httpResponse.statusCode, message: errorBody)
        }

        var accumulated = ""
        var nonSSEBuffer = ""
        var lineCount = 0
        var chunkCount = 0
        onStreamProgress("已连接 \(provider.displayName)，等待首个数据分片…")

        for try await rawLine in bytes.lines {
            lineCount += 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if lineCount <= 5 {
                AILog.debug("SSE", "line#\(lineCount): \(Self.truncateForLog(line, limit: 300))")
            }

            guard line.hasPrefix("data:") else {
                // 如果代理或服务端直接返回了普通 JSON 而非 SSE，保留以便日志排查和兜底解析
                nonSSEBuffer += line
                if lineCount <= 3 {
                    AILog.warning("SSE", "收到非 data: 前缀行: \(Self.truncateForLog(line, limit: 300))")
                }
                continue
            }

            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" || payload.isEmpty {
                AILog.debug("SSE", "收到流结束标记 [DONE]")
                continue
            }

            if let chunk = extractDeltaText(fromSSEPayload: payload, provider: provider) {
                chunkCount += 1
                accumulated += chunk
                onStreamProgress("正在流式生成结构化方案（已接收 \(accumulated.count) 字符）…")
            } else {
                AILog.debug("SSE", "分片未提取到文本，原始 payload: \(Self.truncateForLog(payload, limit: 300))")
            }
        }

        AILog.info("SSE", "流式读取结束: 总非空行=\(lineCount), 有效分片=\(chunkCount), 累计文本=\(accumulated.count) 字符")

        if accumulated.isEmpty && !nonSSEBuffer.isEmpty {
            AILog.warning("SSE", "SSE 文本为空，尝试按非流式 JSON 体提取，长度=\(nonSSEBuffer.count)")
            if let fallbackText = extractTextFromNonSSEBuffer(nonSSEBuffer, provider: provider) {
                return fallbackText
            }
            return nonSSEBuffer
        }

        return accumulated
    }

    private func performNonStreamingRequest(
        request: URLRequest,
        provider: AIProvider,
        session: URLSession
    ) async throws -> String {
        AILog.debug("HTTP", "发送非流式请求…")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            AILog.error("HTTP", "响应不是 HTTPURLResponse")
            throw AIServiceError.emptyOutput
        }

        AILog.info("HTTP", "收到非流式 HTTP \(httpResponse.statusCode) | body=\(data.count) bytes")
        let rawBodyString = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"

        guard (200..<300).contains(httpResponse.statusCode) else {
            AILog.error("HTTP", "HTTP 错误 \(httpResponse.statusCode) 响应体: \(Self.truncateForLog(rawBodyString, limit: 800))")
            throw AIServiceError.invalidResponse(statusCode: httpResponse.statusCode, message: rawBodyString)
        }

        AILog.debug("HTTP", "非流式原始响应: \(Self.truncateForLog(rawBodyString, limit: 600))")

        guard let extracted = extractTextFromNonSSEBuffer(rawBodyString, provider: provider) else {
            AILog.error("HTTP", "无法从响应中提取内容: \(Self.truncateForLog(rawBodyString, limit: 500))")
            throw AIServiceError.emptyOutput
        }
        return extracted
    }

    private func extractTextFromNonSSEBuffer(_ rawString: String, provider: AIProvider) -> String? {
        guard let data = rawString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let json = parsed as? [String: Any] {
            return extractFromSingleResponseObject(json, provider: provider)
        }
        if let jsonArray = parsed as? [[String: Any]], provider == .gemini {
            let combined = jsonArray.compactMap { extractFromSingleResponseObject($0, provider: .gemini) }.joined()
            return combined.isEmpty ? nil : combined
        }
        return nil
    }

    private func extractFromSingleResponseObject(_ json: [String: Any], provider: AIProvider) -> String? {
        switch provider {
        case .openAICompatible:
            if let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }

        case .anthropicClaude:
            if let content = json["content"] as? [[String: Any]] {
                for block in content {
                    if block["type"] as? String == "tool_use",
                       let input = block["input"],
                       let inputData = try? JSONSerialization.data(withJSONObject: input),
                       let inputText = String(data: inputData, encoding: .utf8) {
                        return inputText
                    }
                    if let text = block["text"] as? String {
                        return text
                    }
                }
            }

        case .gemini:
            if let promptFeedback = json["promptFeedback"] as? [String: Any],
               let blockReason = promptFeedback["blockReason"] as? String {
                AILog.warning("Gemini", "promptFeedback blockReason=\(blockReason)")
            }
            if let candidates = json["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first {
                if let finishReason = firstCandidate["finishReason"] as? String, finishReason != "STOP" {
                    AILog.info("Gemini", "finishReason=\(finishReason)")
                }
                if let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]] {
                    let outputParts = parts.filter { ($0["thought"] as? Bool) != true }
                    let thoughtParts = parts.filter { ($0["thought"] as? Bool) == true }
                    if !thoughtParts.isEmpty {
                        let thoughtPreview = thoughtParts.compactMap { $0["text"] as? String }.joined()
                        AILog.debug("Gemini", "跳过模型思考片段(\(thoughtPreview.count) chars)")
                    }
                    let joined = outputParts.compactMap { $0["text"] as? String }.joined()
                    return joined.isEmpty ? nil : joined
                }
            }
        }
        return nil
    }

    private func extractDeltaText(fromSSEPayload payload: String, provider: AIProvider) -> String? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let errorObj = json["error"] as? [String: Any] {
            AILog.error("SSE", "流式分片内包含 error 对象: \(errorObj)")
        }

        switch provider {
        case .openAICompatible:
            guard let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                return nil
            }
            return content

        case .anthropicClaude:
            if let delta = json["delta"] as? [String: Any] {
                if let partialJSON = delta["partial_json"] as? String {
                    return partialJSON
                }
                if let text = delta["text"] as? String {
                    return text
                }
            }
            return nil

        case .gemini:
            if let candidates = json["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first {
                if let finishReason = firstCandidate["finishReason"] as? String {
                    AILog.info("Gemini", "SSE finishReason=\(finishReason)")
                }
                if let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]] {
                    let outputParts = parts.filter { ($0["thought"] as? Bool) != true }
                    let text = outputParts.compactMap { $0["text"] as? String }.joined()
                    return text.isEmpty ? nil : text
                }
            }
            return nil
        }
    }

    // MARK: - Helpers

    private func encodeJPEGDataURL(from image: UIImage) -> (mimeType: String, base64: String)? {
        let maxDimension: CGFloat = 1024
        let size = image.size
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.72) else {
            return nil
        }
        return ("image/jpeg", jpeg.base64EncodedString())
    }

    private static func truncateForLog(_ text: String, limit: Int) -> String {
        if text.count <= limit {
            return text
        }
        return String(text.prefix(limit)) + "…(truncated, total=\(text.count))"
    }

    private static func extractJSONObject(from raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            let filtered = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            trimmed = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace <= lastBrace {
            return String(trimmed[firstBrace...lastBrace])
        }
        return trimmed
    }

    // MARK: - Offline Demo SSE Simulator

    private func simulateStreaming<T: Sendable>(
        steps: [String],
        onStreamProgress: @Sendable (String) -> Void,
        buildResult: () -> T
    ) async throws -> T {
        for step in steps {
            onStreamProgress(step)
            try await Task.sleep(for: .milliseconds(260))
        }
        return buildResult()
    }

    private static func offlineMultiDayPlan(
        daysCount: Int,
        profile: AIProfileContext?,
        snapshot: AISnapshotContext
    ) -> AIMultiDayPlanResponse {
        let diningEnv = profile?.diningEnvironment ?? "居家做饭"
        let dietPrefs = profile?.dietaryPreferences ?? []
        let tempC = Int(snapshot.weatherTempC.rounded())
        let isWarmHumid = snapshot.weatherTempC >= 24.0 && snapshot.weatherHumidity >= 75.0
        let isAcute = snapshot.isAcuteRecovery

        let dayTemplates: [AIDayPlanPayload] = (0..<max(1, min(daysCount, 3))).map { offset in
            let rawCards: [AIPlannedCardPayload]
            let phase: String
            let symptoms: [String]

            if isAcute {
                phase = "急性祛湿恢复期 (第\(offset + 1)/3天)"
                symptoms = snapshot.userReportedSymptoms
                switch offset {
                case 0:
                    rawCards = [
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "上午 08:00-09:00",
                            title: "温热小米粥配蒸蛋 + 餐后炒薏米焦米水",
                            actionDetail: "先吃半碗温热小米粥配水煮蛋垫胃；餐后半小时温饮炒薏米 15g + 陈皮 3g + 炒大米煮水。",
                            reasoning: "受寒脾胃弱忌空腹茶饮，先食温粥再温和化湿。"
                        ),
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "中午 12:00-13:30",
                            title: "山药白扁豆小米暖胃粥",
                            actionDetail: "\(diningEnv)优先选择软烂热食：怀山药 80g 煮小米粥，配清蒸鸡胸肉 100g。",
                            reasoning: "急症第1天减少油腻生冷，减轻脾胃负担。"
                        ),
                        AIPlannedCardPayload(
                            category: "fitness",
                            timeSlot: "下午 17:00-17:30",
                            title: "居家八段锦 + 靠墙静蹲(15min)",
                            actionDetail: "暂停冷水游泳，练习八段锦两遍后做靠墙静蹲 3 组 × 45 秒。",
                            reasoning: "恢复期防受凉耗气，用温和导引代替游泳。"
                        ),
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "傍晚 18:00-18:45",
                            title: "白萝卜陈皮瘦肉暖汤 + 蒸南瓜",
                            actionDetail: "白萝卜丝 150g 配陈皮 1 片、瘦肉片 80g 煮清汤，佐少许蒸贝贝南瓜。",
                            reasoning: "晚餐顺气消导且低脂温软，防止夜间食积停湿。"
                        ),
                        AIPlannedCardPayload(
                            category: "lifestyle",
                            timeSlot: "晚上 21:30",
                            title: "40°C 温水泡脚 + 23:00 熄灯",
                            actionDetail: "泡脚 15 分钟至微润即止，21:30 后仅小口抿水，保证 7.5 小时睡眠。",
                            reasoning: "先补足睡眠节律，帮助湿浊夜间运化。"
                        )
                    ]
                case 1:
                    rawCards = [
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "上午 08:00-09:00",
                            title: "山药小米粥 + 餐后茯苓红枣温饮",
                            actionDetail: "温热山药粥配水煮蛋 1 个；餐后温饮茯苓 6g、炒白术 5g、去核红枣 2 颗焖泡水。",
                            reasoning: "第2天先食谷物固胃气，再健脾益气缓解乏力。"
                        ),
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "中午 12:00-13:30",
                            title: "清蒸鲈鱼 + 蒜蓉油麦菜 + 软米饭",
                            actionDetail: "优质蛋白 160g 搭配温热时蔬与半碗软米饭，细嚼慢咽七分饱。",
                            reasoning: "逐步恢复蛋白摄入，稳住减重期肌肉量。"
                        ),
                        AIPlannedCardPayload(
                            category: "fitness",
                            timeSlot: "下午 17:00-17:30",
                            title: "居家弹力带微抗阻(20min)",
                            actionDetail: "弹力带划船 3×15、臀桥 3×15、死虫式核心 3×12，保持呼吸平稳。",
                            reasoning: "恢复期第2天用低冲击抗阻唤醒代谢。"
                        ),
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "傍晚 18:00-19:00",
                            title: "山药豆腐蒸滑蛋 + 焯生菜",
                            actionDetail: "鸡蛋 2 个蒸滑蛋配嫩豆腐 100g、山药块与温热焯生菜，七分饱停筷。",
                            reasoning: "第2天晚餐温润补蛋白，兼顾脾胃吸收与夜间控脂。"
                        ),
                        AIPlannedCardPayload(
                            category: "lifestyle",
                            timeSlot: "晚上 21:30",
                            title: "顺时针揉腹 + 睡前 2 小时控水",
                            actionDetail: "睡前仰卧轻柔揉腹 36 圈促进肠蠕动，夜间减少大量饮水。",
                            reasoning: "痰湿体质防夜间水湿停滞引起晨起沉重。"
                        )
                    ]
                default:
                    rawCards = [
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "上午 08:00-09:00",
                            title: "杂粮热粥配鸡蛋 + 餐后陈皮温胃饮",
                            actionDetail: "温热燕麦小米粥配水煮蛋；餐后温饮\(isWarmHumid ? "陈皮 3g + 茯苓 5g 泡饮" : "老姜 2 片 + 陈皮 3g 泡饮")。",
                            reasoning: "第3天过渡回稳态，结合\(tempC)°C体感平调脾胃。"
                        ),
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "中午 12:00-13:30",
                            title: "冬瓜薏米瘦肉温汤 + 杂粮饭",
                            actionDetail: "炒薏米 20g 配冬瓜瘦肉清汤与半碗糙米饭，少盐少油。",
                            reasoning: "脾胃恢复后重启高蛋白低脂祛湿饮食。"
                        ),
                        AIPlannedCardPayload(
                            category: "fitness",
                            timeSlot: "下午 16:30-17:20",
                            title: "温和室外游泳(限时30min)",
                            actionDetail: "若\(snapshot.city)维持 \(tempC)°C 且无腹胀，可下水慢游 30 分钟并及时擦干。",
                            reasoning: "结合 \(tempC)°C 天气与游泳偏好逐步恢复。"
                        ),
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "傍晚 18:00-19:00",
                            title: "姜丝丝瓜菌菇虾仁汤（轻食晚餐）",
                            actionDetail: "虾仁 100g、鲜香菇、丝瓜加少许姜丝煮汤，配少许红薯或杂粮。",
                            reasoning: "第3天晚餐清鲜高蛋白，助力游泳后修复不增湿。"
                        ),
                        AIPlannedCardPayload(
                            category: "lifestyle",
                            timeSlot: "晚上 21:30",
                            title: "肩颈拉伸 + 23:00 前入睡",
                            actionDetail: "睡前 10 分钟胸椎与肩颈伸展，远离屏幕准备入睡。",
                            reasoning: "巩固 3 天恢复成果，防止再次熬夜伤脾。"
                        )
                    ]
                }
            } else {
                phase = "日常稳态调理期"
                symptoms = []
                let swimAllowed = LocalContextPlanner.isOutdoorSwimmingSuitable(
                    tempC: snapshot.weatherTempC,
                    condition: snapshot.weatherCondition,
                    windSpeedKmh: snapshot.weatherWindSpeedKmh,
                    isAcuteRecovery: false
                )
                let morningTeaTitle = isWarmHumid
                    ? "温热小米粥配水煮蛋 + 餐后陈皮茯苓轻饮"
                    : (offset == 1 ? "燕麦山药粥配水煮蛋 + 餐后陈皮荷叶饮" : "温热小米山药粥配水煮蛋 + 餐后生姜陈皮饮")
                let morningTeaDetail = isWarmHumid
                    ? "先吃温热小米粥与水煮蛋垫胃；餐后泡饮陈皮 3g + 茯苓 5g（\(snapshot.city)\(tempC)°C偏湿暖，不用纯姜）。"
                    : (offset == 1
                        ? "先吃温热燕麦粥配鸡蛋；餐后陈皮 3g + 干荷叶 2g 沸水冲泡温服，忌冰镇。"
                        : "先吃温热小米山药粥配水煮蛋；餐后老姜 1 片 + 陈皮 3g 焖泡温饮。")

                rawCards = [
                    AIPlannedCardPayload(
                        category: "diet",
                        timeSlot: "上午 08:00-09:00",
                        title: morningTeaTitle,
                        actionDetail: morningTeaDetail,
                        reasoning: isWarmHumid ? "当地\(tempC)°C偏湿暖，先养胃气再平调化湿。" : "先以温粥补谷气，再顺应\(tempC)°C气候调脾。"
                    ),
                    AIPlannedCardPayload(
                        category: "diet",
                        timeSlot: "中午 12:00-13:30",
                        title: offset == 1 ? "清蒸鸡腿配茯苓山药时蔬" : "冬瓜薏米瘦肉温汤 + 杂粮饭",
                        actionDetail: "\(diningEnv)场景控制精制碳水，优先温热瘦肉/鱼虾蛋白搭配清淡蔬菜。",
                        reasoning: "稳态减重期高蛋白低脂，避免滋生痰湿。"
                    ),
                    AIPlannedCardPayload(
                        category: "fitness",
                        timeSlot: "下午 16:30-17:30",
                        title: swimAllowed ? "阳光下室外游泳(\(30 + offset * 5)min)" : "居家哑铃/弹力带微抗阻(25min)",
                        actionDetail: swimAllowed
                            ? "中等配速蛙泳/自由泳，避开深潜，上岸及时披外套保暖。"
                            : "\(snapshot.city) \(tempC)°C \(snapshot.weatherCondition)，室内高脚杯深蹲 3×12、弹力带划船 3×15。",
                        reasoning: swimAllowed
                            ? "\(snapshot.city) \(tempC)°C \(snapshot.weatherCondition)适宜下水，护膝燃脂。"
                            : "\(snapshot.city) \(tempC)°C \(snapshot.weatherCondition)，改室内抗阻防受寒。"
                    ),
                    AIPlannedCardPayload(
                        category: "diet",
                        timeSlot: "傍晚 18:00-19:00",
                        title: offset == 1 ? "清炖鸡丝冬瓜汤 + 清炒菠菜" : "山药虾仁蒸蛋 + 蒜蓉油麦菜",
                        actionDetail: "\(diningEnv)晚餐以优质蛋白配温热时蔬，减半主食并在 19:30 前吃完。",
                        reasoning: "稳态减重期晚餐七分饱低碳水，夜间脾胃无负担。"
                    ),
                    AIPlannedCardPayload(
                        category: "lifestyle",
                        timeSlot: "晚上 21:30",
                        title: offset == 2 ? "艾草温水泡脚 + 踝泵拉伸" : "温水泡脚 + 睡前 2 小时控水",
                        actionDetail: "40°C 温水泡脚 15 分钟，睡前两小时避免大量饮水。",
                        reasoning: "痰湿体质防夜间水湿停滞引发晨起浮肿。"
                    )
                ]
            }

            let adaptedCards = rawCards.map {
                DietaryAdaptationHelper.adaptPayload($0, diningEnvironment: diningEnv, dietaryPreferences: dietPrefs)
            }

            return AIDayPlanPayload(
                dayOffset: offset,
                recoveryPhase: phase,
                detectedSymptoms: symptoms,
                cards: adaptedCards
            )
        }

        let phaseSpec: AIRegimenPhasePayload
        if isAcute {
            phaseSpec = AIRegimenPhasePayload(
                stageKind: RegimenStageKind.acuteRelief.rawValue,
                phaseName: "急性祛湿恢复期",
                therapeuticPrinciple: "温中散寒、先护胃气，暂缓减重与生冷",
                plannedDays: 3,
                exitCriteria: "排便成形不黏腻、胃脘温暖无胀闷",
                nextStageHint: "转入「祛邪疏通期」，逐步恢复蛋白与抗阻"
            )
        } else {
            phaseSpec = AIRegimenPhasePayload(
                stageKind: RegimenStageKind.maintenance.rawValue,
                phaseName: "日常顺时固本期",
                therapeuticPrinciple: "健脾化湿、温阳理气，循序渐进减重",
                plannedDays: 14,
                exitCriteria: "排便成形、晨起轻快不困重且作息平稳",
                nextStageHint: "持续顺时固本，随二十四节气微调"
            )
        }

        return AIMultiDayPlanResponse(
            summary: isAcute
                ? "已按「急则治其标」生成未来 \(dayTemplates.count) 天阶梯式温和恢复方案。"
                : "已结合痰湿质画像与 \(snapshot.city) \(tempC)°C 天气生成未来 \(dayTemplates.count) 天顺时方案。",
            phaseSpec: phaseSpec,
            days: dayTemplates
        )
    }
}
