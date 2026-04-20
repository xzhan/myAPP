import Foundation
import Testing
@testable import PETVocabularyTrainer

struct PETVocabularyTrainerTests {
    @MainActor
    @Test func appModelShowsFeedbackBeforeAdvancingToNextQuestion() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let model = AppModel(store: LocalStore(url: url))
        model.words = [
            VocabularyWord(id: "w1", english: "borrow", primaryChinese: "借入", topic: .school),
            VocabularyWord(id: "w2", english: "teacher", primaryChinese: "老师", topic: .school),
            VocabularyWord(id: "w3", english: "cinema", primaryChinese: "电影院", topic: .places),
            VocabularyWord(id: "w4", english: "ticket", primaryChinese: "票", topic: .transport)
        ]
        model.data.progressByWordID["w1"] = .fresh(for: "w1")
        model.data.progressByWordID["w2"] = .fresh(for: "w2")
        model.data.progressByWordID["w3"] = .fresh(for: "w3")
        model.data.progressByWordID["w4"] = .fresh(for: "w4")
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(wordID: "w1", choices: ["借入", "老师", "电影院", "票"]),
                PersistedQuestion(wordID: "w2", choices: ["老师", "借入", "电影院", "票"])
            ]
        )

        model.submit(choice: "借入")

        #expect(model.answerFeedback?.isCorrect == true)
        #expect(model.answerFeedback?.headline == "Correct")
        #expect(model.currentQuestionWord?.id == "w1")
        #expect(model.currentSession?.correctAnswers == 1)
        #expect(model.quizProgressCount == 1)

        model.advanceAfterFeedback()

        #expect(model.answerFeedback == nil)
        #expect(model.currentQuestionWord?.id == "w2")
        #expect(model.currentQuestionNumber == 2)
    }

    @Test func bundledWordListIsLargeUniqueAndWellDistributed() throws {
        let words = try SeedWordLoader.loadWords()
        let ids = Set(words.map(\.id))
        let englishWords = Set(words.map(\.english))
        let topicCounts = Dictionary(grouping: words, by: \.topic).mapValues(\.count)

        #expect(words.count >= 140)
        #expect(ids.count == words.count)
        #expect(englishWords.count == words.count)
        #expect(Set(topicCounts.keys) == Set(WordTopic.allCases))
        #expect(topicCounts.values.allSatisfy { $0 >= 8 })
    }

    @Test func generatedQuestionsContainVisibleChoices() throws {
        let words = try SeedWordLoader.loadWords()
        let questions = SessionPlanner.placementQuestions(words: words, data: AppStoreData(), count: 12)

        #expect(questions.count == 12)
        #expect(questions.allSatisfy { $0.choices.count == 4 })
        #expect(questions.allSatisfy { Set($0.choices).count == 4 })
        #expect(questions.allSatisfy { $0.choices.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } })
    }

    @Test func masteryEngineMarksWordMasteredAfterThreeCorrectAnswers() {
        var progress = WordProgress.fresh(for: "pet-borrow")

        _ = MasteryEngine.applyAttempt(to: &progress, isCorrect: true, answeredAt: .now)
        _ = MasteryEngine.applyAttempt(to: &progress, isCorrect: true, answeredAt: .now)
        let newlyMastered = MasteryEngine.applyAttempt(to: &progress, isCorrect: true, answeredAt: .now)

        #expect(newlyMastered)
        #expect(progress.isMastered)
        #expect(progress.currentCorrectStreak == 3)
    }

    @Test func masteryEngineResetsStreakAndRaisesReviewPriorityOnFailure() {
        var progress = WordProgress.fresh(for: "pet-borrow")
        progress.currentCorrectStreak = 2

        let newlyMastered = MasteryEngine.applyAttempt(to: &progress, isCorrect: false, answeredAt: .now)

        #expect(!newlyMastered)
        #expect(progress.currentCorrectStreak == 0)
        #expect(progress.reviewPriority == 2)
    }

    @Test func missionPlannerPrioritizesFailedWords() {
        let words = [
            VocabularyWord(id: "failed", english: "borrow", primaryChinese: "借入", topic: .school),
            VocabularyWord(id: "new", english: "cinema", primaryChinese: "电影院", topic: .places),
            VocabularyWord(id: "review", english: "ticket", primaryChinese: "票", topic: .transport),
            VocabularyWord(id: "f1", english: "bread", primaryChinese: "面包", topic: .food),
            VocabularyWord(id: "f2", english: "teacher", primaryChinese: "老师", topic: .school)
        ]
        var data = AppStoreData()
        data.progressByWordID["failed"] = WordProgress(wordID: "failed", currentCorrectStreak: 0, totalCorrect: 0, totalIncorrect: 2, isMastered: false, lastSeenAt: .now, lastIncorrectAt: .now, reviewPriority: 3)
        data.progressByWordID["review"] = WordProgress(wordID: "review", currentCorrectStreak: 1, totalCorrect: 1, totalIncorrect: 0, isMastered: false, lastSeenAt: .now, lastIncorrectAt: nil, reviewPriority: 0)
        data.progressByWordID["new"] = .fresh(for: "new")
        data.progressByWordID["f1"] = .fresh(for: "f1")
        data.progressByWordID["f2"] = .fresh(for: "f2")

        let questions = SessionPlanner.missionQuestions(words: words, data: data, count: 3)

        #expect(questions.count == 3)
        #expect(questions.first?.wordID == "failed")
    }

    @Test func feedbackGeneratorHighlightsWeakTopic() {
        let wordsByID = [
            "school": VocabularyWord(id: "school", english: "borrow", primaryChinese: "借入", topic: .school),
            "places": VocabularyWord(id: "places", english: "cinema", primaryChinese: "电影院", topic: .places)
        ]
        let session = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(wordID: "school", choices: ["借入", "归还", "老师", "学校"]),
                PersistedQuestion(wordID: "places", choices: ["电影院", "车站", "医院", "旅程"])
            ],
            currentIndex: 2,
            correctAnswers: 1,
            attempts: [
                AttemptRecord(sessionID: "s1", wordID: "school", selectedChoice: "归还", correctChoice: "借入", isCorrect: false, topic: .school),
                AttemptRecord(sessionID: "s1", wordID: "places", selectedChoice: "电影院", correctChoice: "电影院", isCorrect: true, topic: .places)
            ],
            newlyMasteredWordIDs: ["places"]
        )

        let summary = FeedbackGenerator.makeSummary(from: session, wordsByID: wordsByID)

        #expect(summary.weakTopics == [.school])
        #expect(summary.body.contains("mastered 1 new PET word"))
        #expect(summary.recommendedMissionTitle.contains("school"))
    }

    @Test func progressAnalyticsSummarizesPointsFocusTopicsAndRank() {
        let words = [
            VocabularyWord(id: "school-1", english: "borrow", primaryChinese: "借入", topic: .school),
            VocabularyWord(id: "school-2", english: "teacher", primaryChinese: "老师", topic: .school),
            VocabularyWord(id: "travel-1", english: "ticket", primaryChinese: "票", topic: .travel)
        ]

        let sampleSummary = SessionSummary(
            mode: .mission,
            startedAt: Date(timeIntervalSince1970: 1_000),
            completedAt: Date(timeIntervalSince1970: 1_300),
            totalQuestions: 5,
            correctAnswers: 4,
            newlyMasteredCount: 1,
            weakTopics: [.travel],
            headline: "Nice work",
            body: "You answered 4 of 5 correctly.",
            recommendedMissionTitle: "Retry travel words"
        )

        var data = AppStoreData()
        data.sessions = [sampleSummary]
        data.progressByWordID["school-1"] = WordProgress(
            wordID: "school-1",
            currentCorrectStreak: 0,
            totalCorrect: 1,
            totalIncorrect: 2,
            isMastered: false,
            lastSeenAt: .now,
            lastIncorrectAt: .now,
            reviewPriority: 3
        )
        data.progressByWordID["school-2"] = WordProgress(
            wordID: "school-2",
            currentCorrectStreak: 1,
            totalCorrect: 2,
            totalIncorrect: 1,
            isMastered: false,
            lastSeenAt: .now,
            lastIncorrectAt: .now.addingTimeInterval(-100),
            reviewPriority: 2
        )

        let focusTopics = ProgressAnalytics.focusTopics(words: words, data: data)

        #expect(ProgressAnalytics.totalPoints(from: [sampleSummary]) == 65)
        #expect(focusTopics.first == .school)
        #expect(ProgressAnalytics.rankTitle(forMasteryPercent: 62) == "Navigator")
    }

    @Test func localStoreRoundTripsIso8601Dates() throws {
        let formatter = ISO8601DateFormatter()
        let sampleDate = try #require(formatter.date(from: "2026-04-20T08:30:00Z"))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let summary = SessionSummary(
            mode: .placement,
            startedAt: sampleDate,
            completedAt: sampleDate,
            totalQuestions: 10,
            correctAnswers: 7,
            newlyMasteredCount: 2,
            weakTopics: [.school],
            headline: "Nice work",
            body: "Coach note",
            recommendedMissionTitle: "Retry school words"
        )

        var storeData = AppStoreData()
        storeData.hasCompletedPlacement = true
        storeData.dailyStreak = 4
        storeData.sessions = [summary]

        let store = LocalStore(url: url)
        try store.save(storeData)
        let loaded = try store.load()

        #expect(loaded.sessions.count == 1)
        #expect(loaded.sessions.first?.completedAt == sampleDate)
        #expect(loaded.dailyStreak == 4)
        #expect(loaded.hasCompletedPlacement)
    }
}
