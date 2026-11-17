import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext

    let onCompleted: () -> Void

    private enum Step: Int, CaseIterable {
        case basics = 0
        case diagnosis = 1
        case permissions = 2
        case assessment = 3

        var title: String {
            switch self {
            case .basics: return "基础体征与偏好"
            case .diagnosis: return "四诊合参辨体质"
            case .permissions: return "环境与顺时感知"
            case .assessment: return "初诊方案生成"
            }
        }
    }

    private enum DiagnosisMode: String, CaseIterable, Identifiable {
        case adaptiveInquiry = "4+2 自适应问诊"
        case importReport = "导入体质报告"

        var id: String { rawValue }
    }

    private struct BaseInquiryQuestion: Identifiable {
        let id: String
        let question: String
        let options: [String]
    }

    private let baseQuestions: [BaseInquiryQuestion] = [
        BaseInquiryQuestion(
            id: "cold_heat_sweat",
            question: "1. 平时更怕冷还是怕热、容易出汗吗？",
            options: [
                "怕冷手脚凉 / 吹风易不适",
                "怕热手心烦热 / 易口渴",
                "怕冷又易上火（上热下寒）",
                "寒热适中 / 不明显"
            ]
        ),
        BaseInquiryQuestion(
            id: "stool_urine",
            question: "2. 日常大便与小便偏哪种表现？",
            options: [
                "大便偏黏腻挂壁 / 不成形",
                "偏稀水样 / 吃凉易腹泻",
                "偏干结难解 / 小便偏黄",
                "成形规律 / 基本正常"
            ]
        ),
        BaseInquiryQuestion(
            id: "mouth_drink",
            question: "3. 晨起口腔感受与饮水偏好？",
            options: [
                "口淡粘腻 / 喜喝温热饮",
                "口干口苦 / 偏爱凉水",
                "口干咽燥 / 喝水不解渴",
                "清爽正常 / 无明显偏好"
            ]
        ),
        BaseInquiryQuestion(
            id: "energy_postmeal",
            question: "4. 餐后或午后精力与体感？",
            options: [
                "头重犯困 / 饭后易胀气",
                "易倦气短 / 说话懒言",
                "烦躁易怒 / 胸胁微闷",
                "精力平稳 / 无明显沉重"
            ]
        )
    ]

    private let dietaryPresets = [
        "忌生冷冰饮", "忌寒凉海鲜", "少油腻甜食", "少辛辣刺激", "偏爱温热汤羹",
        "乳糖不耐/忌牛奶", "不吃牛羊肉", "忌香菜/葱蒜", "清淡素食倾向", "控糖低升糖"
    ]
    private let fitnessPresets = [
        "室外游泳40min", "居家轻抗阻", "八段锦导引", "讨厌传统跑步有氧",
        "餐后散步", "有健身房器械", "羽毛球/球类", "久坐办公护腰", "膝盖不适避跑跳"
    ]
    private let diningOptions = ["居家做饭", "外卖", "食堂"]

    @State private var currentStep: Step = .basics

    // Step 1
    @State private var heightCM: Double = 172.0
    @State private var weightKG: Double = 72.0
    @State private var targetWeightKG: Double = 65.0
    @State private var diningEnvironment: String = "居家做饭"
    @State private var selectedDietPrefs: [String] = ["忌生冷冰饮", "偏爱温热汤羹"]
    @State private var selectedFitnessPrefs: [String] = ["居家轻抗阻", "讨厌传统跑步有氧"]
    @State private var newDietTag: String = ""
    @State private var newFitnessTag: String = ""
    @State private var constraintNote: String = ""
    @State private var isSyncingHealthWeight: Bool = false
    @State private var healthFillMessage: String?

    // Step 2
    @State private var diagnosisMode: DiagnosisMode = .adaptiveInquiry
    @State private var baseAnswers: [String: String] = [:]
    @State private var followUpResponse: AIOnboardingFollowUpResponse?
    @State private var followUpAnswers: [String: String] = [:]
    @State private var isCheckingFollowUp: Bool = false
    @State private var reportText: String = ""
    @State private var selectedReportItem: PhotosPickerItem?
    @State private var isRecognizingReport: Bool = false
    @State private var tongueImage: UIImage?
    @State private var tongueQuality: TonguePhotoQuality?
    @State private var isShowingTongueCapture: Bool = false

    // Step 3
    @State private var city: String = "深圳"
    @State private var weatherTempC: Double = 24.0
    @State private var weatherCondition: String = "晴"
    @State private var weatherHumidity: Double = 68.0
    @State private var weatherWindKmh: Double = 9.0
    @State private var weatherSource: String = "默认初始"
    @State private var isFetchingWeather: Bool = false
    @State private var weatherStatusMessage: String?
    @State private var notificationEnabled: Bool = false
    @State private var notificationStatusMessage: String?
    @State private var isShowingAISettings: Bool = false
    @State private var isAILiveConfigured: Bool = AIConfiguration.load().hasValidKey

    // Step 4
    @State private var isGeneratingAssessment: Bool = false
    @State private var streamingStatus: String?
    @State private var assessmentResult: (response: AIOnboardingConstitutionResponse, source: AIServiceSource)?
    @State private var assessmentError: String?

    private var allBaseAnswered: Bool {
        baseQuestions.allSatisfy { baseAnswers[$0.id] != nil }
    }

    private var allFollowUpAnswered: Bool {
        guard let followUpResponse, followUpResponse.needFollowUp else { return true }
        return followUpResponse.questions.allSatisfy { followUpAnswers[$0.id] != nil }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepProgressHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch currentStep {
                        case .basics:
                            stepBasicsContent
                        case .diagnosis:
                            stepDiagnosisContent
                        case .permissions:
                            stepPermissionsContent
                        case .assessment:
                            stepAssessmentContent
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentStep != .basics {
                        Button("上一步") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentStep = Step(rawValue: currentStep.rawValue - 1) ?? .basics
                            }
                        }
                        .foregroundStyle(AuraTheme.secondaryText)
                        .disabled(isCheckingFollowUp || isGeneratingAssessment)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("示例体验") {
                        enterWithDemoProfile()
                    }
                    .font(.subheadline)
                    .foregroundStyle(AuraTheme.secondaryText)
                    .disabled(isGeneratingAssessment)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
            .sheet(isPresented: $isShowingTongueCapture) {
                TongueCaptureSheet { image, quality in
                    tongueImage = image
                    tongueQuality = quality
                }
            }
            .sheet(isPresented: $isShowingAISettings) {
                AISettingsSheet {
                    isAILiveConfigured = AIConfiguration.load().hasValidKey
                }
            }
            .onChange(of: selectedReportItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await recognizeReportPhoto(newItem)
                }
            }
        }
    }

    // MARK: - Header

    private var stepProgressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AuraLife · 顺时建档")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AuraTheme.sageGreen)

                Spacer()

                Text("第 \(currentStep.rawValue + 1)/\(Step.allCases.count) 步 · \(currentStep.title)")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)
            }

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue ? AuraTheme.sageGreen : AuraTheme.hairline)
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(AuraTheme.canvasBackground)
    }

    // MARK: - Step 1: Basics

    private var stepBasicsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("先认识你的身体与生活习惯")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(AuraTheme.primaryText)

                Text("不需要背卡路里公式，只需 30 秒告诉我们你的体征与忌口。")
                    .font(.subheadline)
                    .foregroundStyle(AuraTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("基础体征与目标")
                        .font(.headline)
                        .foregroundStyle(AuraTheme.primaryText)
                    Spacer()
                    Button {
                        Task {
                            await prefillWeightFromHealthKit()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isSyncingHealthWeight {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "heart.fill")
                                    .font(.caption2)
                            }
                            Text("读取健康体重")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(AuraTheme.inkSlate)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(AuraTheme.inkSlate.opacity(0.12), in: Capsule())
                    }
                    .disabled(isSyncingHealthWeight)
                }

                HStack(spacing: 10) {
                    metricInput(title: "身高 (cm)", value: $heightCM)
                    metricInput(title: "体重 (kg)", value: $weightKG)
                    metricInput(title: "目标 (kg)", value: $targetWeightKG)
                }

                if let healthFillMessage {
                    Text(healthFillMessage)
                        .font(.caption)
                        .foregroundStyle(AuraTheme.sageGreen)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("日常就餐场景")
                        .font(.caption)
                        .foregroundStyle(AuraTheme.secondaryText)
                    Picker("就餐场景", selection: $diningEnvironment) {
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

            VStack(alignment: .leading, spacing: 12) {
                Text("饮食忌口与运动习惯（可多选或自定义）")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)

                Text("饮食忌口 / 偏好")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)

                SelectableChipsWrap(
                    presets: dietaryPresets,
                    selected: $selectedDietPrefs,
                    tint: AuraTheme.sageGreen
                )

                HStack(spacing: 8) {
                    TextField("自定义忌口或过敏原（如：对花生过敏）", text: $newDietTag)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .submitLabel(.done)
                        .onSubmit { addCustomDietTag() }

                    Button("添加") {
                        addCustomDietTag()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AuraTheme.sageGreen)
                    .disabled(newDietTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Divider()

                Text("运动偏好与身体限制")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)

                SelectableChipsWrap(
                    presets: fitnessPresets,
                    selected: $selectedFitnessPrefs,
                    tint: AuraTheme.warmGinger
                )

                HStack(spacing: 8) {
                    TextField("自定义运动习惯或旧伤（如：腰间盘突出）", text: $newFitnessTag)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .submitLabel(.done)
                        .onSubmit { addCustomFitnessTag() }

                    Button("添加") {
                        addCustomFitnessTag()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AuraTheme.warmGinger)
                    .disabled(newFitnessTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("补充说明（可选）")
                        .font(.caption)
                        .foregroundStyle(AuraTheme.secondaryText)
                    TextField("例如：家里只有一对 5kg 哑铃，或正在备孕/服药等", text: $constraintNote, axis: .vertical)
                        .font(.subheadline)
                        .lineLimit(1...3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(16)
            .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
        }
    }

    private func metricInput(title: String, value: Binding<Double>) -> some View {
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

    // MARK: - Step 2: 4+2 Adaptive Inquiry & Tongue Capture

    private var stepDiagnosisContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("中医四诊合参建档")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(AuraTheme.primaryText)

                Text("无现成报告时，通过「十问歌 4+2 自适应问诊」与自然光舌象联合判别，准确率更高。")
                    .font(.subheadline)
                    .foregroundStyle(AuraTheme.secondaryText)
            }

            Picker("采集方式", selection: $diagnosisMode) {
                ForEach(DiagnosisMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if diagnosisMode == .adaptiveInquiry {
                VStack(spacing: 12) {
                    ForEach(baseQuestions) { item in
                        inquiryQuestionCard(
                            question: item.question,
                            options: item.options,
                            selection: Binding(
                                get: { baseAnswers[item.id] },
                                set: { newValue in
                                    baseAnswers[item.id] = newValue
                                    followUpResponse = nil
                                    followUpAnswers.removeAll()
                                }
                            )
                        )
                    }
                }

                if let followUpResponse, followUpResponse.needFollowUp {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "stethoscope")
                                .foregroundStyle(AuraTheme.warmGinger)
                            Text("第 2 层精准排疑追问")
                                .font(.headline)
                                .foregroundStyle(AuraTheme.primaryText)
                        }

                        Text(followUpResponse.reasoningHint)
                            .font(.caption)
                            .foregroundStyle(AuraTheme.secondaryText)

                        ForEach(followUpResponse.questions) { q in
                            inquiryQuestionCard(
                                question: q.question,
                                options: q.options,
                                selection: Binding(
                                    get: { followUpAnswers[q.id] },
                                    set: { followUpAnswers[q.id] = $0 }
                                )
                            )
                        }
                    }
                    .padding(14)
                    .background(AuraTheme.warmGinger.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AuraTheme.warmGinger.opacity(0.32), lineWidth: 1)
                    )
                }
            } else {
                reportImportCard
            }

            tongueCaptureCard
        }
    }

    private func inquiryQuestionCard(
        question: String,
        options: [String],
        selection: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AuraTheme.primaryText)

            VStack(spacing: 7) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection.wrappedValue == option
                    Button {
                        HapticFeedback.impact(.light)
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selection.wrappedValue = option
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? AuraTheme.sageGreen : AuraTheme.secondaryText.opacity(0.5))
                            Text(option)
                                .font(.subheadline)
                                .foregroundStyle(AuraTheme.primaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            isSelected ? AuraTheme.sageGreen.opacity(0.12) : AuraTheme.subtleSurface.opacity(0.8),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? AuraTheme.sageGreen.opacity(0.55) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var reportImportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("粘贴或截图识别第三方报告", systemImage: "doc.text.viewfinder")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)
                Spacer()
                let recognizing = isRecognizingReport
                PhotosPicker(selection: $selectedReportItem, matching: .images) {
                    Label(recognizing ? "识别中…" : "截图识别", systemImage: "photo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AuraTheme.sageGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AuraTheme.sageGreen.opacity(0.14), in: Capsule())
                }
                .disabled(recognizing)
            }

            TextEditor(text: $reportText)
                .font(.subheadline)
                .frame(minHeight: 100)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if reportText.isEmpty {
                        Text("粘贴中医体质问卷或体检摘要（如：痰湿质78分，轻微气虚，肠胃敏感）")
                            .font(.caption)
                            .foregroundStyle(AuraTheme.secondaryText.opacity(0.65))
                            .padding(14)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var tongueCaptureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("望诊加分项：自然光舌象", systemImage: "mouth")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)

                Spacer()

                Text(tongueImage == nil ? "可选 · +14%置信度" : "已采集")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tongueImage == nil ? AuraTheme.warmGinger : AuraTheme.sageGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((tongueImage == nil ? AuraTheme.warmGinger : AuraTheme.sageGreen).opacity(0.14), in: Capsule())
            }

            if let tongueImage {
                HStack(spacing: 12) {
                    Image(uiImage: tongueImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tongueQuality?.statusText ?? "舌象照片已就绪")
                            .font(.caption)
                            .foregroundStyle(AuraTheme.primaryText)
                            .lineLimit(2)

                        HStack(spacing: 10) {
                            Button("重拍 / 更换") {
                                isShowingTongueCapture = true
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AuraTheme.sageGreen)

                            Button("移除") {
                                self.tongueImage = nil
                                self.tongueQuality = nil
                            }
                            .font(.caption)
                            .foregroundStyle(AuraTheme.secondaryText)
                        }
                    }
                }
            } else {
                Text("系统将引导你在自然白光下拍摄无美颜舌象，减少暖光导致的寒热误判。")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)

                Button {
                    isShowingTongueCapture = true
                } label: {
                    Label("拍摄 / 上传标准化舌象", systemImage: "camera.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AuraTheme.sageGreen)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AuraTheme.sageGreen.opacity(0.13), in: Capsule())
                }
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    // MARK: - Step 3: Permissions & Context

    private var stepPermissionsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("开启顺时环境与温柔提醒")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(AuraTheme.primaryText)

                Text("本地气候与节气会参与辨证（排除外湿误判），所有权限均可按需跳过。")
                    .font(.subheadline)
                    .foregroundStyle(AuraTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("本地城市与实时气象", systemImage: "location.fill")
                        .font(.headline)
                        .foregroundStyle(AuraTheme.primaryText)
                    Spacer()
                    Text("\(city) · \(Int(weatherTempC.rounded()))°C \(weatherCondition)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AuraTheme.sageGreen)
                }

                Text("用于结合温湿度、风速与二十四节气调整户外运动及祛湿强度。")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)

                Button {
                    Task {
                        await fetchWeatherInOnboarding()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isFetchingWeather {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Image(systemName: "sun.max.fill")
                        }
                        Text(isFetchingWeather ? "正在获取定位天气…" : "授权定位并同步当前城市天气")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(AuraTheme.sageGreen, in: Capsule())
                }
                .disabled(isFetchingWeather)

                if let weatherStatusMessage {
                    Text(weatherStatusMessage)
                        .font(.caption)
                        .foregroundStyle(AuraTheme.sageGreen)
                }
            }
            .padding(16)
            .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("关键时段温和提醒", systemImage: "bell.badge.fill")
                        .font(.headline)
                        .foregroundStyle(AuraTheme.primaryText)
                    Spacer()
                    Text(notificationEnabled ? "已开启" : "未开启")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(notificationEnabled ? AuraTheme.sageGreen : AuraTheme.secondaryText)
                }

                Text("仅在喝茶饮、运动窗口、睡前控水等节点轻提醒，卡片完成后自动撤销。")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)

                Button {
                    Task {
                        await enableNotificationsInOnboarding()
                    }
                } label: {
                    Text(notificationEnabled ? "已允许温和提醒" : "允许发送温和顺时提醒")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(notificationEnabled ? AuraTheme.sageGreen : AuraTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            notificationEnabled ? AuraTheme.sageGreen.opacity(0.13) : AuraTheme.subtleSurface,
                            in: Capsule()
                        )
                }

                if let notificationStatusMessage {
                    Text(notificationStatusMessage)
                        .font(.caption)
                        .foregroundStyle(AuraTheme.secondaryText)
                }
            }
            .padding(16)
            .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))

            Button {
                isShowingAISettings = true
            } label: {
                HStack {
                    Image(systemName: isAILiveConfigured ? "sparkles" : "cpu")
                        .foregroundStyle(isAILiveConfigured ? AuraTheme.sageGreen : AuraTheme.warmGinger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isAILiveConfigured ? "AI 引擎：已配置云端模型" : "AI 引擎：内置离线演示引擎（可点击配置 Key）")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AuraTheme.primaryText)
                        Text("未填 Key 也可直接完成建档与全流程体验")
                            .font(.caption2)
                            .foregroundStyle(AuraTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(AuraTheme.secondaryText)
                }
                .padding(14)
                .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Step 4: Assessment Result

    private var stepAssessmentContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isGeneratingAssessment {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(AuraTheme.sageGreen)

                    Text(streamingStatus ?? "正在四诊合参并生成第 1 份顺时方案…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AuraTheme.primaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
                .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
            } else if let result = assessmentResult {
                let res = result.response
                let stage = res.suggestedPhaseSpec.resolvedStageKind

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("初诊体质辨识结果")
                            .font(.headline)
                            .foregroundStyle(AuraTheme.primaryText)

                        Spacer()

                        Text("置信度 \(res.clampedConfidence)%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(res.clampedConfidence >= 80 ? AuraTheme.sageGreen : AuraTheme.warmGinger)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background((res.clampedConfidence >= 80 ? AuraTheme.sageGreen : AuraTheme.warmGinger).opacity(0.14), in: Capsule())
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(res.allConstitutionTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AuraTheme.warmGinger)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(AuraTheme.warmGinger.opacity(0.13), in: Capsule())
                            }
                        }
                    }

                    Text(res.clinicalSummary)
                        .font(.subheadline)
                        .foregroundStyle(AuraTheme.primaryText)

                    if res.needsThreeDayTrial {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .foregroundStyle(AuraTheme.warmGinger)
                            Text("已开启「前 3 天以方测证试探校准」：第 2 天将温和复诊，根据你的胃肠与精力反馈将置信度校准至 82%+。")
                                .font(.caption)
                                .foregroundStyle(AuraTheme.primaryText)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AuraTheme.warmGinger.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("初始阶段：\(res.suggestedPhaseSpec.phaseName)（\(stage.displayName)）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(stage.accentColor)
                        Text("治法总则：\(res.suggestedPhaseSpec.therapeuticPrinciple)")
                            .font(.caption)
                            .foregroundStyle(AuraTheme.secondaryText)
                    }
                }
                .padding(16)
                .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(stage.accentColor.opacity(0.35), lineWidth: 1))

                Text("为你准备的首日 \(res.initialDayCards.count) 项顺时安排")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)

                ForEach(Array(res.initialDayCards.enumerated()), id: \.offset) { _, card in
                    let category = card.resolvedCategory
                    let accent = AuraTheme.accent(for: category)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(category.displayName, systemImage: category.systemImage)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(accent.opacity(0.12), in: Capsule())

                            Text(card.timeSlot)
                                .font(.caption2)
                                .foregroundStyle(AuraTheme.secondaryText)
                            Spacer()
                        }

                        Text(card.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AuraTheme.primaryText)

                        Text(card.actionDetail)
                            .font(.caption)
                            .foregroundStyle(AuraTheme.secondaryText)

                        Text("理由：\(card.clampedReasoning)")
                            .font(.caption2)
                            .foregroundStyle(accent)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
                }
            } else if let assessmentError {
                VStack(alignment: .leading, spacing: 10) {
                    Text("生成初诊方案时遇到问题：\(assessmentError)")
                        .font(.subheadline)
                        .foregroundStyle(.red)

                    Button("重试生成") {
                        Task {
                            await runFinalAssessment()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AuraTheme.sageGreen)
                }
                .padding(16)
                .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        Button {
            Task {
                await handlePrimaryAction()
            }
        } label: {
            HStack(spacing: 8) {
                if isCheckingFollowUp || isGeneratingAssessment {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(primaryButtonTitle)
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(isPrimaryEnabled ? AuraTheme.sageGreen : AuraTheme.secondaryText.opacity(0.35), in: Capsule())
        }
        .disabled(!isPrimaryEnabled || isCheckingFollowUp || isGeneratingAssessment)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AuraTheme.canvasBackground.opacity(0.96))
    }

    private var primaryButtonTitle: String {
        switch currentStep {
        case .basics:
            return "下一步：开始四诊辨体质"
        case .diagnosis:
            if isCheckingFollowUp {
                return "正在分析十问歌线索…"
            }
            if diagnosisMode == .adaptiveInquiry && followUpResponse == nil {
                return "校验并进入下一步"
            }
            return "下一步：环境与提醒设置"
        case .permissions:
            return "生成我的第 1 份顺时方案"
        case .assessment:
            return isGeneratingAssessment ? "正在辨证生成…" : "开启顺时调理"
        }
    }

    private var isPrimaryEnabled: Bool {
        switch currentStep {
        case .basics:
            return heightCM > 80 && weightKG > 25 && targetWeightKG > 25
        case .diagnosis:
            if diagnosisMode == .adaptiveInquiry {
                return allBaseAnswered && allFollowUpAnswered
            }
            return !reportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tongueImage != nil
        case .permissions:
            return true
        case .assessment:
            return assessmentResult != nil
        }
    }

    // MARK: - Actions

    private func handlePrimaryAction() async {
        switch currentStep {
        case .basics:
            withAnimation(.easeInOut(duration: 0.22)) {
                currentStep = .diagnosis
            }

        case .diagnosis:
            if diagnosisMode == .adaptiveInquiry && followUpResponse == nil {
                isCheckingFollowUp = true
                defer { isCheckingFollowUp = false }
                let orderedBase = orderedBaseAnswers()
                do {
                    let result = try await AIService.shared.generateAdaptiveOnboardingFollowUp(
                        heightCM: heightCM,
                        weightKG: weightKG,
                        targetWeightKG: targetWeightKG,
                        baseAnswers: orderedBase,
                        reportText: reportText,
                        hasTongueImage: tongueImage != nil,
                        city: city,
                        weatherTempC: weatherTempC,
                        weatherCondition: weatherCondition
                    )
                    if result.payload.needFollowUp && !result.payload.questions.isEmpty {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                            followUpResponse = result.payload
                        }
                        return
                    }
                } catch {
                    // 追问生成异常时平滑进入下一步
                    AILog.warning("Onboarding", "追问阶段异常，跳过追加问题: \(error.localizedDescription)")
                }
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                currentStep = .permissions
            }

        case .permissions:
            withAnimation(.easeInOut(duration: 0.22)) {
                currentStep = .assessment
            }
            await runFinalAssessment()

        case .assessment:
            if let result = assessmentResult {
                persistOnboardingResult(result.response, source: result.source)
                HapticFeedback.notify(.success)
                onCompleted()
            }
        }
    }

    private func orderedBaseAnswers() -> [OnboardingInquiryAnswer] {
        baseQuestions.compactMap { q in
            guard let ans = baseAnswers[q.id] else { return nil }
            return OnboardingInquiryAnswer(id: q.id, question: q.question, answer: ans)
        }
    }

    private func addCustomDietTag() {
        let trimmed = newDietTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !selectedDietPrefs.contains(trimmed) {
            HapticFeedback.impact(.light)
            selectedDietPrefs.append(trimmed)
        }
        newDietTag = ""
    }

    private func addCustomFitnessTag() {
        let trimmed = newFitnessTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !selectedFitnessPrefs.contains(trimmed) {
            HapticFeedback.impact(.light)
            selectedFitnessPrefs.append(trimmed)
        }
        newFitnessTag = ""
    }

    private func orderedAllAnswers() -> [OnboardingInquiryAnswer] {
        var all = orderedBaseAnswers()
        if let followUpQuestions = followUpResponse?.questions {
            for q in followUpQuestions {
                if let ans = followUpAnswers[q.id] {
                    all.append(OnboardingInquiryAnswer(id: q.id, question: q.question, answer: ans))
                }
            }
        }
        let trimmedNote = constraintNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            all.append(OnboardingInquiryAnswer(id: "extra_constraint", question: "个人特殊限制与设备补充", answer: trimmedNote))
        }
        return all
    }

    private func runFinalAssessment() async {
        isGeneratingAssessment = true
        assessmentError = nil
        streamingStatus = "正在综合四诊线索…"
        defer {
            isGeneratingAssessment = false
            streamingStatus = nil
        }

        do {
            let result = try await AIService.shared.evaluateOnboardingConstitution(
                heightCM: heightCM,
                weightKG: weightKG,
                targetWeightKG: targetWeightKG,
                diningEnvironment: diningEnvironment,
                dietaryPreferences: selectedDietPrefs,
                fitnessPreferences: selectedFitnessPrefs,
                allAnswers: orderedAllAnswers(),
                reportText: reportText,
                tongueImage: tongueImage,
                city: city,
                weatherTempC: weatherTempC,
                weatherCondition: weatherCondition,
                weatherHumidity: weatherHumidity,
                onStreamProgress: { progress in
                    Task { @MainActor in
                        streamingStatus = progress
                    }
                }
            )
            withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                assessmentResult = (result.payload, result.source)
            }
        } catch {
            assessmentError = error.localizedDescription
        }
    }

    private func persistOnboardingResult(_ response: AIOnboardingConstitutionResponse, source: AIServiceSource) {
        clearExistingUserDataForRebuild()

        let methodParts: [String] = [
            diagnosisMode == .adaptiveInquiry ? "4+2辨证" : "报告导入",
            tongueImage != nil ? "舌象" : nil
        ].compactMap { $0 }

        let trimmedNote = constraintNote.trimmingCharacters(in: .whitespacesAndNewlines)
        var initialTolerance = [response.baselineToleranceNote]
        if !trimmedNote.isEmpty && !initialTolerance.contains(trimmedNote) {
            initialTolerance.append("个人限制：\(trimmedNote)")
        }

        let profile = UserConstitutionProfile(
            heightCM: heightCM,
            weightKG: weightKG,
            targetWeightKG: targetWeightKG,
            constitutionTags: response.allConstitutionTags,
            dietaryPreferences: selectedDietPrefs,
            fitnessPreferences: selectedFitnessPrefs,
            toleranceNotes: initialTolerance,
            constitutionConfidencePercent: response.clampedConfidence,
            assessmentMethod: methodParts.joined(separator: " + "),
            needsCalibrationTrial: response.needsThreeDayTrial,
            diningEnvironment: diningEnvironment,
            rawReportSummary: reportText.isEmpty ? response.clinicalSummary : reportText
        )
        modelContext.insert(profile)

        let phaseSpec = response.suggestedPhaseSpec
        let phase = RegimenPhase(
            stageKind: phaseSpec.resolvedStageKind,
            phaseName: phaseSpec.phaseName,
            therapeuticPrinciple: phaseSpec.therapeuticPrinciple,
            exitCriteria: phaseSpec.exitCriteria,
            nextStageHint: phaseSpec.nextStageHint,
            startDate: .now,
            plannedDays: phaseSpec.normalizedPlannedDays,
            status: .active,
            triggerSummary: "首次四诊建档（\(profile.assessmentMethod) · \(source.rawValue)）"
        )
        modelContext.insert(phase)

        let evolutionRecord = ConstitutionEvolutionRecord(
            date: .now,
            phaseName: phase.phaseName,
            stageKind: phase.stageKind,
            therapeuticPrinciple: phase.therapeuticPrinciple,
            outcomeTitle: "首次四诊建档",
            clinicalNote: response.clinicalSummary,
            constitutionSnapshotTags: response.allConstitutionTags,
            deltaSummary: response.baselineDeltaSummary,
            toleranceNote: response.baselineToleranceNote
        )
        modelContext.insert(evolutionRecord)

        let solar = SolarTermCalculator.term(for: .now)
        let snapshot = DailyContextSnapshot(
            date: .now,
            weatherTempC: weatherTempC,
            weatherCondition: weatherCondition,
            city: city,
            weatherHumidity: weatherHumidity,
            weatherWindSpeedKmh: weatherWindKmh,
            weatherSource: weatherSource,
            solarTermName: solar.name,
            userReportedSymptoms: [],
            recoveryPhase: phase.badgeText(for: .now),
            therapeuticPrinciple: phase.therapeuticPrinciple,
            regimenPhase: phase
        )
        modelContext.insert(snapshot)

        var cards: [ActionCard] = []
        for (index, item) in response.initialDayCards.enumerated() {
            let card = ActionCard(
                category: item.resolvedCategory,
                timeSlot: item.timeSlot,
                title: item.title,
                actionDetail: item.actionDetail,
                reasoning: item.clampedReasoning,
                isCompleted: false,
                sortOrder: index,
                snapshot: snapshot
            )
            modelContext.insert(card)
            cards.append(card)
        }
        snapshot.actionCards = cards

        try? modelContext.save()
    }

    private func enterWithDemoProfile() {
        clearExistingUserDataForRebuild()
        MockDataSeeder.seedIfNeeded(in: modelContext)
        HapticFeedback.impact(.light)
        onCompleted()
    }

    private func clearExistingUserDataForRebuild() {
        let profiles = (try? modelContext.fetch(FetchDescriptor<UserConstitutionProfile>())) ?? []
        profiles.forEach { modelContext.delete($0) }

        let phases = (try? modelContext.fetch(FetchDescriptor<RegimenPhase>())) ?? []
        phases.forEach { modelContext.delete($0) }

        let snapshots = (try? modelContext.fetch(FetchDescriptor<DailyContextSnapshot>())) ?? []
        snapshots.forEach { modelContext.delete($0) }

        let records = (try? modelContext.fetch(FetchDescriptor<ConstitutionEvolutionRecord>())) ?? []
        records.forEach { modelContext.delete($0) }
    }

    private func prefillWeightFromHealthKit() async {
        isSyncingHealthWeight = true
        defer { isSyncingHealthWeight = false }

        let data = await HealthKitSyncService.shared.syncTodayMetrics()
        if let weight = data.latestWeightKG {
            weightKG = weight
            healthFillMessage = String(format: "已从 Apple 健康读取当前体重：%.1f kg", weight)
        } else {
            healthFillMessage = data.statusMessage
        }
    }

    private func fetchWeatherInOnboarding() async {
        isFetchingWeather = true
        defer { isFetchingWeather = false }

        if let weather = await WeatherContextService.shared.fetchCurrentWeather() {
            city = weather.city
            weatherTempC = weather.tempC
            weatherCondition = weather.condition
            weatherHumidity = weather.humidityPercent
            weatherWindKmh = weather.windSpeedKmh
            weatherSource = weather.source
            weatherStatusMessage = "已同步 \(weather.city) \(Int(weather.tempC.rounded()))°C \(weather.condition)（\(weather.source)）"
        } else {
            weatherStatusMessage = "暂未获取定位，将默认按 \(city) \(Int(weatherTempC.rounded()))°C 作为气候基线。"
        }
    }

    private func enableNotificationsInOnboarding() async {
        let granted = await GentleNotificationService.shared.requestAuthorization()
        notificationEnabled = granted
        var prefs = NotificationPreferences.load()
        prefs.isEnabled = granted
        prefs.save()
        notificationStatusMessage = granted ? "温和提醒已准备就绪。" : "未获得通知权限，后续可在首页铃铛设置。"
    }

    private func recognizeReportPhoto(_ item: PhotosPickerItem) async {
        isRecognizingReport = true
        defer { isRecognizingReport = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let text = try? await ConstitutionReportParser.recognizeText(from: image) else {
            return
        }
        reportText = text
        let parsed = ConstitutionReportParser.parse(text: text)
        if let h = parsed.heightCM { heightCM = h }
        if let w = parsed.weightKG { weightKG = w }
        if let tw = parsed.targetWeightKG { targetWeightKG = tw }
    }
}

private struct SelectableChipsWrap: View {
    let presets: [String]
    @Binding var selected: [String]
    let tint: Color

    private var allDisplayItems: [String] {
        var merged = presets
        for custom in selected where !merged.contains(custom) {
            merged.append(custom)
        }
        return merged
    }

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(allDisplayItems, id: \.self) { item in
                let isSelected = selected.contains(item)
                let isCustom = !presets.contains(item)
                Button {
                    HapticFeedback.impact(.light)
                    if isSelected {
                        selected.removeAll { $0 == item }
                    } else {
                        selected.append(item)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(item)
                            .font(.caption.weight(.medium))
                        if isCustom && isSelected {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .foregroundStyle(isSelected ? .white : AuraTheme.primaryText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(isSelected ? tint : AuraTheme.subtleSurface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    OnboardingFlowView(onCompleted: {})
        .modelContainer(PreviewSupport.makeContainer())
}
