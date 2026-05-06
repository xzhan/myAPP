import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    enum VocabularyImportIntent {
        case basePDF
        case questJSON
        case generic
    }

    typealias ImportPanelPresenter = @MainActor (VocabularyImportIntent, @escaping (Result<URL, Error>) -> Void) -> Void
    typealias ReadingImportPanelPresenter = @MainActor (@escaping (Result<[URL], Error>) -> Void) -> Void
    typealias SpeechPlayer = @MainActor (String, SpeechLanguageHint) -> Void

    enum Screen {
        case loading
        case onboarding
        case dashboard
        case quiz
        case readingQuiz
        case summary
        case review
        case history
        case reading
    }

    private let store: LocalStore
    private let autoAdvanceDelayMultiplier: Double
    private let sleepForNanoseconds: @Sendable (UInt64) async -> Void
    private let presentImportPanel: ImportPanelPresenter
    private let presentReadingImportPanel: ReadingImportPanelPresenter
    private let speakText: SpeechPlayer
    private let reviewNotificationScheduler: any ReviewNotificationScheduling
    private var autoAdvanceTask: Task<Void, Never>?

    var words: [VocabularyWord] = []
    var data = AppStoreData()
    var screen: Screen = .loading
    var latestSummary: SessionSummary?
    var errorMessage: String?
    var answerFeedback: QuizAnswerFeedback?
    var quizStepID = UUID()
    var activeReadingSession: ActiveReadingSession?
    var readingAnswerFeedback: ReadingAnswerFeedback?
    var readingStepID = UUID()
    var isShowingReimportConfirmation = false
    var pendingVocabularyImportURL: URL?
    var pendingVocabularyImportIntent: VocabularyImportIntent = .generic
    var isImportingWordBank = false
    var isShowingReadingReimportConfirmation = false
    var isImportingReadingPack = false
    var selectedReadingPreviewQuestID: String?

    init(
        store: LocalStore = LocalStore(),
        autoAdvanceDelayMultiplier: Double = 1.0,
        presentImportPanel: @escaping ImportPanelPresenter = AppModel.defaultImportPanelPresenter,
        presentReadingImportPanel: @escaping ReadingImportPanelPresenter = AppModel.defaultReadingImportPanelPresenter,
        speakText: @escaping SpeechPlayer = SpeechCoach.shared.speak,
        reviewNotificationScheduler: any ReviewNotificationScheduling = SystemReviewNotificationScheduler(),
        sleepForNanoseconds: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.store = store
        self.autoAdvanceDelayMultiplier = autoAdvanceDelayMultiplier
        self.presentImportPanel = presentImportPanel
        self.presentReadingImportPanel = presentReadingImportPanel
        self.speakText = speakText
        self.reviewNotificationScheduler = reviewNotificationScheduler
        self.sleepForNanoseconds = sleepForNanoseconds
    }

    var wordsByID: [String: VocabularyWord] {
        Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
    }

    var dashboardStats: DashboardStats {
        let masteredCount = data.progressByWordID.values.filter(\.isMastered).count
        let masteryPercent = ProgressAnalytics.masteryPercent(masteredCount: masteredCount, totalWordCount: words.count)
        let reviewCount = dueReviewWords.count
        let focusTopics = ProgressAnalytics.focusTopics(words: words, data: data)
        let missionTitle: String
        if let currentQuestPage {
            missionTitle = "Page \(currentQuestPage.pageNumber) is ready"
        } else if !data.hasCompletedPlacement {
            missionTitle = "Take your placement test"
        } else if reviewCount > 0 {
            missionTitle = "Today's 45-word plan"
        } else {
            missionTitle = "Fresh 45-word plan"
        }

        return DashboardStats(
            masteredCount: masteredCount,
            totalWordCount: words.count,
            masteryPercent: masteryPercent,
            reviewCount: reviewCount,
            dailyTargetWordCount: dailyStudySnapshot.targetWordCount,
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

    var currentQuestion: PersistedQuestion? {
        guard let session = data.activeSession,
              session.currentIndex < session.questions.count else { return nil }
        return session.questions[session.currentIndex]
    }

    var currentQuestionWord: VocabularyWord? {
        guard let question = currentQuestion else { return nil }
        return wordsByID[question.wordID]
    }

    var currentQuestionChoices: [String] {
        if isOnTranslationStep {
            return currentQuestion?.translationChoices ?? []
        }
        return currentQuestion?.choices ?? []
    }

    var currentReadingQuestion: ReadingQuestQuestion? {
        guard let session = activeReadingSession,
              session.stage == .answering,
              session.currentIndex < session.questions.count else { return nil }
        return session.questions[session.currentIndex]
    }

    var currentReadingChoices: [ReadingQuestChoice] {
        currentReadingQuestion?.choices ?? []
    }

    var readingProgressLabel: String {
        guard let session = activeReadingSession else { return "READING" }
        switch session.stage {
        case .questionPreview:
            return "QUESTION PREVIEW"
        case .passageReading:
            return "READ THE PASSAGE"
        case .answering:
            break
        }
        let total = max(1, session.questions.count)
        return "QUESTION \(min(session.currentIndex + 1, total)) / \(total)"
    }

    var readingProgressCount: Int {
        guard let session = activeReadingSession else { return 0 }
        guard session.stage == .answering else { return 0 }
        return min(session.currentIndex + (readingAnswerFeedback == nil ? 0 : 1), session.questions.count)
    }

    var readingSessionStage: ReadingSessionStage? {
        activeReadingSession?.stage
    }

    var currentQuestionStyle: QuestionPresentationStyle {
        currentQuestion?.style ?? .meaningChoice
    }

    var currentExerciseStep: WordExerciseStep {
        currentSession?.currentExerciseStep ?? .meaningChoice
    }

    var isCurrentWordExercise: Bool {
        currentQuestion?.isWordExercise == true
    }

    var isOnSpellingStep: Bool {
        isCurrentWordExercise && currentExerciseStep == .spelling
    }

    var isOnTranslationStep: Bool {
        isCurrentWordExercise && currentExerciseStep == .translation
    }

    var isRetryingSpelling: Bool {
        isOnSpellingStep && currentSession?.pendingSpellingWasCorrect == false
    }

    var isOnPronunciationStep: Bool {
        isCurrentWordExercise && currentExerciseStep == .pronunciation
    }

    var currentQuestionHasTranslationStep: Bool {
        currentQuestion?.hasTranslationStep == true
    }

    var needsPronunciationReinforcement: Bool {
        currentQuestionHasTranslationStep && ((currentSession?.pendingSpellingWasCorrect == false) || isOnPronunciationStep)
    }

    var currentMeaningPrompt: String? {
        currentQuestion?.meaningPrompt
    }

    var currentSpellingPrompt: String? {
        guard let question = currentQuestion,
              let word = currentQuestionWord else {
            return nil
        }
        return question.spellingPrompt(for: word)
    }

    var currentTranslationPrompt: String? {
        currentQuestion?.translationPrompt
    }

    var currentMemoryTip: String? {
        currentQuestion?.memoryTip
    }

    var currentPronunciationTargetWord: String? {
        guard let question = currentQuestion,
              let word = currentQuestionWord else { return nil }
        return correctSpellingAnswer(for: question, word: word)
    }

    func speak(_ text: String, language: SpeechLanguageHint = .automatic) {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return }
        speakText(cleaned, language)
    }

    func speakEnglish(_ text: String) {
        speak(text, language: .english)
    }

    func speakChinese(_ text: String) {
        speak(text, language: .chinese)
    }

    var currentExampleSentence: String? {
        currentQuestion?.exampleSentence
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
        return Int((Double(session.correctAnswers) / Double(session.attempts.count) * 100.0).rounded())
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

    var resumeSessionTitle: String {
        guard let session = currentSession else {
            return "RESUME SESSION"
        }
        return "RESUME \(session.mode.title.uppercased())"
    }

    var shouldNudgeReviewRescueOnCurrentQuest: Bool {
        guard let pageNumber = currentQuestPage?.pageNumber,
              !isQuestPageCompleted(pageNumber),
              reviewRescueSnapshot.currentSprintCount > 0 else {
            return false
        }
        return true
    }

    var shouldResumeHomeQuestSession: Bool {
        guard let session = currentSession,
              session.mode != .placement else {
            return false
        }
        return true
    }

    var homeQuestActionTitle: String {
        shouldResumeHomeQuestSession ? resumeSessionTitle : currentUnitSnapshot.primaryActionTitle
    }

    func performHomeQuestAction() {
        if shouldResumeHomeQuestSession {
            resumeCurrentSession()
        } else {
            performCurrentUnitPrimaryAction()
        }
    }

    var currentUnitResumeSessionTitle: String? {
        guard let session = currentSession else { return nil }
        if session.mode == .mission,
           let questPageNumber = session.questPageNumber,
           questPageNumber != currentQuestPage?.pageNumber {
            return nil
        }
        return resumeSessionTitle
    }

    var quizExitTitle: String {
        data.hasCompletedPlacement ? "BACK TO DASHBOARD" : "BACK TO MAIN"
    }

    var quizProgressLabel: String {
        if isCurrentWordExercise {
            return "WORD \(currentQuestionNumber) / \(currentSession?.questions.count ?? 0)"
        }
        return "QUESTION \(currentQuestionNumber) / \(currentSession?.questions.count ?? 0)"
    }

    var showsCompactWordBankBar: Bool {
        switch screen {
        case .quiz, .readingQuiz, .summary, .review, .history, .reading:
            return true
        case .loading, .onboarding, .dashboard:
            return false
        }
    }

    var hasQuestPages: Bool {
        data.activeWordBankMode == .imported && (!data.wordPages.isEmpty || !data.questPages.isEmpty)
    }

    var areCoreImportLayersReady: Bool {
        !sortedImportedWordPages.isEmpty && data.readingLibrary != nil
    }

    var shouldDeemphasizeImportSurface: Bool {
        areCoreImportLayersReady
    }

    var importedBasePageCount: Int {
        sortedImportedWordPages.count
    }

    var importedQuestPageCount: Int {
        sortedQuestOverlayPages.count
    }

    var importedReadingPageCount: Int {
        sortedReadingQuests.count
    }

    private var sortedQuestOverlayPages: [QuestPage] {
        data.questPages.sorted { $0.pageNumber < $1.pageNumber }
    }

    private var sortedImportedWordPages: [ImportedWordPage] {
        data.wordPages.sorted { $0.pageNumber < $1.pageNumber }
    }

    var sortedQuestPages: [StudyPageReference] {
        let wordPagesByNumber = Dictionary(uniqueKeysWithValues: sortedImportedWordPages.map { ($0.pageNumber, $0) })
        let questPagesByNumber = Dictionary(uniqueKeysWithValues: sortedQuestOverlayPages.map { ($0.pageNumber, $0) })
        let allPageNumbers = Set(wordPagesByNumber.keys).union(questPagesByNumber.keys).sorted()

        return allPageNumbers.compactMap { pageNumber in
            if let questPage = questPagesByNumber[pageNumber] {
                return StudyPageReference(
                    pageNumber: pageNumber,
                    title: questPage.title,
                    wordCount: questPage.wordCount,
                    isQuestEnhanced: true
                )
            }

            guard let wordPage = wordPagesByNumber[pageNumber] else {
                return nil
            }

            return StudyPageReference(
                pageNumber: pageNumber,
                title: wordPage.title,
                wordCount: wordPage.wordCount,
                isQuestEnhanced: false
            )
        }
    }

    var sortedReadingQuests: [ReadingQuest] {
        data.readingQuests.sorted { lhs, rhs in
            switch (lhs.pageNumber, rhs.pageNumber) {
            case let (left?, right?):
                if left != right { return left < right }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var currentQuestPage: StudyPageReference? {
        guard data.activeWordBankMode == .imported else { return nil }
        let orderedPages = sortedQuestPages
        guard !orderedPages.isEmpty else { return nil }

        if let currentQuestPageNumber = data.currentQuestPageNumber,
           let currentPage = orderedPages.first(where: { $0.pageNumber == currentQuestPageNumber }) {
            return currentPage
        }

        if let nextPage = orderedPages.first(where: { !data.completedQuestPages.contains($0.pageNumber) }) {
            return nextPage
        }

        return orderedPages.first
    }

    var currentQuestPageLabel: String? {
        currentQuestPage.map { "Page \($0.pageNumber)" }
    }

    var completedQuestPagesList: [StudyPageReference] {
        sortedQuestPages.filter { isQuestPageCompleted($0.pageNumber) }
    }

    var readyQuestPages: [StudyPageReference] {
        let currentPageNumber = currentQuestPage?.pageNumber
        return sortedQuestPages.filter {
            $0.pageNumber != currentPageNumber && !isQuestPageCompleted($0.pageNumber)
        }
    }

    var baseReadyPages: [StudyPageReference] {
        readyQuestPages.filter { !$0.isQuestEnhanced }
    }

    var questEnhancedPages: [StudyPageReference] {
        readyQuestPages.filter(\.isQuestEnhanced)
    }

    var allQuestEnhancedPages: [StudyPageReference] {
        sortedQuestPages.filter(\.isQuestEnhanced)
    }

    var questPageChooserPages: [StudyPageReference] {
        let enhancedPages = allQuestEnhancedPages
        return enhancedPages.isEmpty ? sortedQuestPages : enhancedPages
    }

    var questPageProgressText: String? {
        guard hasQuestPages else { return nil }
        let baseCount = sortedImportedWordPages.count
        let questCount = sortedQuestOverlayPages.count

        if baseCount > 0 && questCount > 0 {
            return "\(baseCount) / 66 base pages · \(questCount) enhanced quest pages"
        }
        if baseCount > 0 {
            return "\(baseCount) / 66 base pages ready"
        }
        return "\(questCount) / 66 quest pages imported"
    }

    func isQuestPageCompleted(_ pageNumber: Int) -> Bool {
        data.completedQuestPages.contains(pageNumber)
    }

    func isReadingQuestCompleted(_ pageNumber: Int) -> Bool {
        data.completedReadingQuestPages.contains(pageNumber)
    }

    func questPageStatusText(for page: QuestPage) -> String {
        questPageStatusText(for: StudyPageReference(
            pageNumber: page.pageNumber,
            title: page.title,
            wordCount: page.wordCount,
            isQuestEnhanced: true
        ))
    }

    func questPageStatusText(for page: StudyPageReference) -> String {
        if currentQuestPage?.pageNumber == page.pageNumber {
            return page.isQuestEnhanced ? "Current · Quest Enhanced" : "Current · Base Ready"
        }
        if isQuestPageCompleted(page.pageNumber) {
            return page.isQuestEnhanced ? "Completed · Quest Enhanced" : "Completed · Base Ready"
        }
        return page.isQuestEnhanced ? "Quest Enhanced" : "Base Ready"
    }

    func questPageMenuLabel(for page: StudyPageReference) -> String {
        "Page \(page.pageNumber) · \(questPageStatusText(for: page))"
    }

    func readingQuest(forPageNumber pageNumber: Int) -> ReadingQuest? {
        sortedReadingQuests.first(where: { $0.pageNumber == pageNumber })
    }

    var currentReadingQuest: ReadingQuest? {
        guard let currentPage = currentQuestPage else { return nil }
        return readingQuest(forPageNumber: currentPage.pageNumber)
    }

    var selectedReadingPreviewQuest: ReadingQuest? {
        if let selectedReadingPreviewQuestID,
           let selectedQuest = sortedReadingQuests.first(where: { $0.id == selectedReadingPreviewQuestID }) {
            return selectedQuest
        }

        if let currentReadingQuest {
            return currentReadingQuest
        }

        return sortedReadingQuests.first
    }

    private func questOverlayPage(forPageNumber pageNumber: Int) -> QuestPage? {
        sortedQuestOverlayPages.first(where: { $0.pageNumber == pageNumber })
    }

    private func importedWordPage(forPageNumber pageNumber: Int) -> ImportedWordPage? {
        sortedImportedWordPages.first(where: { $0.pageNumber == pageNumber })
    }

    var nextQuestPageAfterCurrent: StudyPageReference? {
        guard let currentPage = currentQuestPage else {
            return sortedQuestPages.first(where: { !isQuestPageCompleted($0.pageNumber) })
        }

        if let nextPage = sortedQuestPages.first(where: { $0.pageNumber > currentPage.pageNumber && !isQuestPageCompleted($0.pageNumber) }) {
            return nextPage
        }

        return sortedQuestPages.first(where: {
            $0.pageNumber != currentPage.pageNumber && !isQuestPageCompleted($0.pageNumber)
        })
    }

    func readingState(forPageNumber pageNumber: Int) -> CurrentUnitReadingState {
        if isReadingQuestCompleted(pageNumber) {
            return .completed
        }

        if let readingQuest = readingQuest(forPageNumber: pageNumber) {
            return readingQuest.isQuizReady ? .ready : .previewOnly
        }

        if data.readingLibrary != nil {
            return .missingForPage
        }

        return .waitingForImport
    }

    private func layerSnapshots(
        for page: StudyPageReference,
        readingState: CurrentUnitReadingState
    ) -> [CurrentUnitLayerSnapshot] {
        let baseLayer = CurrentUnitLayerSnapshot(
            id: "base",
            title: "Base Layer",
            valueText: "Base Ready",
            caption: "Stable PET words for Page \(page.pageNumber) are mapped.",
            style: .ready
        )

        let questLayer = CurrentUnitLayerSnapshot(
            id: "quest",
            title: "Quest Layer",
            valueText: page.isQuestEnhanced ? "Quest Enhanced" : "Quest Pending",
            caption: page.isQuestEnhanced
                ? "This page already has the richer LLM-generated quest overlay."
                : "This page is still running on the base PET layer only.",
            style: page.isQuestEnhanced ? .enhanced : .neutral
        )

        let readingLayer: CurrentUnitLayerSnapshot
        switch readingState {
        case .completed:
            readingLayer = CurrentUnitLayerSnapshot(
                id: "reading",
                title: "Reading Layer",
                valueText: "Reading Done",
                caption: "The matching Reading step for this page is complete.",
                style: .completed
            )
        case .ready:
            readingLayer = CurrentUnitLayerSnapshot(
                id: "reading",
                title: "Reading Layer",
                valueText: "Reading Ready",
                caption: "This page can move straight into graded Reading next.",
                style: .ready
            )
        case .previewOnly:
            readingLayer = CurrentUnitLayerSnapshot(
                id: "reading",
                title: "Reading Layer",
                valueText: "Reading Preview",
                caption: "Reading is imported for this page, but answer keys are still missing.",
                style: .preview
            )
        case .waitingForImport:
            readingLayer = CurrentUnitLayerSnapshot(
                id: "reading",
                title: "Reading Layer",
                valueText: "Reading Waiting",
                caption: "This page is still waiting for a matching Reading import.",
                style: .waiting
            )
        case .missingForPage:
            readingLayer = CurrentUnitLayerSnapshot(
                id: "reading",
                title: "Reading Layer",
                valueText: "Reading Missing",
                caption: "A Reading pack exists, but it does not include this page yet.",
                style: .missing
            )
        }

        return [baseLayer, questLayer, readingLayer]
    }

    var currentQuestPagePreviewSnapshot: QuestPagePreviewSnapshot? {
        guard let page = currentQuestPage else { return nil }

        let readingState = readingState(forPageNumber: page.pageNumber)
        let readingTag: String
        switch readingState {
        case .completed:
            readingTag = "Reading Done"
        case .ready:
            readingTag = "Reading Ready"
        case .previewOnly:
            readingTag = "Reading Preview"
        case .missingForPage:
            readingTag = "Reading Missing"
        case .waitingForImport:
            readingTag = "Reading Waiting"
        }

        if let questPage = questOverlayPage(forPageNumber: page.pageNumber) {
            let firstQuestion = questPage.questions.first
            let firstWord = firstQuestion.flatMap { wordsByID[$0.wordID]?.english } ?? "This page"
            let prompt = firstQuestion?.meaningPrompt
                ?? firstQuestion?.exampleSentence
                ?? firstQuestion?.translationPrompt
                ?? "Quest content is ready."

            return QuestPagePreviewSnapshot(
                title: "Page \(page.pageNumber) quest preview",
                summary: "\(firstWord) · \(questPage.wordCount) quest words",
                previewText: previewExcerpt(from: prompt, limit: 120),
                tags: ["Quest Enhanced", "\(questPage.wordCount) words", readingTag]
            )
        }

        guard let wordPage = importedWordPage(forPageNumber: page.pageNumber) else {
            return nil
        }

        let previewWords = wordPage.wordIDs
            .compactMap { wordsByID[$0]?.english }
            .prefix(5)
            .joined(separator: " · ")

        return QuestPagePreviewSnapshot(
            title: "Page \(page.pageNumber) base preview",
            summary: "Stable PET base · \(wordPage.wordCount) words",
            previewText: previewWords.isEmpty
                ? "This page is ready on the stable PET base layer."
                : previewWords,
            tags: ["Base Ready", "\(wordPage.wordCount) words", readingTag]
        )
    }

    func selectQuestPage(_ pageNumber: Int) {
        guard hasQuestPages,
              sortedQuestPages.contains(where: { $0.pageNumber == pageNumber }) else {
            return
        }

        if let activeSession = data.activeSession,
           activeSession.mode == .mission,
           let activePageNumber = activeSession.questPageNumber,
           activePageNumber != pageNumber {
            cancelAutoAdvance()
            data.activeSession = nil
            answerFeedback = nil
            quizStepID = UUID()
            if screen == .quiz {
                screen = data.hasCompletedPlacement ? .dashboard : .onboarding
            }
        }

        data.currentQuestPageNumber = pageNumber
        try? persist()
    }

    func activateSavedImportedWordBank() {
        guard data.importedLibrary != nil else { return }

        do {
            guard let importedWords = try store.loadImportedWords() else {
                errorMessage = "The saved imported bank could not be found anymore."
                return
            }
            guard createSafetyBackup(reason: "activate-saved-import") else { return }

            cancelAutoAdvance()
            words = importedWords
            data.activeWordBankMode = .imported
            data.hasCompletedPlacement = false
            data.progressByWordID = [:]
            data.activeSession = nil
            data.completedQuestPages = []
            data.completedReadingQuestPages = []
            data.currentQuestPageNumber = sortedQuestPages.first?.pageNumber
            latestSummary = sessionHistory.first
            answerFeedback = nil
            quizStepID = UUID()
            screen = .onboarding
            ensureProgressEntries()
            try persist()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func advanceToNextQuestPage() {
        if let nextPage = nextQuestPageAfterCurrent {
            selectQuestPage(nextPage.pageNumber)
        } else {
            openTrophies()
        }
    }

    var wordBankSnapshot: WordBankSnapshot {
        let savedImportTitle = data.importedLibrary?.name

        if data.activeWordBankMode == .imported, let importedLibrary = data.importedLibrary {
            if hasQuestPages {
                let nextPageText = currentQuestPage.map { "Page \($0.pageNumber) is ready now." } ?? "Page study is ready."
                let subtitle: String

                if !sortedImportedWordPages.isEmpty, !sortedQuestOverlayPages.isEmpty {
                    subtitle = "\(importedLibrary.source.displayName) base import from \(importedLibrary.sourceFilename). \(nextPageText) \(sortedQuestOverlayPages.count) pages already use richer quest overlays, while the rest still follow the same PET page index."
                } else if !sortedImportedWordPages.isEmpty {
                    subtitle = "\(importedLibrary.source.displayName) base import from \(importedLibrary.sourceFilename). \(nextPageText) Each PET page can already drive the same page-first word journey, even before quest overlays arrive."
                } else {
                    subtitle = "\(importedLibrary.source.displayName) import from \(importedLibrary.sourceFilename). \(nextPageText) Each page already includes sentence meaning, spelling, translation, and memory tips."
                }

                return WordBankSnapshot(
                    title: importedLibrary.name,
                    subtitle: subtitle,
                    wordCount: words.count,
                    badgeText: "\(importedLibrary.source.displayName.uppercased()) IMPORT",
                    isImportedActive: true,
                    hasSavedImport: true,
                    savedImportTitle: savedImportTitle,
                    progressText: questPageProgressText
                )
            }

            return WordBankSnapshot(
                title: importedLibrary.name,
                subtitle: "\(importedLibrary.source.displayName) import from \(importedLibrary.sourceFilename). Your 100-word test and daily 45-word plan now use this bank.",
                wordCount: words.count,
                badgeText: "\(importedLibrary.source.displayName.uppercased()) IMPORT",
                isImportedActive: true,
                hasSavedImport: true,
                savedImportTitle: savedImportTitle,
                progressText: nil
            )
        }

        return WordBankSnapshot(
            title: "Built-in PET Starter",
            subtitle: data.importedLibrary == nil
                ? "A bundled starter list for quick testing. Import a PET PDF, CSV, TXT, or JSON bank before you begin serious study."
                : "The bundled starter is active now. Your last imported bank is still saved locally and can be restored without re-importing.",
            wordCount: words.count,
            badgeText: "BUNDLED",
            isImportedActive: false,
            hasSavedImport: data.importedLibrary != nil,
            savedImportTitle: savedImportTitle,
            progressText: data.importedLibrary == nil ? nil : "Saved import: \(data.importedLibrary?.wordCount ?? 0) words"
        )
    }

    var dailyStudySnapshot: DailyStudySnapshot {
        if let currentQuestPage {
            let subtitle = currentQuestPage.isQuestEnhanced
                ? "Start this page's enhanced word quest with sentence meaning choice, Chinese-to-English spelling, and sentence translation using your imported LLM content."
                : "Start this PET base page now. It uses the stable PDF word list for this page, and the same page can later be upgraded by a quest overlay without changing the index."
            let reminderText = currentQuestPage.isQuestEnhanced
                ? "Quest-enhanced pages use your curated examples, translations, and memory tips instead of fallback templates."
                : "This page is running from the stable PET base PDF. When a quest overlay for the same page arrives later, it should strengthen the same page instead of replacing the full bank."
            return DailyStudySnapshot(
                targetWordCount: currentQuestPage.wordCount,
                dueReviewCount: 0,
                freshWordCount: 0,
                activeBankTitle: wordBankSnapshot.title,
                activeBankBadgeText: wordBankSnapshot.badgeText,
                headline: "Today's unit is Page \(currentQuestPage.pageNumber)",
                subtitle: subtitle,
                reminderText: reminderText,
                pageLabel: "PAGE \(currentQuestPage.pageNumber)",
                pageProgressText: questPageProgressText
            )
        }

        let targetWordCount = min(ReviewScheduler.dailyTargetWordCount, words.count)
        let dueCount = min(dueReviewWords.count, targetWordCount)
        let freshCandidates = words.filter { (data.progressByWordID[$0.id] ?? .fresh(for: $0.id)).totalAttempts == 0 }.count
        let freshWordCount = max(0, min(targetWordCount - dueCount, freshCandidates))
        let headline = data.hasCompletedPlacement ? "Today's 45-word study plan" : "Placement source ready"
        let subtitle: String

        if data.hasCompletedPlacement {
            if dueCount > 0 {
                subtitle = "\(dueCount) review words are due now. The rest of today's \(targetWordCount)-word plan will reinforce or introduce new vocabulary from \(wordBankSnapshot.title)."
            } else {
                subtitle = "Today's \(targetWordCount)-word plan will build forward from \(wordBankSnapshot.title) with fresh words and lightly reinforced material."
            }
        } else {
            subtitle = "Your 100-word placement test will use \(wordBankSnapshot.title) so the baseline reflects the active bank."
        }

        return DailyStudySnapshot(
            targetWordCount: targetWordCount,
            dueReviewCount: dueCount,
            freshWordCount: freshWordCount,
            activeBankTitle: wordBankSnapshot.title,
            activeBankBadgeText: wordBankSnapshot.badgeText,
            headline: headline,
            subtitle: subtitle,
            reminderText: "Missed words return on an Ebbinghaus-style schedule: 10 minutes, 1 day, 2 days, 4 days, then 7 days.",
            pageLabel: nil,
            pageProgressText: nil
        )
    }

    var reviewReminderSnapshot: ReviewReminderSnapshot {
        let dueNowCount = dueReviewWords.count
        let scheduledLaterCount = max(0, reviewWords.count - dueNowCount)
        let retryTrackedCount = reviewWords.filter { $0.progress.retryMissCount > 0 }.count
        let nextReminderAt = reviewWords
            .compactMap(\.progress.nextReviewAt)
            .filter { $0 > .now }
            .min()

        let headline: String
        var detail: String

        if dueNowCount > 0 {
            headline = "\(dueNowCount) review reminders are due now"
            detail = "Open Review Rescue first so the due words do not pile up. \(retryTrackedCount) of them were flagged during retry."
        } else if let nextReminderAt {
            headline = "Next reminder: \(nextReminderAt.formatted(date: .abbreviated, time: .shortened))"
            detail = "\(scheduledLaterCount) words are already scheduled to come back, including \(retryTrackedCount) retry-tracked words."
        } else {
            headline = "No reminder backlog right now"
            detail = "New misses will start at the first 10-minute reminder step."
        }

        return ReviewReminderSnapshot(
            dueNowCount: dueNowCount,
            scheduledLaterCount: scheduledLaterCount,
            retryTrackedCount: retryTrackedCount,
            nextReminderAt: nextReminderAt,
            headline: headline,
            detail: detail,
            strategyText: ReviewScheduler.strategyDescription
        )
    }

    var reviewRescueSnapshot: ReviewRescueSnapshot {
        ReviewRescuePlanner.snapshot(
            from: reviewWords,
            memoryTipProvider: { [self] wordID in
                memoryTip(forWordID: wordID)
            },
            contextProvider: { [self] wordID in
                reviewLearningContext(forWordID: wordID)
            }
        )
    }

    var trophiesSnapshot: TrophiesSnapshot {
        let sessions = sessionHistory
        let completedTodayCount = sessions.filter { Calendar.current.isDateInToday($0.completedAt) }.count
        let averageAccuracy = sessions.isEmpty
            ? 0
            : Int((Double(sessions.map(\.accuracyPercent).reduce(0, +)) / Double(sessions.count)).rounded())
        let rescueSnapshot = reviewRescueSnapshot
        let pageStatuses = trophiesPageStatuses

        return TrophiesSnapshot(
            totalSessions: sessions.count,
            completedTodayCount: completedTodayCount,
            averageAccuracyPercent: averageAccuracy,
            dueReviewCount: rescueSnapshot.dueNow.count,
            dailyStreak: data.dailyStreak,
            totalPages: pageStatuses.count,
            questCompletedCount: data.completedQuestPages.count,
            readingCompletedCount: data.completedReadingQuestPages.count,
            pageStatuses: pageStatuses,
            memoryWords: Array(rescueSnapshot.dueNow.words.prefix(8)),
            recentSessions: Array(sessions.prefix(8))
        )
    }

    private var trophiesPageStatuses: [TrophiesPageStatusSnapshot] {
        let basePageNumbers = Set(data.wordPages.map(\.pageNumber))
        let questPageNumbers = Set(data.questPages.map(\.pageNumber))
        let readingPageNumbers = Set(data.readingQuests.compactMap(\.pageNumber))
        let questCompletedPageNumbers = Set(data.completedQuestPages)
        let readingCompletedPageNumbers = Set(data.completedReadingQuestPages)
        let duePageNumbers = dueReviewPageNumbers

        var allPageNumbers = basePageNumbers
            .union(questPageNumbers)
            .union(readingPageNumbers)
            .union(questCompletedPageNumbers)
            .union(readingCompletedPageNumbers)
            .union(duePageNumbers)

        if let currentPageNumber = currentQuestPage?.pageNumber {
            allPageNumbers.insert(currentPageNumber)
        }

        let highestPageNumber = max(66, allPageNumbers.max() ?? 0)
        return (1...highestPageNumber).map { pageNumber in
            TrophiesPageStatusSnapshot(
                pageNumber: pageNumber,
                isCurrent: currentQuestPage?.pageNumber == pageNumber,
                isBaseReady: basePageNumbers.contains(pageNumber),
                isQuestEnhanced: questPageNumbers.contains(pageNumber),
                isQuestCompleted: questCompletedPageNumbers.contains(pageNumber),
                isReadingReady: readingPageNumbers.contains(pageNumber),
                isReadingCompleted: readingCompletedPageNumbers.contains(pageNumber),
                hasReviewDue: duePageNumbers.contains(pageNumber)
            )
        }
    }

    private var dueReviewPageNumbers: Set<Int> {
        let dueWordIDs = Set(dueReviewWords.map(\.word.id))
        guard !dueWordIDs.isEmpty else { return [] }

        var pageNumbers = Set<Int>()
        for page in data.questPages {
            for question in page.questions where dueWordIDs.contains(question.wordID) {
                pageNumbers.insert(question.sourcePageNumber ?? page.pageNumber)
            }
        }

        for page in data.wordPages where !dueWordIDs.isDisjoint(with: page.wordIDs) {
            pageNumbers.insert(page.pageNumber)
        }

        return pageNumbers
    }

    var homeMissionSnapshot: HomeMissionSnapshot {
        let unitSnapshot = currentUnitSnapshot
        let reminderSnapshot = reviewReminderSnapshot
        let rescueSprintCount = reviewRescueSnapshot.currentSprintCount
        let currentPageLabel: String
        let currentPageCaption: String
        let todayDetail: String

        if let currentQuestPage {
            currentPageLabel = "P\(currentQuestPage.pageNumber)"
            currentPageCaption = "CURRENT PAGE"
            todayDetail = "Page \(currentQuestPage.pageNumber) is selected. Choose a different page only when you want to restart the unit flow."
        } else {
            currentPageLabel = "PET"
            currentPageCaption = "SETUP"
            todayDetail = "Import Base or Quest pages first so the learner has a clear page to start from."
        }

        let questStatusText: String
        let questDetail: String
        switch unitSnapshot.wordStatus {
        case .placementNeeded:
            questStatusText = "START HERE"
            questDetail = "Take the benchmark first, then daily page practice can begin."
        case .ready:
            questStatusText = currentQuestPage?.isQuestEnhanced == true ? "MAIN TASK" : "BASE TASK"
            let baseQuestDetail = currentQuestPage?.isQuestEnhanced == true
                ? "Meaning, spelling retry, translation, pronunciation, and memory tip."
                : "Use the stable PET page words now; Quest JSON can enrich this same page later."
            let reminderNudge = shouldNudgeReviewRescueOnCurrentQuest
                ? " Step 4 has \(rescueSprintCount) due review words ready when the learner wants a quick rescue sprint."
                : ""
            questDetail = baseQuestDetail + reminderNudge
        case .completed:
            questStatusText = "DONE"
            questDetail = "The word quest for this page is complete. Continue into the matching Reading step."
        }

        let readingStatusText: String
        let readingDetail: String
        switch unitSnapshot.readingState {
        case .ready:
            readingStatusText = "AFTER QUEST"
            readingDetail = "Questions appear first, then the passage, then graded answers with retry."
        case .completed:
            readingStatusText = "DONE"
            readingDetail = "The matching Reading mission for this page is complete."
        case .previewOnly:
            readingStatusText = "PREVIEW"
            readingDetail = "Reading content is imported, but answer keys are still needed for grading."
        case .waitingForImport:
            readingStatusText = "WAITING"
            readingDetail = "Import the Reading pack so this page can continue after Quest."
        case .missingForPage:
            readingStatusText = "MISSING"
            readingDetail = "A Reading pack exists, but this page is not included yet."
        case nil:
            readingStatusText = "LOCKED"
            readingDetail = "Reading attaches to the selected page after setup and Quest are ready."
        }

        let reminderStatusText: String
        let reminderDetail: String
        if reminderSnapshot.dueNowCount > 0 {
            reminderStatusText = "DUE REVIEW"
            reminderDetail = "\(reminderSnapshot.dueNowCount) missed words are due now. Review before they pile up."
        } else if reminderSnapshot.scheduledLaterCount > 0 {
            reminderStatusText = "SCHEDULED"
            reminderDetail = "\(reminderSnapshot.scheduledLaterCount) words are scheduled by the Ebbinghaus reminder plan."
        } else {
            reminderStatusText = "CLEAR"
            reminderDetail = "No reminder backlog right now. Missed words will return automatically."
        }

        let trophyStatusText = data.sessions.isEmpty ? "HISTORY" : "\(data.sessions.count) SAVED"
        let trophyDetail = data.sessions.isEmpty
            ? "Completed quests will appear here with accuracy, misses, and review words."
            : "Open accuracy, failed words, completed pages, and progress history."

        let baseCount = max(importedBasePageCount, data.importedLibrary == nil ? 0 : 1)
        let readingCount = data.readingLibrary?.articleCount ?? importedReadingPageCount

        return HomeMissionSnapshot(
            title: "PET Mission Map",
            subtitle: "One road for junior learners: pick today's page, finish Quest, continue to Reading, then let Reminder and Trophies guide tomorrow.",
            currentPageLabel: currentPageLabel,
            currentPageCaption: currentPageCaption,
            importActionTitle: "MANAGE RESOURCES",
            steps: [
                HomeMissionStepSnapshot(
                    kind: .todayPage,
                    numberText: "1",
                    statusText: currentQuestPage == nil ? "SETUP" : "READY",
                    title: "Choose Today's Page",
                    detail: todayDetail,
                    actionTitle: currentQuestPage == nil ? "OPEN IMPORT" : "GO TO PAGE",
                    style: .page
                ),
                HomeMissionStepSnapshot(
                    kind: .quest,
                    numberText: "2",
                    statusText: questStatusText,
                    title: "45-Word Quest",
                    detail: questDetail,
                    actionTitle: unitSnapshot.wordStatus == .completed ? nil : unitSnapshot.primaryActionTitle,
                    style: .quest
                ),
                HomeMissionStepSnapshot(
                    kind: .reading,
                    numberText: "3",
                    statusText: readingStatusText,
                    title: "Reading Mission",
                    detail: readingDetail,
                    actionTitle: unitSnapshot.wordStatus == .completed ? unitSnapshot.primaryActionTitle : nil,
                    style: .reading
                ),
                HomeMissionStepSnapshot(
                    kind: .reminder,
                    numberText: "4",
                    statusText: reminderStatusText,
                    title: "Reminder",
                    detail: reminderDetail,
                    actionTitle: reminderSnapshot.dueNowCount > 0 ? "REVIEW NOW" : nil,
                    style: .reminder
                ),
                HomeMissionStepSnapshot(
                    kind: .trophies,
                    numberText: "5",
                    statusText: trophyStatusText,
                    title: "Trophies",
                    detail: trophyDetail,
                    actionTitle: "OPEN TROPHIES",
                    style: .trophies
                )
            ],
            benchmarkTitle: "Benchmark Test",
            benchmarkDetail: "Keep the 100-word vocabulary test separate from the daily route. It measures vocabulary size from the stable Base bank.",
            benchmarkActionTitle: data.activeSession?.mode == .placement ? resumeSessionTitle : "START 100-WORD TEST",
            resources: [
                HomeMissionResourceSnapshot(
                    id: "base",
                    title: "Base",
                    valueText: "\(baseCount)",
                    detail: baseCount == 1 && importedBasePageCount == 0 ? "saved PDF" : "base pages"
                ),
                HomeMissionResourceSnapshot(
                    id: "quest",
                    title: "Quest",
                    valueText: "\(importedQuestPageCount)",
                    detail: "enhanced pages"
                ),
                HomeMissionResourceSnapshot(
                    id: "reading",
                    title: "Reading",
                    valueText: "\(readingCount)",
                    detail: "reading pages"
                )
            ]
        )
    }

    var currentUnitSnapshot: CurrentUnitSnapshot {
        if let currentQuestPage {
            let pageNumber = currentQuestPage.pageNumber
            let wordQuestCompleted = isQuestPageCompleted(pageNumber)
            let readingState = readingState(forPageNumber: pageNumber)
            let layerSnapshots = layerSnapshots(for: currentQuestPage, readingState: readingState)
            let wordCompletedCount = completedQuestPagesList.count
            let readingCompletedCount = data.completedReadingQuestPages.count
            let progressText = "\(wordCompletedCount) word pages done · \(readingCompletedCount) reading pages done"

            if !wordQuestCompleted {
                let subtitle = currentQuestPage.isQuestEnhanced
                    ? "Finish this page's enhanced word quest first. Reading stays attached to the same page so the unit feels like one guided journey instead of two disconnected tools."
                    : "Finish this PET base word page first. Reading stays attached to the same page, and future quest overlays for this page should strengthen the same unit instead of changing the page order."
                let targetCaption = currentQuestPage.isQuestEnhanced
                    ? "Words waiting in this enhanced page quest"
                    : "Words waiting in this PET base page"
                let nextHint = currentQuestPage.isQuestEnhanced
                    ? "After the word quest, this same page should continue into Reading."
                    : "This page is stable already. Later quest overlays should enrich it without moving the learner away from the same page."
                return CurrentUnitSnapshot(
                    title: "Current Unit: Page \(pageNumber)",
                    subtitle: subtitle,
                    stageBadgeText: "STEP 1 OF 2",
                    pageBadgeText: "PAGE \(pageNumber)",
                    progressText: progressText,
                    layerSnapshots: layerSnapshots,
                    wordStatus: .ready,
                    readingState: readingState,
                    targetValueText: "\(currentQuestPage.wordCount)",
                    targetCaption: targetCaption,
                    primaryAction: .startMission,
                    primaryActionTitle: "START WORD QUEST",
                    nextHint: nextHint
                )
            }

            switch readingState {
            case .completed:
                let nextActionTitle = nextQuestPageAfterCurrent.map { "GO TO PAGE \($0.pageNumber)" } ?? "OPEN TROPHIES"
                return CurrentUnitSnapshot(
                    title: "Current Unit: Page \(pageNumber)",
                    subtitle: "Both parts of this page are complete. The page is now a finished unit, so the next step is either the next unfinished page or your Trophy shelf.",
                    stageBadgeText: "UNIT COMPLETE",
                    pageBadgeText: "PAGE \(pageNumber)",
                    progressText: progressText,
                    layerSnapshots: layerSnapshots,
                    wordStatus: .completed,
                    readingState: .completed,
                    targetValueText: nextQuestPageAfterCurrent.map { "Page \($0.pageNumber)" } ?? "All done",
                    targetCaption: nextQuestPageAfterCurrent == nil ? "All imported word pages are complete" : "Next unfinished word page",
                    primaryAction: nextQuestPageAfterCurrent == nil ? .openTrophies : .advanceToNextQuestPage,
                    primaryActionTitle: nextActionTitle,
                    nextHint: nextQuestPageAfterCurrent == nil
                        ? "There is no later unfinished page right now."
                        : "Move on only after this page feels complete."
                )
            case .ready:
                return CurrentUnitSnapshot(
                    title: "Current Unit: Page \(pageNumber)",
                    subtitle: "The word quest is done. Reading for the same page is already imported with answer keys, so Reading is the next real step in the unit.",
                    stageBadgeText: "STEP 2 OF 2",
                    pageBadgeText: "PAGE \(pageNumber)",
                    progressText: progressText,
                    layerSnapshots: layerSnapshots,
                    wordStatus: .completed,
                    readingState: .ready,
                    targetValueText: "\(currentReadingQuest?.questionCount ?? 0)",
                    targetCaption: "Reading questions ready for this page",
                    primaryAction: .startReadingQuest,
                    primaryActionTitle: "START READING NOW",
                    nextHint: "This keeps the learner on the same page instead of jumping away too early."
                )
            case .previewOnly:
                let previewQuestionCount = currentReadingQuest?.questionCount ?? 0
                return CurrentUnitSnapshot(
                    title: "Current Unit: Page \(pageNumber)",
                    subtitle: "The word quest is done. Reading for this page already exists, but it is still preview-only until answer keys arrive.",
                    stageBadgeText: "STEP 2 OF 2",
                    pageBadgeText: "PAGE \(pageNumber)",
                    progressText: progressText,
                    layerSnapshots: layerSnapshots,
                    wordStatus: .completed,
                    readingState: .previewOnly,
                    targetValueText: previewQuestionCount > 0 ? "\(previewQuestionCount)" : "1 page",
                    targetCaption: previewQuestionCount > 0 ? "Reading questions imported for preview" : "Reading page imported for preview",
                    primaryAction: .openReadingHub,
                    primaryActionTitle: "OPEN READING PREVIEW",
                    nextHint: "Once this page gets answer keys, the same slot can become a graded Reading step."
                )
            case .waitingForImport:
                return CurrentUnitSnapshot(
                    title: "Current Unit: Page \(pageNumber)",
                    subtitle: "The word quest is done, but this page does not have Reading content yet. Keep the page selected here so the next step stays obvious when Reading is imported.",
                    stageBadgeText: "STEP 2 OF 2",
                    pageBadgeText: "PAGE \(pageNumber)",
                    progressText: progressText,
                    layerSnapshots: layerSnapshots,
                    wordStatus: .completed,
                    readingState: .waitingForImport,
                    targetValueText: "66",
                    targetCaption: "Planned PET reading pages overall",
                    primaryAction: .openReadingHub,
                    primaryActionTitle: "OPEN READING HUB",
                    nextHint: "You can still choose a later page manually, but the mainline should keep Reading visible as the missing next step."
                )
            case .missingForPage:
                return CurrentUnitSnapshot(
                    title: "Current Unit: Page \(pageNumber)",
                    subtitle: "A Reading pack is imported, but it does not include this page yet. The unit should stay here until the matching Reading page arrives or you intentionally move on.",
                    stageBadgeText: "STEP 2 OF 2",
                    pageBadgeText: "PAGE \(pageNumber)",
                    progressText: progressText,
                    layerSnapshots: layerSnapshots,
                    wordStatus: .completed,
                    readingState: .missingForPage,
                    targetValueText: "\(readingCenterSnapshot.articleCount)",
                    targetCaption: "Reading articles already imported",
                    primaryAction: .openReadingHub,
                    primaryActionTitle: "CHECK READING PACK",
                    nextHint: "The mismatch is clearer here than silently auto-advancing to the next word page."
                )
            }
        }

        if data.hasCompletedPlacement {
            let snapshot = dailyStudySnapshot
            return CurrentUnitSnapshot(
                title: "Current Unit: Daily Study",
                subtitle: snapshot.subtitle,
                stageBadgeText: "DAILY LOOP",
                pageBadgeText: nil,
                progressText: nil,
                layerSnapshots: [],
                wordStatus: .ready,
                readingState: nil,
                targetValueText: "\(snapshot.targetWordCount)",
                targetCaption: "Words in today's plan",
                primaryAction: .startMission,
                primaryActionTitle: "START TODAY'S 45-WORD PLAN",
                nextHint: snapshot.reminderText
            )
        }

        return CurrentUnitSnapshot(
            title: "Current Unit: Placement",
            subtitle: "Start with the 100-word placement so the app can estimate your PET vocabulary level before it builds the daily study path.",
            stageBadgeText: "STEP 1",
            pageBadgeText: nil,
            progressText: nil,
            layerSnapshots: [],
            wordStatus: .placementNeeded,
            readingState: nil,
            targetValueText: "\(min(100, words.count))",
            targetCaption: "Words in the placement baseline",
            primaryAction: .startPlacement,
            primaryActionTitle: "START 100-WORD TEST",
            nextHint: "After placement, the app switches to the daily 45-word loop."
        )
    }

    var readingCenterSnapshot: ReadingCenterSnapshot {
        let quizReadyCount = sortedReadingQuests.filter(\.isQuizReady).count
        let previewOnlyCount = max(0, sortedReadingQuests.count - quizReadyCount)

        if let readingLibrary = data.readingLibrary {
            let matchedPages = sortedReadingQuests.compactMap(\.pageNumber).count
            return ReadingCenterSnapshot(
                title: "Reading Adventure",
                subtitle: "\(readingLibrary.name) is ready. \(matchedPages) imported reading pages can line up directly with the same word-page index.",
                statusLabel: "READY",
                articleCount: readingLibrary.articleCount,
                totalPlannedArticleCount: 66,
                importHint: quizReadyCount > 0
                    ? "\(quizReadyCount) reading quests already include answer keys. \(previewOnlyCount) are preview-only."
                    : "This pack is imported and preview-ready. PDF pages and txt quests both map by page number so Reading page 14 can follow Word page 14.",
                quizReadyCount: quizReadyCount,
                previewOnlyCount: previewOnlyCount
            )
        }

        return ReadingCenterSnapshot(
            title: "Reading Adventure",
            subtitle: "A 66-article PET reading pack will live here. The hub is ready now so learners already know where reading practice belongs.",
            statusLabel: "WAITING",
            articleCount: 0,
            totalPlannedArticleCount: 66,
            importHint: "Import one `.txt` or `.pdf` reading file, several supported files, or one folder. PDF pages will match the same PET page index as the word bank.",
            quizReadyCount: 0,
            previewOnlyCount: 0
        )
    }

    var importLaneSnapshots: [ImportLaneSnapshot] {
        let baseStatusText: String
        let baseDetail: String
        let baseActionTitle: String

        if !sortedImportedWordPages.isEmpty, let importedLibrary = data.importedLibrary {
            baseStatusText = "Base Ready"
            baseDetail = "\(importedLibrary.name) is carrying the stable PET page skeleton for placement and page study."
            baseActionTitle = "IMPORT NEW BASE PDF"
        } else if data.importedLibrary?.source == .pdf {
            baseStatusText = "Base Saved"
            baseDetail = "A PET base PDF is saved locally, but the stable page skeleton is not active yet."
            baseActionTitle = "IMPORT BASE PDF"
        } else {
            baseStatusText = "Waiting"
            baseDetail = "Import the stable `PET全.pdf` bank here so Base Assessment can estimate vocabulary size from the real PET page index."
            baseActionTitle = "IMPORT BASE PDF"
        }

        let questStatusText: String
        let questDetail: String
        if !sortedQuestOverlayPages.isEmpty {
            questStatusText = "Quest Enhanced"
            questDetail = "\(sortedQuestOverlayPages.count) page overlays are already enriching the same PET index without replacing the base layer."
        } else {
            questStatusText = "Quest Pending"
            questDetail = "Quest JSON stays optional. You can keep adding new pages over time without wiping Base or Reading."
        }

        let readingStatusText: String
        let readingDetail: String
        if let readingLibrary = data.readingLibrary {
            readingStatusText = "Reading Ready"
            readingDetail = "\(readingLibrary.articleCount) reading pages are imported and aligned to the same page numbers."
        } else {
            readingStatusText = "Reading Waiting"
            readingDetail = "Import the reading pack here so each finished word page can continue straight into Reading."
        }

        return [
            ImportLaneSnapshot(
                kind: .base,
                title: "Base PDF",
                statusText: baseStatusText,
                detail: baseDetail,
                actionTitle: baseActionTitle
            ),
            ImportLaneSnapshot(
                kind: .quest,
                title: "Quest JSON",
                statusText: questStatusText,
                detail: questDetail,
                actionTitle: "IMPORT QUEST JSON"
            ),
            ImportLaneSnapshot(
                kind: .reading,
                title: "Reading",
                statusText: readingStatusText,
                detail: readingDetail,
                actionTitle: "IMPORT READING"
            )
        ]
    }

    func importPreviewSnapshot(for kind: ImportLaneKind) -> ImportPreviewSnapshot? {
        switch kind {
        case .base:
            return baseImportPreviewSnapshot
        case .quest:
            return questImportPreviewSnapshot
        case .reading:
            return readingImportPreviewSnapshot
        }
    }

    private var baseImportPreviewSnapshot: ImportPreviewSnapshot? {
        guard let page = currentQuestPage.flatMap({ importedWordPage(forPageNumber: $0.pageNumber) }) ?? sortedImportedWordPages.first else {
            return nil
        }

        let previewWords = page.wordIDs
            .compactMap { wordsByID[$0]?.english }
            .prefix(4)
            .joined(separator: " · ")

        let subtitle = previewWords.isEmpty
            ? "Stable PET base words are ready for placement and page study."
            : previewWords

        return ImportPreviewSnapshot(
            id: "base-\(page.pageNumber)",
            title: "Page \(page.pageNumber) base preview",
            subtitle: subtitle,
            tags: [
                "\(page.wordCount) words",
                "Stable base",
                page.sourceFilename
            ]
        )
    }

    private var questImportPreviewSnapshot: ImportPreviewSnapshot? {
        guard let page = currentQuestPage.flatMap({ questOverlayPage(forPageNumber: $0.pageNumber) }) ?? sortedQuestOverlayPages.first else {
            return nil
        }

        let firstQuestion = page.questions.first
        let firstWord = firstQuestion.flatMap { wordsByID[$0.wordID]?.english }
        let prompt = firstQuestion?.meaningPrompt
            ?? firstQuestion?.exampleSentence
            ?? firstQuestion?.translationPrompt
            ?? "This quest page is ready."
        let compactPrompt = previewExcerpt(from: prompt, limit: 110)
        let subtitle = [firstWord, compactPrompt]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")

        var tags = [
            "\(page.wordCount) words",
            "Meaning + Spelling"
        ]
        if page.questions.contains(where: \.hasTranslationStep) {
            tags.append("Translation")
        }

        return ImportPreviewSnapshot(
            id: "quest-\(page.pageNumber)",
            title: "Page \(page.pageNumber) quest preview",
            subtitle: subtitle.isEmpty ? "Quest content is imported and ready." : subtitle,
            tags: tags
        )
    }

    private var readingImportPreviewSnapshot: ImportPreviewSnapshot? {
        guard let quest = selectedReadingPreviewQuest ?? currentReadingQuest ?? sortedReadingQuests.first else {
            return nil
        }

        let pageTag = quest.pageNumber.map { "Page \($0)" } ?? "Reading"
        let questionTag = quest.questionCount > 0 ? "\(quest.questionCount) questions" : "Passage preview"
        let statusTag = quest.isQuizReady ? "Quiz ready" : "Preview only"

        return ImportPreviewSnapshot(
            id: quest.id,
            title: "\(pageTag) reading preview",
            subtitle: previewExcerpt(from: quest.passage, limit: 120),
            tags: [questionTag, statusTag, quest.sourceFilename]
        )
    }

    private func previewExcerpt(from text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > limit else { return collapsed }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return collapsed[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var studyTrackSnapshots: [StudyTrackSnapshot] {
        let baseTrack = StudyTrackSnapshot(
            id: "base-assessment",
            title: "Base Assessment",
            statusText: sortedImportedWordPages.isEmpty ? "Waiting for Base PDF" : "Ready for vocabulary check",
            detail: sortedImportedWordPages.isEmpty
                ? "Import the stable PET base PDF first. This track exists to estimate a child's vocabulary size from the benchmark bank."
                : "Use the base PET bank to run the 100-word vocabulary-level check. Quest overlays can grow later without changing this benchmark role.",
            primaryActionTitle: sortedImportedWordPages.isEmpty ? "IMPORT BASE PDF" : "START 100-WORD TEST"
        )

        let dailyStatusText: String
        let dailyDetail: String
        let dailyActionTitle: String

        if let currentQuestPage {
            let readingState = readingState(forPageNumber: currentQuestPage.pageNumber)
            if isQuestPageCompleted(currentQuestPage.pageNumber) {
                switch readingState {
                case .ready:
                    dailyStatusText = "Reading is next"
                    dailyDetail = "Quest 45 is done for Page \(currentQuestPage.pageNumber). The loop should continue straight into graded Reading."
                    dailyActionTitle = "START READING NOW"
                case .previewOnly:
                    dailyStatusText = "Reading preview is next"
                    dailyDetail = "Quest 45 is done for Page \(currentQuestPage.pageNumber). The matching reading page is imported, but it is still preview-only."
                    dailyActionTitle = "OPEN READING PREVIEW"
                case .completed:
                    dailyStatusText = "Current page complete"
                    dailyDetail = "Both the word quest and Reading step are done for Page \(currentQuestPage.pageNumber)."
                    dailyActionTitle = nextQuestPageAfterCurrent == nil ? "VIEW TROPHIES" : "GO TO PAGE \(nextQuestPageAfterCurrent?.pageNumber ?? currentQuestPage.pageNumber)"
                case .waitingForImport:
                    dailyStatusText = "Waiting for Reading"
                    dailyDetail = "Quest 45 is done, but the matching reading page has not been imported yet."
                    dailyActionTitle = "IMPORT READING"
                case .missingForPage:
                    dailyStatusText = "Reading index mismatch"
                    dailyDetail = "A reading pack is imported, but it does not include the current quest page yet."
                    dailyActionTitle = "OPEN READING HUB"
                }
            } else {
                dailyStatusText = currentQuestPage.isQuestEnhanced ? "Quest 45 ready" : "Base page ready"
                dailyDetail = currentQuestPage.isQuestEnhanced
                    ? "Today's guided loop is Page \(currentQuestPage.pageNumber): finish Quest 45 first, then continue into Reading."
                    : "Today's page is running from the base PET layer. Finish the page words first, then continue into Reading when it is available."
                dailyActionTitle = "START TEST 45"
            }
        } else {
            dailyStatusText = "Waiting for page study"
            dailyDetail = "Quest 45 becomes the daily mainline once page-based PET data is imported."
            dailyActionTitle = "IMPORT QUEST JSON"
        }

        let dailyTrack = StudyTrackSnapshot(
            id: "daily-quest",
            title: "Daily Quest Loop",
            statusText: dailyStatusText,
            detail: dailyDetail,
            primaryActionTitle: dailyActionTitle
        )

        return [baseTrack, dailyTrack]
    }

    var activeSessionWordBankBadgeText: String {
        if let questPageNumber = data.activeSession?.questPageNumber {
            return "PAGE \(questPageNumber)"
        }
        if data.activeWordBankMode == .imported, let importedLibrary = data.importedLibrary {
            return "\(importedLibrary.source.displayName.uppercased()) · \(importedLibrary.name)"
        }
        return "BUNDLED · PET STARTER"
    }

    var reimportConfirmationMessage: String {
        guard let importedLibrary = data.importedLibrary else {
            return "Importing a new bank will replace the current progress."
        }

        return "\(importedLibrary.name) is already saved. Importing another word bank will replace that saved \(importedLibrary.source.displayName.lowercased()) library and reset only the current word-bank progress. Trophies stay."
    }

    var readingReimportConfirmationMessage: String {
        guard let readingLibrary = data.readingLibrary else {
            return "Importing a new reading pack will replace the current reading articles."
        }

        return "\(readingLibrary.name) is already in Reading. Importing another reading pack will replace those articles, but it will not reset your vocabulary placement or word review history."
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
            let progress = data.progressByWordID[word.id] ?? .fresh(for: word.id)
            guard ReviewScheduler.isScheduled(progress) else {
                return nil
            }
            return (word, progress)
        }
        .sorted { lhs, rhs in
            let leftDue = ReviewScheduler.isDue(lhs.progress)
            let rightDue = ReviewScheduler.isDue(rhs.progress)
            if leftDue != rightDue {
                return leftDue && !rightDue
            }
            let leftDate = lhs.progress.nextReviewAt ?? lhs.progress.lastIncorrectAt ?? .distantPast
            let rightDate = rhs.progress.nextReviewAt ?? rhs.progress.lastIncorrectAt ?? .distantPast
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            if lhs.progress.reviewPriority != rhs.progress.reviewPriority {
                return lhs.progress.reviewPriority > rhs.progress.reviewPriority
            }
            return lhs.word.english < rhs.word.english
        }
    }

    var reviewWordSnapshots: [SessionReviewWordSnapshot] {
        reviewWords.map { item in
            let context = reviewLearningContext(forWordID: item.word.id)
            return SessionReviewWordSnapshot(
                english: item.word.english,
                primaryChinese: item.word.primaryChinese,
                topic: item.word.topic,
                nextReviewAt: item.progress.nextReviewAt,
                reviewStep: item.progress.reviewStep,
                retryMissCount: item.progress.retryMissCount,
                memoryTip: memoryTip(forWordID: item.word.id),
                exampleSentence: context?.exampleSentence,
                exampleTranslation: context?.exampleTranslation
            )
        }
    }

    var dueReviewWords: [(word: VocabularyWord, progress: WordProgress)] {
        reviewWords.filter { ReviewScheduler.isDue($0.progress) }
    }

    var sessionHistory: [SessionSummary] {
        data.sessions.sorted { $0.completedAt > $1.completedAt }
    }

    func bootstrap() {
        do {
            let seedWords = try SeedWordLoader.loadWords()
            try store.installBundledInitialDataIfNeeded()
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
                words = loadedData.activeWordBankMode == .imported ? importedWords : seedWords
            } else {
                if loadedData.importedLibrary != nil {
                    let preservedReadingLibrary = loadedData.readingLibrary
                    let preservedReadingQuests = loadedData.readingQuests
                    let preservedSessions = loadedData.sessions
                    let preservedDailyStreak = loadedData.dailyStreak
                    let preservedLastCompletedDayKey = loadedData.lastCompletedDayKey
                    loadedData = AppStoreData()
                    loadedData.readingLibrary = preservedReadingLibrary
                    loadedData.readingQuests = preservedReadingQuests
                    loadedData.sessions = preservedSessions
                    loadedData.dailyStreak = preservedDailyStreak
                    loadedData.lastCompletedDayKey = preservedLastCompletedDayKey
                }
                words = seedWords
            }

            data = loadedData
            normalizeLegacyActiveSessionIfNeeded()
            if hasQuestPages, data.currentQuestPageNumber == nil {
                data.currentQuestPageNumber = currentQuestPage?.pageNumber
            }
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
            if let fallbackWords = try? SeedWordLoader.loadWords() {
                words = fallbackWords
                data = AppStoreData()
                latestSummary = nil
                answerFeedback = nil
                quizStepID = UUID()
                ensureProgressEntries()
                errorMessage = "Saved progress could not be loaded, so the app reopened with the built-in PET starter."
            } else {
                errorMessage = error.localizedDescription
            }
            screen = .onboarding
        }
    }

    func openDashboard() {
        cancelAutoAdvance()
        activeReadingSession = nil
        readingAnswerFeedback = nil
        screen = .dashboard
    }

    func openMainSurface() {
        cancelAutoAdvance()
        activeReadingSession = nil
        readingAnswerFeedback = nil
        screen = data.hasCompletedPlacement ? .dashboard : .onboarding
    }

    func openReview() {
        cancelAutoAdvance()
        activeReadingSession = nil
        readingAnswerFeedback = nil
        screen = .review
    }

    func enableReviewNotifications() async {
        let isAllowed = await reviewNotificationScheduler.requestAuthorization()
        data.reviewNotificationPreferences.isEnabled = isAllowed
        data.reviewNotificationPreferences.permissionDenied = !isAllowed
        let plan = isAllowed ? ReviewNotificationPlanner.plan(from: reviewReminderSnapshot) : nil
        data.reviewNotificationPreferences.lastScheduledAt = plan?.fireDate
        try? persist()
        await reviewNotificationScheduler.apply(plan: plan)
    }

    func disableReviewNotifications() async {
        data.reviewNotificationPreferences.isEnabled = false
        data.reviewNotificationPreferences.permissionDenied = false
        data.reviewNotificationPreferences.lastScheduledAt = nil
        try? persist()
        await reviewNotificationScheduler.apply(plan: nil)
    }

    func openTrophies() {
        cancelAutoAdvance()
        activeReadingSession = nil
        readingAnswerFeedback = nil
        screen = .history
    }

    func openHistory() {
        openTrophies()
    }

    func openReading() {
        cancelAutoAdvance()
        activeReadingSession = nil
        readingAnswerFeedback = nil
        syncReadingPreviewSelection()
        screen = .reading
    }

    func performCurrentUnitPrimaryAction() {
        switch currentUnitSnapshot.primaryAction {
        case .startPlacement:
            startPlacement()
        case .startMission:
            startMission()
        case .startReadingQuest:
            startCurrentReadingQuest()
        case .openReadingHub:
            openReading()
        case .advanceToNextQuestPage:
            advanceToNextQuestPage()
        case .openTrophies:
            openTrophies()
        }
    }

    func resetReadingLibrary() {
        guard createSafetyBackup(reason: "reset-reading-library") else { return }

        data.readingLibrary = nil
        data.readingQuests = []
        data.completedReadingQuestPages = []
        selectedReadingPreviewQuestID = nil
        activeReadingSession = nil
        readingAnswerFeedback = nil
        try? persist()
    }

    func selectReadingPreviewQuest(id: String) {
        guard sortedReadingQuests.contains(where: { $0.id == id }) else { return }
        selectedReadingPreviewQuestID = id
    }

    func selectReadingPreviewPage(_ pageNumber: Int) {
        guard let quest = sortedReadingQuests.first(where: { $0.pageNumber == pageNumber }) else {
            return
        }
        selectedReadingPreviewQuestID = quest.id
    }

    func startSelectedReadingPreview() {
        guard let quest = selectedReadingPreviewQuest else {
            openReading()
            return
        }
        startReadingQuest(quest)
    }

    func resumeCurrentSession() {
        guard data.activeSession != nil else { return }
        cancelAutoAdvance()
        if normalizeLegacyActiveSessionIfNeeded() {
            try? persist()
        }
        answerFeedback = nil
        screen = .quiz
    }

    func leaveQuiz() {
        cancelAutoAdvance()

        if completePendingAnswerIfNeeded() {
            return
        }

        screen = data.hasCompletedPlacement ? .dashboard : .onboarding
        try? persist()
    }

    func requestVocabularyImport() {
        requestBaseImport()
    }

    func requestBaseImport() {
        if screen == .quiz {
            leaveQuiz()
        }
        pendingVocabularyImportIntent = .basePDF
        presentImportPanel(.basePDF) { [weak self] result in
            self?.handleVocabularyImportSelection(result, intent: .basePDF)
        }
    }

    func requestQuestImport() {
        if screen == .quiz {
            leaveQuiz()
        }
        pendingVocabularyImportIntent = .questJSON
        presentImportPanel(.questJSON) { [weak self] result in
            self?.handleVocabularyImportSelection(result, intent: .questJSON)
        }
    }

    func requestReadingImport() {
        if data.readingLibrary != nil {
            isShowingReadingReimportConfirmation = true
            return
        }

        presentReadingImportPanel { [weak self] result in
            self?.handleReadingImportSelection(result)
        }
    }

    func confirmVocabularyReimport() {
        isShowingReimportConfirmation = false
        guard let pendingVocabularyImportURL else { return }
        self.pendingVocabularyImportURL = nil
        startVocabularyImport(from: pendingVocabularyImportURL, intent: pendingVocabularyImportIntent)
    }

    private func shouldMergeQuestOverlay(from url: URL) -> Bool {
        data.activeWordBankMode == .imported
            && !data.wordPages.isEmpty
            && VocabularyImportService.isQuestOverlayFile(at: url)
    }

    private func shouldWarnBeforeReplacingWordBank(with url: URL) -> Bool {
        guard data.importedLibrary != nil else { return false }
        return !shouldMergeQuestOverlay(from: url)
    }

    func dismissPendingVocabularyReplacement() {
        pendingVocabularyImportURL = nil
        pendingVocabularyImportIntent = .generic
        isShowingReimportConfirmation = false
    }

    func handleVocabularyImportSelection(
        _ result: Result<URL, Error>,
        intent: VocabularyImportIntent? = nil
    ) {
        let resolvedIntent = intent ?? pendingVocabularyImportIntent
        switch result {
        case .success(let url):
            if resolvedIntent == .basePDF, url.pathExtension.lowercased() != "pdf" {
                errorMessage = "Base import expects the stable PET PDF so placement and page indexes stay aligned."
                return
            }

            if resolvedIntent == .questJSON, !VocabularyImportService.isQuestOverlayFile(at: url) {
                errorMessage = "Quest import expects a `vocab_quests` JSON file so new pages can layer onto the same PET index."
                return
            }

            if shouldWarnBeforeReplacingWordBank(with: url) {
                pendingVocabularyImportURL = url
                pendingVocabularyImportIntent = resolvedIntent
                isShowingReimportConfirmation = true
                return
            }
            startVocabularyImport(from: url, intent: resolvedIntent)
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func confirmReadingReimport() {
        isShowingReadingReimportConfirmation = false
        presentReadingImportPanel { [weak self] result in
            self?.handleReadingImportSelection(result)
        }
    }

    func handleReadingImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            startReadingImport(from: urls)
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func startCurrentReadingQuest() {
        guard let currentPage = currentQuestPage else {
            openReading()
            return
        }
        startReadingQuest(forPageNumber: currentPage.pageNumber)
    }

    func resetToBundledWordBank() {
        cancelAutoAdvance()

        do {
            let seedWords = try SeedWordLoader.loadWords()
            guard createSafetyBackup(reason: "use-bundled-starter") else { return }

            words = seedWords
            data.activeWordBankMode = .bundled
            data.hasCompletedPlacement = false
            data.progressByWordID = [:]
            data.activeSession = nil
            data.completedQuestPages = []
            data.completedReadingQuestPages = []
            data.currentQuestPageNumber = nil
            latestSummary = sessionHistory.first
            answerFeedback = nil
            activeReadingSession = nil
            readingAnswerFeedback = nil
            quizStepID = UUID()
            screen = .onboarding
            ensureProgressEntries()
            try persist()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startPlacement() {
        let questions = SessionPlanner.placementQuestions(words: words, data: data, count: min(100, words.count))
        startSession(mode: .placement, questions: questions)
    }

    func startMission() {
        if let questPage = currentQuestPage {
            let questions = questionsForStudyPage(pageNumber: questPage.pageNumber)
            startSession(mode: .mission, questions: questions, questPageNumber: questPage.pageNumber, questPageTitle: questPage.title)
            return
        }

        let count = dailyStudySnapshot.targetWordCount
        let questions = SessionPlanner.missionQuestions(
            words: words,
            data: data,
            count: count,
            preferredTopics: personalizedMissionPlan?.focusTopics ?? []
        )
        startSession(mode: .mission, questions: questions)
    }

    func startFailedReview() {
        let questions = SessionPlanner.failedReviewQuestions(words: words, data: data, count: ReviewRescuePlanner.rescueSprintSize)
        startSession(mode: .failedReview, questions: questions)
    }

    func startReadingQuest(forPageNumber pageNumber: Int) {
        guard let readingQuest = readingQuest(forPageNumber: pageNumber) else {
            openReading()
            return
        }
        startReadingQuest(readingQuest)
    }

    func submitReadingChoice(letter: String) {
        guard var session = activeReadingSession,
              session.stage == .answering,
              session.currentIndex < session.questions.count,
              readingAnswerFeedback == nil else {
            return
        }

        let question = session.questions[session.currentIndex]
        guard let selectedChoice = question.choices.first(where: { $0.letter == letter }) else {
            return
        }

        session.selectedChoicesByQuestionNumber[question.number] = letter

        let correctLetter = question.correctChoiceLetter
        let correctChoice = correctLetter.flatMap { expected in
            question.choices.first(where: { $0.letter == expected })
        }
        let isCorrect = correctLetter.map { $0 == letter }

        if isCorrect == true {
            session.correctAnswers += 1
        }

        let shouldRevealAnswer = session.isPreviewOnly || isCorrect == true

        activeReadingSession = session
        readingAnswerFeedback = ReadingAnswerFeedback(
            selectedLetter: selectedChoice.letter,
            correctLetter: shouldRevealAnswer ? correctLetter : nil,
            isCorrect: isCorrect,
            selectedText: selectedChoice.text,
            correctText: shouldRevealAnswer ? correctChoice?.text : nil,
            headline: readingFeedbackHeadline(isCorrect: isCorrect, previewOnly: session.isPreviewOnly),
            detail: readingFeedbackDetail(
                isCorrect: isCorrect,
                previewOnly: session.isPreviewOnly,
                correctLetter: shouldRevealAnswer ? correctLetter : nil,
                correctText: shouldRevealAnswer ? correctChoice?.text : nil
            )
        )
    }

    func advanceReadingQuestionPreview() {
        guard var session = activeReadingSession,
              session.stage == .questionPreview else {
            return
        }

        session.stage = .passageReading
        activeReadingSession = session
        readingAnswerFeedback = nil
        readingStepID = UUID()
    }

    func startReadingQuestions() {
        guard var session = activeReadingSession,
              session.stage == .passageReading else {
            return
        }

        session.stage = .answering
        session.currentIndex = 0
        activeReadingSession = session
        readingAnswerFeedback = nil
        readingStepID = UUID()
    }

    func retryCurrentReadingQuestion() {
        guard let feedback = readingAnswerFeedback,
              feedback.isCorrect == false,
              var session = activeReadingSession,
              session.stage == .answering else {
            return
        }

        if session.currentIndex < session.questions.count {
            let question = session.questions[session.currentIndex]
            session.selectedChoicesByQuestionNumber[question.number] = nil
        }

        activeReadingSession = session
        readingAnswerFeedback = nil
        readingStepID = UUID()
    }

    func advanceReadingAfterFeedback() {
        guard var session = activeReadingSession else { return }
        guard readingAnswerFeedback?.isCorrect != false else { return }

        readingAnswerFeedback = nil
        session.currentIndex += 1

        if session.currentIndex >= session.questions.count {
            finishReadingSession(session)
        } else {
            activeReadingSession = session
            readingStepID = UUID()
        }
    }

    func leaveReadingQuiz() {
        cancelAutoAdvance()
        if let session = activeReadingSession {
            selectedReadingPreviewQuestID = session.questID
        }
        activeReadingSession = nil
        readingAnswerFeedback = nil
        readingStepID = UUID()
        screen = .reading
    }

    private func questionsForStudyPage(pageNumber: Int) -> [PersistedQuestion] {
        if let questOverlay = questOverlayPage(forPageNumber: pageNumber) {
            return questOverlay.questions
        }

        guard let wordPage = importedWordPage(forPageNumber: pageNumber) else {
            return []
        }

        return SessionPlanner.pageQuestions(
            words: words,
            wordIDs: wordPage.wordIDs,
            pageNumber: wordPage.pageNumber,
            pageTitle: wordPage.title
        )
    }

    func submit(choice: String) {
        guard var session = data.activeSession,
              session.currentIndex < session.questions.count,
              answerFeedback == nil,
              let word = currentQuestionWord,
              let question = currentQuestion else {
            return
        }

        if question.isWordExercise && session.mode != .placement {
            if session.currentExerciseStep == .translation {
                let meaningChoice = session.pendingMeaningChoice ?? ""
                let meaningWasCorrect = session.pendingMeaningWasCorrect ?? false
                let spellingWasCorrect = session.pendingSpellingWasCorrect ?? false
                let translationCorrectChoice = question.translationCorrectChoice ?? ""
                let translationWasCorrect = choice == translationCorrectChoice

                session.pendingTranslationChoice = choice
                session.pendingTranslationWasCorrect = translationWasCorrect
                let pronunciationRating = session.pendingPronunciationRating

                let isCorrect = meaningWasCorrect && spellingWasCorrect && translationWasCorrect

                let attempt = AttemptRecord(
                    sessionID: session.id,
                    wordID: word.id,
                    selectedChoice: "Meaning: \(meaningChoice.ifEmpty("No choice")) | Pronunciation: \(pronunciationRating?.feedbackLabel ?? "Not checked") | Spelling: \((session.pendingSpellingAnswer ?? correctSpellingAnswer(for: question, word: word)).ifEmpty(correctSpellingAnswer(for: question, word: word))) | Translation: \(choice)",
                    correctChoice: "Meaning: \(correctMeaningChoice(for: question, word: word)) | Pronunciation: Self-check | Spelling: \(correctSpellingAnswer(for: question, word: word)) | Translation: \(translationCorrectChoice)",
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
                    correctChoice: translationCorrectChoice,
                    isCorrect: isCorrect,
                    newlyMastered: newlyMastered,
                    resultingStreak: progress.currentCorrectStreak,
                    correctMeaning: correctMeaningChoice(for: question, word: word),
                    correctSpelling: correctSpellingAnswer(for: question, word: word),
                    correctTranslation: translationCorrectChoice,
                    revealedSentence: question.exampleSentence,
                    revealedTranslation: question.exampleTranslation,
                    meaningWasCorrect: meaningWasCorrect,
                    spellingWasCorrect: spellingWasCorrect,
                    translationWasCorrect: translationWasCorrect,
                    pronunciationRating: pronunciationRating,
                    memoryTip: question.memoryTip
                )
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    answerFeedback = feedback
                }
                scheduleAutoAdvance(for: feedback)
                return
            }

            guard session.currentExerciseStep == .meaningChoice else {
                return
            }

            session.pendingMeaningChoice = choice
            session.pendingMeaningWasCorrect = choice == correctMeaningChoice(for: question, word: word)
            session.pendingPronunciationRating = nil
            session.currentExerciseStep = .pronunciation
            data.activeSession = session
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                quizStepID = UUID()
            }
            try? persist()
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
            resultingStreak: progress.currentCorrectStreak,
            correctMeaning: word.primaryChinese,
            correctSpelling: nil,
            correctTranslation: nil,
            revealedSentence: nil,
            revealedTranslation: nil,
            meaningWasCorrect: isCorrect,
            spellingWasCorrect: nil,
            translationWasCorrect: nil,
            pronunciationRating: nil,
            memoryTip: nil
        )
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            answerFeedback = feedback
        }
        scheduleAutoAdvance(for: feedback)
    }

    func submitSpelling(answer: String) {
        guard var session = data.activeSession,
              session.currentIndex < session.questions.count,
              answerFeedback == nil,
              let word = currentQuestionWord,
              let question = currentQuestion,
              question.isWordExercise,
              session.currentExerciseStep == .spelling else {
            return
        }

        let spellingAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spellingAnswer.isEmpty else { return }

        let meaningChoice = session.pendingMeaningChoice ?? ""
        let meaningWasCorrect = session.pendingMeaningWasCorrect ?? false
        let isSpellingMatch = spellingAnswerMatches(
            spellingAnswer,
            correctAnswer: correctSpellingAnswer(for: question, word: word)
        )
        session.pendingSpellingAnswer = spellingAnswer

        if !isSpellingMatch {
            session.pendingSpellingWasCorrect = false
            var progress = data.progressByWordID[word.id] ?? .fresh(for: word.id)
            ReviewScheduler.recordRetrySignal(to: &progress, answeredAt: .now)
            data.progressByWordID[word.id] = progress
            data.activeSession = session
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                quizStepID = UUID()
            }
            try? persist()
            rescheduleReviewNotificationIfEnabled()
            return
        }

        let spellingWasCorrect = true
        session.pendingSpellingWasCorrect = true

        if question.hasTranslationStep {
            session.currentExerciseStep = .translation
            data.activeSession = session
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                quizStepID = UUID()
            }
            try? persist()
            return
        }

        let isCorrect = meaningWasCorrect && spellingWasCorrect
        let pronunciationRating = session.pendingPronunciationRating

        let attempt = AttemptRecord(
            sessionID: session.id,
            wordID: word.id,
            selectedChoice: "Meaning: \(meaningChoice.ifEmpty("No choice")) | Pronunciation: \(pronunciationRating?.feedbackLabel ?? "Not checked") | Spelling: \(spellingAnswer)",
            correctChoice: "Meaning: \(correctMeaningChoice(for: question, word: word)) | Pronunciation: Self-check | Spelling: \(correctSpellingAnswer(for: question, word: word))",
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
            selectedChoice: spellingAnswer,
            correctChoice: correctSpellingAnswer(for: question, word: word),
            isCorrect: isCorrect,
            newlyMastered: newlyMastered,
            resultingStreak: progress.currentCorrectStreak,
            correctMeaning: correctMeaningChoice(for: question, word: word),
            correctSpelling: correctSpellingAnswer(for: question, word: word),
            correctTranslation: nil,
            revealedSentence: question.exampleSentence,
            revealedTranslation: question.exampleTranslation,
            meaningWasCorrect: meaningWasCorrect,
            spellingWasCorrect: spellingWasCorrect,
            translationWasCorrect: nil,
            pronunciationRating: pronunciationRating,
            memoryTip: question.memoryTip
        )
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            answerFeedback = feedback
        }
        scheduleAutoAdvance(for: feedback)
    }

    func submitPronunciationRating(_ rating: PronunciationRating) {
        guard var session = data.activeSession,
              session.currentIndex < session.questions.count,
              answerFeedback == nil,
              let word = currentQuestionWord,
              let question = currentQuestion,
              question.isWordExercise,
              session.currentExerciseStep == .pronunciation else {
            return
        }

        if !rating.countsAsStrong {
            var progress = data.progressByWordID[word.id] ?? .fresh(for: word.id)
            ReviewScheduler.recordRetrySignal(to: &progress, answeredAt: .now)
            data.progressByWordID[word.id] = progress
        }

        session.pendingPronunciationRating = rating
        session.currentExerciseStep = .spelling
        data.activeSession = session
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            quizStepID = UUID()
        }
        try? persist()
        rescheduleReviewNotificationIfEnabled()
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
        session.currentExerciseStep = .meaningChoice
        session.pendingMeaningChoice = nil
        session.pendingMeaningWasCorrect = nil
        session.pendingSpellingAnswer = nil
        session.pendingSpellingWasCorrect = nil
        session.pendingPronunciationRating = nil
        session.pendingTranslationChoice = nil
        session.pendingTranslationWasCorrect = nil

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

    private func startSession(
        mode: SessionMode,
        questions: [PersistedQuestion],
        questPageNumber: Int? = nil,
        questPageTitle: String? = nil
    ) {
        guard !questions.isEmpty else {
            errorMessage = "No words are available for this session yet."
            screen = .dashboard
            return
        }

        cancelAutoAdvance()
        latestSummary = nil
        errorMessage = nil
        answerFeedback = nil
        activeReadingSession = nil
        readingAnswerFeedback = nil
        readingStepID = UUID()
        quizStepID = UUID()
        data.activeSession = ActiveSession(
            mode: mode,
            questPageNumber: questPageNumber,
            questPageTitle: questPageTitle,
            questions: questions
        )
        screen = .quiz
        try? persist()
    }

    @discardableResult
    private func normalizeLegacyActiveSessionIfNeeded() -> Bool {
        guard var session = data.activeSession else {
            return false
        }

        var didNormalize = false

        if session.mode == .failedReview,
           session.questions.count > ReviewRescuePlanner.rescueSprintSize {
            session.questions = Array(session.questions.prefix(ReviewRescuePlanner.rescueSprintSize))
            session.currentIndex = min(session.currentIndex, session.questions.count - 1)

            let retainedWordIDs = Set(session.questions.map(\.wordID))
            session.attempts = session.attempts.filter { retainedWordIDs.contains($0.wordID) }
            session.correctAnswers = session.attempts.filter(\.isCorrect).count
            session.newlyMasteredWordIDs = session.newlyMasteredWordIDs.filter { retainedWordIDs.contains($0) }
            didNormalize = true
        }

        let needsPronunciationStepRollback = session.currentExerciseStep == .pronunciation
            && (session.pendingMeaningChoice == nil
                || session.pendingSpellingAnswer != nil
                || session.pendingSpellingWasCorrect != nil
                || session.pendingTranslationChoice != nil
                || session.pendingTranslationWasCorrect != nil)

        if needsPronunciationStepRollback {
            session.currentExerciseStep = .spelling
            session.pendingSpellingWasCorrect = false
            session.pendingPronunciationRating = nil
            session.pendingTranslationChoice = nil
            session.pendingTranslationWasCorrect = nil
            didNormalize = true
        }

        if didNormalize {
            data.activeSession = session
        }
        return didNormalize
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
            questPageNumber: session.questPageNumber,
            questPageTitle: session.questPageTitle,
            totalQuestions: session.questions.count,
            correctAnswers: session.correctAnswers,
            newlyMasteredCount: session.newlyMasteredWordIDs.count,
            weakTopics: feedback.weakTopics,
            headline: feedback.headline,
            body: feedback.body,
            recommendedMissionTitle: feedback.recommendedMissionTitle,
            placementTopicInsights: placementTopicInsights,
            reviewWords: makeReviewWordSnapshots(from: session)
        )

        if session.mode == .placement {
            data.hasCompletedPlacement = true
        } else if session.mode == .mission, let questPageNumber = session.questPageNumber {
            if !data.completedQuestPages.contains(questPageNumber) {
                data.completedQuestPages.append(questPageNumber)
            }
            data.currentQuestPageNumber = questPageNumber
        }

        updateDailyStreak(completedAt)
        data.sessions.insert(summary, at: 0)
        data.activeSession = nil
        latestSummary = summary
        answerFeedback = nil
        quizStepID = UUID()

        if session.mode == .mission,
           let questPageNumber = session.questPageNumber,
           let readingQuest = readingQuest(forPageNumber: questPageNumber) {
            try? persist()
            rescheduleReviewNotificationIfEnabled()
            if readingQuest.isQuizReady {
                startReadingQuest(forPageNumber: questPageNumber)
            } else {
                openReading()
            }
            return
        }

        screen = .summary
        try? persist()
        rescheduleReviewNotificationIfEnabled()
    }

    private func finishReadingSession(_ session: ActiveReadingSession) {
        let completedAt = Date()
        let accuracy = session.questions.isEmpty ? 0 : Int((Double(session.correctAnswers) / Double(session.questions.count) * 100.0).rounded())
        let headline: String
        let body: String
        let recommendedMissionTitle: String

        if session.isPreviewOnly {
            headline = "Reading preview finished"
            body = "You reviewed the matching reading page for this unit. Once answer keys are imported, the same page can become a graded Reading step."
            recommendedMissionTitle = nextQuestPageAfterCurrent == nil ? "VIEW TROPHIES" : "GO TO PAGE \(nextQuestPageAfterCurrent?.pageNumber ?? 0)"
        } else if accuracy == 100 {
            headline = "Reading quest cleared"
            body = "You finished the matching Reading step with \(session.correctAnswers) correct answers out of \(session.questions.count)."
            recommendedMissionTitle = nextQuestPageAfterCurrent == nil ? "VIEW TROPHIES" : "GO TO PAGE \(nextQuestPageAfterCurrent?.pageNumber ?? 0)"
        } else {
            headline = "Reading needs another pass"
            body = "This page's Reading step ended at \(accuracy)% accuracy. Review the passage and try again before you move too far ahead."
            recommendedMissionTitle = "RETRY READING"
        }

        let summary = SessionSummary(
            mode: .readingQuest,
            startedAt: session.startedAt,
            completedAt: completedAt,
            questPageNumber: session.pageNumber,
            questPageTitle: session.questTitle,
            totalQuestions: max(session.questions.count, 1),
            correctAnswers: session.isPreviewOnly ? max(session.questions.count, 1) : session.correctAnswers,
            newlyMasteredCount: 0,
            weakTopics: [],
            headline: headline,
            body: body,
            recommendedMissionTitle: recommendedMissionTitle,
            reviewWords: []
        )

        if !session.isPreviewOnly,
           accuracy == 100,
           let pageNumber = session.pageNumber,
           !data.completedReadingQuestPages.contains(pageNumber) {
            data.completedReadingQuestPages.append(pageNumber)
        }

        updateDailyStreak(completedAt)
        data.sessions.insert(summary, at: 0)
        latestSummary = summary
        activeReadingSession = nil
        readingAnswerFeedback = nil
        readingStepID = UUID()
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

    private func mergeQuestPages(existing: [QuestPage], incoming: [QuestPage]) -> [QuestPage] {
        var pagesByNumber = Dictionary(uniqueKeysWithValues: existing.map { ($0.pageNumber, $0) })
        for page in incoming {
            pagesByNumber[page.pageNumber] = page
        }
        return pagesByNumber.values.sorted { $0.pageNumber < $1.pageNumber }
    }

    private func makeReviewWordSnapshots(from session: ActiveSession) -> [SessionReviewWordSnapshot] {
        var seenWordIDs = Set<String>()

        return session.attempts.compactMap { attempt in
            guard !attempt.isCorrect,
                  seenWordIDs.insert(attempt.wordID).inserted,
                  let word = wordsByID[attempt.wordID] else {
                return nil
            }

            let progress = data.progressByWordID[attempt.wordID] ?? .fresh(for: attempt.wordID)
            let question = session.questions.first(where: { $0.wordID == attempt.wordID })
            let context = reviewLearningContext(from: question) ?? reviewLearningContext(forWordID: attempt.wordID)
            return SessionReviewWordSnapshot(
                english: word.english,
                primaryChinese: word.primaryChinese,
                topic: word.topic,
                nextReviewAt: progress.nextReviewAt,
                reviewStep: progress.reviewStep,
                retryMissCount: progress.retryMissCount,
                memoryTip: question?.memoryTip ?? memoryTip(forWordID: attempt.wordID),
                exampleSentence: context?.exampleSentence,
                exampleTranslation: context?.exampleTranslation
            )
        }
    }

    private func completePendingAnswerIfNeeded() -> Bool {
        guard answerFeedback != nil, var session = data.activeSession else {
            answerFeedback = nil
            return false
        }

        answerFeedback = nil
        session.currentIndex += 1
        session.currentExerciseStep = .meaningChoice
        session.pendingMeaningChoice = nil
        session.pendingMeaningWasCorrect = nil
        session.pendingSpellingAnswer = nil
        session.pendingSpellingWasCorrect = nil
        session.pendingTranslationChoice = nil
        session.pendingTranslationWasCorrect = nil

        if session.currentIndex >= session.questions.count {
            finish(session: session)
            return true
        }

        data.activeSession = session
        return false
    }

    private func startVocabularyImport(from url: URL, intent: VocabularyImportIntent) {
        guard !isImportingWordBank, !isImportingReadingPack else { return }

        cancelAutoAdvance()
        isImportingWordBank = true
        errorMessage = nil

        let storeURL = store.url
        let existingWords = words
        let existingImportedLibrary = data.importedLibrary
        let canMergeQuestOverlay = intent != .basePDF
            && data.activeWordBankMode == .imported
            && !data.wordPages.isEmpty
        let backupReason: String = switch intent {
        case .basePDF: "import-base-pdf"
        case .questJSON: "import-quest-json"
        case .generic: "import-word-bank"
        }

        guard createSafetyBackup(reason: backupReason) else {
            isImportingWordBank = false
            return
        }

        enum VocabularyImportOutcome {
            case replace(ImportedWordLibrary)
            case overlay(ImportedQuestOverlay)
        }

        Task { [url] in
            do {
                let outcome = try await Task.detached(priority: .userInitiated) {
                    let seedWords = try SeedWordLoader.loadWords()
                    let localStore = LocalStore(url: storeURL)

                    if canMergeQuestOverlay {
                        if let overlay = try? VocabularyImportService.importQuestOverlay(
                            from: url,
                            existingWords: existingWords,
                            seedWords: seedWords
                        ) {
                            try localStore.saveImportedWords(overlay.words)
                            return VocabularyImportOutcome.overlay(overlay)
                        }
                    }

                    let importedLibrary = try VocabularyImportService.importWordLibrary(from: url, seedWords: seedWords)
                    try localStore.saveImportedWords(importedLibrary.words)
                    return VocabularyImportOutcome.replace(importedLibrary)
                }.value

                switch outcome {
                case .replace(let importedLibrary):
                    let preservedReadingLibrary = data.readingLibrary
                    let preservedReadingQuests = data.readingQuests
                    let preservedSessions = data.sessions
                    let preservedDailyStreak = data.dailyStreak
                    let preservedLastCompletedDayKey = data.lastCompletedDayKey
                    words = importedLibrary.words
                    data = AppStoreData()
                    data.activeWordBankMode = .imported
                    data.importedLibrary = importedLibrary.metadata
                    data.wordPages = importedLibrary.wordPages
                    data.questPages = importedLibrary.questPages
                    data.currentQuestPageNumber = importedLibrary.wordPages.sorted(by: { $0.pageNumber < $1.pageNumber }).first?.pageNumber
                        ?? importedLibrary.questPages.sorted(by: { $0.pageNumber < $1.pageNumber }).first?.pageNumber
                    data.readingLibrary = preservedReadingLibrary
                    data.readingQuests = preservedReadingQuests
                    data.sessions = preservedSessions
                    data.dailyStreak = preservedDailyStreak
                    data.lastCompletedDayKey = preservedLastCompletedDayKey
                    latestSummary = sessionHistory.first
                    answerFeedback = nil
                    activeReadingSession = nil
                    readingAnswerFeedback = nil
                    readingStepID = UUID()
                    quizStepID = UUID()
                    screen = .onboarding
                    ensureProgressEntries()
                    try persist()

                case .overlay(let overlay):
                    words = overlay.words
                    data.activeWordBankMode = .imported
                    if data.importedLibrary == nil {
                        data.importedLibrary = existingImportedLibrary
                    }
                    data.questPages = mergeQuestPages(existing: data.questPages, incoming: overlay.questPages)
                    if let selectedPageNumber = data.currentQuestPageNumber,
                       !sortedQuestPages.contains(where: { $0.pageNumber == selectedPageNumber }) {
                        data.currentQuestPageNumber = sortedQuestPages.first?.pageNumber
                    } else if data.currentQuestPageNumber == nil {
                        data.currentQuestPageNumber = sortedQuestPages.first?.pageNumber
                    }
                    latestSummary = sessionHistory.first
                    answerFeedback = nil
                    activeReadingSession = nil
                    readingAnswerFeedback = nil
                    readingStepID = UUID()
                    quizStepID = UUID()
                    ensureProgressEntries()
                    try persist()
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isImportingWordBank = false
        }
    }

    private func startReadingImport(from urls: [URL]) {
        guard !isImportingWordBank, !isImportingReadingPack else { return }
        guard !urls.isEmpty else { return }

        cancelAutoAdvance()
        isImportingReadingPack = true
        errorMessage = nil

        guard createSafetyBackup(reason: "import-reading-pack") else {
            isImportingReadingPack = false
            return
        }

        Task { [urls] in
            do {
                let importedReading = try await Task.detached(priority: .userInitiated) {
                    try ReadingImportService.importReadingLibrary(from: urls)
                }.value

                data.readingLibrary = importedReading.metadata
                data.readingQuests = importedReading.quests
                syncReadingPreviewSelection()
                activeReadingSession = nil
                readingAnswerFeedback = nil
                readingStepID = UUID()

                if let currentPage = currentQuestPage,
                   isQuestPageCompleted(currentPage.pageNumber),
                   let matchedQuest = readingQuest(forPageNumber: currentPage.pageNumber),
                   matchedQuest.isQuizReady {
                    startReadingQuest(forPageNumber: currentPage.pageNumber)
                } else {
                    screen = .reading
                }
                try persist()
            } catch {
                errorMessage = error.localizedDescription
            }

            isImportingReadingPack = false
        }
    }

    func readingPreviewMenuLabel(for quest: ReadingQuest) -> String {
        let pageLabel = quest.pageNumber.map { "Page \($0)" } ?? quest.title
        let stateLabel: String

        if quest.isQuizReady {
            stateLabel = "Quiz Ready"
        } else if quest.questionCount > 0 {
            stateLabel = "Preview Only"
        } else {
            stateLabel = "Passage Only"
        }

        return "\(pageLabel) · \(stateLabel)"
    }

    private func syncReadingPreviewSelection() {
        if let selectedReadingPreviewQuestID,
           sortedReadingQuests.contains(where: { $0.id == selectedReadingPreviewQuestID }) {
            return
        }

        selectedReadingPreviewQuestID = currentReadingQuest?.id ?? sortedReadingQuests.first?.id
    }

    private func startReadingQuest(_ readingQuest: ReadingQuest) {
        cancelAutoAdvance()
        selectedReadingPreviewQuestID = readingQuest.id
        activeReadingSession = ActiveReadingSession(
            questID: readingQuest.id,
            questTitle: readingQuest.title,
            pageNumber: readingQuest.pageNumber,
            passage: readingQuest.passage,
            questions: readingQuest.questions,
            isPreviewOnly: !readingQuest.isQuizReady
        )
        readingAnswerFeedback = nil
        readingStepID = UUID()
        screen = .readingQuiz
    }

    func memoryTip(forWordID wordID: String) -> String? {
        if let sessionQuestion = data.activeSession?.questions.first(where: { $0.wordID == wordID }),
           let memoryTip = sessionQuestion.memoryTip?.trimmingCharacters(in: .whitespacesAndNewlines),
           !memoryTip.isEmpty {
            return memoryTip
        }

        for page in data.questPages {
            if let memoryTip = page.questions.first(where: { $0.wordID == wordID })?.memoryTip?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !memoryTip.isEmpty {
                return memoryTip
            }
        }

        return nil
    }

    private func reviewLearningContext(forWordID wordID: String) -> ReviewRescueWordContext? {
        if let sessionQuestion = data.activeSession?.questions.first(where: { $0.wordID == wordID }),
           let context = reviewLearningContext(from: sessionQuestion) {
            return context
        }

        for page in data.questPages {
            if let question = page.questions.first(where: { $0.wordID == wordID }),
               let context = reviewLearningContext(from: question) {
                return context
            }
        }

        return nil
    }

    private func reviewLearningContext(from question: PersistedQuestion?) -> ReviewRescueWordContext? {
        guard let question else { return nil }
        let exampleSentence = cleanedReviewText(question.exampleSentence)
        let exampleTranslation = cleanedReviewText(question.exampleTranslation)

        guard exampleSentence != nil || exampleTranslation != nil else {
            return nil
        }

        return ReviewRescueWordContext(
            exampleSentence: exampleSentence,
            exampleTranslation: exampleTranslation
        )
    }

    private func cleanedReviewText(_ text: String?) -> String? {
        let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    private func makeAnswerFeedback(
        selectedChoice: String,
        correctChoice: String,
        isCorrect: Bool,
        newlyMastered: Bool,
        resultingStreak: Int,
        correctMeaning: String,
        correctSpelling: String?,
        correctTranslation: String?,
        revealedSentence: String?,
        revealedTranslation: String?,
        meaningWasCorrect: Bool?,
        spellingWasCorrect: Bool?,
        translationWasCorrect: Bool?,
        pronunciationRating: PronunciationRating?,
        memoryTip: String?
    ) -> QuizAnswerFeedback {
        let pointsEarned = (isCorrect ? 10 : 0) + (newlyMastered ? 25 : 0)
        let autoAdvanceDelay: TimeInterval
        let requiresManualAdvance: Bool
        let headline: String
        var detail: String
        let meaningStatus = meaningWasCorrect
        let spellingStatus = spellingWasCorrect
        let translationStatus = translationWasCorrect

        if correctTranslation != nil {
            autoAdvanceDelay = newlyMastered ? 2.35 : 2.05
            requiresManualAdvance = true
            if newlyMastered {
                headline = "Page word locked in"
                detail = "You cleared meaning, spelling, and sentence translation, then completed the mastery loop for this word."
            } else if isCorrect && resultingStreak == 2 {
                headline = "Excellent three-step recall"
                detail = "All three checks were right. One more full pass later will mark this word as mastered."
            } else if isCorrect {
                headline = "Quest cleared"
                detail = "You matched the sentence meaning, spelled the word, and translated the sentence correctly."
            } else if meaningStatus == false {
                headline = "Meaning needs work"
                detail = "The sentence meaning choice missed the target word. This page word will come back in review."
            } else if spellingStatus == false {
                headline = "Spelling needs work"
                detail = "The sentence meaning was right, but the Chinese-to-English spelling was off."
            } else if translationStatus == false {
                headline = "Translation needs work"
                detail = "Meaning and spelling were right, but the sentence translation still needs another pass."
            } else {
                headline = "Let's revisit this page word"
                detail = "One or more steps were off, so this word will return again."
            }

            if let pronunciationRating {
                switch pronunciationRating {
                case .needsPractice:
                    detail += " You also marked the pronunciation as needing more practice."
                case .almostThere:
                    detail += " You finished with an extra pronunciation check and marked it almost there."
                case .clear:
                    detail += " You finished with an extra pronunciation check and marked it clear and confident."
                }
            }
        } else if correctSpelling != nil {
            autoAdvanceDelay = newlyMastered ? 2.2 : 1.95
            requiresManualAdvance = false
            if newlyMastered {
                headline = "Word locked in"
                detail = "You matched the meaning and spelling, then completed the 3-pass mastery loop for this word."
            } else if isCorrect && resultingStreak == 2 {
                headline = "Strong recall"
                detail = "Both parts were correct. One more successful word cycle later will mark this word as mastered."
            } else if isCorrect {
                headline = "Nice work"
                detail = "You matched the meaning and spelled the word correctly from the sentence clue."
            } else if meaningStatus == false && spellingStatus == true {
                headline = "Meaning needs work"
                detail = "Your spelling was right, but the meaning choice was off. This word will come back in review."
            } else if meaningStatus == true && spellingStatus == false {
                headline = "Spelling needs work"
                detail = "You chose the right meaning, but the spelling was off. This word will come back in review."
            } else {
                headline = "Let's revisit this word"
                detail = "Both the meaning and spelling need another pass. This word will come back in review."
            }
        } else if newlyMastered {
            autoAdvanceDelay = 1.85
            requiresManualAdvance = false
            headline = "Mastery unlocked"
            detail = "You got it right and completed the 3-correct streak for this word."
        } else if isCorrect && resultingStreak == 2 {
            autoAdvanceDelay = 1.45
            requiresManualAdvance = false
            headline = "Nice work"
            detail = "One more correct answer on a later attempt will mark this word as mastered."
        } else if isCorrect {
            autoAdvanceDelay = 1.2
            requiresManualAdvance = false
            headline = "Correct"
            detail = "You chose the right Chinese meaning. Keep building the streak."
        } else {
            autoAdvanceDelay = 1.75
            requiresManualAdvance = false
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
            requiresManualAdvance: requiresManualAdvance,
            headline: headline,
            detail: detail,
            correctMeaning: correctMeaning,
            correctSpelling: correctSpelling,
            correctTranslation: correctTranslation,
            revealedSentence: revealedSentence,
            revealedTranslation: revealedTranslation,
            meaningWasCorrect: meaningWasCorrect,
            spellingWasCorrect: spellingWasCorrect,
            translationWasCorrect: translationWasCorrect,
            pronunciationRating: pronunciationRating,
            memoryTip: memoryTip
        )
    }

    private func readingFeedbackHeadline(isCorrect: Bool?, previewOnly: Bool) -> String {
        if previewOnly {
            return "Reading preview saved"
        }
        if isCorrect == true {
            return "Nice reading pick"
        }
        return "Check the passage again"
    }

    private func readingFeedbackDetail(
        isCorrect: Bool?,
        previewOnly: Bool,
        correctLetter: String?,
        correctText: String?
    ) -> String {
        if previewOnly {
            return "This page is still preview-only, so your choice is recorded without grading."
        }
        if isCorrect == true {
            return "That answer matches the passage."
        }
        if let correctLetter, let correctText {
            return "The matching answer was \(correctLetter): \(correctText)"
        }
        return "Not quite yet. Read the passage again and retry this question."
    }

    private func scheduleAutoAdvance(for feedback: QuizAnswerFeedback) {
        cancelAutoAdvance()

        guard !feedback.requiresManualAdvance else { return }

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

    private func correctMeaningChoice(for question: PersistedQuestion, word: VocabularyWord) -> String {
        question.meaningCorrectChoice?.ifEmpty(word.primaryChinese) ?? word.primaryChinese
    }

    private func correctSpellingAnswer(for question: PersistedQuestion, word: VocabularyWord) -> String {
        question.spellingCorrectAnswer?.ifEmpty(word.english) ?? word.english
    }

    private func persist() throws {
        try store.save(data)
    }

    private func rescheduleReviewNotificationIfEnabled() {
        guard data.reviewNotificationPreferences.isEnabled else { return }

        let plan = ReviewNotificationPlanner.plan(from: reviewReminderSnapshot)
        data.reviewNotificationPreferences.lastScheduledAt = plan?.fireDate
        try? store.save(data)

        Task { @MainActor [reviewNotificationScheduler] in
            await reviewNotificationScheduler.apply(plan: plan)
        }
    }

    private func createSafetyBackup(reason: String) -> Bool {
        do {
            _ = try store.backupExistingData(reason: reason)
            return true
        } catch {
            errorMessage = "Could not create a local backup before changing saved data: \(error.localizedDescription)"
            return false
        }
    }

    private static func defaultImportPanelPresenter(
        intent: VocabularyImportIntent,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.prompt = "Import"

        switch intent {
        case .basePDF:
            panel.message = "Choose the stable PET base PDF. This powers Base Assessment and the page-aligned PET skeleton."
            panel.allowedContentTypes = [.pdf]
        case .questJSON:
            panel.message = "Choose a `vocab_quests` JSON file. This adds or updates page overlays without wiping Reading."
            panel.allowedContentTypes = [.json]
        case .generic:
            panel.message = "Choose a PET PDF, CSV, TXT, or JSON word bank."
            panel.allowedContentTypes = [.pdf, .json, .commaSeparatedText, .plainText]
        }

        panel.begin { response in
            if response == .OK, let url = panel.url {
                completion(.success(url))
            } else {
                let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
                completion(.failure(error))
            }
        }
    }

    private static func defaultReadingImportPanelPresenter(completion: @escaping (Result<[URL], Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.prompt = "Import"
        panel.message = "Choose one Reading `.txt` or `.pdf` file, several supported files, or one folder that contains them. PDF pages will match the same PET page index."
        panel.allowedContentTypes = [.plainText, .pdf]

        panel.begin { response in
            if response == .OK, !panel.urls.isEmpty {
                completion(.success(panel.urls))
            } else {
                let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
                completion(.failure(error))
            }
        }
    }

    private func normalizeWordAnswer(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private func spellingAnswerMatches(_ answer: String, correctAnswer: String) -> Bool {
        let normalizedAnswer = normalizeWordAnswer(answer)
        return acceptedSpellingAnswers(for: correctAnswer).contains(normalizedAnswer)
    }

    private func acceptedSpellingAnswers(for correctAnswer: String) -> Set<String> {
        let answerParts = correctAnswer.components(separatedBy: CharacterSet(charactersIn: "/,;|"))
        return answerParts.reduce(into: Set<String>()) { acceptedAnswers, rawPart in
            acceptedAnswers.insertNormalized(rawPart, using: normalizeWordAnswer)

            for expandedAnswer in expandOptionalParentheticalLetters(in: rawPart) {
                acceptedAnswers.insertNormalized(expandedAnswer, using: normalizeWordAnswer)
            }
        }
    }

    private func expandOptionalParentheticalLetters(in value: String) -> [String] {
        var variants = [""]
        var index = value.startIndex

        while index < value.endIndex {
            if value[index] == "(",
               let closingIndex = value[index...].firstIndex(of: ")") {
                let optionalLetters = String(value[value.index(after: index)..<closingIndex])
                if isAttachedOptionalLetterGroup(optionalLetters, in: value, openingIndex: index) {
                    let withOptionalLetters = variants.map { $0 + optionalLetters }
                    variants.append(contentsOf: withOptionalLetters)
                    index = value.index(after: closingIndex)
                    continue
                }
            }

            let character = String(value[index])
            variants = variants.map { $0 + character }
            index = value.index(after: index)
        }

        return variants
    }

    private func isAttachedOptionalLetterGroup(_ value: String, in original: String, openingIndex: String.Index) -> Bool {
        guard !value.isEmpty,
              value.count <= 8,
              value.rangeOfCharacter(from: CharacterSet.letters.inverted) == nil,
              openingIndex > original.startIndex else {
            return false
        }

        let previousCharacter = original[original.index(before: openingIndex)]
        return !previousCharacter.isWhitespace
    }
}

private extension Set where Element == String {
    mutating func insertNormalized(_ value: String, using normalizer: (String) -> String) {
        let normalizedValue = normalizer(value)
        if !normalizedValue.isEmpty {
            insert(normalizedValue)
        }
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

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
