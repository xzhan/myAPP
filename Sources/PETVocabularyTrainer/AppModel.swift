import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Screen {
        case loading
        case onboarding
        case dashboard
        case quiz
        case summary
        case review
        case history
    }

    private let store: LocalStore
    private let autoAdvanceDelayMultiplier: Double
    private let sleepForNanoseconds: @Sendable (UInt64) async -> Void
    private var autoAdvanceTask: Task<Void, Never>?

    var words: [VocabularyWord] = []
    var data = AppStoreData()
    var screen: Screen = .loading
    var latestSummary: SessionSummary?
    var errorMessage: String?
    var answerFeedback: QuizAnswerFeedback?
    var quizStepID = UUID()
    var isShowingLibraryImporter = false

    init(
        store: LocalStore = LocalStore(),
        autoAdvanceDelayMultiplier: Double = 1.0,
        sleepForNanoseconds: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.store = store
        self.autoAdvanceDelayMultiplier = autoAdvanceDelayMultiplier
        self.sleepForNanoseconds = sleepForNanoseconds
    }

    var wordsByID: [String: VocabularyWord] {
        Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
    }

    var dashboardStats: DashboardStats {
        let masteredCount = data.progressByWordID.values.filter(\.isMastered).count
        let masteryPercent = ProgressAnalytics.masteryPercent(masteredCount: masteredCount, totalWordCount: words.count)
        let reviewCount = data.progressByWordID.values.filter { $0.reviewPriority > 0 }.count
        let focusTopics = ProgressAnalytics.focusTopics(words: words, data: data)
        let missionTitle: String
        if !data.hasCompletedPlacement {
            missionTitle = "Take your placement test"
        } else if reviewCount > 0 {
            missionTitle = "Review Rescue"
        } else {
            missionTitle = "Daily Sprint"
        }

        return DashboardStats(
            masteredCount: masteredCount,
            totalWordCount: words.count,
            masteryPercent: masteryPercent,
            reviewCount: reviewCount,
            dailyStreak: data.dailyStreak,
            totalPoints: ProgressAnalytics.totalPoints(from: data.sessions),
            rankTitle: ProgressAnalytics.rankTitle(forMasteryPercent: masteryPercent),
            missionTitle: missionTitle,
            missionSubtitle: ProgressAnalytics.missionSubtitle(
                hasCompletedPlacement: data.hasCompletedPlacement,
                reviewCount: reviewCount,
                focusTopics: focusTopics,
                dailyStreak: data.dailyStreak
            ),
            focusTopics: focusTopics
        )
    }

    var currentSession: ActiveSession? {
        data.activeSession
    }

    var currentQuestionWord: VocabularyWord? {
        guard let session = data.activeSession,
              session.currentIndex < session.questions.count else { return nil }
        let question = session.questions[session.currentIndex]
        return wordsByID[question.wordID]
    }

    var currentQuestionChoices: [String] {
        guard let session = data.activeSession,
              session.currentIndex < session.questions.count else { return [] }
        return session.questions[session.currentIndex].choices
    }

    var currentQuestionNumber: Int {
        guard let session = data.activeSession else { return 0 }
        return min(session.currentIndex + 1, session.questions.count)
    }

    var quizProgressCount: Int {
        guard let session = data.activeSession else { return 0 }
        let completedCount = session.currentIndex + (answerFeedback == nil ? 0 : 1)
        return min(completedCount, session.questions.count)
    }

    var currentAccuracyPercent: Int {
        guard let session = data.activeSession, !session.attempts.isEmpty else { return 0 }
        return Int((Double(session.correctAnswers) / Double(session.attempts.count)) * 100.0)
    }

    var currentWordProgress: WordProgress? {
        guard let word = currentQuestionWord else { return nil }
        return data.progressByWordID[word.id] ?? .fresh(for: word.id)
    }

    var latestPointsEarned: Int {
        latestSummary?.pointsEarned ?? 0
    }

    var latestPlacementSummary: SessionSummary? {
        sessionHistory.first { $0.mode == .placement }
    }

    var latestPlacementEstimate: PlacementEstimate? {
        guard let summary = latestPlacementSummary else { return nil }
        return PlacementEstimator.estimate(
            correctAnswers: summary.correctAnswers,
            totalQuestions: summary.totalQuestions
        )
    }

    var latestPlacementStudyPlan: PlacementStudyPlan? {
        guard let summary = latestPlacementSummary else { return nil }
        return PlacementPlanner.plan(
            correctAnswers: summary.correctAnswers,
            totalQuestions: summary.totalQuestions,
            weakTopics: summary.weakTopics,
            topicInsights: summary.placementTopicInsights ?? []
        )
    }

    var personalizedMissionPlan: PersonalizedMissionPlan? {
        MissionPersonalizer.plan(
            from: latestPlacementStudyPlan,
            reviewCount: dashboardStats.reviewCount,
            dailyStreak: data.dailyStreak
        )
    }

    var wordBankSnapshot: WordBankSnapshot {
        if let importedLibrary = data.importedLibrary {
            return WordBankSnapshot(
                title: importedLibrary.name,
                subtitle: "\(importedLibrary.source.displayName) import from \(importedLibrary.sourceFilename). Placement and daily missions now use this full bank.",
                wordCount: words.count,
                badgeText: "\(importedLibrary.source.displayName.uppercased()) IMPORT",
                isImported: true
            )
        }

        return WordBankSnapshot(
            title: "Built-in PET Starter",
            subtitle: "A bundled starter list for quick testing. Import a full PET PDF, CSV, TXT, or JSON bank whenever you are ready.",
            wordCount: words.count,
            badgeText: "BUNDLED",
            isImported: false
        )
    }

    var livePlacementEstimate: PlacementEstimate? {
        guard let session = data.activeSession,
              session.mode == .placement,
              !session.attempts.isEmpty else { return nil }
        return PlacementEstimator.estimate(
            correctAnswers: session.correctAnswers,
            totalQuestions: session.attempts.count
        )
    }

    var reviewWords: [(word: VocabularyWord, progress: WordProgress)] {
        words.compactMap { word in
            guard let progress = data.progressByWordID[word.id], progress.reviewPriority > 0 else {
                return nil
            }
            return (word, progress)
        }
        .sorted { lhs, rhs in
            if lhs.progress.reviewPriority != rhs.progress.reviewPriority {
                return lhs.progress.reviewPriority > rhs.progress.reviewPriority
            }
            return lhs.word.english < rhs.word.english
        }
    }

    var sessionHistory: [SessionSummary] {
        data.sessions.sorted { $0.completedAt > $1.completedAt }
    }

    func bootstrap() {
        do {
            let seedWords = try SeedWordLoader.loadWords()
            var loadedData = try store.load()
            let importedWords = try store.loadImportedWords()

            if let importedWords {
                let metadata = loadedData.importedLibrary ?? WordLibraryMetadata(
                    name: "Imported PET Word Bank",
                    sourceFilename: "imported_words.json",
                    importedAt: .now,
                    wordCount: importedWords.count,
                    source: .json
                )
                loadedData.importedLibrary = metadata
                words = importedWords
            } else {
                if loadedData.importedLibrary != nil {
                    loadedData = AppStoreData()
                }
                words = seedWords
            }

            data = loadedData
            ensureProgressEntries()
            latestSummary = sessionHistory.first

            if data.activeSession != nil {
                screen = .quiz
            } else if data.hasCompletedPlacement {
                screen = .dashboard
            } else {
                screen = .onboarding
            }

            try persist()
        } catch {
            errorMessage = error.localizedDescription
            screen = .onboarding
        }
    }

    func openDashboard() {
        cancelAutoAdvance()
        screen = .dashboard
    }

    func openReview() {
        cancelAutoAdvance()
        screen = .review
    }

    func openHistory() {
        cancelAutoAdvance()
        screen = .history
    }

    func requestVocabularyImport() {
        isShowingLibraryImporter = true
    }

    func handleVocabularyImportSelection(_ result: Result<URL, Error>) {
        isShowingLibraryImporter = false

        switch result {
        case .success(let url):
            importVocabulary(from: url)
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func resetToBundledWordBank() {
        cancelAutoAdvance()

        do {
            words = try SeedWordLoader.loadWords()
            data = AppStoreData()
            latestSummary = nil
            answerFeedback = nil
            quizStepID = UUID()
            screen = .onboarding
            try store.deleteImportedWords()
            ensureProgressEntries()
            try persist()
            errorMessage = "Returned to the bundled starter word bank."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startPlacement() {
        let questions = SessionPlanner.placementQuestions(words: words, data: data, count: min(100, words.count))
        startSession(mode: .placement, questions: questions)
    }

    func startMission() {
        let recommendedCount = personalizedMissionPlan?.recommendedQuestionCount ?? 15
        let count = min(words.count, max(10, min(recommendedCount, 20)))
        let questions = SessionPlanner.missionQuestions(
            words: words,
            data: data,
            count: count,
            preferredTopics: personalizedMissionPlan?.focusTopics ?? []
        )
        startSession(mode: .mission, questions: questions)
    }

    func startFailedReview() {
        let questions = SessionPlanner.failedReviewQuestions(words: words, data: data, count: 10)
        startSession(mode: .failedReview, questions: questions)
    }

    func submit(choice: String) {
        guard var session = data.activeSession,
              session.currentIndex < session.questions.count,
              answerFeedback == nil,
              let word = currentQuestionWord else {
            return
        }

        let isCorrect = choice == word.primaryChinese
        let attempt = AttemptRecord(
            sessionID: session.id,
            wordID: word.id,
            selectedChoice: choice,
            correctChoice: word.primaryChinese,
            isCorrect: isCorrect,
            topic: word.topic
        )
        session.attempts.append(attempt)
        session.correctAnswers += isCorrect ? 1 : 0

        var progress = data.progressByWordID[word.id] ?? .fresh(for: word.id)
        let newlyMastered = MasteryEngine.applyAttempt(to: &progress, isCorrect: isCorrect, answeredAt: attempt.answeredAt)
        data.progressByWordID[word.id] = progress
        if newlyMastered {
            session.newlyMasteredWordIDs.append(word.id)
        }

        data.activeSession = session
        let feedback = makeAnswerFeedback(
            selectedChoice: choice,
            correctChoice: word.primaryChinese,
            isCorrect: isCorrect,
            newlyMastered: newlyMastered,
            resultingStreak: progress.currentCorrectStreak
        )
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            answerFeedback = feedback
        }
        scheduleAutoAdvance(for: feedback)
    }

    func advanceAfterFeedback(triggeredAutomatically: Bool = false) {
        guard var session = data.activeSession, answerFeedback != nil else {
            return
        }

        if triggeredAutomatically {
            autoAdvanceTask = nil
        } else {
            cancelAutoAdvance()
        }

        answerFeedback = nil
        session.currentIndex += 1

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            quizStepID = UUID()
        }

        if session.currentIndex >= session.questions.count {
            finish(session: session)
        } else {
            data.activeSession = session
            try? persist()
        }
    }

    private func startSession(mode: SessionMode, questions: [PersistedQuestion]) {
        guard !questions.isEmpty else {
            errorMessage = "No words are available for this session yet."
            screen = .dashboard
            return
        }

        cancelAutoAdvance()
        latestSummary = nil
        errorMessage = nil
        answerFeedback = nil
        quizStepID = UUID()
        data.activeSession = ActiveSession(mode: mode, questions: questions)
        screen = .quiz
        try? persist()
    }

    private func finish(session: ActiveSession) {
        cancelAutoAdvance()
        let feedback = FeedbackGenerator.makeSummary(from: session, wordsByID: wordsByID)
        let completedAt = Date()
        let placementTopicInsights = session.mode == .placement
            ? PlacementPlanner.topicInsights(from: session.attempts)
            : nil
        let summary = SessionSummary(
            mode: session.mode,
            startedAt: session.startedAt,
            completedAt: completedAt,
            totalQuestions: session.questions.count,
            correctAnswers: session.correctAnswers,
            newlyMasteredCount: session.newlyMasteredWordIDs.count,
            weakTopics: feedback.weakTopics,
            headline: feedback.headline,
            body: feedback.body,
            recommendedMissionTitle: feedback.recommendedMissionTitle,
            placementTopicInsights: placementTopicInsights
        )

        if session.mode == .placement {
            data.hasCompletedPlacement = true
        }

        updateDailyStreak(completedAt)
        data.sessions.insert(summary, at: 0)
        data.activeSession = nil
        latestSummary = summary
        screen = .summary
        try? persist()
    }

    private func updateDailyStreak(_ date: Date) {
        let today = DayKey.forDate(date)
        guard data.lastCompletedDayKey != today else { return }

        if let lastKey = data.lastCompletedDayKey,
           let lastDate = ISO8601DateFormatter.dayDate(from: lastKey),
           Calendar(identifier: .gregorian).dateComponents([.day], from: lastDate, to: date).day == 1 {
            data.dailyStreak += 1
        } else {
            data.dailyStreak = 1
        }

        data.lastCompletedDayKey = today
    }

    private func ensureProgressEntries() {
        for word in words where data.progressByWordID[word.id] == nil {
            data.progressByWordID[word.id] = .fresh(for: word.id)
        }
    }

    private func importVocabulary(from url: URL) {
        cancelAutoAdvance()

        do {
            let seedWords = try SeedWordLoader.loadWords()
            let importedLibrary = try VocabularyImportService.importWordLibrary(from: url, seedWords: seedWords)
            try store.saveImportedWords(importedLibrary.words)

            words = importedLibrary.words
            data = AppStoreData()
            data.importedLibrary = importedLibrary.metadata
            latestSummary = nil
            answerFeedback = nil
            quizStepID = UUID()
            screen = .onboarding
            ensureProgressEntries()
            try persist()
            errorMessage = "Imported \(importedLibrary.metadata.wordCount) words from \(importedLibrary.metadata.sourceFilename). Your next test will use this bank."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeAnswerFeedback(
        selectedChoice: String,
        correctChoice: String,
        isCorrect: Bool,
        newlyMastered: Bool,
        resultingStreak: Int
    ) -> QuizAnswerFeedback {
        let pointsEarned = (isCorrect ? 10 : 0) + (newlyMastered ? 25 : 0)
        let autoAdvanceDelay: TimeInterval
        let headline: String
        let detail: String

        if newlyMastered {
            autoAdvanceDelay = 1.85
            headline = "Mastery unlocked"
            detail = "You got it right and completed the 3-correct streak for this word."
        } else if isCorrect && resultingStreak == 2 {
            autoAdvanceDelay = 1.45
            headline = "Nice work"
            detail = "One more correct answer on a later attempt will mark this word as mastered."
        } else if isCorrect {
            autoAdvanceDelay = 1.2
            headline = "Correct"
            detail = "You chose the right Chinese meaning. Keep building the streak."
        } else {
            autoAdvanceDelay = 1.75
            headline = "Not quite"
            detail = "The correct answer is \(correctChoice). This word will return soon in review."
        }

        return QuizAnswerFeedback(
            selectedChoice: selectedChoice,
            correctChoice: correctChoice,
            isCorrect: isCorrect,
            newlyMastered: newlyMastered,
            resultingStreak: resultingStreak,
            pointsEarned: pointsEarned,
            autoAdvanceDelay: autoAdvanceDelay,
            headline: headline,
            detail: detail
        )
    }

    private func scheduleAutoAdvance(for feedback: QuizAnswerFeedback) {
        cancelAutoAdvance()

        let delay = max(0, feedback.autoAdvanceDelay * autoAdvanceDelayMultiplier)
        autoAdvanceTask = Task { [sleepForNanoseconds, weak self] in
            await sleepForNanoseconds(UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.answerFeedback != nil else { return }
                self.advanceAfterFeedback(triggeredAutomatically: true)
            }
        }
    }

    private func cancelAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
    }

    private func persist() throws {
        try store.save(data)
    }
}

private extension ISO8601DateFormatter {
    static func dayDate(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}
