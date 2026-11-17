import Foundation
import SwiftData

@Model
final class ConstitutionEvolutionRecord {
    var id: UUID
    var date: Date
    var phaseName: String
    var stageKindRawValue: String
    var therapeuticPrinciple: String
    var outcomeTitle: String
    var clinicalNote: String
    var constitutionSnapshotTags: [String]
    var deltaSummary: String
    var toleranceNote: String
    var primaryConstitutionScore: Int?

    var stageKind: RegimenStageKind {
        RegimenStageKind.infer(from: stageKindRawValue)
    }

    init(
        id: UUID = UUID(),
        date: Date = .now,
        phaseName: String,
        stageKind: RegimenStageKind,
        therapeuticPrinciple: String,
        outcomeTitle: String,
        clinicalNote: String,
        constitutionSnapshotTags: [String],
        deltaSummary: String,
        toleranceNote: String,
        primaryConstitutionScore: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.phaseName = phaseName
        self.stageKindRawValue = stageKind.rawValue
        self.therapeuticPrinciple = therapeuticPrinciple
        self.outcomeTitle = outcomeTitle
        self.clinicalNote = clinicalNote
        self.constitutionSnapshotTags = constitutionSnapshotTags
        self.deltaSummary = deltaSummary
        self.toleranceNote = toleranceNote
        self.primaryConstitutionScore = primaryConstitutionScore ?? Self.extractScore(from: constitutionSnapshotTags)
    }

    static func extractScore(from tags: [String]) -> Int? {
        guard let first = tags.first else { return nil }
        let pattern = #"(\d{2,3})\s*分"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: first, range: NSRange(first.startIndex..., in: first)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: first) else {
            return nil
        }
        return Int(first[range])
    }
}
