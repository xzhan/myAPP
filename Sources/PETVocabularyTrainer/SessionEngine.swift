import Foundation

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

enum MasteryEngine {
    @discardableResult
    static func applyAttempt(to progress: inout WordProgress, isCorrect: Bool, answeredAt: Date) -> Bool {
        let wasMastered = progress.isMastered
        progress.lastSeenAt = answeredAt

        if isCorrect {
            progress.currentCorrectStreak += 1
            progress.totalCorrect += 1
            progress.reviewPriority = max(0, progress.reviewPriority - 1)
        } else {
            progress.currentCorrectStreak = 0
            progress.totalIncorrect += 1
            progress.lastIncorrectAt = answeredAt
            progress.reviewPriority += 2
        }

        progress.isMastered = progress.currentCorrectStreak >= 3
        return !wasMastered && progress.isMastered
    }
}

enum SessionPlanner {
    static func placementQuestions(words: [VocabularyWord], data: AppStoreData, count: Int = 20) -> [PersistedQuestion] {
        let ordered = words
            .filter { !progress(for: $0.id, in: data).isMastered }
            .sorted { $0.english.localizedCaseInsensitiveCompare($1.english) == .orderedAscending }
        return buildQuestions(from: Array(ordered.prefix(count)), allWords: words)
    }

    static func missionQuestions(words: [VocabularyWord], data: AppStoreData, count: Int = 15) -> [PersistedQuestion] {
        let failed = wordsMatching(words: words, data: data) { progress in
            progress.reviewPriority > 0
        }
        .sorted { lhs, rhs in
            let leftProgress = progress(for: lhs.id, in: data)
            let rightProgress = progress(for: rhs.id, in: data)
            if leftProgress.reviewPriority != rightProgress.reviewPriority {
                return leftProgress.reviewPriority > rightProgress.reviewPriority
            }
            return (leftProgress.lastIncorrectAt ?? .distantPast) > (rightProgress.lastIncorrectAt ?? .distantPast)
        }

        let reviewing = wordsMatching(words: words, data: data) { progress in
            !progress.isMastered && progress.reviewPriority == 0 && progress.totalAttempts > 0
        }
        .sorted { lhs, rhs in lhs.english < rhs.english }

        let newWords = wordsMatching(words: words, data: data) { progress in
            progress.totalAttempts == 0
        }
        .sorted { lhs, rhs in lhs.english < rhs.english }

        let ordered = (failed + reviewing + newWords).uniqued()
        let chosen = Array(ordered.prefix(max(1, count)))
        return buildQuestions(from: chosen, allWords: words)
    }

    static func failedReviewQuestions(words: [VocabularyWord], data: AppStoreData, count: Int = 10) -> [PersistedQuestion] {
        let failed = wordsMatching(words: words, data: data) { progress in
            progress.reviewPriority > 0
        }
        .sorted { lhs, rhs in
            let leftProgress = progress(for: lhs.id, in: data)
            let rightProgress = progress(for: rhs.id, in: data)
            if leftProgress.reviewPriority != rightProgress.reviewPriority {
                return leftProgress.reviewPriority > rightProgress.reviewPriority
            }
            return (leftProgress.lastIncorrectAt ?? .distantPast) > (rightProgress.lastIncorrectAt ?? .distantPast)
        }

        let chosen = Array(failed.prefix(max(1, count)))
        return chosen.isEmpty ? missionQuestions(words: words, data: data, count: count) : buildQuestions(from: chosen, allWords: words)
    }

    private static func wordsMatching(words: [VocabularyWord], data: AppStoreData, predicate: (WordProgress) -> Bool) -> [VocabularyWord] {
        words.filter { predicate(progress(for: $0.id, in: data)) }
    }

    private static func progress(for wordID: String, in data: AppStoreData) -> WordProgress {
        data.progressByWordID[wordID] ?? .fresh(for: wordID)
    }

    private static func buildQuestions(from selected: [VocabularyWord], allWords: [VocabularyWord]) -> [PersistedQuestion] {
        selected.map { word in
            let choices = buildChoices(for: word, allWords: allWords)
            return PersistedQuestion(wordID: word.id, choices: choices)
        }
    }

    private static func buildChoices(for word: VocabularyWord, allWords: [VocabularyWord]) -> [String] {
        let sameTopic = allWords
            .filter { $0.id != word.id && $0.topic == word.topic }
            .map(\.primaryChinese)
        let otherTopics = allWords
            .filter { $0.id != word.id && $0.topic != word.topic }
            .map(\.primaryChinese)
        let cleanedChoices = ([word.primaryChinese] + sameTopic + otherTopics)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()

        if cleanedChoices.count >= 4 {
            return Array(cleanedChoices.prefix(4)).shuffled()
        }

        return cleanedChoices.shuffled()
    }
}

enum FeedbackGenerator {
    static func makeSummary(from session: ActiveSession, wordsByID: [String: VocabularyWord]) -> FeedbackSummary {
        let incorrectAttempts = session.attempts.filter { !$0.isCorrect }
        let weakTopics = Dictionary(grouping: incorrectAttempts, by: \.topic)
            .sorted { lhs, rhs in lhs.value.count > rhs.value.count }
            .map(\.key)

        if session.mode == .placement {
            let estimate = PlacementEstimator.estimate(
                correctAnswers: session.correctAnswers,
                totalQuestions: session.questions.count
            )
            let weakTopicText = weakTopics.first?.displayName.lowercased() ?? "mixed PET topics"
            let body = "You answered \(session.correctAnswers) of \(session.questions.count) correctly. Your estimated PET-style vocabulary is about \(estimate.estimatedVocabularySize) words out of a 3,000-word benchmark. \(estimate.guidance)"

            return FeedbackSummary(
                headline: "Placement complete",
                body: body,
                weakTopics: Array(weakTopics.prefix(2)),
                recommendedMissionTitle: "Start daily review for \(weakTopicText)"
            )
        }

        let masteredCount = session.newlyMasteredWordIDs.count
        let wordLabel = masteredCount == 1 ? "word" : "words"
        let headline: String
        switch Double(session.correctAnswers) / Double(max(session.questions.count, 1)) {
        case 0.9...: headline = "Excellent work"
        case 0.7...: headline = "Nice work"
        default: headline = "Keep going"
        }

        let topicSentence: String
        if let firstWeak = weakTopics.first {
            topicSentence = "\(firstWeak.displayName) words still need attention."
        } else {
            topicSentence = "You kept the momentum going across topics."
        }

        let masteredWordHighlight: String
        if let firstMastered = session.newlyMasteredWordIDs.first,
           let word = wordsByID[firstMastered] {
            masteredWordHighlight = "You locked in \(word.english)."
        } else if masteredCount > 0 {
            masteredWordHighlight = "Your review loop is paying off."
        } else {
            masteredWordHighlight = "Your next mission can push this higher."
        }

        let recommendedMission: String
        if let firstWeak = weakTopics.first {
            recommendedMission = "Retry 8 weak \(firstWeak.displayName.lowercased()) words"
        } else {
            recommendedMission = "Start another mixed PET mission"
        }

        let body = "You answered \(session.correctAnswers) of \(session.questions.count) correctly and mastered \(masteredCount) new PET \(wordLabel). \(masteredWordHighlight) \(topicSentence)"

        return FeedbackSummary(
            headline: headline,
            body: body,
            weakTopics: Array(weakTopics.prefix(2)),
            recommendedMissionTitle: recommendedMission
        )
    }
}

enum PlacementEstimator {
    static let benchmarkVocabularySize = 3_000

    static func estimate(correctAnswers: Int, totalQuestions: Int) -> PlacementEstimate {
        let ratio = max(0, min(Double(correctAnswers) / Double(max(totalQuestions, 1)), 1.0))
        let rawEstimate = Int((ratio * Double(benchmarkVocabularySize)).rounded())
        let roundedEstimate = Int((Double(rawEstimate) / 50.0).rounded() * 50.0)

        let placementBand: String
        let guidance: String

        switch roundedEstimate {
        case ..<1_200:
            placementBand = "Foundation Builder"
            guidance = "Focus on high-frequency review first and use daily missions to build your base."
        case ..<1_800:
            placementBand = "Emerging PET"
            guidance = "You already have a base. Daily missions should grow this quickly, especially on missed words."
        case ..<2_400:
            placementBand = "PET Developing"
            guidance = "You are entering a strong PET range. Keep pushing weak topics and failed-word review."
        case ..<2_800:
            placementBand = "PET Strong"
            guidance = "You already know a solid PET-style core. Now focus on accuracy and finishing weaker topic groups."
        default:
            placementBand = "PET Ready"
            guidance = "You are performing near the top of this 3,000-word benchmark. Use missions to sharpen consistency."
        }

        return PlacementEstimate(
            estimatedVocabularySize: roundedEstimate,
            benchmarkVocabularySize: benchmarkVocabularySize,
            placementBand: placementBand,
            guidance: guidance
        )
    }
}

enum ProgressAnalytics {
    static func totalPoints(from sessions: [SessionSummary]) -> Int {
        sessions.reduce(0) { $0 + $1.pointsEarned }
    }

    static func masteryPercent(masteredCount: Int, totalWordCount: Int) -> Int {
        guard totalWordCount > 0 else { return 0 }
        return Int((Double(masteredCount) / Double(totalWordCount)) * 100.0)
    }

    static func rankTitle(forMasteryPercent masteryPercent: Int) -> String {
        switch masteryPercent {
        case 0..<15: return "Explorer"
        case 15..<35: return "Pathfinder"
        case 35..<60: return "Climber"
        case 60..<85: return "Navigator"
        default: return "Champion"
        }
    }

    static func focusTopics(words: [VocabularyWord], data: AppStoreData, limit: Int = 3) -> [WordTopic] {
        let wordsByID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        let queueTopics = data.progressByWordID.values
            .filter { $0.reviewPriority > 0 }
            .sorted { lhs, rhs in
                if lhs.reviewPriority != rhs.reviewPriority {
                    return lhs.reviewPriority > rhs.reviewPriority
                }
                return (lhs.lastIncorrectAt ?? .distantPast) > (rhs.lastIncorrectAt ?? .distantPast)
            }
            .compactMap { wordsByID[$0.wordID]?.topic }

        let historyTopics = data.sessions.prefix(5).flatMap(\.weakTopics)
        return Array((queueTopics + historyTopics).uniqued().prefix(limit))
    }

    static func missionSubtitle(hasCompletedPlacement: Bool, reviewCount: Int, focusTopics: [WordTopic], dailyStreak: Int) -> String {
        if !hasCompletedPlacement {
            return "Get your first baseline before you start chasing streaks."
        }
        if reviewCount > 0 {
            let focusText = focusTopics.first?.displayName.lowercased() ?? "your weak topics"
            return "Priority mission: rescue review words and tighten up \(focusText)."
        }
        if dailyStreak > 1 {
            return "Keep your \(dailyStreak)-day streak alive with a fresh 15-word sprint."
        }
        return "Build momentum with a fresh mixed mission and start stacking points."
    }
}

enum DayKey {
    static func forDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
