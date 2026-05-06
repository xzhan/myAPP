import AppKit
import AVFoundation
import Foundation
import PDFKit
import Speech
import Testing
@testable import PETVocabularyTrainer

struct PETVocabularyTrainerTests {
    @MainActor
    private final class FakeReviewNotificationScheduler: ReviewNotificationScheduling {
        var authorizationResult = true
        var requestedAuthorizationCount = 0
        var appliedPlans: [ReviewNotificationPlan?] = []

        func requestAuthorization() async -> Bool {
            requestedAuthorizationCount += 1
            return authorizationResult
        }

        func apply(plan: ReviewNotificationPlan?) async {
            appliedPlans.append(plan)
        }
    }

    private static func isolatedStore() -> LocalStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")
        return LocalStore(url: url)
    }

    @MainActor
    private static func waitForCondition(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition(), DispatchTime.now().uptimeNanoseconds < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(condition())
    }

    @Test func pronunciationAssessmentRatesRecognizedSpeechAgainstTargetWord() {
        #expect(PronunciationAssessment.rate(spokenText: "influence", targetWord: "influence") == .clear)
        #expect(PronunciationAssessment.rate(spokenText: "influnce", targetWord: "influence") == .almostThere)
        #expect(PronunciationAssessment.rate(spokenText: "argum", targetWord: "argument") == .almostThere)
        #expect(PronunciationAssessment.rate(spokenText: "teacher", targetWord: "influence") == .needsPractice)
    }

    @Test func pronunciationRatingUsesGentleHeartFeedback() {
        #expect(PronunciationRating.clear.heartMeter == "❤️❤️❤️")
        #expect(PronunciationRating.almostThere.heartMeter == "🤍❤️❤️")
        #expect(PronunciationRating.needsPractice.heartMeter == "🤍🤍❤️")
        #expect(PronunciationRating.almostThere.feedbackLabel == "Almost heard")
        #expect(PronunciationRating.almostThere.countsAsStrong == true)
    }

    @Test func pronunciationAssessmentFindsTargetInsideRecognizerPhrase() {
        #expect(PronunciationAssessment.rate(spokenText: "I said influence", targetWord: "influence") == .clear)
        #expect(PronunciationAssessment.rate(spokenText: "in fluence", targetWord: "influence") == .almostThere)
        #expect(PronunciationAssessment.rate(spokenText: "", targetWord: "influence") == .needsPractice)
    }

    @MainActor
    @Test func pronunciationSpeechCoachFallsBackWhenPermissionIsUnavailable() async throws {
        let coach = PronunciationSpeechCoach(
            permissionProvider: PronunciationPermissionProvider(
                requestSpeechAuthorization: { .unavailable },
                requestMicrophoneAuthorization: { .authorized }
            )
        )

        coach.start(targetWord: "influence")

        try await Self.waitForCondition { coach.state == .unavailable }
        #expect(coach.rating == nil)
        #expect(coach.message.contains("self-check"))
    }

    @MainActor
    @Test func pronunciationSpeechCoachGuidesUserToSettingsAfterMicrophoneDenied() async throws {
        let coach = PronunciationSpeechCoach(
            permissionProvider: PronunciationPermissionProvider(
                requestSpeechAuthorization: { .authorized },
                requestMicrophoneAuthorization: { .denied }
            )
        )

        coach.start(targetWord: "influence")

        try await Self.waitForCondition { coach.state == .unavailable }
        #expect(coach.permissionRecovery?.title == "Open Microphone Settings")
        #expect(coach.permissionRecovery?.settingsURL.absoluteString.contains("Privacy_Microphone") == true)
        #expect(coach.message.contains("System Settings"))
    }

    @Test func pronunciationAudioInputValidationRejectsInvalidHeadsetFormats() {
        #expect(PronunciationAudioInput.isUsable(sampleRate: 0, channelCount: 1) == false)
        #expect(PronunciationAudioInput.isUsable(sampleRate: 44_100, channelCount: 0) == false)
        #expect(PronunciationAudioInput.isUsable(sampleRate: 44_100, channelCount: 1) == true)
    }

    @Test func pronunciationAudioTapHandlerCanRunOffMainActorQueue() throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
        let time = AVAudioTime(sampleTime: 0, atRate: 44_100)
        let handler = PronunciationAudioTap.makeHandler(request: request)
        buffer.frameLength = 128

        DispatchQueue.global(qos: .userInitiated).sync {
            handler(buffer, time)
        }

        request.endAudio()
    }

    @Test func swiftRunExecutableEmbedsSpeechPrivacyInfoPlist() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let packageManifest = try String(
            contentsOf: packageRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let infoPlistURL = packageRoot.appendingPathComponent("Sources/PETVocabularyTrainer/Info.plist")
        let infoPlist = try String(contentsOf: infoPlistURL, encoding: .utf8)

        #expect(packageManifest.contains("__info_plist"))
        #expect(packageManifest.contains("Sources/PETVocabularyTrainer/Info.plist"))
        #expect(infoPlist.contains("NSMicrophoneUsageDescription"))
        #expect(infoPlist.contains("NSSpeechRecognitionUsageDescription"))
    }

    @Test func petPDFWordParserHandlesWrappedPETEntries() throws {
        let sample = """
        剑桥五级-PET词汇-2020更新版词库 学习日期:
        第20关
        ①
        crowd 群众,
        一伙
        mathematics/math
        s 数学
        examination/exa
        m 检查,考试
        l 我
        May 五月
        may 可以,可能
        打印时间:2025-07-21
        """

        let entries = try PETPDFWordParser.parse(text: sample)

        #expect(entries.count == 6)
        #expect(entries[0].english == "crowd")
        #expect(entries[0].primaryChinese == "群众,一伙")
        #expect(entries[1].english == "mathematics/maths")
        #expect(entries[1].primaryChinese == "数学")
        #expect(entries[2].english == "examination/exam")
        #expect(entries[3].english == "I")
        #expect(entries[4].english == "May")
        #expect(entries[5].english == "may")
    }

    @Test func vocabularyImportServiceImportsCSVBanksForTesting() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("pet-bank.csv")

        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }

        let contents = (0..<120)
            .map { "word\($0),词\($0)" }
            .joined(separator: "\n")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)

        let imported = try VocabularyImportService.importWordLibrary(from: fileURL, seedWords: try SeedWordLoader.loadWords())

        #expect(imported.words.count == 120)
        #expect(imported.metadata.source == .csv)
        #expect(imported.metadata.wordCount == 120)
        #expect(imported.words.first?.id == "word0")
    }

    @Test func vocabularyImportServiceImportsQuestJSONAsPageBundles() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("vocab_quests 38.json")

        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Self.sampleQuestJSONData().write(to: fileURL)

        let imported = try VocabularyImportService.importWordLibrary(from: fileURL, seedWords: [])
        let firstPage = try #require(imported.questPages.first)
        let firstQuestion = try #require(firstPage.questions.first)

        #expect(imported.metadata.source == .questJSON)
        #expect(imported.metadata.wordCount == 2)
        #expect(imported.questPages.map(\.pageNumber) == [37, 38])
        #expect(firstPage.title == "PET全_Page_37_03261514")
        #expect(firstPage.wordCount == 1)
        #expect(firstQuestion.style == .wordExercise)
        #expect(firstQuestion.meaningPrompt == "The director told the actors where to stand.")
        #expect(firstQuestion.meaningCorrectChoice == "导演")
        #expect(firstQuestion.spellingPromptText == "导演: ___")
        #expect(firstQuestion.spellingCorrectAnswer == "director")
        #expect(firstQuestion.translationPrompt == "导演告诉演员们该站在哪里。")
        #expect(firstQuestion.translationChoices.count == 4)
        #expect(firstQuestion.translationCorrectChoice == "The director told the actors where to stand.")
        #expect(firstQuestion.memoryTip?.contains("Direct-or") == true)
        #expect(firstQuestion.exampleTranslation == "导演告诉演员们该站在哪里。")
    }

    @Test func vocabularyImportServiceHandlesQuestPagesWithSameNormalizedEnglishKey() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("duplicate-quest.json")

        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Self.duplicateNormalizedQuestJSONData().write(to: fileURL)

        let imported = try VocabularyImportService.importWordLibrary(from: fileURL, seedWords: [])
        let page37Question = try #require(imported.questPages.first(where: { $0.pageNumber == 37 })?.questions.first)
        let page38Question = try #require(imported.questPages.first(where: { $0.pageNumber == 38 })?.questions.first)

        #expect(imported.questPages.count == 2)
        #expect(imported.words.map(\.english).contains("Miss"))
        #expect(imported.words.map(\.english).contains("miss"))
        #expect(page37Question.wordID != page38Question.wordID)
        #expect(page37Question.meaningCorrectChoice == "小姐")
        #expect(page38Question.meaningCorrectChoice == "想念")
    }

    @Test func vocabularyImportServiceMergesDuplicateOriginalVocabEntriesInsideQuestSession() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("duplicate-original-vocab.json")

        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Self.duplicateOriginalVocabQuestJSONData().write(to: fileURL)

        let imported = try VocabularyImportService.importWordLibrary(from: fileURL, seedWords: [])
        let firstPage = try #require(imported.questPages.first)
        let firstQuestion = try #require(firstPage.questions.first)

        #expect(imported.questPages.map(\.pageNumber) == [14])
        #expect(imported.words.map(\.english).contains("homework"))
        #expect(firstQuestion.wordID == "homework")
        #expect(firstQuestion.exampleSentence == "She finished her homework before dinner.")
        #expect(firstQuestion.exampleTranslation == "她在晚饭前完成了作业。")
    }

    @Test func vocabularyImportServiceHandlesLongUnknownWordsWithoutOverflowingTopicHash() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("pet-bank-overflow.csv")

        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }

        let giantStem = String(repeating: "zzzzzzzzzz", count: 50)
        let contents = (0..<120)
            .map { "\(giantStem)\($0),词\($0)" }
            .joined(separator: "\n")

        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)

        let imported = try VocabularyImportService.importWordLibrary(from: fileURL, seedWords: [])

        #expect(imported.words.count == 120)
        #expect(imported.words.allSatisfy { !$0.english.isEmpty })
    }

    @Test func readingImportServiceParsesSingleQuestTXTWithoutAnswerKeys() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("PET全_Page_1.txt")

        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Self.sampleReadingQuestText(
            title: "PET全_Page_1_03261327",
            includeAnswers: false
        ).write(to: fileURL, atomically: true, encoding: .utf8)

        let imported = try ReadingImportService.importReadingLibrary(from: [fileURL])
        let quest = try #require(imported.quests.first)

        #expect(imported.metadata.articleCount == 1)
        #expect(quest.title == "PET全_Page_1_03261327")
        #expect(quest.pageNumber == 1)
        #expect(quest.questionCount == 5)
        #expect(quest.isQuizReady == false)
        #expect(quest.questions.first?.choices.count == 4)
    }

    @Test func readingImportServiceImportsFolderAndSortsByPageNumber() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Self.sampleReadingQuestText(title: "PET全_Page_2_03261327", includeAnswers: true)
            .write(to: directoryURL.appendingPathComponent("page-2.txt"), atomically: true, encoding: .utf8)
        try Self.sampleReadingQuestText(title: "PET全_Page_1_03261327", includeAnswers: false)
            .write(to: directoryURL.appendingPathComponent("page-1.txt"), atomically: true, encoding: .utf8)

        let imported = try ReadingImportService.importReadingLibrary(from: [directoryURL])

        #expect(imported.quests.map(\.pageNumber) == [1, 2])
        #expect(imported.quests[0].isQuizReady == false)
        #expect(imported.quests[1].isQuizReady == true)
    }

    @MainActor
    @Test func readingImportServiceParsesPDFPagesAsPageMatchedPreviewQuests() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("PET_Reading.pdf")

        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Self.makeReadingPDF(
            at: fileURL,
            pages: [
                "Last Tuesday, Sarah packed her luggage for a trip to a winter resort.",
                "Tom revised his homework before the speaking test."
            ]
        )

        let imported = try ReadingImportService.importReadingLibrary(from: [fileURL])

        #expect(imported.metadata.articleCount == 2)
        #expect(imported.quests.map(\.pageNumber) == [1, 2])
        #expect(imported.quests.allSatisfy { !$0.isQuizReady })
        #expect(imported.quests.allSatisfy { $0.questionCount == 0 })
        #expect(imported.quests[0].title == "PET_Reading_Page_1")
    }

    @MainActor
    @Test func vocabularyImportServiceParsesPETPDFIntoStableWordPages() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("PET全.pdf")

        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Self.makeReadingPDF(
            at: fileURL,
            pages: [
                Self.sampleVocabularyPDFPage(pageNumber: 1, startIndex: 0, count: 60),
                Self.sampleVocabularyPDFPage(pageNumber: 2, startIndex: 60, count: 60)
            ]
        )

        let imported = try VocabularyImportService.importWordLibrary(from: fileURL, seedWords: [])

        #expect(imported.metadata.source == .pdf)
        #expect(imported.wordPages.map(\.pageNumber) == [1, 2])
        #expect(imported.wordPages[0].wordCount == 60)
        #expect(imported.wordPages[1].wordCount == 60)
        #expect(imported.questPages.isEmpty)
        #expect(imported.words.count == 120)
    }

    @MainActor
    @Test func appModelCompletesVocabularyImportWithoutLeavingBlockingState() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("pet-bank.csv")
        let storeURL = tempDirectory.appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let contents = (0..<120)
            .map { "word\($0),词\($0)" }
            .joined(separator: "\n")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)

        let model = AppModel(store: LocalStore(url: storeURL))

        model.handleVocabularyImportSelection(.success(fileURL))

        #expect(model.isImportingWordBank)

        let deadline = Date().addingTimeInterval(5)
        while model.isImportingWordBank && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(!model.isImportingWordBank)
        #expect(model.words.count == 120)
        #expect(model.wordBankSnapshot.isImportedActive)
        #expect(model.errorMessage == nil)
        #expect(model.screen == .onboarding)
    }

    @MainActor
    @Test func resetToBundledPreservesSavedImportAndTrophies() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = tempDirectory.appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let store = LocalStore(url: storeURL)
        let importedWords = [
            VocabularyWord(id: "import-1", english: "director", primaryChinese: "导演", topic: .people)
        ]
        try store.saveImportedWords(importedWords)

        let summary = SessionSummary(
            mode: .mission,
            startedAt: .now,
            completedAt: .now,
            totalQuestions: 1,
            correctAnswers: 1,
            newlyMasteredCount: 0,
            weakTopics: [],
            headline: "Nice work",
            body: "Recorded trophy",
            recommendedMissionTitle: "Keep going"
        )

        let model = AppModel(store: store)
        model.words = importedWords
        model.data.activeWordBankMode = .imported
        model.data.importedLibrary = WordLibraryMetadata(
            name: "Imported PET Word Bank",
            sourceFilename: "imported_words.json",
            importedAt: .now,
            wordCount: importedWords.count,
            source: .json
        )
        model.data.questPages = [QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: [])]
        model.data.currentQuestPageNumber = 14
        model.data.hasCompletedPlacement = true
        model.data.progressByWordID["import-1"] = .fresh(for: "import-1")
        model.data.sessions = [summary]

        model.resetToBundledWordBank()

        #expect(model.data.activeWordBankMode == .bundled)
        #expect(model.data.importedLibrary?.name == "Imported PET Word Bank")
        #expect(model.data.sessions.count == 1)
        #expect(model.wordBankSnapshot.isImportedActive == false)
        #expect(model.wordBankSnapshot.hasSavedImport == true)
        #expect((try store.loadImportedWords())?.count == 1)
    }

    @MainActor
    @Test func activateSavedImportedWordBankRestoresCachedImportWithoutReimporting() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = tempDirectory.appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let store = LocalStore(url: storeURL)
        let importedWords = [
            VocabularyWord(id: "import-1", english: "director", primaryChinese: "导演", topic: .people)
        ]
        try store.saveImportedWords(importedWords)

        let model = AppModel(store: store)
        model.words = try SeedWordLoader.loadWords()
        model.data.activeWordBankMode = .bundled
        model.data.importedLibrary = WordLibraryMetadata(
            name: "Saved Quest Bank",
            sourceFilename: "saved.json",
            importedAt: .now,
            wordCount: importedWords.count,
            source: .questJSON
        )
        model.data.questPages = [QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: [])]

        model.activateSavedImportedWordBank()

        #expect(model.data.activeWordBankMode == .imported)
        #expect(model.words == importedWords)
        #expect(model.currentQuestPage?.pageNumber == 14)
        #expect(model.wordBankSnapshot.isImportedActive == true)
    }

    @MainActor
    @Test func bootstrapUsesBundledWordsWhileKeepingSavedImportCache() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = tempDirectory.appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let store = LocalStore(url: storeURL)
        let importedWords = [
            VocabularyWord(id: "import-1", english: "director", primaryChinese: "导演", topic: .people)
        ]
        try store.saveImportedWords(importedWords)

        var data = AppStoreData()
        data.activeWordBankMode = .bundled
        data.importedLibrary = WordLibraryMetadata(
            name: "Saved Quest Bank",
            sourceFilename: "saved.json",
            importedAt: .now,
            wordCount: importedWords.count,
            source: .questJSON
        )
        data.questPages = [QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: [])]
        try store.save(data)

        let model = AppModel(store: store)
        model.bootstrap()

        #expect(model.data.activeWordBankMode == .bundled)
        #expect(model.wordBankSnapshot.isImportedActive == false)
        #expect(model.wordBankSnapshot.hasSavedImport == true)
        #expect(model.words.contains(where: { $0.id == "import-1" }) == false)
    }

    @MainActor
    @Test func appModelReadingImportPreservesExistingWordProgress() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("reading-page-1.txt")
        let storeURL = tempDirectory.appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Self.sampleReadingQuestText(title: "PET全_Page_1_03261327", includeAnswers: false)
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let model = AppModel(store: LocalStore(url: storeURL))
        model.words = [
            VocabularyWord(id: "w1", english: "borrow", primaryChinese: "借入", topic: .school)
        ]
        model.data.hasCompletedPlacement = true
        model.data.progressByWordID["w1"] = WordProgress(
            wordID: "w1",
            currentCorrectStreak: 2,
            totalCorrect: 2,
            totalIncorrect: 1,
            isMastered: false,
            lastSeenAt: .now,
            lastIncorrectAt: .now,
            reviewPriority: 2,
            reviewStep: 1,
            nextReviewAt: .now.addingTimeInterval(3_600)
        )

        model.handleReadingImportSelection(.success([fileURL]))

        let deadline = Date().addingTimeInterval(5)
        while model.isImportingReadingPack && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(!model.isImportingReadingPack)
        #expect(model.words.map(\.english) == ["borrow"])
        #expect(model.data.hasCompletedPlacement)
        #expect(model.data.progressByWordID["w1"]?.currentCorrectStreak == 2)
        #expect(model.data.readingLibrary?.articleCount == 1)
        #expect(model.data.readingQuests.count == 1)
        #expect(model.screen == .reading)
    }

    @MainActor
    @Test func appModelWarnsBeforeReplacingImportedWordBankAfterFileSelection() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = url.appendingPathComponent("replacement.csv")

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try (0..<120)
            .map { "word\($0),词\($0)" }
            .joined(separator: "\n")
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let model = AppModel(store: LocalStore(url: url.appendingPathComponent("store.json")))
        model.data.importedLibrary = WordLibraryMetadata(
            name: "PET全",
            sourceFilename: "PET全.pdf",
            importedAt: .now,
            wordCount: 2_925,
            source: .pdf
        )

        model.handleVocabularyImportSelection(.success(fileURL))

        #expect(model.isShowingReimportConfirmation)
        #expect(model.pendingVocabularyImportURL == fileURL)

        model.dismissPendingVocabularyReplacement()

        #expect(!model.isShowingReimportConfirmation)
        #expect(model.pendingVocabularyImportURL == nil)
    }

    @MainActor
    @Test func appModelRequestsImportPanelForFreshImports() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")
        var didPresentImportPanel = false

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let model = AppModel(
            store: LocalStore(url: url),
            presentImportPanel: { _, _ in
                didPresentImportPanel = true
            }
        )

        model.requestBaseImport()

        #expect(didPresentImportPanel)
        #expect(!model.isShowingReimportConfirmation)
    }

    @MainActor
    @Test func appModelRequestsQuestImportPanelSeparately() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")
        var capturedIntent: AppModel.VocabularyImportIntent?

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let model = AppModel(
            store: LocalStore(url: url),
            presentImportPanel: { intent, _ in
                capturedIntent = intent
            }
        )

        model.requestQuestImport()

        #expect(capturedIntent == .questJSON)
    }

    @MainActor
    @Test func appModelMergesQuestOverlayIntoExistingPDFBaseWithoutResettingProgress() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let questURL = tempDirectory.appendingPathComponent("vocab_quests 38.json")
        let storeURL = tempDirectory.appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Self.sampleQuestJSONData().write(to: questURL)

        let store = LocalStore(url: storeURL)
        let baseWords = [
            VocabularyWord(id: "director", english: "director", primaryChinese: "导演", topic: .people),
            VocabularyWord(id: "australia", english: "Australia", primaryChinese: "澳大利亚", topic: .places)
        ]
        try store.saveImportedWords(baseWords)

        let model = AppModel(store: store)
        model.words = baseWords
        model.data.activeWordBankMode = .imported
        model.data.importedLibrary = WordLibraryMetadata(
            name: "PET全",
            sourceFilename: "PET全.pdf",
            importedAt: .now,
            wordCount: baseWords.count,
            source: .pdf
        )
        model.data.wordPages = [
            ImportedWordPage(pageNumber: 37, title: "PET全_Page_37", wordIDs: ["director"], sourceFilename: "PET全.pdf"),
            ImportedWordPage(pageNumber: 38, title: "PET全_Page_38", wordIDs: ["australia"], sourceFilename: "PET全.pdf")
        ]
        model.data.currentQuestPageNumber = 37
        model.data.hasCompletedPlacement = true
        model.data.progressByWordID["director"] = WordProgress(
            wordID: "director",
            currentCorrectStreak: 2,
            totalCorrect: 2,
            totalIncorrect: 1,
            isMastered: false,
            lastSeenAt: .now,
            lastIncorrectAt: .now,
            reviewPriority: 2,
            reviewStep: 1,
            nextReviewAt: .now.addingTimeInterval(3_600)
        )

        model.handleVocabularyImportSelection(.success(questURL))

        let deadline = Date().addingTimeInterval(5)
        while model.isImportingWordBank && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(!model.isImportingWordBank)
        #expect(model.errorMessage == nil)
        #expect(model.isShowingReimportConfirmation == false)
        #expect(model.data.wordPages.map(\.pageNumber) == [37, 38])
        #expect(model.data.questPages.map(\.pageNumber) == [37, 38])
        #expect(model.data.progressByWordID["director"]?.currentCorrectStreak == 2)
        #expect(model.currentQuestPage?.pageNumber == 37)
        #expect(model.currentQuestPage?.isQuestEnhanced == true)
    }

    @Test func placementEstimatorConvertsPlacementScoreIntoVocabularyBand() {
        let estimate = PlacementEstimator.estimate(correctAnswers: 80, totalQuestions: 100)

        #expect(estimate.estimatedVocabularySize == 2_400)
        #expect(estimate.benchmarkVocabularySize == 3_000)
        #expect(estimate.remainingToBenchmark == 600)
        #expect(estimate.placementBand == "PET Strong")
        #expect(estimate.weeklyGoalWords == 70)
    }

    @Test func placementPlannerBuildsNextWeekStudyPlanFromWeakTopics() {
        let plan = PlacementPlanner.plan(
            correctAnswers: 60,
            totalQuestions: 100,
            weakTopics: [.travel, .school]
        )

        #expect(plan.estimate.estimatedVocabularySize == 1_800)
        #expect(plan.focusTopics == [.travel, .school])
        #expect(plan.nextWeekActions.count == 3)
        #expect(plan.nextWeekActions[1].contains("1200"))
        #expect(plan.nextWeekActions[2].contains("travel, school"))
    }

    @Test func placementTopicInsightsSortWeakestTopicsFirst() {
        let attempts = [
            AttemptRecord(sessionID: "s", wordID: "a1", selectedChoice: "错", correctChoice: "对", isCorrect: false, topic: .travel),
            AttemptRecord(sessionID: "s", wordID: "a2", selectedChoice: "错", correctChoice: "对", isCorrect: false, topic: .travel),
            AttemptRecord(sessionID: "s", wordID: "b1", selectedChoice: "对", correctChoice: "对", isCorrect: true, topic: .school),
            AttemptRecord(sessionID: "s", wordID: "b2", selectedChoice: "错", correctChoice: "对", isCorrect: false, topic: .school)
        ]

        let insights = PlacementPlanner.topicInsights(from: attempts)

        #expect(insights.first?.topic == .travel)
        #expect(insights.first?.accuracyPercent == 0)
        #expect(insights.last?.topic == .school)
    }

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

    @MainActor
    @Test func appModelCanAutoAdvanceAfterFeedback() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let model = AppModel(
            store: LocalStore(url: url),
            autoAdvanceDelayMultiplier: 0,
            sleepForNanoseconds: { _ in
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        )
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
        for _ in 0..<20 where model.answerFeedback != nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(model.answerFeedback == nil)
        #expect(model.currentQuestionWord?.id == "w2")
        #expect(model.currentQuestionNumber == 2)
    }

    @MainActor
    @Test func appModelDoesNotAutoAdvanceAfterFinalTranslationFeedback() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let model = AppModel(
            store: LocalStore(url: url),
            autoAdvanceDelayMultiplier: 0,
            sleepForNanoseconds: { _ in
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        )
        model.words = [
            VocabularyWord(id: "w1", english: "director", primaryChinese: "导演", topic: .people),
            VocabularyWord(id: "w2", english: "teacher", primaryChinese: "老师", topic: .school),
            VocabularyWord(id: "w3", english: "bird", primaryChinese: "小鸟", topic: .people),
            VocabularyWord(id: "w4", english: "desk", primaryChinese: "书桌", topic: .school)
        ]
        model.data.progressByWordID["w1"] = .fresh(for: "w1")
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(
                    wordID: "w1",
                    choices: ["导演", "老师", "小鸟", "书桌"],
                    style: .wordExercise,
                    exampleSentence: "The director told the actors where to stand.",
                    meaningPrompt: "The director told the actors where to stand.",
                    meaningCorrectChoice: "导演",
                    spellingPromptText: "导演: ___",
                    spellingCorrectAnswer: "director",
                    translationPrompt: "导演告诉演员们该站在哪里。",
                    translationChoices: [
                        "The director told the actors where to stand.",
                        "The teacher told the actors where to stand.",
                        "The director asked the actors to dance.",
                        "The actors told the director where to stand."
                    ],
                    translationCorrectChoice: "The director told the actors where to stand."
                )
            ]
        )

        model.submit(choice: "导演")
        model.submitPronunciationRating(.clear)
        model.submitSpelling(answer: "director")
        model.submit(choice: "The director told the actors where to stand.")

        #expect(model.answerFeedback?.requiresManualAdvance == true)

        for _ in 0..<20 where model.answerFeedback != nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(model.answerFeedback != nil)
        #expect(model.currentQuestionWord?.id == "w1")

        model.advanceAfterFeedback()

        #expect(model.answerFeedback == nil)
        #expect(model.currentSession == nil)
        #expect(model.screen == .summary)
    }

    @MainActor
    @Test func appModelKeepsWrongSpellingOnRetryBeforeTranslation() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let model = AppModel(store: LocalStore(url: url))
        model.words = [
            VocabularyWord(id: "w1", english: "director", primaryChinese: "导演", topic: .people)
        ]
        model.data.progressByWordID["w1"] = .fresh(for: "w1")
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(
                    wordID: "w1",
                    choices: ["导演", "老师", "小鸟", "书桌"],
                    style: .wordExercise,
                    exampleSentence: "The director told the actors where to stand.",
                    meaningPrompt: "The director told the actors where to stand.",
                    meaningCorrectChoice: "导演",
                    spellingPromptText: "导演: ___",
                    spellingCorrectAnswer: "director",
                    translationPrompt: "导演告诉演员们该站在哪里。",
                    translationChoices: [
                        "The director told the actors where to stand.",
                        "The teacher told the actors where to stand.",
                        "The director asked the actors to dance.",
                        "The actors told the director where to stand."
                    ],
                    translationCorrectChoice: "The director told the actors where to stand.",
                    memoryTip: "Direct-or: The person who gives direct orders to the actors."
                )
            ]
        )

        #expect(model.currentMemoryTip?.contains("Direct-or") == true)

        model.submit(choice: "导演")
        model.submitPronunciationRating(.clear)
        model.submitSpelling(answer: "dirctor")

        #expect(model.isOnSpellingStep == true)
        #expect(model.isRetryingSpelling == true)
        #expect(model.answerFeedback == nil)

        model.submitSpelling(answer: "director")

        #expect(model.isOnTranslationStep == true)

        model.submit(choice: "The director told the actors where to stand.")

        let feedback = try #require(model.answerFeedback)
        #expect(feedback.isCorrect == true)
        #expect(feedback.spellingWasCorrect == true)
        #expect(feedback.translationWasCorrect == true)
        #expect(feedback.requiresManualAdvance == true)
        #expect(model.data.progressByWordID["w1"]?.retryMissCount == 1)
        #expect(model.data.progressByWordID["w1"]?.nextReviewAt != nil)

        model.advanceAfterFeedback()

        let summary = try #require(model.latestSummary)
        #expect(summary.correctAnswers == 1)
        #expect(summary.reviewWords.isEmpty)
        #expect(model.reviewReminderSnapshot.retryTrackedCount == 1)
    }

    @MainActor
    @Test func appModelResumeNormalizesLegacyPronunciationStepIntoSpellingRetry() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let model = AppModel(store: LocalStore(url: url))
        model.words = [
            VocabularyWord(id: "w1", english: "director", primaryChinese: "导演", topic: .people)
        ]
        model.data.progressByWordID["w1"] = .fresh(for: "w1")
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(
                    wordID: "w1",
                    choices: ["导演", "老师", "小鸟", "书桌"],
                    style: .wordExercise,
                    exampleSentence: "The director told the actors where to stand.",
                    meaningPrompt: "The director told the actors where to stand.",
                    meaningCorrectChoice: "导演",
                    spellingPromptText: "导演: ___",
                    spellingCorrectAnswer: "director",
                    translationPrompt: "导演告诉演员们该站在哪里。",
                    translationChoices: [
                        "The director told the actors where to stand.",
                        "The teacher told the actors where to stand.",
                        "The director asked the actors to dance.",
                        "The actors told the director where to stand."
                    ],
                    translationCorrectChoice: "The director told the actors where to stand."
                )
            ],
            currentExerciseStep: .pronunciation,
            pendingMeaningChoice: "导演",
            pendingMeaningWasCorrect: true,
            pendingSpellingAnswer: "dirctor",
            pendingSpellingWasCorrect: false,
            pendingTranslationChoice: "The director told the actors where to stand.",
            pendingTranslationWasCorrect: true
        )

        model.resumeCurrentSession()

        #expect(model.currentExerciseStep == .spelling)
        #expect(model.isRetryingSpelling == true)
        #expect(model.currentSession?.pendingTranslationChoice == nil)
        #expect(model.currentSession?.pendingTranslationWasCorrect == nil)
    }

    @MainActor
    @Test func appModelCanLeaveQuizAndResumeLater() {
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
        model.screen = .quiz

        model.leaveQuiz()

        #expect(model.screen == .onboarding)
        #expect(model.currentSession?.mode == .mission)
        #expect(model.currentQuestionWord?.id == "w1")

        model.resumeCurrentSession()

        #expect(model.screen == .quiz)
        #expect(model.currentQuestionWord?.id == "w1")
    }

    @MainActor
    @Test func appModelLeavingQuizAfterAnswerMovesToNextQuestionOnResume() {
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
        model.screen = .quiz

        model.submit(choice: "借入")
        #expect(model.answerFeedback?.isCorrect == true)

        model.leaveQuiz()

        #expect(model.answerFeedback == nil)
        #expect(model.screen == .onboarding)
        #expect(model.currentQuestionWord?.id == "w2")

        model.resumeCurrentSession()
        #expect(model.screen == .quiz)
        #expect(model.currentQuestionWord?.id == "w2")
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
        #expect(progress.reviewStep == 0)
        #expect(progress.nextReviewAt != nil)
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

    @Test func missionPlannerPrioritizesDueReviewWordsInDailyPlan() {
        let dueWords = (0..<5).map {
            VocabularyWord(id: "due-\($0)", english: "due\($0)", primaryChinese: "到期\($0)", topic: .school)
        }
        let freshWords = (0..<45).map {
            VocabularyWord(id: "fresh-\($0)", english: "fresh\($0)", primaryChinese: "新词\($0)", topic: .travel)
        }
        let words = dueWords + freshWords

        var data = AppStoreData()
        dueWords.forEach { word in
            data.progressByWordID[word.id] = WordProgress(
                wordID: word.id,
                currentCorrectStreak: 0,
                totalCorrect: 0,
                totalIncorrect: 1,
                isMastered: false,
                lastSeenAt: .now,
                lastIncorrectAt: .now,
                reviewPriority: 2,
                reviewStep: 0,
                nextReviewAt: .now.addingTimeInterval(-60)
            )
        }
        freshWords.forEach { data.progressByWordID[$0.id] = .fresh(for: $0.id) }

        let questions = SessionPlanner.missionQuestions(words: words, data: data, count: 10)

        #expect(questions.count == 10)
        #expect(Set(questions.prefix(5).map(\.wordID)) == Set(dueWords.map(\.id)))
    }

    @Test func missionPlannerUsesPreferredTopicsForNonFailedWords() {
        let words = [
            VocabularyWord(id: "travel-1", english: "airport", primaryChinese: "机场", topic: .travel),
            VocabularyWord(id: "travel-2", english: "hotel", primaryChinese: "酒店", topic: .travel),
            VocabularyWord(id: "school-1", english: "teacher", primaryChinese: "老师", topic: .school),
            VocabularyWord(id: "school-2", english: "lesson", primaryChinese: "课程", topic: .school),
            VocabularyWord(id: "food-1", english: "bread", primaryChinese: "面包", topic: .food)
        ]
        var data = AppStoreData()
        words.forEach { data.progressByWordID[$0.id] = .fresh(for: $0.id) }

        let questions = SessionPlanner.missionQuestions(
            words: words,
            data: data,
            count: 3,
            preferredTopics: [.travel]
        )

        #expect(questions.count == 3)
        #expect(questions.prefix(2).allSatisfy { ["travel-1", "travel-2"].contains($0.wordID) })
    }

    @Test func missionPlannerBuildsWordExercisesWithSentenceClues() throws {
        let words = [
            VocabularyWord(id: "school-1", english: "borrow", primaryChinese: "借入", topic: .school),
            VocabularyWord(id: "travel-1", english: "ticket", primaryChinese: "票", topic: .travel),
            VocabularyWord(id: "food-1", english: "bread", primaryChinese: "面包", topic: .food),
            VocabularyWord(id: "places-1", english: "cinema", primaryChinese: "电影院", topic: .places)
        ]
        var data = AppStoreData()
        words.forEach { data.progressByWordID[$0.id] = .fresh(for: $0.id) }

        let questions = SessionPlanner.missionQuestions(words: words, data: data, count: 3)

        #expect(questions.count == 3)
        #expect(questions.allSatisfy { $0.style == .wordExercise })

        for question in questions {
            let word = try #require(words.first { $0.id == question.wordID })
            #expect(question.exampleSentence?.contains(word.english) == true)
            #expect(question.spellingPrompt(for: word)?.contains("____") == true)
        }
    }

    @Test func exampleSentenceGeneratorUsesNaturalCueForProperNouns() {
        let word = VocabularyWord(id: "places-2", english: "Africa", primaryChinese: "非洲", topic: .health)

        let sentence = ExampleSentenceGenerator.sentence(for: word)

        #expect(sentence == "They read a short article about Africa in class today.")
    }

    @MainActor
    @Test func appModelDailyWordExerciseOnlyGradesAfterSpellingStep() {
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
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(
                    wordID: "w1",
                    choices: ["借入", "老师", "电影院", "票"],
                    style: .wordExercise,
                    exampleSentence: "In class today, we practised the word borrow together."
                )
            ]
        )

        model.submit(choice: "借入")

        #expect(model.currentExerciseStep == .pronunciation)
        #expect(model.currentSession?.attempts.isEmpty == true)
        #expect(model.currentSession?.correctAnswers == 0)
        #expect(model.answerFeedback == nil)

        model.submitPronunciationRating(.clear)

        #expect(model.currentExerciseStep == .spelling)

        model.submitSpelling(answer: "borrow")

        #expect(model.currentSession?.attempts.count == 1)
        #expect(model.currentSession?.correctAnswers == 1)
        #expect(model.answerFeedback?.isCorrect == true)
        #expect(model.answerFeedback?.meaningWasCorrect == true)
        #expect(model.answerFeedback?.spellingWasCorrect == true)
        #expect(model.data.progressByWordID["w1"]?.currentCorrectStreak == 1)
        #expect(model.data.progressByWordID["w1"]?.totalIncorrect == 0)
    }

    @MainActor
    @Test func appModelDailyWordExerciseAllowsInlineSpellingRetryBeforeGrading() {
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
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(
                    wordID: "w1",
                    choices: ["借入", "老师", "电影院", "票"],
                    style: .wordExercise,
                    exampleSentence: "In class today, we practised the word borrow together."
                )
            ]
        )

        model.submit(choice: "借入")
        model.submitPronunciationRating(.clear)
        model.submitSpelling(answer: "borow")

        #expect(model.isOnSpellingStep == true)
        #expect(model.isRetryingSpelling == true)
        #expect(model.currentSession?.attempts.isEmpty == true)
        #expect(model.answerFeedback == nil)
        #expect(model.data.progressByWordID["w1"]?.retryMissCount == 1)
        #expect(model.data.progressByWordID["w1"]?.nextReviewAt != nil)

        model.submitSpelling(answer: "borrow")

        #expect(model.currentSession?.attempts.count == 1)
        #expect(model.currentSession?.correctAnswers == 1)
        #expect(model.answerFeedback?.isCorrect == true)
        #expect(model.answerFeedback?.spellingWasCorrect == true)
        #expect(model.data.progressByWordID["w1"]?.totalIncorrect == 0)
        #expect(model.data.progressByWordID["w1"]?.retryMissCount == 1)
        #expect(model.reviewReminderSnapshot.retryTrackedCount == 1)
    }

    @MainActor
    @Test func appModelAcceptsOptionalParentheticalLettersInSpellingAnswers() {
        func makeModel() -> AppModel {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("store.json")
            let model = AppModel(store: LocalStore(url: url))
            model.words = [
                VocabularyWord(id: "w1", english: "blond(e)", primaryChinese: "金发的", topic: .people),
                VocabularyWord(id: "w2", english: "teacher", primaryChinese: "老师", topic: .school),
                VocabularyWord(id: "w3", english: "cinema", primaryChinese: "电影院", topic: .places),
                VocabularyWord(id: "w4", english: "ticket", primaryChinese: "票", topic: .transport)
            ]
            model.data.progressByWordID["w1"] = .fresh(for: "w1")
            model.data.activeSession = ActiveSession(
                mode: .mission,
                questions: [
                    PersistedQuestion(
                        wordID: "w1",
                        choices: ["金发的", "老师", "电影院", "票"],
                        style: .wordExercise,
                        exampleSentence: "The blond girl smiled.",
                        meaningPrompt: "The blond girl smiled.",
                        meaningCorrectChoice: "金发的",
                        spellingPromptText: "金发的: ___",
                        spellingCorrectAnswer: "blond(e)"
                    )
                ]
            )
            return model
        }

        let blondModel = makeModel()
        blondModel.submit(choice: "金发的")
        blondModel.submitPronunciationRating(.clear)
        blondModel.submitSpelling(answer: "Blond")

        #expect(blondModel.answerFeedback?.spellingWasCorrect == true)
        #expect(blondModel.answerFeedback?.isCorrect == true)
        #expect(blondModel.data.progressByWordID["w1"]?.retryMissCount == 0)

        let blondeModel = makeModel()
        blondeModel.submit(choice: "金发的")
        blondeModel.submitPronunciationRating(.clear)
        blondeModel.submitSpelling(answer: "blonde")

        #expect(blondeModel.answerFeedback?.spellingWasCorrect == true)
        #expect(blondeModel.answerFeedback?.isCorrect == true)
        #expect(blondeModel.data.progressByWordID["w1"]?.retryMissCount == 0)
    }

    @MainActor
    @Test func appModelQuestWordExerciseOnlyGradesAfterTranslationStep() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let model = AppModel(store: LocalStore(url: url))
        model.words = [
            VocabularyWord(id: "w1", english: "director", primaryChinese: "导演", topic: .people),
            VocabularyWord(id: "w2", english: "teacher", primaryChinese: "老师", topic: .school),
            VocabularyWord(id: "w3", english: "desk", primaryChinese: "书桌", topic: .school),
            VocabularyWord(id: "w4", english: "bird", primaryChinese: "小鸟", topic: .places)
        ]
        model.data.progressByWordID["w1"] = .fresh(for: "w1")
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(
                    wordID: "w1",
                    choices: ["书桌", "导演", "老师", "小鸟"],
                    style: .wordExercise,
                    exampleSentence: "The director told the actors where to stand.",
                    meaningPrompt: "The director told the actors where to stand.",
                    meaningCorrectChoice: "导演",
                    spellingPromptText: "导演: ___",
                    spellingCorrectAnswer: "director",
                    translationPrompt: "导演告诉演员们该站在哪里。",
                    translationChoices: [
                        "The director told the actors where to stand.",
                        "The teacher told the actors where to stand.",
                        "The director asked the actors to dance.",
                        "The actors told the director where to stand."
                    ],
                    translationCorrectChoice: "The director told the actors where to stand.",
                    memoryTip: "Direct-or: The person who gives direct orders to the actors!",
                    exampleTranslation: "导演告诉演员们该站在哪里。",
                    sourcePageNumber: 37,
                    sourcePageTitle: "PET全_Page_37_03261514"
                )
            ]
        )

        model.submit(choice: "导演")

        #expect(model.currentExerciseStep == .pronunciation)
        #expect(model.currentSession?.attempts.isEmpty == true)
        #expect(model.currentSession?.correctAnswers == 0)
        #expect(model.answerFeedback == nil)

        model.submitPronunciationRating(.clear)

        #expect(model.currentExerciseStep == .spelling)

        model.submitSpelling(answer: "director")

        #expect(model.currentExerciseStep == .translation)
        #expect(model.currentQuestionChoices.count == 4)
        #expect(model.currentSession?.attempts.isEmpty == true)
        #expect(model.currentSession?.correctAnswers == 0)
        #expect(model.answerFeedback == nil)

        model.submit(choice: "The director told the actors where to stand.")

        #expect(model.currentSession?.attempts.count == 1)
        #expect(model.currentSession?.correctAnswers == 1)
        #expect(model.answerFeedback?.isCorrect == true)
        #expect(model.answerFeedback?.meaningWasCorrect == true)
        #expect(model.answerFeedback?.spellingWasCorrect == true)
        #expect(model.answerFeedback?.translationWasCorrect == true)
        #expect(model.answerFeedback?.correctTranslation == "The director told the actors where to stand.")
        #expect(model.answerFeedback?.revealedTranslation == "导演告诉演员们该站在哪里。")
        #expect(model.answerFeedback?.memoryTip?.contains("direct orders") == true)
        #expect(model.data.progressByWordID["w1"]?.currentCorrectStreak == 1)
    }

    @MainActor
    @Test func wordExerciseMovesFromMeaningToPronunciationBeforeSpelling() {
        let model = AppModel(store: Self.isolatedStore())
        model.words = [
            VocabularyWord(id: "w1", english: "director", primaryChinese: "导演", topic: .people)
        ]
        model.data.progressByWordID["w1"] = .fresh(for: "w1")
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(
                    wordID: "w1",
                    choices: ["导演", "老师", "小鸟", "书桌"],
                    style: .wordExercise,
                    exampleSentence: "The director told the actors where to stand.",
                    meaningPrompt: "The director told the actors where to stand.",
                    meaningCorrectChoice: "导演",
                    spellingPromptText: "导演: ___",
                    spellingCorrectAnswer: "director",
                    translationPrompt: "导演告诉演员们该站在哪里。",
                    translationChoices: [
                        "The director told the actors where to stand.",
                        "The teacher told the actors where to stand.",
                        "The director asked the actors to dance.",
                        "The actors told the director where to stand."
                    ],
                    translationCorrectChoice: "The director told the actors where to stand."
                )
            ]
        )

        model.submit(choice: "导演")

        #expect(model.isOnPronunciationStep == true)
        #expect(model.currentExerciseStep == .pronunciation)
        #expect(model.currentSession?.attempts.isEmpty == true)
        #expect(model.currentSession?.correctAnswers == 0)
        #expect(model.answerFeedback == nil)
    }

    @MainActor
    @Test func weakPronunciationSelfCheckAdvancesToSpellingAndSchedulesReview() {
        let model = AppModel(store: Self.isolatedStore())
        model.words = [
            VocabularyWord(id: "w1", english: "director", primaryChinese: "导演", topic: .people)
        ]
        model.data.progressByWordID["w1"] = .fresh(for: "w1")
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(
                    wordID: "w1",
                    choices: ["导演", "老师", "小鸟", "书桌"],
                    style: .wordExercise,
                    exampleSentence: "The director told the actors where to stand.",
                    meaningPrompt: "The director told the actors where to stand.",
                    meaningCorrectChoice: "导演",
                    spellingPromptText: "导演: ___",
                    spellingCorrectAnswer: "director"
                )
            ]
        )

        model.submit(choice: "导演")
        model.submitPronunciationRating(.needsPractice)

        #expect(model.isOnSpellingStep == true)
        #expect(model.currentSession?.attempts.isEmpty == true)
        #expect(model.answerFeedback == nil)
        #expect(model.data.progressByWordID["w1"]?.retryMissCount == 1)
        #expect(model.data.progressByWordID["w1"]?.nextReviewAt != nil)
    }

    @MainActor
    @Test func pronunciationSelfCheckIsCarriedIntoFinalFeedback() {
        let model = AppModel(store: Self.isolatedStore())
        model.words = [
            VocabularyWord(id: "w1", english: "director", primaryChinese: "导演", topic: .people)
        ]
        model.data.progressByWordID["w1"] = .fresh(for: "w1")
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(
                    wordID: "w1",
                    choices: ["导演", "老师", "小鸟", "书桌"],
                    style: .wordExercise,
                    exampleSentence: "The director told the actors where to stand.",
                    meaningPrompt: "The director told the actors where to stand.",
                    meaningCorrectChoice: "导演",
                    spellingPromptText: "导演: ___",
                    spellingCorrectAnswer: "director",
                    translationPrompt: "导演告诉演员们该站在哪里。",
                    translationChoices: [
                        "The director told the actors where to stand.",
                        "The teacher told the actors where to stand.",
                        "The director asked the actors to dance.",
                        "The actors told the director where to stand."
                    ],
                    translationCorrectChoice: "The director told the actors where to stand."
                )
            ]
        )

        model.submit(choice: "导演")
        model.submitPronunciationRating(.needsPractice)
        model.submitSpelling(answer: "director")
        model.submit(choice: "The director told the actors where to stand.")

        #expect(model.answerFeedback?.isCorrect == true)
        #expect(model.answerFeedback?.pronunciationRating == .needsPractice)
        #expect(model.answerFeedback?.detail.contains("pronunciation") == true)
        #expect(model.data.progressByWordID["w1"]?.retryMissCount == 1)
    }

    @MainActor
    @Test func appModelDailyWordExerciseFailsWhenMeaningOrSpellingIsWrong() {
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
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(
                    wordID: "w1",
                    choices: ["借入", "老师", "电影院", "票"],
                    style: .wordExercise,
                    exampleSentence: "In class today, we practised the word borrow together."
                )
            ]
        )

        model.submit(choice: "老师")
        model.submitPronunciationRating(.clear)
        model.submitSpelling(answer: "borrow")

        #expect(model.currentSession?.attempts.count == 1)
        #expect(model.currentSession?.correctAnswers == 0)
        #expect(model.answerFeedback?.isCorrect == false)
        #expect(model.answerFeedback?.meaningWasCorrect == false)
        #expect(model.answerFeedback?.spellingWasCorrect == true)
        #expect(model.data.progressByWordID["w1"]?.totalIncorrect == 1)
        #expect(model.data.progressByWordID["w1"]?.nextReviewAt != nil)
    }

    @MainActor
    @Test func appModelQuestMissionKeepsCurrentPageAndPromotesReadingAfterWordCompletion() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let model = AppModel(store: LocalStore(url: url))
        model.words = [
            VocabularyWord(id: "w1", english: "director", primaryChinese: "导演", topic: .people),
            VocabularyWord(id: "w2", english: "Australia", primaryChinese: "澳大利亚", topic: .travel),
            VocabularyWord(id: "w3", english: "teacher", primaryChinese: "老师", topic: .school),
            VocabularyWord(id: "w4", english: "desk", primaryChinese: "书桌", topic: .school),
            VocabularyWord(id: "w5", english: "bird", primaryChinese: "小鸟", topic: .places)
        ]
        model.data.activeWordBankMode = .imported
        model.words.forEach { model.data.progressByWordID[$0.id] = .fresh(for: $0.id) }
        model.data.questPages = [
            QuestPage(
                pageNumber: 37,
                title: "PET全_Page_37_03261514",
                questions: [
                    PersistedQuestion(
                        wordID: "w1",
                        choices: ["书桌", "导演", "老师", "小鸟"],
                        style: .wordExercise,
                        exampleSentence: "The director told the actors where to stand.",
                        meaningPrompt: "The director told the actors where to stand.",
                        meaningCorrectChoice: "导演",
                        spellingPromptText: "导演: ___",
                        spellingCorrectAnswer: "director",
                        translationPrompt: "导演告诉演员们该站在哪里。",
                        translationChoices: [
                            "The director told the actors where to stand.",
                            "The teacher told the actors where to stand.",
                            "The director asked the actors to dance.",
                            "The actors told the director where to stand."
                        ],
                        translationCorrectChoice: "The director told the actors where to stand.",
                        memoryTip: "Direct-or: The person who gives direct orders to the actors!",
                        exampleTranslation: "导演告诉演员们该站在哪里。",
                        sourcePageNumber: 37,
                        sourcePageTitle: "PET全_Page_37_03261514"
                    )
                ]
            ),
            QuestPage(
                pageNumber: 38,
                title: "PET全_Page_38_03261514",
                questions: [
                    PersistedQuestion(
                        wordID: "w2",
                        choices: ["澳大利亚", "导演", "老师", "小鸟"],
                        style: .wordExercise,
                        exampleSentence: "Kangaroos are found in the wild in Australia.",
                        meaningPrompt: "Kangaroos are found in the wild in Australia.",
                        meaningCorrectChoice: "澳大利亚",
                        spellingPromptText: "澳大利亚: ___",
                        spellingCorrectAnswer: "Australia",
                        translationPrompt: "袋鼠生活在澳大利亚的荒野中。",
                        translationChoices: [
                            "Kangaroos are found in the wild in Australia.",
                            "Kangaroos live near the school in Australia.",
                            "Australia is full of wild birds.",
                            "I saw a kangaroo in the park."
                        ],
                        translationCorrectChoice: "Kangaroos are found in the wild in Australia.",
                        memoryTip: "Imagine a giant ORANGE map of Australia.",
                        exampleTranslation: "袋鼠生活在澳大利亚的荒野中。",
                        sourcePageNumber: 38,
                        sourcePageTitle: "PET全_Page_38_03261514"
                    )
                ]
            )
        ]
        model.data.currentQuestPageNumber = 37

        model.startMission()

        #expect(model.currentSession?.questPageNumber == 37)
        #expect(model.currentQuestionWord?.english == "director")

        model.submit(choice: "导演")
        model.submitPronunciationRating(.clear)
        model.submitSpelling(answer: "director")
        model.submit(choice: "The director told the actors where to stand.")

        #expect(model.answerFeedback?.isCorrect == true)

        model.advanceAfterFeedback()

        #expect(model.screen == .summary)
        #expect(model.latestSummary?.questPageNumber == 37)
        #expect(model.data.completedQuestPages == [37])
        #expect(model.data.currentQuestPageNumber == 37)
        #expect(model.currentQuestPage?.pageNumber == 37)
        #expect(model.currentUnitSnapshot.stageBadgeText == "STEP 2 OF 2")
        #expect(model.currentUnitSnapshot.primaryAction == .openReadingHub)
        #expect(model.currentUnitSnapshot.primaryActionTitle == "OPEN READING HUB")
    }

    @MainActor
    @Test func appModelSelectQuestPageUpdatesAndPersistsCurrentLaunchTarget() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let model = AppModel(store: LocalStore(url: url))
        model.data.activeWordBankMode = .imported
        model.data.questPages = [
            QuestPage(pageNumber: 13, title: "PET全_Page_13", questions: []),
            QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: []),
            QuestPage(pageNumber: 15, title: "PET全_Page_15", questions: [])
        ]
        model.data.currentQuestPageNumber = 13
        model.data.completedQuestPages = [13]

        model.selectQuestPage(14)

        #expect(model.data.currentQuestPageNumber == 14)
        #expect(model.currentQuestPage?.pageNumber == 14)
        #expect(model.data.completedQuestPages == [13])

        let loaded = try LocalStore(url: url).load()
        #expect(loaded.currentQuestPageNumber == 14)
        #expect(loaded.completedQuestPages == [13])
    }

    @MainActor
    @Test func selectingNewQuestPageClearsPausedMissionFromAnotherPage() {
        let model = AppModel(store: Self.isolatedStore())
        model.data.activeWordBankMode = .imported
        model.data.questPages = [
            QuestPage(pageNumber: 13, title: "PET全_Page_13", questions: []),
            QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: [])
        ]
        model.data.currentQuestPageNumber = 13
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questPageNumber: 13,
            questPageTitle: "PET全_Page_13",
            questions: [
                PersistedQuestion(wordID: "w1", choices: ["A", "B", "C", "D"])
            ]
        )

        model.selectQuestPage(14)

        #expect(model.data.currentQuestPageNumber == 14)
        #expect(model.currentQuestPage?.pageNumber == 14)
        #expect(model.data.activeSession == nil)
        #expect(model.currentUnitSnapshot.primaryActionTitle == "START WORD QUEST")
    }

    @MainActor
    @Test func questCompletionAutoStartsReadingWhenCurrentPageReadingIsReady() {
        let model = AppModel(store: Self.isolatedStore())
        model.words = [
            VocabularyWord(id: "w1", english: "director", primaryChinese: "导演", topic: .people)
        ]
        model.data.activeWordBankMode = .imported
        model.data.progressByWordID["w1"] = .fresh(for: "w1")
        model.data.questPages = [
            QuestPage(
                pageNumber: 14,
                title: "PET全_Page_14",
                questions: [
                    PersistedQuestion(
                        wordID: "w1",
                        choices: ["导演", "老师", "书桌", "小鸟"],
                        style: .wordExercise,
                        exampleSentence: "The director told the actors where to stand.",
                        meaningPrompt: "The director told the actors where to stand.",
                        meaningCorrectChoice: "导演",
                        spellingPromptText: "导演: ___",
                        spellingCorrectAnswer: "director",
                        translationPrompt: "导演告诉演员们该站在哪里。",
                        translationChoices: [
                            "The director told the actors where to stand.",
                            "The teacher told the actors where to stand.",
                            "The director asked the actors to dance.",
                            "The actors told the director where to stand."
                        ],
                        translationCorrectChoice: "The director told the actors where to stand."
                    )
                ]
            )
        ]
        model.data.currentQuestPageNumber = 14
        model.data.readingLibrary = ReadingLibraryMetadata(name: "PET Reading", importedAt: .now, articleCount: 1)
        model.data.readingQuests = [
            ReadingQuest(
                id: "reading-14",
                title: "PET全_Page_14",
                pageNumber: 14,
                passage: "The director shouted action to start the movie.",
                questions: [
                    ReadingQuestQuestion(
                        number: 1,
                        prompt: "Who shouted action?",
                        choices: [
                            ReadingQuestChoice(letter: "A", text: "The teacher"),
                            ReadingQuestChoice(letter: "B", text: "The director"),
                            ReadingQuestChoice(letter: "C", text: "The student"),
                            ReadingQuestChoice(letter: "D", text: "The bird")
                        ],
                        correctChoiceLetter: "B"
                    )
                ],
                sourceFilename: "page14.txt"
            )
        ]

        model.startMission()
        model.submit(choice: "导演")
        model.submitPronunciationRating(.clear)
        model.submitSpelling(answer: "director")
        model.submit(choice: "The director told the actors where to stand.")
        model.advanceAfterFeedback()

        #expect(model.screen == .readingQuiz)
        #expect(model.latestSummary?.mode == .mission)
        #expect(model.activeReadingSession?.pageNumber == 14)
        #expect(model.currentUnitSnapshot.primaryAction == .startReadingQuest)

        model.advanceReadingQuestionPreview()
        model.startReadingQuestions()
        model.submitReadingChoice(letter: "B")

        #expect(model.readingAnswerFeedback?.isCorrect == true)

        model.advanceReadingAfterFeedback()

        #expect(model.screen == .summary)
        #expect(model.latestSummary?.mode == .readingQuest)
        #expect(model.data.completedReadingQuestPages == [14])
    }

    @MainActor
    @Test func appModelSelectQuestPageIgnoresMissingImportedPage() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let model = AppModel(store: LocalStore(url: url))
        model.data.activeWordBankMode = .imported
        model.data.questPages = [
            QuestPage(pageNumber: 13, title: "PET全_Page_13", questions: []),
            QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: [])
        ]
        model.data.currentQuestPageNumber = 13
        model.data.completedQuestPages = [13]

        model.selectQuestPage(66)

        #expect(model.data.currentQuestPageNumber == 13)
        #expect(model.currentQuestPage?.pageNumber == 13)
        #expect(model.data.completedQuestPages == [13])
    }

    @MainActor
    @Test func currentUnitSnapshotShowsBaseReadyWhenOnlyPETBasePageExists() {
        let model = AppModel(store: Self.isolatedStore())
        model.data.activeWordBankMode = .imported
        model.data.wordPages = [
            ImportedWordPage(pageNumber: 14, title: "PET全_Page_14", wordIDs: ["director"], sourceFilename: "PET全.pdf")
        ]
        model.data.currentQuestPageNumber = 14

        let snapshot = model.currentUnitSnapshot

        #expect(snapshot.layerSnapshots.map(\.valueText) == ["Base Ready", "Quest Pending", "Reading Waiting"])
        #expect(snapshot.layerSnapshots.map(\.title) == ["Base Layer", "Quest Layer", "Reading Layer"])
        #expect(snapshot.targetCaption == "Words waiting in this PET base page")
        #expect(snapshot.primaryActionTitle == "START WORD QUEST")
    }

    @MainActor
    @Test func homeMissionSnapshotBuildsHorizontalMainlineFromCurrentPage() {
        let model = AppModel(store: Self.isolatedStore())
        model.data.activeWordBankMode = .imported
        model.data.importedLibrary = WordLibraryMetadata(
            name: "PET全",
            sourceFilename: "PET全.pdf",
            importedAt: .now,
            wordCount: 90,
            source: .pdf
        )
        model.data.wordPages = [
            ImportedWordPage(pageNumber: 14, title: "PET全_Page_14", wordIDs: ["director"], sourceFilename: "PET全.pdf")
        ]
        model.data.questPages = [
            QuestPage(
                pageNumber: 14,
                title: "PET全_Page_14",
                questions: [
                    PersistedQuestion(wordID: "review-0", choices: ["词0", "词1", "词2", "词3"], style: .wordExercise)
                ]
            )
        ]
        model.data.currentQuestPageNumber = 14
        model.data.readingLibrary = ReadingLibraryMetadata(name: "PET Reading", importedAt: .now, articleCount: 66)
        model.data.readingQuests = [
            ReadingQuest(
                id: "reading-14",
                title: "PET全_Page_14",
                pageNumber: 14,
                passage: "The director shouted action to start the movie.",
                questions: [
                    ReadingQuestQuestion(
                        number: 1,
                        prompt: "Who shouted action?",
                        choices: [
                            ReadingQuestChoice(letter: "A", text: "The teacher"),
                            ReadingQuestChoice(letter: "B", text: "The director"),
                            ReadingQuestChoice(letter: "C", text: "The student"),
                            ReadingQuestChoice(letter: "D", text: "The bird")
                        ],
                        correctChoiceLetter: "B"
                    )
                ],
                sourceFilename: "page14.txt"
            )
        ]

        let snapshot = model.homeMissionSnapshot

        #expect(snapshot.currentPageLabel == "P14")
        #expect(snapshot.steps.map(\.kind) == [.todayPage, .quest, .reading, .reminder, .trophies])
        #expect(snapshot.steps[0].title == "Choose Today's Page")
        #expect(snapshot.steps[1].title == "45-Word Quest")
        #expect(snapshot.steps[2].title == "Reading Mission")
        #expect(snapshot.steps[3].title == "Reminder")
        #expect(snapshot.steps[4].title == "Trophies")
        #expect(snapshot.benchmarkTitle == "Benchmark Test")
        #expect(snapshot.importActionTitle == "MANAGE RESOURCES")
        #expect(snapshot.resources.map(\.title) == ["Base", "Quest", "Reading"])
        #expect(snapshot.resources.map(\.valueText) == ["1", "1", "66"])
    }

    @MainActor
    @Test func homeMissionQuestStepNudgesDueReviewWithoutBlockingDailyQuest() {
        let now = Date(timeIntervalSinceReferenceDate: 300_000)
        let model = AppModel(store: Self.isolatedStore())
        model.words = (0..<8).map { index in
            VocabularyWord(
                id: "review-\(index)",
                english: "word\(index)",
                primaryChinese: "词\(index)",
                topic: .school
            )
        }
        model.data.activeWordBankMode = .imported
        model.data.wordPages = [
            ImportedWordPage(
                pageNumber: 14,
                title: "PET全_Page_14",
                wordIDs: model.words.map(\.id),
                sourceFilename: "PET全.pdf"
            )
        ]
        model.data.questPages = [
            QuestPage(
                pageNumber: 14,
                title: "PET全_Page_14",
                questions: [
                    PersistedQuestion(wordID: "review-0", choices: ["词0", "词1", "词2", "词3"], style: .wordExercise)
                ]
            )
        ]
        model.data.currentQuestPageNumber = 14
        for (index, word) in model.words.enumerated() {
            model.data.progressByWordID[word.id] = WordProgress(
                wordID: word.id,
                currentCorrectStreak: 0,
                totalCorrect: 1,
                totalIncorrect: 2,
                isMastered: false,
                lastSeenAt: now.addingTimeInterval(-3_600),
                lastIncorrectAt: now.addingTimeInterval(-3_600),
                reviewPriority: 8 - index,
                reviewStep: 0,
                nextReviewAt: now.addingTimeInterval(-Double(index + 1) * 60)
            )
        }

        let snapshot = model.homeMissionSnapshot
        let questStep = snapshot.steps[1]

        #expect(model.currentUnitSnapshot.primaryAction == .startMission)
        #expect(questStep.statusText == "MAIN TASK")
        #expect(questStep.detail.contains("Step 4 has 5 due review words"))
        #expect(questStep.actionTitle == "START WORD QUEST")
        #expect(model.homeQuestActionTitle == "START WORD QUEST")

        model.performHomeQuestAction()

        #expect(model.currentSession?.mode == .mission)
    }

    @MainActor
    @Test func homeMissionQuestStepResumesEmptyDailySessionEvenWhenReviewsAreDue() {
        let now = Date(timeIntervalSinceReferenceDate: 300_000)
        let model = AppModel(store: Self.isolatedStore())
        model.words = (0..<6).map { index in
            VocabularyWord(
                id: "empty-review-\(index)",
                english: "word\(index)",
                primaryChinese: "词\(index)",
                topic: .school
            )
        }
        model.data.activeWordBankMode = .imported
        model.data.wordPages = [
            ImportedWordPage(
                pageNumber: 14,
                title: "PET全_Page_14",
                wordIDs: model.words.map(\.id),
                sourceFilename: "PET全.pdf"
            )
        ]
        model.data.questPages = [
            QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: [])
        ]
        model.data.currentQuestPageNumber = 14
        for (index, word) in model.words.enumerated() {
            model.data.progressByWordID[word.id] = WordProgress(
                wordID: word.id,
                currentCorrectStreak: 0,
                totalCorrect: 1,
                totalIncorrect: 2,
                isMastered: false,
                lastSeenAt: now.addingTimeInterval(-3_600),
                lastIncorrectAt: now.addingTimeInterval(-3_600),
                reviewPriority: 6 - index,
                reviewStep: 0,
                nextReviewAt: now.addingTimeInterval(-Double(index + 1) * 60)
            )
        }
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(wordID: "empty-review-0", choices: ["词0", "词1", "词2", "词3"], style: .wordExercise)
            ]
        )

        #expect(model.homeQuestActionTitle == "RESUME DAILY MISSION")

        model.performHomeQuestAction()

        #expect(model.currentSession?.mode == .mission)
    }

    @MainActor
    @Test func homeMissionQuestStepPreservesStartedDailySessionEvenWhenReviewsAreDue() {
        let now = Date(timeIntervalSinceReferenceDate: 300_000)
        let model = AppModel(store: Self.isolatedStore())
        model.words = (0..<6).map { index in
            VocabularyWord(
                id: "started-review-\(index)",
                english: "word\(index)",
                primaryChinese: "词\(index)",
                topic: .school
            )
        }
        model.data.activeWordBankMode = .imported
        model.data.wordPages = [
            ImportedWordPage(
                pageNumber: 14,
                title: "PET全_Page_14",
                wordIDs: model.words.map(\.id),
                sourceFilename: "PET全.pdf"
            )
        ]
        model.data.questPages = [
            QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: [])
        ]
        model.data.currentQuestPageNumber = 14
        for (index, word) in model.words.enumerated() {
            model.data.progressByWordID[word.id] = WordProgress(
                wordID: word.id,
                currentCorrectStreak: 0,
                totalCorrect: 1,
                totalIncorrect: 2,
                isMastered: false,
                lastSeenAt: now.addingTimeInterval(-3_600),
                lastIncorrectAt: now.addingTimeInterval(-3_600),
                reviewPriority: 6 - index,
                reviewStep: 0,
                nextReviewAt: now.addingTimeInterval(-Double(index + 1) * 60)
            )
        }
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(wordID: "started-review-0", choices: ["词0", "词1", "词2", "词3"], style: .wordExercise)
            ],
            currentIndex: 1,
            attempts: [
                AttemptRecord(
                    sessionID: "started-session",
                    wordID: "started-review-0",
                    selectedChoice: "词0",
                    correctChoice: "词0",
                    isCorrect: true,
                    topic: .school
                )
            ]
        )

        #expect(model.homeQuestActionTitle == "RESUME DAILY MISSION")

        model.performHomeQuestAction()

        #expect(model.currentSession?.mode == .mission)
    }

    @MainActor
    @Test func homeMissionSnapshotDoesNotMutateImportedDataHistoryOrReviewProgress() {
        let model = AppModel(store: Self.isolatedStore())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        model.data.activeWordBankMode = .imported
        model.data.importedLibrary = WordLibraryMetadata(
            name: "PET全",
            sourceFilename: "PET全.pdf",
            importedAt: now,
            wordCount: 45,
            source: .pdf
        )
        model.data.wordPages = [
            ImportedWordPage(pageNumber: 14, title: "PET全_Page_14", wordIDs: ["director"], sourceFilename: "PET全.pdf")
        ]
        model.data.questPages = [
            QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: [])
        ]
        model.data.currentQuestPageNumber = 14
        model.data.progressByWordID["director"] = WordProgress(
            wordID: "director",
            currentCorrectStreak: 0,
            totalCorrect: 1,
            totalIncorrect: 2,
            retryMissCount: 1,
            isMastered: false,
            lastSeenAt: now,
            lastIncorrectAt: now,
            lastRetryMissAt: now,
            reviewPriority: 3,
            reviewStep: 1,
            nextReviewAt: now.addingTimeInterval(86_400)
        )
        model.data.sessions = [
            SessionSummary(
                mode: .mission,
                startedAt: now.addingTimeInterval(-600),
                completedAt: now,
                questPageNumber: 14,
                questPageTitle: "PET全_Page_14",
                totalQuestions: 3,
                correctAnswers: 2,
                newlyMasteredCount: 1,
                weakTopics: [.people],
                headline: "Good practice",
                body: "Director needs review.",
                recommendedMissionTitle: "Review weak words",
                reviewWords: [
                    SessionReviewWordSnapshot(
                        english: "director",
                        primaryChinese: "导演",
                        topic: .people,
                        nextReviewAt: now.addingTimeInterval(86_400),
                        reviewStep: 1,
                        retryMissCount: 1,
                        memoryTip: "Direct-or"
                    )
                ]
            )
        ]

        let before = model.data

        _ = model.homeMissionSnapshot

        #expect(model.data == before)
    }

    @MainActor
    @Test func currentUnitSnapshotShowsPreviewReadingWhenAnswersAreNotImportedYet() {
        let model = AppModel(store: Self.isolatedStore())
        model.data.activeWordBankMode = .imported
        model.data.questPages = [
            QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: [])
        ]
        model.data.currentQuestPageNumber = 14
        model.data.completedQuestPages = [14]
        model.data.readingLibrary = ReadingLibraryMetadata(
            name: "Reading Preview Pack",
            importedAt: .now,
            articleCount: 1
        )
        model.data.readingQuests = [
            ReadingQuest(
                id: "reading-14",
                title: "Reading Quest: PET全_Page_14",
                pageNumber: 14,
                passage: "Sample passage",
                questions: [
                    ReadingQuestQuestion(
                        number: 1,
                        prompt: "What happened?",
                        choices: [
                            ReadingQuestChoice(letter: "A", text: "A"),
                            ReadingQuestChoice(letter: "B", text: "B"),
                            ReadingQuestChoice(letter: "C", text: "C"),
                            ReadingQuestChoice(letter: "D", text: "D")
                        ],
                        correctChoiceLetter: nil
                    )
                ],
                sourceFilename: "page14.txt"
            )
        ]

        let snapshot = model.currentUnitSnapshot

        #expect(snapshot.readingState == .previewOnly)
        #expect(snapshot.layerSnapshots.map(\.valueText) == ["Base Ready", "Quest Enhanced", "Reading Preview"])
        #expect(snapshot.primaryAction == .openReadingHub)
        #expect(snapshot.primaryActionTitle == "OPEN READING PREVIEW")
        #expect(snapshot.stageBadgeText == "STEP 2 OF 2")
    }

    @MainActor
    @Test func importHubBuildsInlinePreviewSnapshotsForBaseQuestAndReading() throws {
        let model = AppModel(store: Self.isolatedStore())
        model.words = [
            VocabularyWord(id: "director", english: "director", primaryChinese: "导演", topic: .people),
            VocabularyWord(id: "homework", english: "homework", primaryChinese: "作业", topic: .school)
        ]
        model.data.activeWordBankMode = .imported
        model.data.importedLibrary = WordLibraryMetadata(
            name: "PET全",
            sourceFilename: "PET全.pdf",
            importedAt: .now,
            wordCount: 2,
            source: .pdf
        )
        model.data.wordPages = [
            ImportedWordPage(
                pageNumber: 14,
                title: "PET全_Page_14",
                wordIDs: ["director", "homework"],
                sourceFilename: "PET全.pdf"
            )
        ]
        model.data.questPages = [
            QuestPage(
                pageNumber: 14,
                title: "PET全_Page_14",
                questions: [
                    PersistedQuestion(
                        wordID: "director",
                        choices: ["导演", "老师", "书桌", "小鸟"],
                        style: .wordExercise,
                        exampleSentence: "The director told the actors where to stand.",
                        meaningPrompt: "The director told the actors where to stand.",
                        meaningCorrectChoice: "导演",
                        spellingPromptText: "导演: ___",
                        spellingCorrectAnswer: "director",
                        translationPrompt: "导演告诉演员们该站在哪里。",
                        translationChoices: [
                            "The director told the actors where to stand.",
                            "The teacher told the actors where to stand.",
                            "The director asked the actors to dance.",
                            "The actors told the director where to stand."
                        ],
                        translationCorrectChoice: "The director told the actors where to stand."
                    )
                ]
            )
        ]
        model.data.currentQuestPageNumber = 14
        model.data.readingLibrary = ReadingLibraryMetadata(
            name: "Reading Pack",
            importedAt: .now,
            articleCount: 1
        )
        model.data.readingQuests = [
            ReadingQuest(
                id: "reading-14",
                title: "Reading Quest: PET全_Page_14",
                pageNumber: 14,
                passage: "Last Tuesday, Sarah packed her luggage for a trip to a winter resort.",
                questions: [
                    ReadingQuestQuestion(
                        number: 1,
                        prompt: "When did Sarah start her journey?",
                        choices: [
                            ReadingQuestChoice(letter: "A", text: "On a Monday"),
                            ReadingQuestChoice(letter: "B", text: "On a Tuesday"),
                            ReadingQuestChoice(letter: "C", text: "On a Wednesday"),
                            ReadingQuestChoice(letter: "D", text: "On a Thursday")
                        ],
                        correctChoiceLetter: nil
                    )
                ],
                sourceFilename: "reading-page-14.txt"
            )
        ]

        let basePreview = try #require(model.importPreviewSnapshot(for: .base))
        let questPreview = try #require(model.importPreviewSnapshot(for: .quest))
        let readingPreview = try #require(model.importPreviewSnapshot(for: .reading))

        #expect(basePreview.title == "Page 14 base preview")
        #expect(basePreview.subtitle.contains("director"))
        #expect(basePreview.tags.contains("PET全.pdf"))
        #expect(questPreview.title == "Page 14 quest preview")
        #expect(questPreview.subtitle.contains("director"))
        #expect(questPreview.tags.contains("Translation"))
        #expect(readingPreview.title == "Page 14 reading preview")
        #expect(readingPreview.tags.contains("Preview only"))
    }

    @MainActor
    @Test func currentUnitPrimaryActionAdvancesToNextPageOnlyAfterWholeUnitIsComplete() {
        let model = AppModel(store: Self.isolatedStore())
        model.data.activeWordBankMode = .imported
        model.data.questPages = [
            QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: []),
            QuestPage(pageNumber: 15, title: "PET全_Page_15", questions: [])
        ]
        model.data.currentQuestPageNumber = 14
        model.data.completedQuestPages = [14]
        model.data.completedReadingQuestPages = [14]

        #expect(model.currentUnitSnapshot.primaryAction == .advanceToNextQuestPage)
        #expect(model.currentUnitSnapshot.primaryActionTitle == "GO TO PAGE 15")

        model.performCurrentUnitPrimaryAction()

        #expect(model.data.currentQuestPageNumber == 15)
        #expect(model.currentQuestPage?.pageNumber == 15)
    }

    @MainActor
    @Test func questPageChooserPrefersQuestEnhancedSequenceWhenAvailable() {
        let model = AppModel(store: Self.isolatedStore())
        model.data.activeWordBankMode = .imported
        model.data.wordPages = [
            ImportedWordPage(pageNumber: 13, title: "PET全_Page_13", wordIDs: [], sourceFilename: "PET全.pdf"),
            ImportedWordPage(pageNumber: 14, title: "PET全_Page_14", wordIDs: [], sourceFilename: "PET全.pdf"),
            ImportedWordPage(pageNumber: 15, title: "PET全_Page_15", wordIDs: [], sourceFilename: "PET全.pdf")
        ]
        model.data.questPages = [
            QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: []),
            QuestPage(pageNumber: 21, title: "PET全_Page_21", questions: [])
        ]
        model.data.currentQuestPageNumber = 13

        #expect(model.questPageChooserPages.map(\.pageNumber) == [14, 21])
    }

    @MainActor
    @Test func currentQuestPagePreviewSnapshotShowsBasicInfoAndPreview() throws {
        let model = AppModel(store: Self.isolatedStore())
        model.words = [
            VocabularyWord(id: "director", english: "director", primaryChinese: "导演", topic: .people),
            VocabularyWord(id: "homework", english: "homework", primaryChinese: "作业", topic: .school)
        ]
        model.data.activeWordBankMode = .imported
        model.data.questPages = [
            QuestPage(
                pageNumber: 14,
                title: "PET全_Page_14",
                questions: [
                    PersistedQuestion(
                        wordID: "director",
                        choices: ["导演", "老师", "书桌", "小鸟"],
                        style: .wordExercise,
                        exampleSentence: "The director told the actors where to stand.",
                        meaningPrompt: "The director told the actors where to stand.",
                        meaningCorrectChoice: "导演",
                        spellingPromptText: "导演: ___",
                        spellingCorrectAnswer: "director"
                    )
                ]
            )
        ]
        model.data.currentQuestPageNumber = 14
        model.data.readingLibrary = ReadingLibraryMetadata(
            name: "Reading Pack",
            importedAt: .now,
            articleCount: 1
        )
        model.data.readingQuests = [
            ReadingQuest(
                id: "reading-14",
                title: "Reading Quest: PET全_Page_14",
                pageNumber: 14,
                passage: "Page 14 reading passage",
                questions: [
                    ReadingQuestQuestion(
                        number: 1,
                        prompt: "When did Sarah travel?",
                        choices: [
                            ReadingQuestChoice(letter: "A", text: "A"),
                            ReadingQuestChoice(letter: "B", text: "B"),
                            ReadingQuestChoice(letter: "C", text: "C"),
                            ReadingQuestChoice(letter: "D", text: "D")
                        ],
                        correctChoiceLetter: nil
                    )
                ],
                sourceFilename: "page14.txt"
            )
        ]

        let preview = try #require(model.currentQuestPagePreviewSnapshot)

        #expect(preview.title == "Page 14 quest preview")
        #expect(preview.summary.contains("director"))
        #expect(preview.previewText.contains("The director told the actors where to stand."))
        #expect(preview.tags.contains("Quest Enhanced"))
        #expect(preview.tags.contains("Reading Preview"))
    }

    @MainActor
    @Test func importSurfaceBecomesSecondaryAfterBaseAndReadingAreReady() {
        let model = AppModel(store: Self.isolatedStore())
        model.data.activeWordBankMode = .imported
        model.data.wordPages = [
            ImportedWordPage(pageNumber: 14, title: "PET全_Page_14", wordIDs: [], sourceFilename: "PET全.pdf")
        ]

        #expect(model.areCoreImportLayersReady == false)
        #expect(model.shouldDeemphasizeImportSurface == false)

        model.data.readingLibrary = ReadingLibraryMetadata(
            name: "Reading Pack",
            importedAt: .now,
            articleCount: 66
        )

        #expect(model.areCoreImportLayersReady)
        #expect(model.shouldDeemphasizeImportSurface)
        #expect(model.importedBasePageCount == 1)
    }

    @MainActor
    @Test func appModelSpeechHelpersPreserveEnglishAndChineseHints() {
        var spoken: [(String, SpeechLanguageHint)] = []
        let model = AppModel(
            store: Self.isolatedStore(),
            speakText: { text, language in
                spoken.append((text, language))
            }
        )

        model.speakEnglish("director")
        model.speakChinese("导演告诉演员们该站在哪里。")
        model.speak("  sentence   clue  ", language: .automatic)

        #expect(spoken.count == 3)
        #expect(spoken[0].0 == "director")
        #expect(spoken[0].1 == .english)
        #expect(spoken[1].0 == "导演告诉演员们该站在哪里。")
        #expect(spoken[1].1 == .chinese)
        #expect(spoken[2].0 == "sentence clue")
        #expect(spoken[2].1 == .automatic)
    }

    @MainActor
    @Test func readingPreviewSelectionCanSwitchToAnotherImportedPage() {
        let model = AppModel(store: Self.isolatedStore())
        model.data.activeWordBankMode = .imported
        model.data.questPages = [
            QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: []),
            QuestPage(pageNumber: 21, title: "PET全_Page_21", questions: [])
        ]
        model.data.currentQuestPageNumber = 14
        model.data.readingLibrary = ReadingLibraryMetadata(
            name: "Reading Pack",
            importedAt: .now,
            articleCount: 2
        )
        model.data.readingQuests = [
            ReadingQuest(
                id: "reading-14",
                title: "Reading Quest: PET全_Page_14",
                pageNumber: 14,
                passage: "Page 14 passage",
                questions: [
                    ReadingQuestQuestion(
                        number: 1,
                        prompt: "Q14",
                        choices: [
                            ReadingQuestChoice(letter: "A", text: "A"),
                            ReadingQuestChoice(letter: "B", text: "B"),
                            ReadingQuestChoice(letter: "C", text: "C"),
                            ReadingQuestChoice(letter: "D", text: "D")
                        ],
                        correctChoiceLetter: "A"
                    )
                ],
                sourceFilename: "page14.txt"
            ),
            ReadingQuest(
                id: "reading-21",
                title: "Reading Quest: PET全_Page_21",
                pageNumber: 21,
                passage: "Page 21 passage",
                questions: [
                    ReadingQuestQuestion(
                        number: 1,
                        prompt: "Q21",
                        choices: [
                            ReadingQuestChoice(letter: "A", text: "A"),
                            ReadingQuestChoice(letter: "B", text: "B"),
                            ReadingQuestChoice(letter: "C", text: "C"),
                            ReadingQuestChoice(letter: "D", text: "D")
                        ],
                        correctChoiceLetter: nil
                    )
                ],
                sourceFilename: "page21.txt"
            )
        ]

        model.openReading()
        #expect(model.selectedReadingPreviewQuest?.pageNumber == 14)

        model.selectReadingPreviewPage(21)
        #expect(model.selectedReadingPreviewQuest?.pageNumber == 21)

        model.startSelectedReadingPreview()
        #expect(model.activeReadingSession?.pageNumber == 21)
        #expect(model.activeReadingSession?.questID == "reading-21")
        #expect(model.screen == .readingQuiz)
    }

    @MainActor
    @Test func readingQuestShowsQuestionsBeforePassageAndQuestions() {
        let model = AppModel(store: Self.isolatedStore())
        model.data.activeWordBankMode = .imported
        model.data.questPages = [
            QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: [])
        ]
        model.data.currentQuestPageNumber = 14
        model.data.readingLibrary = ReadingLibraryMetadata(
            name: "Reading Pack",
            importedAt: .now,
            articleCount: 1
        )
        model.data.readingQuests = [
            ReadingQuest(
                id: "reading-14",
                title: "Reading Quest: PET全_Page_14",
                pageNumber: 14,
                passage: "Page 14 passage",
                questions: [
                    ReadingQuestQuestion(
                        number: 1,
                        prompt: "Q1",
                        choices: [
                            ReadingQuestChoice(letter: "A", text: "A"),
                            ReadingQuestChoice(letter: "B", text: "B"),
                            ReadingQuestChoice(letter: "C", text: "C"),
                            ReadingQuestChoice(letter: "D", text: "D")
                        ],
                        correctChoiceLetter: "A"
                    ),
                    ReadingQuestQuestion(
                        number: 2,
                        prompt: "Q2",
                        choices: [
                            ReadingQuestChoice(letter: "A", text: "A2"),
                            ReadingQuestChoice(letter: "B", text: "B2"),
                            ReadingQuestChoice(letter: "C", text: "C2"),
                            ReadingQuestChoice(letter: "D", text: "D2")
                        ],
                        correctChoiceLetter: "B"
                    )
                ],
                sourceFilename: "page14.txt"
            )
        ]

        model.startCurrentReadingQuest()
        #expect(model.activeReadingSession?.stage == .questionPreview)
        #expect(model.currentReadingQuestion == nil)

        model.advanceReadingQuestionPreview()
        #expect(model.activeReadingSession?.stage == .passageReading)
        #expect(model.currentReadingQuestion == nil)

        model.startReadingQuestions()
        #expect(model.activeReadingSession?.stage == .answering)
        #expect(model.currentReadingQuestion?.number == 1)
    }

    @MainActor
    @Test func readingQuestWrongAnswerRetriesCurrentQuestionBeforeAdvancing() {
        let model = AppModel(store: Self.isolatedStore())
        model.data.activeWordBankMode = .imported
        model.data.questPages = [
            QuestPage(pageNumber: 14, title: "PET全_Page_14", questions: [])
        ]
        model.data.currentQuestPageNumber = 14
        model.data.readingLibrary = ReadingLibraryMetadata(
            name: "Reading Pack",
            importedAt: .now,
            articleCount: 1
        )
        model.data.readingQuests = [
            ReadingQuest(
                id: "reading-14",
                title: "Reading Quest: PET全_Page_14",
                pageNumber: 14,
                passage: "Page 14 passage",
                questions: [
                    ReadingQuestQuestion(
                        number: 1,
                        prompt: "Q1",
                        choices: [
                            ReadingQuestChoice(letter: "A", text: "A"),
                            ReadingQuestChoice(letter: "B", text: "B"),
                            ReadingQuestChoice(letter: "C", text: "C"),
                            ReadingQuestChoice(letter: "D", text: "D")
                        ],
                        correctChoiceLetter: "B"
                    )
                ],
                sourceFilename: "page14.txt"
            )
        ]

        model.startCurrentReadingQuest()
        model.advanceReadingQuestionPreview()
        model.startReadingQuestions()
        model.submitReadingChoice(letter: "A")

        #expect(model.readingAnswerFeedback?.isCorrect == false)
        #expect(model.activeReadingSession?.currentIndex == 0)
        #expect(model.activeReadingSession?.correctAnswers == 0)

        model.retryCurrentReadingQuestion()

        #expect(model.readingAnswerFeedback == nil)
        #expect(model.activeReadingSession?.currentIndex == 0)
        #expect(model.currentReadingQuestion?.number == 1)

        model.submitReadingChoice(letter: "B")
        #expect(model.readingAnswerFeedback?.isCorrect == true)

        model.advanceReadingAfterFeedback()

        #expect(model.screen == .summary)
        #expect(model.latestSummary?.mode == .readingQuest)
        #expect(model.data.completedReadingQuestPages == [14])
    }

    @MainActor
    @Test func openMainSurfaceReturnsToCorrectRootScreen() {
        let onboardingModel = AppModel(store: Self.isolatedStore())
        onboardingModel.data.hasCompletedPlacement = false
        onboardingModel.screen = .reading
        onboardingModel.openMainSurface()
        #expect(onboardingModel.screen == .onboarding)

        let dashboardModel = AppModel(store: Self.isolatedStore())
        dashboardModel.data.hasCompletedPlacement = true
        dashboardModel.screen = .reading
        dashboardModel.openMainSurface()
        #expect(dashboardModel.screen == .dashboard)
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

    @Test func feedbackGeneratorLabelsFailedReviewAsRescueSprint() {
        let session = ActiveSession(
            mode: .failedReview,
            questions: (0..<5).map { index in
                PersistedQuestion(wordID: "word-\(index)", choices: ["A", "B", "C", "D"])
            },
            currentIndex: 5,
            correctAnswers: 4,
            attempts: [
                AttemptRecord(sessionID: "s1", wordID: "word-0", selectedChoice: "A", correctChoice: "A", isCorrect: true, topic: .school),
                AttemptRecord(sessionID: "s1", wordID: "word-1", selectedChoice: "A", correctChoice: "A", isCorrect: true, topic: .school),
                AttemptRecord(sessionID: "s1", wordID: "word-2", selectedChoice: "A", correctChoice: "A", isCorrect: true, topic: .school),
                AttemptRecord(sessionID: "s1", wordID: "word-3", selectedChoice: "A", correctChoice: "A", isCorrect: true, topic: .school),
                AttemptRecord(sessionID: "s1", wordID: "word-4", selectedChoice: "B", correctChoice: "A", isCorrect: false, topic: .school)
            ]
        )

        let summary = FeedbackGenerator.makeSummary(from: session, wordsByID: [:])

        #expect(summary.headline == "Rescue sprint cleared")
        #expect(summary.body.contains("rescued 4 of 5"))
        #expect(summary.body.contains("small win"))
        #expect(summary.recommendedMissionTitle == "Choose next rescue step")
    }

    @Test func placementSummaryIncludesEstimatedVocabularyLanguage() {
        let session = ActiveSession(
            mode: .placement,
            questions: [
                PersistedQuestion(wordID: "school", choices: ["借入", "归还", "老师", "学校"]),
                PersistedQuestion(wordID: "places", choices: ["电影院", "车站", "医院", "旅程"])
            ],
            currentIndex: 2,
            correctAnswers: 1,
            attempts: [
                AttemptRecord(sessionID: "s1", wordID: "school", selectedChoice: "借入", correctChoice: "借入", isCorrect: true, topic: .school),
                AttemptRecord(sessionID: "s1", wordID: "places", selectedChoice: "车站", correctChoice: "电影院", isCorrect: false, topic: .places)
            ],
            newlyMasteredWordIDs: []
        )

        let summary = FeedbackGenerator.makeSummary(from: session, wordsByID: [:])

        #expect(summary.headline == "Placement complete")
        #expect(summary.body.contains("estimated PET-style vocabulary"))
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

    @Test func sessionSummaryAccuracyRoundsInsteadOfTruncating() {
        let summary = SessionSummary(
            mode: .mission,
            startedAt: .now,
            completedAt: .now,
            totalQuestions: 3,
            correctAnswers: 2,
            newlyMasteredCount: 0,
            weakTopics: [],
            headline: "Nice work",
            body: "Coach note",
            recommendedMissionTitle: "Retry later"
        )
        let topicInsight = PlacementTopicInsight(topic: .school, correctAnswers: 1, totalQuestions: 6)

        #expect(summary.accuracyPercent == 67)
        #expect(topicInsight.accuracyPercent == 17)
    }

    @MainActor
    @Test func appModelStoresReadableReviewWordsInLatestTrophy() throws {
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
        model.words.forEach { model.data.progressByWordID[$0.id] = .fresh(for: $0.id) }
        model.data.activeSession = ActiveSession(
            mode: .mission,
            questions: [
                PersistedQuestion(
                    wordID: "w1",
                    choices: ["借入", "老师", "电影院", "票"],
                    style: .wordExercise,
                    exampleSentence: "In class today, we practised the word borrow together."
                )
            ]
        )

        model.submit(choice: "老师")
        model.submitPronunciationRating(.clear)
        model.submitSpelling(answer: "borrow")
        model.advanceAfterFeedback()

        let summary = try #require(model.latestSummary)
        let reviewWord = try #require(summary.reviewWords.first)

        #expect(summary.failedAnswers == 1)
        #expect(reviewWord.english == "borrow")
        #expect(reviewWord.primaryChinese == "借入")
        #expect(reviewWord.topic == .school)
        #expect(reviewWord.nextReviewAt != nil)
        #expect(reviewWord.reviewStep == 0)
    }

    @MainActor
    @Test func reviewWordSnapshotsCarryMemoryTipsIntoReview() throws {
        let model = AppModel(store: Self.isolatedStore())
        model.words = [
            VocabularyWord(id: "w1", english: "borrow", primaryChinese: "借入", topic: .school)
        ]
        model.data.progressByWordID["w1"] = WordProgress(
            wordID: "w1",
            currentCorrectStreak: 0,
            totalCorrect: 0,
            totalIncorrect: 1,
            isMastered: false,
            lastSeenAt: .now,
            lastIncorrectAt: .now,
            reviewPriority: 2,
            reviewStep: 0,
            nextReviewAt: .now.addingTimeInterval(-60)
        )
        model.data.questPages = [
            QuestPage(
                pageNumber: 14,
                title: "PET全_Page_14",
                questions: [
                    PersistedQuestion(
                        wordID: "w1",
                        choices: ["借入", "归还", "老师", "学校"],
                        style: .wordExercise,
                        exampleSentence: "May I borrow your dictionary?",
                        memoryTip: "Borrow sounds like bringing a book back later.",
                        exampleTranslation: "我可以借用你的词典吗？"
                    )
                ]
            )
        ]

        let reviewWord = try #require(model.reviewWordSnapshots.first)

        #expect(reviewWord.english == "borrow")
        #expect(reviewWord.memoryTip == "Borrow sounds like bringing a book back later.")
        #expect(reviewWord.exampleSentence == "May I borrow your dictionary?")
        #expect(reviewWord.exampleTranslation == "我可以借用你的词典吗？")

        let rescueWord = try #require(model.reviewRescueSnapshot.dueNow.words.first)
        #expect(rescueWord.exampleSentence == "May I borrow your dictionary?")
        #expect(rescueWord.exampleTranslation == "我可以借用你的词典吗？")
    }

    @MainActor
    @Test func trophiesSnapshotSummarizesOverviewPageMapAndMemoryPath() throws {
        let model = AppModel(store: Self.isolatedStore())
        let now = Date.now
        model.words = [
            VocabularyWord(id: "w1", english: "borrow", primaryChinese: "借入", topic: .school),
            VocabularyWord(id: "w2", english: "cinema", primaryChinese: "电影院", topic: .places)
        ]
        model.data.activeWordBankMode = .imported
        model.data.dailyStreak = 4
        model.data.currentQuestPageNumber = 14
        model.data.wordPages = [
            ImportedWordPage(pageNumber: 14, title: "PET全_Page_14", wordIDs: ["w1", "w2"], sourceFilename: "PET全.pdf")
        ]
        model.data.questPages = [
            QuestPage(
                pageNumber: 14,
                title: "PET全_Page_14_Quest",
                questions: [
                    PersistedQuestion(
                        wordID: "w1",
                        choices: ["借入", "归还", "老师", "学校"],
                        style: .wordExercise,
                        exampleSentence: "May I borrow your dictionary?",
                        memoryTip: "Borrow sounds like bringing a book back later.",
                        exampleTranslation: "我可以借用你的词典吗？",
                        sourcePageNumber: 14,
                        sourcePageTitle: "PET全_Page_14_Quest"
                    )
                ]
            )
        ]
        model.data.readingQuests = [
            ReadingQuest(
                id: "reading-14",
                title: "Reading Quest: PET全_Page_14",
                pageNumber: 14,
                passage: "A short reading passage.",
                questions: [],
                sourceFilename: "reading-page-14.txt"
            )
        ]
        model.data.completedQuestPages = [14]
        model.data.completedReadingQuestPages = [14]
        model.data.sessions = [
            SessionSummary(
                mode: .mission,
                startedAt: now.addingTimeInterval(-900),
                completedAt: now,
                questPageNumber: 14,
                questPageTitle: "PET全_Page_14_Quest",
                totalQuestions: 10,
                correctAnswers: 9,
                newlyMasteredCount: 2,
                weakTopics: [],
                headline: "Page 14 cleared",
                body: "Great progress.",
                recommendedMissionTitle: "Continue Reading"
            ),
            SessionSummary(
                mode: .readingQuest,
                startedAt: now.addingTimeInterval(-172_800),
                completedAt: now.addingTimeInterval(-172_500),
                questPageNumber: 13,
                questPageTitle: "Reading Quest: PET全_Page_13",
                totalQuestions: 10,
                correctAnswers: 6,
                newlyMasteredCount: 0,
                weakTopics: [.school],
                headline: "Reading complete",
                body: "Keep practicing.",
                recommendedMissionTitle: "Review missed words"
            )
        ]
        model.data.progressByWordID["w1"] = WordProgress(
            wordID: "w1",
            currentCorrectStreak: 0,
            totalCorrect: 1,
            totalIncorrect: 2,
            retryMissCount: 1,
            isMastered: false,
            lastSeenAt: now,
            lastIncorrectAt: now,
            reviewPriority: 3,
            reviewStep: 1,
            nextReviewAt: now.addingTimeInterval(-60)
        )

        let snapshot = model.trophiesSnapshot
        let page14 = try #require(snapshot.pageStatuses.first(where: { $0.pageNumber == 14 }))

        #expect(snapshot.totalSessions == 2)
        #expect(snapshot.completedTodayCount == 1)
        #expect(snapshot.averageAccuracyPercent == 75)
        #expect(snapshot.dueReviewCount == 1)
        #expect(snapshot.dailyStreak == 4)
        #expect(snapshot.questCompletedCount == 1)
        #expect(snapshot.readingCompletedCount == 1)
        #expect(page14.isCurrent)
        #expect(page14.isBaseReady)
        #expect(page14.isQuestEnhanced)
        #expect(page14.isQuestCompleted)
        #expect(page14.isReadingReady)
        #expect(page14.isReadingCompleted)
        #expect(page14.hasReviewDue)
        #expect(snapshot.memoryWords.first?.english == "borrow")
    }

    @MainActor
    @Test func appModelBuildsReminderSnapshotFromDueAndScheduledWords() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let model = AppModel(store: LocalStore(url: url))
        model.words = [
            VocabularyWord(id: "due", english: "borrow", primaryChinese: "借入", topic: .school),
            VocabularyWord(id: "later", english: "cinema", primaryChinese: "电影院", topic: .places)
        ]
        model.data.progressByWordID["due"] = WordProgress(
            wordID: "due",
            currentCorrectStreak: 0,
            totalCorrect: 0,
            totalIncorrect: 1,
            isMastered: false,
            lastSeenAt: .now,
            lastIncorrectAt: .now,
            reviewPriority: 2,
            reviewStep: 0,
            nextReviewAt: .now.addingTimeInterval(-60)
        )
        model.data.progressByWordID["later"] = WordProgress(
            wordID: "later",
            currentCorrectStreak: 0,
            totalCorrect: 0,
            totalIncorrect: 1,
            isMastered: false,
            lastSeenAt: .now,
            lastIncorrectAt: .now,
            reviewPriority: 2,
            reviewStep: 1,
            nextReviewAt: .now.addingTimeInterval(3_600)
        )

        let snapshot = model.reviewReminderSnapshot

        #expect(snapshot.dueNowCount == 1)
        #expect(snapshot.scheduledLaterCount == 1)
        #expect(snapshot.headline.contains("due now"))
        #expect(snapshot.strategyText == ReviewScheduler.strategyDescription)
    }

    @Test func reviewRescuePlannerSplitsDueSoonAndBacklogWords() throws {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        let dueWord = VocabularyWord(id: "attitude", english: "attitude", primaryChinese: "态度", topic: .feelings)
        let soonWord = VocabularyWord(id: "influence", english: "influence", primaryChinese: "影响", topic: .communication)
        let backlogWord = VocabularyWord(id: "argument", english: "argument", primaryChinese: "争论", topic: .communication)
        let dueProgress = WordProgress(
            wordID: dueWord.id,
            currentCorrectStreak: 0,
            totalCorrect: 1,
            totalIncorrect: 2,
            retryMissCount: 1,
            isMastered: false,
            lastSeenAt: now.addingTimeInterval(-3_600),
            lastIncorrectAt: now.addingTimeInterval(-3_600),
            reviewPriority: 3,
            reviewStep: 1,
            nextReviewAt: now.addingTimeInterval(-60)
        )
        let soonProgress = WordProgress(
            wordID: soonWord.id,
            currentCorrectStreak: 1,
            totalCorrect: 2,
            totalIncorrect: 1,
            isMastered: false,
            lastSeenAt: now.addingTimeInterval(-3_600),
            lastIncorrectAt: now.addingTimeInterval(-3_600),
            reviewPriority: 1,
            reviewStep: 2,
            nextReviewAt: now.addingTimeInterval(3_600)
        )
        let backlogProgress = WordProgress(
            wordID: backlogWord.id,
            currentCorrectStreak: 1,
            totalCorrect: 2,
            totalIncorrect: 1,
            isMastered: false,
            lastSeenAt: now.addingTimeInterval(-3_600),
            lastIncorrectAt: now.addingTimeInterval(-3_600),
            reviewPriority: 1,
            reviewStep: 3,
            nextReviewAt: now.addingTimeInterval(3 * 24 * 60 * 60)
        )

        let snapshot = ReviewRescuePlanner.snapshot(
            from: [
                (word: backlogWord, progress: backlogProgress),
                (word: dueWord, progress: dueProgress),
                (word: soonWord, progress: soonProgress)
            ],
            memoryTipProvider: { wordID in wordID == dueWord.id ? "Attitude is how you stand toward something." : nil },
            now: now
        )

        #expect(snapshot.dueNow.count == 1)
        #expect(snapshot.comingSoon.count == 1)
        #expect(snapshot.backlog.count == 1)
        let dueSnapshot = try #require(snapshot.dueNow.words.first)
        #expect(dueSnapshot.english == "attitude")
        #expect(dueSnapshot.memoryTip == "Attitude is how you stand toward something.")
        #expect(dueSnapshot.stageIndex == 1)
        #expect(dueSnapshot.stageCount == 5)
        #expect(dueSnapshot.weakPointText == "Spelling retry")
        #expect(dueSnapshot.quickListenTitle == "Play word")
        #expect(snapshot.primaryActionTitle == "START 1-WORD RESCUE")
    }

    @Test func reviewRescuePlannerTurnsLargeDueBacklogIntoFiveWordSprint() {
        let now = Date(timeIntervalSinceReferenceDate: 200_000)
        let items: [(word: VocabularyWord, progress: WordProgress)] = (0..<8).map { index in
            let word = VocabularyWord(
                id: "due-\(index)",
                english: "word\(index)",
                primaryChinese: "词\(index)",
                topic: .school
            )
            let progress = WordProgress(
                wordID: word.id,
                currentCorrectStreak: 0,
                totalCorrect: 1,
                totalIncorrect: 2,
                retryMissCount: index.isMultiple(of: 2) ? 1 : 0,
                isMastered: false,
                lastSeenAt: now.addingTimeInterval(-3_600),
                lastIncorrectAt: now.addingTimeInterval(-3_600),
                reviewPriority: 8 - index,
                reviewStep: 0,
                nextReviewAt: now.addingTimeInterval(-Double(index + 1) * 60)
            )
            return (word, progress)
        }

        let snapshot = ReviewRescuePlanner.snapshot(
            from: items,
            memoryTipProvider: { _ in nil },
            now: now
        )

        #expect(snapshot.dueNow.count == 8)
        #expect(snapshot.currentSprintCount == 5)
        #expect(snapshot.waitingDueCount == 3)
        #expect(snapshot.primaryActionTitle == "START 5-WORD RESCUE")
        #expect(snapshot.rescuePackTitle == "5 words need rescue now")
        #expect(snapshot.rescuePackDetail.contains("3 more"))
        #expect(snapshot.rescuePackDetail.contains("safely waiting"))
    }

    @MainActor
    @Test func appModelStartsOnlyFiveDueWordsForReviewRescue() {
        let now = Date(timeIntervalSinceReferenceDate: 200_000)
        let model = AppModel(store: Self.isolatedStore())
        model.words = (0..<8).map { index in
            VocabularyWord(
                id: "due-\(index)",
                english: "word\(index)",
                primaryChinese: "词\(index)",
                topic: .school
            )
        }
        for (index, word) in model.words.enumerated() {
            model.data.progressByWordID[word.id] = WordProgress(
                wordID: word.id,
                currentCorrectStreak: 0,
                totalCorrect: 1,
                totalIncorrect: 2,
                isMastered: false,
                lastSeenAt: now.addingTimeInterval(-3_600),
                lastIncorrectAt: now.addingTimeInterval(-3_600),
                reviewPriority: 8 - index,
                reviewStep: 0,
                nextReviewAt: now.addingTimeInterval(-Double(index + 1) * 60)
            )
        }

        model.startFailedReview()

        #expect(model.currentSession?.mode == .failedReview)
        #expect(model.currentSession?.questions.count == 5)
    }

    @MainActor
    @Test func appModelResumeTrimsLegacyFailedReviewSessionToFiveWordSprint() {
        let model = AppModel(store: Self.isolatedStore())
        model.words = (0..<10).map { index in
            VocabularyWord(
                id: "legacy-due-\(index)",
                english: "word\(index)",
                primaryChinese: "词\(index)",
                topic: .school
            )
        }
        model.data.activeSession = ActiveSession(
            mode: .failedReview,
            questions: model.words.map { word in
                PersistedQuestion(wordID: word.id, choices: ["词0", "词1", "词2", "词3"], style: .wordExercise)
            }
        )

        model.resumeCurrentSession()

        #expect(model.screen == .quiz)
        #expect(model.currentSession?.mode == .failedReview)
        #expect(model.currentSession?.questions.count == ReviewRescuePlanner.rescueSprintSize)
        #expect(model.quizProgressLabel == "WORD 1 / 5")
    }

    @Test func reviewNotificationPlannerBuildsDueNowDigest() throws {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        let snapshot = ReviewReminderSnapshot(
            dueNowCount: 8,
            scheduledLaterCount: 14,
            retryTrackedCount: 3,
            nextReminderAt: nil,
            headline: "8 review reminders are due now",
            detail: "Open Review Rescue first.",
            strategyText: ReviewScheduler.strategyDescription
        )

        let plan = try #require(ReviewNotificationPlanner.plan(from: snapshot, now: now))

        #expect(plan.identifier == ReviewNotificationPlan.identifier)
        #expect(plan.title == "Review Rescue is ready")
        #expect(plan.body.contains("8 PET words are due"))
        #expect(Int(plan.fireDate.timeIntervalSince(now)) == 15 * 60)
    }

    @Test func reviewNotificationPlannerUsesNextFutureReminderWhenNothingIsDue() throws {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        let future = now.addingTimeInterval(3_600)
        let snapshot = ReviewReminderSnapshot(
            dueNowCount: 0,
            scheduledLaterCount: 4,
            retryTrackedCount: 1,
            nextReminderAt: future,
            headline: "Next reminder later",
            detail: "Four words are coming back.",
            strategyText: ReviewScheduler.strategyDescription
        )

        let plan = try #require(ReviewNotificationPlanner.plan(from: snapshot, now: now))

        #expect(plan.fireDate == future)
        #expect(plan.body.contains("4 PET words are coming back"))
    }

    @Test func legacyAppStoreDataLoadsWithReviewNotificationsDisabled() throws {
        let data = try JSONDecoder().decode(AppStoreData.self, from: Data("{}".utf8))

        #expect(data.reviewNotificationPreferences.isEnabled == false)
        #expect(data.reviewNotificationPreferences.permissionDenied == false)
        #expect(data.reviewNotificationPreferences.lastScheduledAt == nil)
    }

    @MainActor
    @Test func appModelEnablingReviewNotificationsPersistsAndSchedulesDigest() async throws {
        let store = Self.isolatedStore()
        let scheduler = FakeReviewNotificationScheduler()
        let model = AppModel(store: store, reviewNotificationScheduler: scheduler)
        model.words = [
            VocabularyWord(id: "attitude", english: "attitude", primaryChinese: "态度", topic: .feelings)
        ]
        model.data.progressByWordID["attitude"] = WordProgress(
            wordID: "attitude",
            currentCorrectStreak: 0,
            totalCorrect: 0,
            totalIncorrect: 1,
            isMastered: false,
            lastSeenAt: .now.addingTimeInterval(-3_600),
            lastIncorrectAt: .now.addingTimeInterval(-3_600),
            reviewPriority: 2,
            reviewStep: 0,
            nextReviewAt: .now.addingTimeInterval(-60)
        )

        await model.enableReviewNotifications()

        #expect(model.data.reviewNotificationPreferences.isEnabled == true)
        #expect(model.data.reviewNotificationPreferences.permissionDenied == false)
        #expect(scheduler.requestedAuthorizationCount == 1)
        let appliedPlan = try #require(scheduler.appliedPlans.compactMap { $0 }.last)
        #expect(appliedPlan.body.contains("1 PET words are due"))
        let savedData = try store.load()
        #expect(savedData.reviewNotificationPreferences.isEnabled == true)
        let savedScheduledAt = try #require(savedData.reviewNotificationPreferences.lastScheduledAt)
        let modelScheduledAt = try #require(model.data.reviewNotificationPreferences.lastScheduledAt)
        #expect(abs(savedScheduledAt.timeIntervalSince(modelScheduledAt)) < 1)
    }

    @MainActor
    @Test func appModelDisablingReviewNotificationsPersistsAndCancelsDigest() async throws {
        let store = Self.isolatedStore()
        let scheduler = FakeReviewNotificationScheduler()
        let model = AppModel(store: store, reviewNotificationScheduler: scheduler)
        model.data.reviewNotificationPreferences = ReviewNotificationPreferences(
            isEnabled: true,
            permissionDenied: false,
            lastScheduledAt: .now.addingTimeInterval(3_600)
        )

        await model.disableReviewNotifications()

        #expect(model.data.reviewNotificationPreferences.isEnabled == false)
        #expect(model.data.reviewNotificationPreferences.lastScheduledAt == nil)
        #expect(scheduler.appliedPlans.count == 1)
        #expect(scheduler.appliedPlans.last! == nil)
        let savedData = try store.load()
        #expect(savedData.reviewNotificationPreferences.isEnabled == false)
        #expect(savedData.reviewNotificationPreferences.lastScheduledAt == nil)
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

    @Test func localStoreInstallsBundledInitialDataOnFirstLaunch() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let initialDataURL = tempDirectory.appendingPathComponent("InitialData", isDirectory: true)
        let targetStoreURL = tempDirectory.appendingPathComponent("AppSupport", isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let seedStore = LocalStore(url: initialDataURL.appendingPathComponent("store.json"))
        var seedData = AppStoreData()
        seedData.activeWordBankMode = .imported
        seedData.importedLibrary = WordLibraryMetadata(
            name: "Seed PET",
            sourceFilename: "PET全.pdf",
            importedAt: .now,
            wordCount: 1,
            source: .pdf
        )
        seedData.readingLibrary = ReadingLibraryMetadata(name: "Seed Reading", importedAt: .now, articleCount: 1)
        try seedStore.save(seedData)
        try seedStore.saveImportedWords([
            VocabularyWord(id: "seed-1", english: "director", primaryChinese: "导演", topic: .people)
        ])

        let targetStore = LocalStore(url: targetStoreURL)
        try targetStore.installBundledInitialDataIfNeeded(from: initialDataURL)

        let loaded = try targetStore.load()
        let maybeLoadedWords = try targetStore.loadImportedWords()
        let loadedWords = try #require(maybeLoadedWords)
        #expect(loaded.activeWordBankMode == .imported)
        #expect(loaded.importedLibrary?.name == "Seed PET")
        #expect(loaded.readingLibrary?.name == "Seed Reading")
        #expect(loadedWords.map(\.english) == ["director"])

        let existingEmptyStoreURL = tempDirectory.appendingPathComponent("ExistingEmpty", isDirectory: true)
            .appendingPathComponent("store.json")
        let existingEmptyStore = LocalStore(url: existingEmptyStoreURL)
        var emptyData = AppStoreData()
        emptyData.sessions = [
            SessionSummary(
                mode: .placement,
                startedAt: .now,
                completedAt: .now,
                totalQuestions: 1,
                correctAnswers: 1,
                newlyMasteredCount: 0,
                weakTopics: [],
                headline: "Existing trophy",
                body: "Should stay",
                recommendedMissionTitle: "Keep going"
            )
        ]
        try existingEmptyStore.save(emptyData)

        try existingEmptyStore.installBundledInitialDataIfNeeded(from: initialDataURL)

        let repairedData = try existingEmptyStore.load()
        let maybeRepairedWords = try existingEmptyStore.loadImportedWords()
        let repairedWords = try #require(maybeRepairedWords)
        #expect(repairedData.importedLibrary?.name == "Seed PET")
        #expect(repairedData.readingLibrary?.name == "Seed Reading")
        #expect(repairedData.sessions.first?.headline == "Existing trophy")
        #expect(repairedWords.map(\.english) == ["director"])
    }

    @Test func localStoreBacksUpStoreAndImportedWordsBeforeRiskyChanges() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = tempDirectory.appendingPathComponent("AppSupport", isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = LocalStore(url: storeURL)
        var storeData = AppStoreData()
        storeData.dailyStreak = 3
        storeData.sessions = [
            SessionSummary(
                mode: .mission,
                startedAt: .now,
                completedAt: .now,
                totalQuestions: 1,
                correctAnswers: 1,
                newlyMasteredCount: 0,
                weakTopics: [],
                headline: "Existing trophy",
                body: "Keep this",
                recommendedMissionTitle: "Continue"
            )
        ]
        try store.save(storeData)
        try store.saveImportedWords([
            VocabularyWord(id: "backup-1", english: "director", primaryChinese: "导演", topic: .people)
        ])

        let maybeBackupURL = try store.backupExistingData(
            reason: "import quest",
            now: Date(timeIntervalSince1970: 0)
        )
        let backupURL = try #require(maybeBackupURL)
        let backupStore = LocalStore(url: backupURL.appendingPathComponent("store.json"))
        let backedUpWords = try #require(try backupStore.loadImportedWords())

        #expect(backupURL.lastPathComponent.contains("import-quest"))
        #expect(try backupStore.load().dailyStreak == 3)
        #expect(try backupStore.load().sessions.first?.headline == "Existing trophy")
        #expect(backedUpWords.map(\.english) == ["director"])
    }

    @Test func localStoreInitialDataDoesNotOverwriteExistingImportOrHistory() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let initialDataURL = tempDirectory.appendingPathComponent("InitialData", isDirectory: true)
        let targetStoreURL = tempDirectory.appendingPathComponent("AppSupport", isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let seedStore = LocalStore(url: initialDataURL.appendingPathComponent("store.json"))
        var seedData = AppStoreData()
        seedData.activeWordBankMode = .imported
        seedData.importedLibrary = WordLibraryMetadata(
            name: "Seed PET",
            sourceFilename: "PET全.pdf",
            importedAt: .now,
            wordCount: 1,
            source: .pdf
        )
        seedData.questPages = [QuestPage(pageNumber: 1, title: "Seed Page 1", questions: [])]
        seedData.readingLibrary = ReadingLibraryMetadata(name: "Seed Reading", importedAt: .now, articleCount: 1)
        try seedStore.save(seedData)
        try seedStore.saveImportedWords([
            VocabularyWord(id: "seed-1", english: "seed", primaryChinese: "种子", topic: .school)
        ])

        let targetStore = LocalStore(url: targetStoreURL)
        var existingData = AppStoreData()
        existingData.activeWordBankMode = .imported
        existingData.importedLibrary = WordLibraryMetadata(
            name: "Personal PET",
            sourceFilename: "personal.pdf",
            importedAt: .now,
            wordCount: 1,
            source: .pdf
        )
        existingData.questPages = [QuestPage(pageNumber: 14, title: "Personal Page 14", questions: [])]
        existingData.sessions = [
            SessionSummary(
                mode: .mission,
                startedAt: .now,
                completedAt: .now,
                totalQuestions: 1,
                correctAnswers: 1,
                newlyMasteredCount: 0,
                weakTopics: [],
                headline: "Personal trophy",
                body: "Must survive first launch repair",
                recommendedMissionTitle: "Keep going"
            )
        ]
        try targetStore.save(existingData)
        try targetStore.saveImportedWords([
            VocabularyWord(id: "personal-1", english: "personal", primaryChinese: "个人的", topic: .people)
        ])

        try targetStore.installBundledInitialDataIfNeeded(from: initialDataURL)

        let loaded = try targetStore.load()
        let loadedWords = try #require(try targetStore.loadImportedWords())
        #expect(loaded.importedLibrary?.name == "Personal PET")
        #expect(loaded.questPages.map(\.pageNumber) == [14])
        #expect(loaded.readingLibrary?.name == "Seed Reading")
        #expect(loaded.sessions.first?.headline == "Personal trophy")
        #expect(loadedWords.map(\.english) == ["personal"])
    }

    @Test func localStoreLoadsLegacyWordProgressWithoutReviewScheduleFields() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let legacyJSON = """
        {
          "dailyStreak" : 2,
          "hasCompletedPlacement" : true,
          "progressByWordID" : {
            "school-1" : {
              "currentCorrectStreak" : 1,
              "isMastered" : false,
              "reviewPriority" : 3,
              "totalCorrect" : 2,
              "totalIncorrect" : 1,
              "wordID" : "school-1"
            }
          },
          "sessions" : []
        }
        """

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try legacyJSON.write(to: url, atomically: true, encoding: .utf8)

        let loaded = try LocalStore(url: url).load()
        let progress = try #require(loaded.progressByWordID["school-1"])

        #expect(loaded.hasCompletedPlacement)
        #expect(loaded.dailyStreak == 2)
        #expect(progress.reviewStep == 0)
        #expect(progress.nextReviewAt == nil)
        #expect(progress.lastSeenAt == nil)
        #expect(progress.lastIncorrectAt == nil)
    }

    @Test func localStoreLoadsLegacySessionSummaryWithoutReviewWords() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let legacyJSON = """
        {
          "sessions" : [
            {
              "body" : "Coach note",
              "completedAt" : "2026-04-20T08:30:00Z",
              "correctAnswers" : 7,
              "headline" : "Nice work",
              "mode" : "mission",
              "newlyMasteredCount" : 2,
              "recommendedMissionTitle" : "Retry school words",
              "startedAt" : "2026-04-20T08:00:00Z",
              "totalQuestions" : 10,
              "weakTopics" : ["school"]
            }
          ]
        }
        """

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try legacyJSON.write(to: url, atomically: true, encoding: .utf8)

        let loaded = try LocalStore(url: url).load()
        let summary = try #require(loaded.sessions.first)

        #expect(summary.reviewWords.isEmpty)
        #expect(summary.accuracyPercent == 70)
    }

    @MainActor
    @Test func appModelBootstrapLoadsLegacyStoreWithoutDroppingSeedWords() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let legacyJSON = """
        {
          "hasCompletedPlacement" : false,
          "progressByWordID" : {
            "borrow" : {
              "currentCorrectStreak" : 0,
              "isMastered" : false,
              "reviewPriority" : 0,
              "totalCorrect" : 0,
              "totalIncorrect" : 0,
              "wordID" : "borrow"
            }
          },
          "sessions" : []
        }
        """

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try legacyJSON.write(to: url, atomically: true, encoding: .utf8)

        let model = AppModel(store: LocalStore(url: url))
        model.bootstrap()

        #expect(model.errorMessage == nil)
        #expect(model.words.count > 0)
        #expect(model.wordBankSnapshot.wordCount == model.words.count)
        #expect(model.screen == .onboarding)
        #expect(model.data.progressByWordID["borrow"]?.reviewStep == 0)
        #expect(model.data.progressByWordID["borrow"]?.nextReviewAt == nil)
    }

    @MainActor
    @Test func appModelBootstrapFallsBackToBundledWordsWhenStoreIsUnreadable() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.json")

        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{not valid json}".write(to: url, atomically: true, encoding: .utf8)

        let model = AppModel(store: LocalStore(url: url))
        model.bootstrap()

        #expect(model.words.count > 0)
        #expect(model.wordBankSnapshot.wordCount == model.words.count)
        #expect(model.screen == .onboarding)
        #expect(model.errorMessage == "Saved progress could not be loaded, so the app reopened with the built-in PET starter.")
    }

    @MainActor
    @Test func spellingTextFieldUsesNativeEditableSingleLineConfiguration() throws {
        let field = makeSpellingTextField(
            placeholder: "Type the English spelling here",
            delegate: nil
        )
        let cell = try #require(field.cell as? NSTextFieldCell)

        #expect(field.isEditable)
        #expect(field.isSelectable)
        #expect(!field.isBordered)
        #expect(!field.drawsBackground)
        #expect(field.placeholderAttributedString?.string == "Type the English spelling here")
        #expect(field.translatesAutoresizingMaskIntoConstraints == false)
        #expect(cell.usesSingleLineMode)
        #expect(!cell.wraps)
        #expect(cell.isScrollable)
    }

    @MainActor
    @Test func spellingTextFieldContainerPinsFieldToAllEdges() {
        let container = SpellingTextFieldContainer(frame: .zero)
        let field = makeSpellingTextField(placeholder: "Type", delegate: nil)

        container.install(textField: field)

        #expect(container.subviews.count == 1)
        #expect(container.textField === field)
        #expect(container.constraints.count == 4)
    }

    @MainActor
    @Test func spellingBindingSyncSkipsReverseOverwriteWhileEditing() {
        let field = makeSpellingTextField(placeholder: "Type", delegate: nil)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let host = NSView(frame: window.contentView?.bounds ?? .zero)
        host.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = host
        host.addSubview(field)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            field.topAnchor.constraint(equalTo: host.topAnchor),
            field.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])

        window.makeFirstResponder(field)

        #expect(field.currentEditor() != nil)
        #expect(shouldSyncSpellingFieldFromBinding(textField: field, bindingText: "") == false)
    }

    @MainActor
    @Test func spellingEditorTextPrefersLiveFieldEditorContent() {
        let field = makeSpellingTextField(placeholder: "Type", delegate: nil)
        let editor = NSTextView(frame: .zero)
        editor.string = "africa"

        let notification = Notification(
            name: NSControl.textDidChangeNotification,
            object: field,
            userInfo: ["NSFieldEditor": editor]
        )

        #expect(currentSpellingEditorText(textField: field, notification: notification) == "africa")
    }

    private static func sampleReadingQuestText(title: String, includeAnswers: Bool) -> String {
        let answersBlock = includeAnswers ? """

        --- ANSWERS ---

        1. B
        2. B
        3. B
        4. C
        5. B
        """ : ""

        return """
        Reading Quest: \(title)

        --- READING PASSAGE ---

        Last Tuesday, Sarah packed her luggage for a trip to a winter resort. She was confident that her new snowboard would be useful. Before leaving, she checked her smart phone to confirm the password for the lodge. The journey was long, but she felt fully prepared. Upon arrival, she walked along the pavement toward the cafeteria to grab a biscuit. Inside, she overheard a photographer making a comment about how attractive the mountain views were. Sarah hoped the weather would stay cool so she could avoid any crash on the slopes that might injure her. She wanted to maintain her good health, so she ate a healthy lunch. Later, she met a group of friends who were playing chess. They tried to convince her to join their party, but she decided to think about her homework instead. She felt smart for choosing to rest, knowing that eighty percent of successful athletes prioritize recovery. Even a tiny mistake could ruin her progress, so she decided to sleep early, ensuring she could wake up refreshed for her next adventure.

        --- QUESTIONS ---

        1. When did Sarah start her journey to the resort?
           A) On a Monday
           B) On a Tuesday
           C) On a Wednesday
           D) On a Thursday

        2. How did Sarah feel about her snowboarding trip?
           A) Nervous
           B) Confident
           C) Bored
           D) Angry

        3. Where did Sarah go when she first arrived?
           A) To the slopes
           B) To the cafeteria
           C) To her bedroom
           D) To a party

        4. What did the photographer comment on?
           A) The quality of the food
           B) The difficulty of the slopes
           C) The beauty of the mountain views
           D) The comfort of the hotel

        5. Why did Sarah choose not to join the party?
           A) She was too tired
           B) She wanted to do her homework
           C) She didn't know anyone
           D) She had to pack her luggage\(answersBlock)
        """
    }

    private static func sampleVocabularyPDFPage(pageNumber: Int, startIndex: Int, count: Int) -> String {
        let wordLines = (startIndex..<(startIndex + count)).map { index in
            "word\(index) 词\(index)"
        }
        return """
        剑桥五级-PET词汇-2020更新版词库 学习日期:
        第\(pageNumber)关
        _______
        \(wordLines.joined(separator: "\n"))
        """
    }

    @MainActor
    private static func makeReadingPDF(at url: URL, pages: [String]) throws {
        let document = PDFDocument()

        for (index, pageText) in pages.enumerated() {
            let lineCount = pageText.components(separatedBy: .newlines).count
            let pageHeight = max(900, CGFloat(lineCount) * 28)
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: pageHeight))
            textView.font = .systemFont(ofSize: 18, weight: .regular)
            textView.string = pageText
            let pageData = textView.dataWithPDF(inside: textView.bounds)
            guard let pageDocument = PDFDocument(data: pageData),
                  let page = pageDocument.page(at: 0) else {
                Issue.record("Failed to build PDF fixture page")
                return
            }
            document.insert(page, at: index)
        }

        guard document.write(to: url) else {
            Issue.record("Failed to write PDF fixture")
            return
        }
    }

    private static func sampleQuestJSONData() throws -> Data {
        let payload: [String: Any] = [
            "vocabQuestVersion": 1,
            "exportType": "quests",
            "sessions": [
                makeQuestSession(
                    id: "page-37",
                    title: "PET全_Page_37_03261514",
                    word: "director",
                    meaning: "导演",
                    meaningPrompt: "The director told the actors where to stand.",
                    meaningChoices: ["书桌", "导演", "老师", "小鸟"],
                    spellingPrompt: "导演: ___",
                    translationPrompt: "导演告诉演员们该站在哪里。",
                    translationChoices: [
                        "The director told the actors where to stand.",
                        "The teacher told the actors where to stand.",
                        "The director asked the actors to dance.",
                        "The actors told the director where to stand."
                    ],
                    example: "The director told the actors where to stand.",
                    exampleTranslation: "导演告诉演员们该站在哪里。",
                    memoryTip: "Direct-or: The person who gives direct orders to the actors!"
                ),
                makeQuestSession(
                    id: "page-38",
                    title: "PET全_Page_38_03261514",
                    word: "Australia",
                    meaning: "澳大利亚",
                    meaningPrompt: "Kangaroos are found in the wild in Australia.",
                    meaningChoices: ["澳大利亚", "导演", "老师", "小鸟"],
                    spellingPrompt: "澳大利亚: ___",
                    translationPrompt: "袋鼠生活在澳大利亚的荒野中。",
                    translationChoices: [
                        "Kangaroos are found in the wild in Australia.",
                        "Kangaroos live near the school in Australia.",
                        "Australia is full of wild birds.",
                        "I saw a kangaroo in the park."
                    ],
                    example: "Kangaroos are found in the wild in Australia.",
                    exampleTranslation: "袋鼠生活在澳大利亚的荒野中。",
                    memoryTip: "Imagine a giant ORANGE map of Australia."
                )
            ]
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func duplicateNormalizedQuestJSONData() throws -> Data {
        let payload: [String: Any] = [
            "vocabQuestVersion": 1,
            "exportType": "quests",
            "sessions": [
                makeQuestSession(
                    id: "page-37-miss",
                    title: "PET全_Page_37_03261514",
                    word: "Miss",
                    meaning: "小姐",
                    meaningPrompt: "Miss Brown is our new teacher.",
                    meaningChoices: ["老师", "小姐", "司机", "医生"],
                    spellingPrompt: "小姐: ___",
                    translationPrompt: "布朗小姐是我们的新老师。",
                    translationChoices: [
                        "Miss Brown is our new teacher.",
                        "Brown missed our new teacher.",
                        "The new teacher is late.",
                        "Our teacher likes brown bags."
                    ],
                    example: "Miss Brown is our new teacher.",
                    exampleTranslation: "布朗小姐是我们的新老师。",
                    memoryTip: "Miss with a capital M can be a title."
                ),
                makeQuestSession(
                    id: "page-38-miss",
                    title: "PET全_Page_38_03261514",
                    word: "miss",
                    meaning: "想念",
                    meaningPrompt: "I miss my family when I travel.",
                    meaningChoices: ["想念", "小姐", "司机", "医生"],
                    spellingPrompt: "想念: ___",
                    translationPrompt: "旅行时我会想念家人。",
                    translationChoices: [
                        "I miss my family when I travel.",
                        "My family misses the train.",
                        "I travel with my family.",
                        "My family likes travel."
                    ],
                    example: "I miss my family when I travel.",
                    exampleTranslation: "旅行时我会想念家人。",
                    memoryTip: "miss can also mean to feel someone is absent."
                )
            ]
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func duplicateOriginalVocabQuestJSONData() throws -> Data {
        let payload: [String: Any] = [
            "vocabQuestVersion": 1,
            "exportType": "quests",
            "sessions": [
                [
                    "id": "page-14-homework",
                    "title": "PET全_Page_14_03261514",
                    "createdAt": 1_744_558_114,
                    "category": "PET",
                    "isPassed": false,
                    "isMastered": false,
                    "wordsToReview": [],
                    "originalVocab": [
                        [
                            "id": "homework-1",
                            "word": "homework",
                            "meaning": "作业",
                            "example": "Homework helps students review after class.",
                            "exampleTranslation": "作业能帮助学生课后复习。"
                        ],
                        [
                            "id": "homework-2",
                            "word": "homework",
                            "meaning": "家庭作业",
                            "example": "She finished her homework before dinner.",
                            "exampleTranslation": "她在晚饭前完成了作业。"
                        ]
                    ],
                    "questions": [
                        makeQuestQuestion(
                            id: "page-14-homework-meaning",
                            type: "multiple_choice",
                            question: "She finished her homework before dinner.",
                            options: ["作业", "老师", "导游", "书桌"],
                            correctAnswer: "作业",
                            memoryTip: "Home-work: work you do at home after school.",
                            word: "homework",
                            meaning: "作业",
                            example: "She finished her homework before dinner.",
                            exampleTranslation: "她在晚饭前完成了作业。"
                        ),
                        makeQuestQuestion(
                            id: "page-14-homework-spelling",
                            type: "fill_in_blank",
                            question: "作业: ___",
                            options: [],
                            correctAnswer: "homework",
                            memoryTip: "Home-work: work you do at home after school.",
                            word: "homework",
                            meaning: "作业",
                            example: "She finished her homework before dinner.",
                            exampleTranslation: "她在晚饭前完成了作业。"
                        ),
                        makeQuestQuestion(
                            id: "page-14-homework-translation",
                            type: "sentence_translation",
                            question: "她在晚饭前完成了作业。",
                            options: [
                                "She finished her homework before dinner.",
                                "She forgot her homework before dinner.",
                                "Homework was ready after dinner.",
                                "Her teacher collected the homework."
                            ],
                            correctAnswer: "She finished her homework before dinner.",
                            memoryTip: "Home-work: work you do at home after school.",
                            word: "homework",
                            meaning: "作业",
                            example: "She finished her homework before dinner.",
                            exampleTranslation: "她在晚饭前完成了作业。"
                        )
                    ]
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func makeQuestSession(
        id: String,
        title: String,
        word: String,
        meaning: String,
        meaningPrompt: String,
        meaningChoices: [String],
        spellingPrompt: String,
        translationPrompt: String,
        translationChoices: [String],
        example: String,
        exampleTranslation: String,
        memoryTip: String
    ) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "createdAt": 1_744_558_114,
            "category": "PET",
            "isPassed": false,
            "isMastered": false,
            "wordsToReview": [],
            "questions": [
                makeQuestQuestion(
                    id: "\(id)-meaning",
                    type: "multiple_choice",
                    question: meaningPrompt,
                    options: meaningChoices,
                    correctAnswer: meaning,
                    memoryTip: memoryTip,
                    word: word,
                    meaning: meaning,
                    example: example,
                    exampleTranslation: exampleTranslation
                ),
                makeQuestQuestion(
                    id: "\(id)-spelling",
                    type: "fill_in_blank",
                    question: spellingPrompt,
                    options: [],
                    correctAnswer: word,
                    memoryTip: memoryTip,
                    word: word,
                    meaning: meaning,
                    example: example,
                    exampleTranslation: exampleTranslation
                ),
                makeQuestQuestion(
                    id: "\(id)-translation",
                    type: "sentence_translation",
                    question: translationPrompt,
                    options: translationChoices,
                    correctAnswer: example,
                    memoryTip: memoryTip,
                    word: word,
                    meaning: meaning,
                    example: example,
                    exampleTranslation: exampleTranslation
                )
            ]
        ]
    }

    private static func makeQuestQuestion(
        id: String,
        type: String,
        question: String,
        options: [String],
        correctAnswer: String,
        memoryTip: String,
        word: String,
        meaning: String,
        example: String,
        exampleTranslation: String
    ) -> [String: Any] {
        [
            "id": id,
            "type": type,
            "question": question,
            "options": options,
            "correctAnswer": correctAnswer,
            "explanation": "Test fixture explanation",
            "memoryTip": memoryTip,
            "word": word,
            "meaning": meaning,
            "example": example,
            "exampleTranslation": exampleTranslation
        ]
    }
}
