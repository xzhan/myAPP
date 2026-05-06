import Foundation

enum PronunciationAssessment {
    static func rate(spokenText: String, targetWord: String) -> PronunciationRating {
        let target = normalizedToken(targetWord)
        guard !target.isEmpty else { return .needsPractice }

        let tokens = normalizedTokens(from: spokenText)
        guard !tokens.isEmpty else { return .needsPractice }

        if tokens.contains(target) {
            return .clear
        }

        let compactSpeech = tokens.joined()
        if compactSpeech == target {
            return .almostThere
        }

        let candidates = tokens + [compactSpeech]
        let bestSimilarity = candidates
            .map { similarity(between: $0, and: target) }
            .max() ?? 0

        if bestSimilarity >= 0.92 {
            return .clear
        }
        if bestSimilarity >= 0.60 {
            return .almostThere
        }
        return .needsPractice
    }

    static func normalizedTokens(from text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map(normalizedToken)
            .filter { !$0.isEmpty }
    }

    private static func normalizedToken(_ text: String) -> String {
        text
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func similarity(between left: String, and right: String) -> Double {
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }

        let distance = editDistance(Array(left), Array(right))
        let length = max(left.count, right.count)
        return max(0, 1 - (Double(distance) / Double(length)))
    }

    private static func editDistance(_ left: [Character], _ right: [Character]) -> Int {
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex

            for rightIndex in 1...right.count {
                let substitutionCost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + substitutionCost
                )
            }

            swap(&previous, &current)
        }

        return previous[right.count]
    }
}
