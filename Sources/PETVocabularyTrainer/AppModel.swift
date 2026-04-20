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

    var words: [VocabularyWord] = []
    var data = AppStoreData()
    var screen: Screen = .loading
    var latestSummary: SessionSummary?
    var errorMessage: String?
    var answerFeedback: QuizAnswerFeedback?
    var quizStepID = UUID()

    init(store: LocalStore = LocalStore()) {
        self.store = store
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
            words = try SeedWordLoader.loadWords()
            data = try store.load()
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
        screen = .dashboard
    }

    func openReview() {
        screen = .review
    }

    func openHistory() {
        screen = .history
    }

    func startPlacement() {
        let questions = SessionPlanner.placementQuestions(words: words, data: data, count: min(100, words.count))
        startSession(mode: .placement, questions: questions)
    }

    func startMission() {
        let questions = SessionPlanner.missionQuestions(words: words, data: data, count: min(15, max(10, words.count)))
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
        answerFeedback = makeAnswerFeedback(
            selectedChoice: choice,
            correctChoice: word.primaryChinese,
            isCorrect: isCorrect,
            newlyMastered: newlyMastered,
            resultingStreak: progress.currentCorrectStreak
        )
    }

    func advanceAfterFeedback() {
        guard var session = data.activeSession, answerFeedback != nil else {
            return
        }

        answerFeedback = nil
        session.currentIndex += 1

        withAnimation(.easeInOut(duration: 0.28)) {
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

        latestSummary = nil
        errorMessage = nil
        answerFeedback = nil
        quizStepID = UUID()
        data.activeSession = ActiveSession(mode: mode, questions: questions)
        screen = .quiz
        try? persist()
    }

    private func finish(session: ActiveSession) {
        let feedback = FeedbackGenerator.makeSummary(from: session, wordsByID: wordsByID)
        let completedAt = Date()
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
            recommendedMissionTitle: feedback.recommendedMissionTitle
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

    private func makeAnswerFeedback(
        selectedChoice: String,
        correctChoice: String,
        isCorrect: Bool,
        newlyMastered: Bool,
        resultingStreak: Int
    ) -> QuizAnswerFeedback {
        let pointsEarned = (isCorrect ? 10 : 0) + (newlyMastered ? 25 : 0)
        let headline: String
        let detail: String

        if newlyMastered {
            headline = "Mastery unlocked"
            detail = "You got it right and completed the 3-correct streak for this word."
        } else if isCorrect && resultingStreak == 2 {
            headline = "Nice work"
            detail = "One more correct answer on a later attempt will mark this word as mastered."
        } else if isCorrect {
            headline = "Correct"
            detail = "You chose the right Chinese meaning. Keep building the streak."
        } else {
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
            headline: headline,
            detail: detail
        )
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
