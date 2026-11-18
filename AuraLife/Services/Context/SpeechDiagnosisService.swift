import AVFoundation
import Foundation
import Observation
@preconcurrency import Speech

@MainActor
@Observable
final class SpeechDiagnosisService {
    static let shared = SpeechDiagnosisService()

    private(set) var isRecording: Bool = false
    private(set) var transcript: String = ""
    private(set) var normalizedLevel: Double = 0.0
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var acousticSummary: String?
    private(set) var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timerTask: Task<Void, Never>?
    private var rmsSamples: [Double] = []
    private var recordingStartDate: Date?

    private init() {}

    func toggleRecording(onTranscriptUpdate: @escaping @MainActor (String) -> Void) async {
        if isRecording {
            stopRecording()
        } else {
            await startRecording(onTranscriptUpdate: onTranscriptUpdate)
        }
    }

    func startRecording(onTranscriptUpdate: @escaping @MainActor (String) -> Void) async {
        stopRecording()
        errorMessage = nil
        transcript = ""
        acousticSummary = nil
        rmsSamples.removeAll()

        let speechGranted = await requestSpeechPermission()
        guard speechGranted else {
            errorMessage = "未获得语音识别权限，请在系统设置中开启语音识别。"
            return
        }

        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            errorMessage = "未获得麦克风权限，请在系统设置中允许访问麦克风。"
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable else {
            errorMessage = "当前设备语音识别服务暂不可用，请稍后重试或直接打字输入。"
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = false
            }

            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0 else {
                errorMessage = "未检测到可用的音频输入通道（模拟器请确认麦克风或直接打字）。"
                return
            }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self, weak request] buffer, _ in
                request?.append(buffer)
                let rms = Self.computeRMS(from: buffer)
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    self.rmsSamples.append(rms)
                    self.normalizedLevel = min(1.0, max(0.0, rms * 14.0))
                }
            }

            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.recognitionRequest = request
            self.isRecording = true
            self.recordingStartDate = .now
            self.elapsedSeconds = 0

            timerTask = Task { @MainActor [weak self] in
                while let self, self.isRecording {
                    if let start = self.recordingStartDate {
                        self.elapsedSeconds = Date().timeIntervalSince(start)
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }

            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let errDesc = error?.localizedDescription

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let text {
                        self.transcript = text
                        onTranscriptUpdate(text)
                    }
                    if isFinal || errDesc != nil {
                        if let errDesc, self.transcript.isEmpty {
                            self.errorMessage = "语音识别中断：\(errDesc)"
                        }
                        self.finishInternalRecording()
                    }
                }
            }

            AILog.info("Speech", "已启动中文语音口述识别")
        } catch {
            AILog.error("Speech", "语音采集启动失败: \(error.localizedDescription)")
            errorMessage = "语音采集启动失败：\(error.localizedDescription)"
            finishInternalRecording()
        }
    }

    func stopRecording() {
        guard isRecording || audioEngine != nil else { return }
        recognitionRequest?.endAudio()
        finishInternalRecording()
    }

    private func finishInternalRecording() {
        timerTask?.cancel()
        timerTask = nil

        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        normalizedLevel = 0.0

        evaluateAcousticSummary()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func evaluateAcousticSummary() {
        guard !rmsSamples.isEmpty else { return }
        let avg = rmsSamples.reduce(0, +) / Double(rmsSamples.count)
        let quietRatio = Double(rmsSamples.filter { $0 < 0.012 }.count) / Double(rmsSamples.count)
        let charCount = transcript.trimmingCharacters(in: .whitespacesAndNewlines).count

        if avg < 0.018 || quietRatio > 0.72 {
            acousticSummary = "闻诊声息参考：声音偏轻细/停顿较多（若非故意压低音量，可作为气虚偏弱辅助参考）"
        } else if charCount > 0 && elapsedSeconds > 3.0 && Double(charCount) / elapsedSeconds > 4.2 {
            acousticSummary = "闻诊声息参考：语速偏快、吐字连贯"
        } else {
            acousticSummary = "闻诊声息参考：语音音量平稳、气机尚充"
        }
    }

    private func requestSpeechPermission() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return true }
        if current == .denied || current == .restricted { return false }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private nonisolated static func computeRMS(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0.0 }

        let samples = channelData[0]
        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = samples[index]
            sum += sample * sample
        }
        return sqrt(Double(sum) / Double(frameCount))
    }
}
