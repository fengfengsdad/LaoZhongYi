import Foundation
import UIKit
import Vision

struct ParsedConstitutionReport: Sendable {
    var heightCM: Double?
    var weightKG: Double?
    var targetWeightKG: Double?
    var constitutionTags: [String]
    var dietaryPreferences: [String]
    var fitnessPreferences: [String]
    var extractedText: String
}

enum ConstitutionReportParser {
    static func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            return ""
        }

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }

    static func parse(text: String) -> ParsedConstitutionReport {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let heightCM = firstMatch(
            in: normalized,
            pattern: #"(\d{3}(?:\.\d+)?)\s*(?:cm|CM|厘米)"#
        ).flatMap(Double.init)

        let weightKG = firstMatch(
            in: normalized,
            pattern: #"(?:体重|当前体重|Weight)?[：:\s]*(\d{2,3}(?:\.\d+)?)\s*(?:kg|KG|公斤)"#
        ).flatMap(Double.init)

        let targetWeightKG = firstMatch(
            in: normalized,
            pattern: #"(?:目标|目标体重)[：:\s]*(\d{2,3}(?:\.\d+)?)\s*(?:kg|KG|公斤)"#
        ).flatMap(Double.init)

        let knownConstitutions = [
            "痰湿质", "湿热质", "气虚质", "阳虚质", "阴虚质",
            "血瘀质", "气郁质", "特禀质", "平和质", "脾虚", "肠胃敏感", "轻微气虚"
        ]

        var tags: [String] = []
        for keyword in knownConstitutions {
            if normalized.contains(keyword) {
                let scorePattern = "\(keyword)[：:\\s]*(\\d{2,3})\\s*分"
                if let score = firstMatch(in: normalized, pattern: scorePattern) {
                    tags.append("\(keyword)\(score)分")
                } else {
                    tags.append(keyword)
                }
            }
        }

        var dietary: [String] = []
        let dietKeywords: [(String, String)] = [
            ("生冷", "忌生冷冰饮"),
            ("冰饮", "忌生冷冰饮"),
            ("海鲜", "少寒凉海鲜"),
            ("螃蟹", "少寒凉海鲜"),
            ("油腻", "少油腻甜食"),
            ("辛辣", "忌辛辣刺激"),
            ("温热", "偏爱温热汤羹"),
            ("清淡", "清淡少盐饮食")
        ]
        for (needle, tag) in dietKeywords where normalized.contains(needle) {
            if !dietary.contains(tag) {
                dietary.append(tag)
            }
        }

        var fitness: [String] = []
        let fitnessKeywords: [(String, String)] = [
            ("游泳", "室外游泳40min"),
            ("抗阻", "居家轻抗阻"),
            ("力量", "居家轻抗阻"),
            ("散步", "餐后快走/散步"),
            ("八段锦", "晨起八段锦拉伸"),
            ("瑜伽", "温和伸展训练")
        ]
        for (needle, tag) in fitnessKeywords where normalized.contains(needle) {
            if !fitness.contains(tag) {
                fitness.append(tag)
            }
        }

        return ParsedConstitutionReport(
            heightCM: heightCM,
            weightKG: weightKG,
            targetWeightKG: targetWeightKG,
            constitutionTags: tags,
            dietaryPreferences: dietary,
            fitnessPreferences: fitness,
            extractedText: normalized
        )
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }
}
