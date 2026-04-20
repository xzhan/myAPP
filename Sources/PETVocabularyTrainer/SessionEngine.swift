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
        let distractors = Array((sameTopic + otherTopics).uniqued().prefix(3))
        return ([word.primaryChinese] + distractors).shuffled()
    }
}

enum FeedbackGenerator {
    static func makeSummary(from session: ActiveSession, wordsByID: [String: VocabularyWord]) -> FeedbackSummary {
        let incorrectAttempts = session.attempts.filter { !$0.isCorrect }
        let weakTopics = Dictionary(grouping: incorrectAttempts, by: \.topic)
            .sorted { lhs, rhs in lhs.value.count > rhs.value.count }
            .map(\.key)

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

        let recommendedMission: String
        if let firstWeak = weakTopics.first {
            recommendedMission = "Retry 8 weak \(firstWeak.displayName.lowercased()) words"
        } else {
            recommendedMission = "Start another mixed PET mission"
        }

        let body = "You answered \(session.correctAnswers) of \(session.questions.count) correctly and mastered \(masteredCount) new PET \(wordLabel). \(topicSentence)"

        return FeedbackSummary(
            headline: headline,
            body: body,
            weakTopics: Array(weakTopics.prefix(2)),
            recommendedMissionTitle: recommendedMission
        )
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
