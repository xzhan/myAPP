import Testing
@testable import PETVocabularyTrainer

struct PETVocabularyTrainerTests {
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
}
