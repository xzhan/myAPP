import Foundation

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

enum ReviewScheduler {
    static let dailyTargetWordCount = 45
    static let spacedIntervals: [TimeInterval] = [
        10 * 60,
        24 * 60 * 60,
        2 * 24 * 60 * 60,
        4 * 24 * 60 * 60,
        7 * 24 * 60 * 60
    ]
    static let spacedIntervalLabels = [
        "10 minutes",
        "1 day",
        "2 days",
        "4 days",
        "7 days"
    ]

    static func isScheduled(_ progress: WordProgress) -> Bool {
        progress.nextReviewAt != nil || progress.reviewPriority > 0
    }

    static func isDue(_ progress: WordProgress, now: Date = .now) -> Bool {
        if let nextReviewAt = progress.nextReviewAt {
            return nextReviewAt <= now
        }
        return progress.reviewPriority > 0
    }

    static func registerFailure(to progress: inout WordProgress, answeredAt: Date) {
        progress.reviewStep = 0
        progress.nextReviewAt = answeredAt.addingTimeInterval(spacedIntervals[0])
    }

    static func recordRetrySignal(to progress: inout WordProgress, answeredAt: Date) {
        progress.retryMissCount += 1
        progress.lastRetryMissAt = answeredAt
        progress.reviewStep = 0
        let retryReminderAt = answeredAt.addingTimeInterval(spacedIntervals[0])
        if let nextReviewAt = progress.nextReviewAt {
            progress.nextReviewAt = min(nextReviewAt, retryReminderAt)
        } else {
            progress.nextReviewAt = retryReminderAt
        }
        progress.reviewPriority = max(progress.reviewPriority, 2)
    }

    static func registerSuccess(to progress: inout WordProgress, answeredAt: Date) {
        guard progress.nextReviewAt != nil || progress.totalIncorrect > 0 else { return }

        let nextStep = min(progress.reviewStep + 1, spacedIntervals.count - 1)
        progress.reviewStep = nextStep
        progress.nextReviewAt = answeredAt.addingTimeInterval(spacedIntervals[nextStep])
    }

    static var strategyDescription: String {
        "Missed words return in 10 minutes, 1 day, 2 days, 4 days, then 7 days."
    }

    static func stageLabel(forStep step: Int) -> String {
        let clampedStep = min(max(step, 0), spacedIntervalLabels.count - 1)
        return "Step \(clampedStep + 1) · \(spacedIntervalLabels[clampedStep])"
    }

    static func reminderCaption(for progress: WordProgress, now: Date = .now) -> String {
        guard let nextReviewAt = progress.nextReviewAt else {
            return isDue(progress, now: now) ? "Due now" : "Scheduled"
        }

        if nextReviewAt <= now {
            return "Due now"
        }

        return "Due \(nextReviewAt.formatted(date: .abbreviated, time: .shortened))"
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
            ReviewScheduler.registerSuccess(to: &progress, answeredAt: answeredAt)
        } else {
            progress.currentCorrectStreak = 0
            progress.totalIncorrect += 1
            progress.lastIncorrectAt = answeredAt
            progress.reviewPriority += 2
            ReviewScheduler.registerFailure(to: &progress, answeredAt: answeredAt)
        }

        progress.isMastered = progress.currentCorrectStreak >= 3
        if progress.isMastered {
            progress.reviewPriority = 0
            progress.nextReviewAt = nil
        }
        return !wasMastered && progress.isMastered
    }
}

enum SessionPlanner {
    static func placementQuestions(words: [VocabularyWord], data: AppStoreData, count: Int = 20) -> [PersistedQuestion] {
        let ordered = words
            .filter { !progress(for: $0.id, in: data).isMastered }
            .sorted { $0.english.localizedCaseInsensitiveCompare($1.english) == .orderedAscending }
        return buildQuestions(from: Array(ordered.prefix(count)), allWords: words, style: .meaningChoice)
    }

    static func missionQuestions(words: [VocabularyWord], data: AppStoreData, count: Int = 15, preferredTopics: [WordTopic] = []) -> [PersistedQuestion] {
        let now = Date()

        let failed = wordsMatching(words: words, data: data) { progress in
            ReviewScheduler.isDue(progress, now: now)
        }
        .sorted { lhs, rhs in
            let leftProgress = progress(for: lhs.id, in: data)
            let rightProgress = progress(for: rhs.id, in: data)
            let leftDate = leftProgress.nextReviewAt ?? leftProgress.lastIncorrectAt ?? .distantPast
            let rightDate = rightProgress.nextReviewAt ?? rightProgress.lastIncorrectAt ?? .distantPast
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            if leftProgress.reviewPriority != rightProgress.reviewPriority {
                return leftProgress.reviewPriority > rightProgress.reviewPriority
            }
            return (leftProgress.lastIncorrectAt ?? .distantPast) > (rightProgress.lastIncorrectAt ?? .distantPast)
        }

        let reviewing = wordsMatching(words: words, data: data) { progress in
            !progress.isMastered && progress.totalAttempts > 0 && !ReviewScheduler.isDue(progress, now: now)
        }
        .sorted { lhs, rhs in
            let leftProgress = progress(for: lhs.id, in: data)
            let rightProgress = progress(for: rhs.id, in: data)
            let leftScheduled = ReviewScheduler.isScheduled(leftProgress)
            let rightScheduled = ReviewScheduler.isScheduled(rightProgress)
            if leftScheduled != rightScheduled {
                return leftScheduled && !rightScheduled
            }
            let leftScore = topicPriority(for: lhs.topic, preferredTopics: preferredTopics)
            let rightScore = topicPriority(for: rhs.topic, preferredTopics: preferredTopics)
            if leftScore != rightScore {
                return leftScore < rightScore
            }
            return lhs.english < rhs.english
        }

        let newWords = wordsMatching(words: words, data: data) { progress in
            progress.totalAttempts == 0
        }
        .sorted { lhs, rhs in
            let leftScore = topicPriority(for: lhs.topic, preferredTopics: preferredTopics)
            let rightScore = topicPriority(for: rhs.topic, preferredTopics: preferredTopics)
            if leftScore != rightScore {
                return leftScore < rightScore
            }
            return lhs.english < rhs.english
        }

        let ordered = (failed + reviewing + newWords).uniqued()
        let chosen = Array(ordered.prefix(max(1, count)))
        return buildQuestions(from: chosen, allWords: words, style: .wordExercise)
    }

    static func failedReviewQuestions(words: [VocabularyWord], data: AppStoreData, count: Int = 10) -> [PersistedQuestion] {
        let now = Date()

        let failed = wordsMatching(words: words, data: data) { progress in
            ReviewScheduler.isScheduled(progress)
        }
        .sorted { lhs, rhs in
            let leftProgress = progress(for: lhs.id, in: data)
            let rightProgress = progress(for: rhs.id, in: data)
            let leftDue = ReviewScheduler.isDue(leftProgress, now: now)
            let rightDue = ReviewScheduler.isDue(rightProgress, now: now)
            if leftDue != rightDue {
                return leftDue && !rightDue
            }
            let leftDate = leftProgress.nextReviewAt ?? leftProgress.lastIncorrectAt ?? .distantPast
            let rightDate = rightProgress.nextReviewAt ?? rightProgress.lastIncorrectAt ?? .distantPast
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            if leftProgress.reviewPriority != rightProgress.reviewPriority {
                return leftProgress.reviewPriority > rightProgress.reviewPriority
            }
            return (leftProgress.lastIncorrectAt ?? .distantPast) > (rightProgress.lastIncorrectAt ?? .distantPast)
        }

        let chosen = Array(failed.prefix(max(1, count)))
        return chosen.isEmpty
            ? missionQuestions(words: words, data: data, count: count)
            : buildQuestions(from: chosen, allWords: words, style: .wordExercise)
    }

    static func pageQuestions(
        words: [VocabularyWord],
        wordIDs: [String],
        pageNumber: Int,
        pageTitle: String
    ) -> [PersistedQuestion] {
        let wordsByID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        let selectedWords = wordIDs.compactMap { wordsByID[$0] }
        return buildQuestions(
            from: selectedWords,
            allWords: words,
            style: .wordExercise,
            sourcePageNumber: pageNumber,
            sourcePageTitle: pageTitle
        )
    }

    private static func wordsMatching(words: [VocabularyWord], data: AppStoreData, predicate: (WordProgress) -> Bool) -> [VocabularyWord] {
        words.filter { predicate(progress(for: $0.id, in: data)) }
    }

    private static func progress(for wordID: String, in data: AppStoreData) -> WordProgress {
        data.progressByWordID[wordID] ?? .fresh(for: wordID)
    }

    private static func topicPriority(for topic: WordTopic, preferredTopics: [WordTopic]) -> Int {
        preferredTopics.firstIndex(of: topic) ?? Int.max
    }

    private static func buildQuestions(
        from selected: [VocabularyWord],
        allWords: [VocabularyWord],
        style: QuestionPresentationStyle,
        sourcePageNumber: Int? = nil,
        sourcePageTitle: String? = nil
    ) -> [PersistedQuestion] {
        selected.map { word in
            let choices = buildChoices(for: word, allWords: allWords)
            return PersistedQuestion(
                wordID: word.id,
                choices: choices,
                style: style,
                exampleSentence: style == .wordExercise ? ExampleSentenceGenerator.sentence(for: word) : nil,
                sourcePageNumber: sourcePageNumber,
                sourcePageTitle: sourcePageTitle
            )
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

enum ExampleSentenceGenerator {
    static func sentence(for word: VocabularyWord) -> String {
        let english = word.english.trimmingCharacters(in: .whitespacesAndNewlines)

        if looksLikeProperNoun(english) {
            return "They read a short article about \(english) in class today."
        }

        if looksLikeAdverb(english) {
            return "She answered \(english) during the speaking task."
        }

        if looksLikeAdjective(english) {
            return "After the discussion, everyone felt \(english) about the result."
        }

        if word.topic == .actions || looksLikeVerb(english) {
            return "Please \(english) the answer before the lesson ends."
        }

        switch word.topic {
        case .school:
            return "The teacher wrote \(english) on the board for today's review."
        case .travel:
            return "The travel guide mentioned \(english) on the first page."
        case .home:
            return "At home, they kept \(english) near the window."
        case .food:
            return "For lunch, she ordered \(english) with a warm drink."
        case .health:
            return "The doctor mentioned \(english) during the check-up."
        case .shopping:
            return "She bought \(english) at the market on Saturday."
        case .transport:
            return "They missed the \(english) and waited for the next one."
        case .work:
            return "At work, the manager asked for the \(english) before noon."
        case .people:
            return "Everyone said the \(english) was friendly and easy to talk to."
        case .feelings:
            return "He tried to hide the feeling of \(english) after the news."
        case .places:
            return "They were excited to visit \(english) during the school exchange."
        case .actions:
            return "Please \(english) the answer before the lesson ends."
        case .time:
            return "They planned to meet in the \(english) after class."
        case .communication:
            return "In the dialogue, she sent a short \(english) before dinner."
        }
    }

    private static func looksLikeProperNoun(_ english: String) -> Bool {
        guard let firstCharacter = english.first else { return false }
        return firstCharacter.isUppercase
    }

    private static func looksLikeAdverb(_ english: String) -> Bool {
        english.lowercased().hasSuffix("ly")
    }

    private static func looksLikeAdjective(_ english: String) -> Bool {
        let lowercased = english.lowercased()
        let suffixes = ["ous", "ful", "able", "ible", "ive", "al", "ic", "ish", "less"]
        return suffixes.contains { lowercased.hasSuffix($0) }
    }

    private static func looksLikeVerb(_ english: String) -> Bool {
        let lowercased = english.lowercased()
        let verbHints = ["ate", "fy", "ise", "ize", "ing", "ed", "en"]
        return verbHints.contains { lowercased.hasSuffix($0) }
    }
}

enum FeedbackGenerator {
    static func makeSummary(from session: ActiveSession, wordsByID: [String: VocabularyWord]) -> FeedbackSummary {
        let incorrectAttempts = session.attempts.filter { !$0.isCorrect }
        let weakTopics = Dictionary(grouping: incorrectAttempts, by: \.topic)
            .sorted { lhs, rhs in lhs.value.count > rhs.value.count }
            .map(\.key)

        if session.mode == .placement {
            let topicInsights = PlacementPlanner.topicInsights(from: session.attempts)
            let studyPlan = PlacementPlanner.plan(
                correctAnswers: session.correctAnswers,
                totalQuestions: session.questions.count,
                weakTopics: Array(weakTopics.prefix(3)),
                topicInsights: topicInsights
            )
            let weakTopicText = studyPlan.focusTopics.first?.displayName.lowercased() ?? "mixed PET topics"
            let body = "You answered \(session.correctAnswers) of \(session.questions.count) correctly. Your estimated PET-style vocabulary is about \(studyPlan.estimate.estimatedVocabularySize) words out of a 3,000-word benchmark, leaving about \(studyPlan.estimate.remainingToBenchmark) words to close the gap. \(studyPlan.estimate.guidance)"

            return FeedbackSummary(
                headline: "Placement complete",
                body: body,
                weakTopics: Array(weakTopics.prefix(2)),
                recommendedMissionTitle: "Start daily review for \(weakTopicText)"
            )
        }

        if session.mode == .failedReview {
            let totalQuestions = max(session.questions.count, 1)
            let rescuedCount = session.correctAnswers
            let waitingText = incorrectAttempts.isEmpty
                ? "Every word in this sprint is warmer now."
                : "\(incorrectAttempts.count) word\(incorrectAttempts.count == 1 ? "" : "s") will return on the memory curve."

            return FeedbackSummary(
                headline: "Rescue sprint cleared",
                body: "You rescued \(rescuedCount) of \(totalQuestions) words. That small win keeps the backlog friendly instead of boring. \(waitingText)",
                weakTopics: Array(weakTopics.prefix(2)),
                recommendedMissionTitle: "Choose next rescue step"
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
        let remainingToBenchmark = max(0, benchmarkVocabularySize - roundedEstimate)

        let placementBand: String
        let guidance: String
        let dailyGoalWords: Int

        switch roundedEstimate {
        case ..<1_200:
            placementBand = "Foundation Builder"
            guidance = "Focus on high-frequency review first and use daily missions to build your base."
            dailyGoalWords = 18
        case ..<1_800:
            placementBand = "Emerging PET"
            guidance = "You already have a base. Daily missions should grow this quickly, especially on missed words."
            dailyGoalWords = 16
        case ..<2_400:
            placementBand = "PET Developing"
            guidance = "You are entering a strong PET range. Keep pushing weak topics and failed-word review."
            dailyGoalWords = 14
        case ..<2_800:
            placementBand = "PET Strong"
            guidance = "You already know a solid PET-style core. Now focus on accuracy and finishing weaker topic groups."
            dailyGoalWords = 10
        default:
            placementBand = "PET Ready"
            guidance = "You are performing near the top of this 3,000-word benchmark. Use missions to sharpen consistency."
            dailyGoalWords = 8
        }

        let weeklyGoalWords = min(max(dailyGoalWords * 7, dailyGoalWords), max(remainingToBenchmark, dailyGoalWords))

        return PlacementEstimate(
            estimatedVocabularySize: roundedEstimate,
            benchmarkVocabularySize: benchmarkVocabularySize,
            remainingToBenchmark: remainingToBenchmark,
            placementBand: placementBand,
            guidance: guidance,
            dailyGoalWords: dailyGoalWords,
            weeklyGoalWords: weeklyGoalWords
        )
    }
}

enum PlacementPlanner {
    static func topicInsights(from attempts: [AttemptRecord]) -> [PlacementTopicInsight] {
        Dictionary(grouping: attempts, by: \.topic)
            .map { topic, groupedAttempts in
                PlacementTopicInsight(
                    topic: topic,
                    correctAnswers: groupedAttempts.filter(\.isCorrect).count,
                    totalQuestions: groupedAttempts.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.accuracyPercent != rhs.accuracyPercent {
                    return lhs.accuracyPercent < rhs.accuracyPercent
                }
                return lhs.totalQuestions > rhs.totalQuestions
            }
    }

    static func plan(
        correctAnswers: Int,
        totalQuestions: Int,
        weakTopics: [WordTopic],
        topicInsights: [PlacementTopicInsight] = []
    ) -> PlacementStudyPlan {
        let estimate = PlacementEstimator.estimate(correctAnswers: correctAnswers, totalQuestions: totalQuestions)
        let focusTopics = topicInsights.isEmpty
            ? Array(weakTopics.prefix(3))
            : Array(topicInsights.prefix(3).map(\.topic))
        let focusTopicText: String
        if focusTopics.isEmpty {
            focusTopicText = "mixed PET topics"
        } else if focusTopics.count == 1 {
            focusTopicText = focusTopics[0].displayName.lowercased()
        } else {
            focusTopicText = focusTopics.map { $0.displayName.lowercased() }.joined(separator: ", ")
        }

        let nextWeekActions = [
            "Target about \(estimate.dailyGoalWords) words per day for the next 7 days.",
            "Use review missions to close the remaining \(estimate.remainingToBenchmark) words toward the 3,000-word PET benchmark.",
            "Spend extra time on \(focusTopicText) because those were your weakest topics in the placement test."
        ]

        return PlacementStudyPlan(
            estimate: estimate,
            focusTopics: focusTopics,
            nextWeekActions: nextWeekActions,
            topicInsights: topicInsights
        )
    }
}

enum MissionPersonalizer {
    static func plan(from studyPlan: PlacementStudyPlan?, reviewCount: Int, dailyStreak: Int) -> PersonalizedMissionPlan? {
        guard let studyPlan else { return nil }

        let focusTopics = studyPlan.focusTopics
        let topicLabel: String
        if focusTopics.isEmpty {
            topicLabel = "Mixed PET"
        } else if focusTopics.count == 1 {
            topicLabel = focusTopics[0].displayName
        } else {
            topicLabel = focusTopics.prefix(2).map(\.displayName).joined(separator: " + ")
        }

        let questionCount = ReviewScheduler.dailyTargetWordCount
        let subtitle: String
        if reviewCount > 0 {
            subtitle = "Your 45-word plan starts with \(reviewCount) review words due now, then fills the rest with \(topicLabel.lowercased()) meaning, sentence, and spelling reinforcement."
        } else if dailyStreak > 1 {
            subtitle = "Keep your streak alive with a full 45-word \(topicLabel.lowercased()) study block tuned for meaning, sentence context, and spelling."
        } else {
            subtitle = "Start a 45-word \(topicLabel.lowercased()) study block with meaning choice, sentence clues, and spelling checks."
        }
        let freshWordCount = max(0, questionCount - min(reviewCount, questionCount))

        return PersonalizedMissionPlan(
            title: "\(topicLabel) 45-word plan",
            subtitle: subtitle,
            recommendedQuestionCount: questionCount,
            dueReviewCount: reviewCount,
            freshWordCount: freshWordCount,
            focusTopics: focusTopics,
            rewardText: "Finish all \(questionCount) words today to balance due review with fresh progress toward the \(studyPlan.estimate.remainingToBenchmark)-word gap."
        )
    }
}

enum ProgressAnalytics {
    static func totalPoints(from sessions: [SessionSummary]) -> Int {
        sessions.reduce(0) { $0 + $1.pointsEarned }
    }

    static func masteryPercent(masteredCount: Int, totalWordCount: Int) -> Int {
        guard totalWordCount > 0 else { return 0 }
        return Int((Double(masteredCount) / Double(totalWordCount) * 100.0).rounded())
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
            .filter { ReviewScheduler.isScheduled($0) }
            .sorted { lhs, rhs in
                let leftDate = lhs.nextReviewAt ?? lhs.lastIncorrectAt ?? .distantPast
                let rightDate = rhs.nextReviewAt ?? rhs.lastIncorrectAt ?? .distantPast
                if leftDate != rightDate {
                    return leftDate < rightDate
                }
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
            return "Today's 45-word plan starts with \(reviewCount) review words due now and tightens up \(focusText) through meaning, sentence, and spelling practice."
        }
        if dailyStreak > 1 {
            return "Keep your \(dailyStreak)-day streak alive with today's 45-word meaning and spelling plan."
        }
        return "Build momentum with a 45-word mixed plan and start stacking points."
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
