import Foundation

enum WordTopic: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case school
    case travel
    case home
    case food
    case health
    case shopping
    case transport
    case work
    case people
    case feelings
    case places
    case actions
    case time
    case communication

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .home: return "Home"
        case .food: return "Food"
        case .health: return "Health"
        case .school: return "School"
        case .travel: return "Travel"
        case .shopping: return "Shopping"
        case .transport: return "Transport"
        case .work: return "Work"
        case .people: return "People"
        case .feelings: return "Feelings"
        case .places: return "Places"
        case .actions: return "Actions"
        case .time: return "Time"
        case .communication: return "Communication"
        }
    }
}

struct VocabularyWord: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let english: String
    let primaryChinese: String
    let topic: WordTopic
}

struct WordProgress: Codable, Hashable {
    var wordID: String
    var currentCorrectStreak: Int
    var totalCorrect: Int
    var totalIncorrect: Int
    var retryMissCount: Int
    var isMastered: Bool
    var lastSeenAt: Date?
    var lastIncorrectAt: Date?
    var lastRetryMissAt: Date?
    var reviewPriority: Int
    var reviewStep: Int = 0
    var nextReviewAt: Date? = nil

    init(
        wordID: String,
        currentCorrectStreak: Int,
        totalCorrect: Int,
        totalIncorrect: Int,
        retryMissCount: Int = 0,
        isMastered: Bool,
        lastSeenAt: Date?,
        lastIncorrectAt: Date?,
        lastRetryMissAt: Date? = nil,
        reviewPriority: Int,
        reviewStep: Int = 0,
        nextReviewAt: Date? = nil
    ) {
        self.wordID = wordID
        self.currentCorrectStreak = currentCorrectStreak
        self.totalCorrect = totalCorrect
        self.totalIncorrect = totalIncorrect
        self.retryMissCount = retryMissCount
        self.isMastered = isMastered
        self.lastSeenAt = lastSeenAt
        self.lastIncorrectAt = lastIncorrectAt
        self.lastRetryMissAt = lastRetryMissAt
        self.reviewPriority = reviewPriority
        self.reviewStep = reviewStep
        self.nextReviewAt = nextReviewAt
    }

    static func fresh(for wordID: String) -> Self {
        Self(
            wordID: wordID,
            currentCorrectStreak: 0,
            totalCorrect: 0,
            totalIncorrect: 0,
            retryMissCount: 0,
            isMastered: false,
            lastSeenAt: nil,
            lastIncorrectAt: nil,
            lastRetryMissAt: nil,
            reviewPriority: 0,
            reviewStep: 0,
            nextReviewAt: nil
        )
    }

    var totalAttempts: Int { totalCorrect + totalIncorrect }

    enum CodingKeys: String, CodingKey {
        case wordID
        case currentCorrectStreak
        case totalCorrect
        case totalIncorrect
        case retryMissCount
        case isMastered
        case lastSeenAt
        case lastIncorrectAt
        case lastRetryMissAt
        case reviewPriority
        case reviewStep
        case nextReviewAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wordID = try container.decode(String.self, forKey: .wordID)
        currentCorrectStreak = try container.decodeIfPresent(Int.self, forKey: .currentCorrectStreak) ?? 0
        totalCorrect = try container.decodeIfPresent(Int.self, forKey: .totalCorrect) ?? 0
        totalIncorrect = try container.decodeIfPresent(Int.self, forKey: .totalIncorrect) ?? 0
        retryMissCount = try container.decodeIfPresent(Int.self, forKey: .retryMissCount) ?? 0
        isMastered = try container.decodeIfPresent(Bool.self, forKey: .isMastered) ?? false
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        lastIncorrectAt = try container.decodeIfPresent(Date.self, forKey: .lastIncorrectAt)
        lastRetryMissAt = try container.decodeIfPresent(Date.self, forKey: .lastRetryMissAt)
        reviewPriority = try container.decodeIfPresent(Int.self, forKey: .reviewPriority) ?? 0
        reviewStep = try container.decodeIfPresent(Int.self, forKey: .reviewStep) ?? 0
        nextReviewAt = try container.decodeIfPresent(Date.self, forKey: .nextReviewAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wordID, forKey: .wordID)
        try container.encode(currentCorrectStreak, forKey: .currentCorrectStreak)
        try container.encode(totalCorrect, forKey: .totalCorrect)
        try container.encode(totalIncorrect, forKey: .totalIncorrect)
        try container.encode(retryMissCount, forKey: .retryMissCount)
        try container.encode(isMastered, forKey: .isMastered)
        try container.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
        try container.encodeIfPresent(lastIncorrectAt, forKey: .lastIncorrectAt)
        try container.encodeIfPresent(lastRetryMissAt, forKey: .lastRetryMissAt)
        try container.encode(reviewPriority, forKey: .reviewPriority)
        try container.encode(reviewStep, forKey: .reviewStep)
        try container.encodeIfPresent(nextReviewAt, forKey: .nextReviewAt)
    }
}

enum SessionMode: String, Codable, Hashable {
    case placement
    case mission
    case failedReview
    case readingQuest

    var title: String {
        switch self {
        case .placement: return "Placement Test"
        case .mission: return "Daily Mission"
        case .failedReview: return "Retry Failed Words"
        case .readingQuest: return "Reading Quest"
        }
    }
}

enum QuestionPresentationStyle: String, Codable, Hashable {
    case meaningChoice
    case wordExercise
}

enum WordExerciseStep: String, Codable, Hashable {
    case meaningChoice
    case spelling
    case translation
    case pronunciation
}

enum PronunciationRating: String, Codable, CaseIterable, Hashable {
    case needsPractice
    case almostThere
    case clear

    var displayTitle: String {
        switch self {
        case .needsPractice:
            return "\(heartMeter) · Not heard clearly"
        case .almostThere:
            return "\(heartMeter) · Almost heard"
        case .clear:
            return "\(heartMeter) · Heard clearly"
        }
    }

    var feedbackLabel: String {
        switch self {
        case .needsPractice:
            return "Not heard clearly"
        case .almostThere:
            return "Almost heard"
        case .clear:
            return "Heard clearly"
        }
    }

    var heartMeter: String {
        switch self {
        case .needsPractice:
            return "🤍🤍❤️"
        case .almostThere:
            return "🤍❤️❤️"
        case .clear:
            return "❤️❤️❤️"
        }
    }

    var countsAsStrong: Bool {
        self != .needsPractice
    }
}

struct AttemptRecord: Codable, Identifiable, Hashable {
    let id: String
    let sessionID: String
    let wordID: String
    let selectedChoice: String
    let correctChoice: String
    let isCorrect: Bool
    let topic: WordTopic
    let answeredAt: Date

    init(
        id: String = UUID().uuidString,
        sessionID: String,
        wordID: String,
        selectedChoice: String,
        correctChoice: String,
        isCorrect: Bool,
        topic: WordTopic,
        answeredAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.wordID = wordID
        self.selectedChoice = selectedChoice
        self.correctChoice = correctChoice
        self.isCorrect = isCorrect
        self.topic = topic
        self.answeredAt = answeredAt
    }
}

struct PersistedQuestion: Codable, Identifiable, Hashable {
    let id: String
    let wordID: String
    let choices: [String]
    let style: QuestionPresentationStyle
    let exampleSentence: String?
    let meaningPrompt: String?
    let meaningCorrectChoice: String?
    let spellingPromptText: String?
    let spellingCorrectAnswer: String?
    let translationPrompt: String?
    let translationChoices: [String]
    let translationCorrectChoice: String?
    let memoryTip: String?
    let exampleTranslation: String?
    let sourcePageNumber: Int?
    let sourcePageTitle: String?

    init(
        id: String = UUID().uuidString,
        wordID: String,
        choices: [String],
        style: QuestionPresentationStyle = .meaningChoice,
        exampleSentence: String? = nil,
        meaningPrompt: String? = nil,
        meaningCorrectChoice: String? = nil,
        spellingPromptText: String? = nil,
        spellingCorrectAnswer: String? = nil,
        translationPrompt: String? = nil,
        translationChoices: [String] = [],
        translationCorrectChoice: String? = nil,
        memoryTip: String? = nil,
        exampleTranslation: String? = nil,
        sourcePageNumber: Int? = nil,
        sourcePageTitle: String? = nil
    ) {
        self.id = id
        self.wordID = wordID
        self.choices = choices
        self.style = style
        self.exampleSentence = exampleSentence
        self.meaningPrompt = meaningPrompt
        self.meaningCorrectChoice = meaningCorrectChoice
        self.spellingPromptText = spellingPromptText
        self.spellingCorrectAnswer = spellingCorrectAnswer
        self.translationPrompt = translationPrompt
        self.translationChoices = translationChoices
        self.translationCorrectChoice = translationCorrectChoice
        self.memoryTip = memoryTip
        self.exampleTranslation = exampleTranslation
        self.sourcePageNumber = sourcePageNumber
        self.sourcePageTitle = sourcePageTitle
    }

    enum CodingKeys: String, CodingKey {
        case id
        case wordID
        case choices
        case style
        case exampleSentence
        case meaningPrompt
        case meaningCorrectChoice
        case spellingPromptText
        case spellingCorrectAnswer
        case translationPrompt
        case translationChoices
        case translationCorrectChoice
        case memoryTip
        case exampleTranslation
        case sourcePageNumber
        case sourcePageTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        wordID = try container.decode(String.self, forKey: .wordID)
        choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
        style = try container.decodeIfPresent(QuestionPresentationStyle.self, forKey: .style) ?? .meaningChoice
        exampleSentence = try container.decodeIfPresent(String.self, forKey: .exampleSentence)
        meaningPrompt = try container.decodeIfPresent(String.self, forKey: .meaningPrompt)
        meaningCorrectChoice = try container.decodeIfPresent(String.self, forKey: .meaningCorrectChoice)
        spellingPromptText = try container.decodeIfPresent(String.self, forKey: .spellingPromptText)
        spellingCorrectAnswer = try container.decodeIfPresent(String.self, forKey: .spellingCorrectAnswer)
        translationPrompt = try container.decodeIfPresent(String.self, forKey: .translationPrompt)
        translationChoices = try container.decodeIfPresent([String].self, forKey: .translationChoices) ?? []
        translationCorrectChoice = try container.decodeIfPresent(String.self, forKey: .translationCorrectChoice)
        memoryTip = try container.decodeIfPresent(String.self, forKey: .memoryTip)
        exampleTranslation = try container.decodeIfPresent(String.self, forKey: .exampleTranslation)
        sourcePageNumber = try container.decodeIfPresent(Int.self, forKey: .sourcePageNumber)
        sourcePageTitle = try container.decodeIfPresent(String.self, forKey: .sourcePageTitle)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(wordID, forKey: .wordID)
        try container.encode(choices, forKey: .choices)
        try container.encode(style, forKey: .style)
        try container.encodeIfPresent(exampleSentence, forKey: .exampleSentence)
        try container.encodeIfPresent(meaningPrompt, forKey: .meaningPrompt)
        try container.encodeIfPresent(meaningCorrectChoice, forKey: .meaningCorrectChoice)
        try container.encodeIfPresent(spellingPromptText, forKey: .spellingPromptText)
        try container.encodeIfPresent(spellingCorrectAnswer, forKey: .spellingCorrectAnswer)
        try container.encode(translationChoices, forKey: .translationChoices)
        try container.encodeIfPresent(translationPrompt, forKey: .translationPrompt)
        try container.encodeIfPresent(translationCorrectChoice, forKey: .translationCorrectChoice)
        try container.encodeIfPresent(memoryTip, forKey: .memoryTip)
        try container.encodeIfPresent(exampleTranslation, forKey: .exampleTranslation)
        try container.encodeIfPresent(sourcePageNumber, forKey: .sourcePageNumber)
        try container.encodeIfPresent(sourcePageTitle, forKey: .sourcePageTitle)
    }

    var isWordExercise: Bool {
        style == .wordExercise
    }

    var hasTranslationStep: Bool {
        !translationChoices.isEmpty && !(translationCorrectChoice?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func spellingPrompt(for word: VocabularyWord) -> String? {
        if let spellingPromptText, !spellingPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return spellingPromptText
        }

        guard let exampleSentence, !exampleSentence.isEmpty else {
            return nil
        }

        let placeholder = "____"
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let range = exampleSentence.range(of: word.english, options: options)

        guard let range else {
            return exampleSentence
        }

        var prompt = exampleSentence
        prompt.replaceSubrange(range, with: placeholder)
        return prompt
    }
}

struct ActiveSession: Codable, Hashable {
    let id: String
    let mode: SessionMode
    let startedAt: Date
    let questPageNumber: Int?
    let questPageTitle: String?
    var questions: [PersistedQuestion]
    var currentIndex: Int
    var correctAnswers: Int
    var attempts: [AttemptRecord]
    var newlyMasteredWordIDs: [String]
    var currentExerciseStep: WordExerciseStep
    var pendingMeaningChoice: String?
    var pendingMeaningWasCorrect: Bool?
    var pendingSpellingAnswer: String?
    var pendingSpellingWasCorrect: Bool?
    var pendingPronunciationRating: PronunciationRating?
    var pendingTranslationChoice: String?
    var pendingTranslationWasCorrect: Bool?

    init(
        id: String = UUID().uuidString,
        mode: SessionMode,
        startedAt: Date = .now,
        questPageNumber: Int? = nil,
        questPageTitle: String? = nil,
        questions: [PersistedQuestion],
        currentIndex: Int = 0,
        correctAnswers: Int = 0,
        attempts: [AttemptRecord] = [],
        newlyMasteredWordIDs: [String] = [],
        currentExerciseStep: WordExerciseStep = .meaningChoice,
        pendingMeaningChoice: String? = nil,
        pendingMeaningWasCorrect: Bool? = nil,
        pendingSpellingAnswer: String? = nil,
        pendingSpellingWasCorrect: Bool? = nil,
        pendingPronunciationRating: PronunciationRating? = nil,
        pendingTranslationChoice: String? = nil,
        pendingTranslationWasCorrect: Bool? = nil
    ) {
        self.id = id
        self.mode = mode
        self.startedAt = startedAt
        self.questPageNumber = questPageNumber
        self.questPageTitle = questPageTitle
        self.questions = questions
        self.currentIndex = currentIndex
        self.correctAnswers = correctAnswers
        self.attempts = attempts
        self.newlyMasteredWordIDs = newlyMasteredWordIDs
        self.currentExerciseStep = currentExerciseStep
        self.pendingMeaningChoice = pendingMeaningChoice
        self.pendingMeaningWasCorrect = pendingMeaningWasCorrect
        self.pendingSpellingAnswer = pendingSpellingAnswer
        self.pendingSpellingWasCorrect = pendingSpellingWasCorrect
        self.pendingPronunciationRating = pendingPronunciationRating
        self.pendingTranslationChoice = pendingTranslationChoice
        self.pendingTranslationWasCorrect = pendingTranslationWasCorrect
    }

    enum CodingKeys: String, CodingKey {
        case id
        case mode
        case startedAt
        case questPageNumber
        case questPageTitle
        case questions
        case currentIndex
        case correctAnswers
        case attempts
        case newlyMasteredWordIDs
        case currentExerciseStep
        case pendingMeaningChoice
        case pendingMeaningWasCorrect
        case pendingSpellingAnswer
        case pendingSpellingWasCorrect
        case pendingPronunciationRating
        case pendingTranslationChoice
        case pendingTranslationWasCorrect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        mode = try container.decode(SessionMode.self, forKey: .mode)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        questPageNumber = try container.decodeIfPresent(Int.self, forKey: .questPageNumber)
        questPageTitle = try container.decodeIfPresent(String.self, forKey: .questPageTitle)
        questions = try container.decode([PersistedQuestion].self, forKey: .questions)
        currentIndex = try container.decodeIfPresent(Int.self, forKey: .currentIndex) ?? 0
        correctAnswers = try container.decodeIfPresent(Int.self, forKey: .correctAnswers) ?? 0
        attempts = try container.decodeIfPresent([AttemptRecord].self, forKey: .attempts) ?? []
        newlyMasteredWordIDs = try container.decodeIfPresent([String].self, forKey: .newlyMasteredWordIDs) ?? []
        currentExerciseStep = try container.decodeIfPresent(WordExerciseStep.self, forKey: .currentExerciseStep) ?? .meaningChoice
        pendingMeaningChoice = try container.decodeIfPresent(String.self, forKey: .pendingMeaningChoice)
        pendingMeaningWasCorrect = try container.decodeIfPresent(Bool.self, forKey: .pendingMeaningWasCorrect)
        pendingSpellingAnswer = try container.decodeIfPresent(String.self, forKey: .pendingSpellingAnswer)
        pendingSpellingWasCorrect = try container.decodeIfPresent(Bool.self, forKey: .pendingSpellingWasCorrect)
        pendingPronunciationRating = try container.decodeIfPresent(PronunciationRating.self, forKey: .pendingPronunciationRating)
        pendingTranslationChoice = try container.decodeIfPresent(String.self, forKey: .pendingTranslationChoice)
        pendingTranslationWasCorrect = try container.decodeIfPresent(Bool.self, forKey: .pendingTranslationWasCorrect)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mode, forKey: .mode)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(questPageNumber, forKey: .questPageNumber)
        try container.encodeIfPresent(questPageTitle, forKey: .questPageTitle)
        try container.encode(questions, forKey: .questions)
        try container.encode(currentIndex, forKey: .currentIndex)
        try container.encode(correctAnswers, forKey: .correctAnswers)
        try container.encode(attempts, forKey: .attempts)
        try container.encode(newlyMasteredWordIDs, forKey: .newlyMasteredWordIDs)
        try container.encode(currentExerciseStep, forKey: .currentExerciseStep)
        try container.encodeIfPresent(pendingMeaningChoice, forKey: .pendingMeaningChoice)
        try container.encodeIfPresent(pendingMeaningWasCorrect, forKey: .pendingMeaningWasCorrect)
        try container.encodeIfPresent(pendingSpellingAnswer, forKey: .pendingSpellingAnswer)
        try container.encodeIfPresent(pendingSpellingWasCorrect, forKey: .pendingSpellingWasCorrect)
        try container.encodeIfPresent(pendingPronunciationRating, forKey: .pendingPronunciationRating)
        try container.encodeIfPresent(pendingTranslationChoice, forKey: .pendingTranslationChoice)
        try container.encodeIfPresent(pendingTranslationWasCorrect, forKey: .pendingTranslationWasCorrect)
    }
}

struct SessionSummary: Codable, Identifiable, Hashable {
    let id: String
    let mode: SessionMode
    let startedAt: Date
    let completedAt: Date
    let questPageNumber: Int?
    let questPageTitle: String?
    let totalQuestions: Int
    let correctAnswers: Int
    let newlyMasteredCount: Int
    let weakTopics: [WordTopic]
    let headline: String
    let body: String
    let recommendedMissionTitle: String
    let placementTopicInsights: [PlacementTopicInsight]?
    let reviewWords: [SessionReviewWordSnapshot]

    init(
        id: String = UUID().uuidString,
        mode: SessionMode,
        startedAt: Date,
        completedAt: Date,
        questPageNumber: Int? = nil,
        questPageTitle: String? = nil,
        totalQuestions: Int,
        correctAnswers: Int,
        newlyMasteredCount: Int,
        weakTopics: [WordTopic],
        headline: String,
        body: String,
        recommendedMissionTitle: String,
        placementTopicInsights: [PlacementTopicInsight]? = nil,
        reviewWords: [SessionReviewWordSnapshot] = []
    ) {
        self.id = id
        self.mode = mode
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.questPageNumber = questPageNumber
        self.questPageTitle = questPageTitle
        self.totalQuestions = totalQuestions
        self.correctAnswers = correctAnswers
        self.newlyMasteredCount = newlyMasteredCount
        self.weakTopics = weakTopics
        self.headline = headline
        self.body = body
        self.recommendedMissionTitle = recommendedMissionTitle
        self.placementTopicInsights = placementTopicInsights
        self.reviewWords = reviewWords
    }

    enum CodingKeys: String, CodingKey {
        case id
        case mode
        case startedAt
        case completedAt
        case questPageNumber
        case questPageTitle
        case totalQuestions
        case correctAnswers
        case newlyMasteredCount
        case weakTopics
        case headline
        case body
        case recommendedMissionTitle
        case placementTopicInsights
        case reviewWords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        mode = try container.decode(SessionMode.self, forKey: .mode)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        questPageNumber = try container.decodeIfPresent(Int.self, forKey: .questPageNumber)
        questPageTitle = try container.decodeIfPresent(String.self, forKey: .questPageTitle)
        totalQuestions = try container.decodeIfPresent(Int.self, forKey: .totalQuestions) ?? 0
        correctAnswers = try container.decodeIfPresent(Int.self, forKey: .correctAnswers) ?? 0
        newlyMasteredCount = try container.decodeIfPresent(Int.self, forKey: .newlyMasteredCount) ?? 0
        weakTopics = try container.decodeIfPresent([WordTopic].self, forKey: .weakTopics) ?? []
        headline = try container.decodeIfPresent(String.self, forKey: .headline) ?? "Session complete"
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? "Your session has been recorded locally."
        recommendedMissionTitle = try container.decodeIfPresent(String.self, forKey: .recommendedMissionTitle) ?? "Start another study block"
        placementTopicInsights = try container.decodeIfPresent([PlacementTopicInsight].self, forKey: .placementTopicInsights)
        reviewWords = try container.decodeIfPresent([SessionReviewWordSnapshot].self, forKey: .reviewWords) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mode, forKey: .mode)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(questPageNumber, forKey: .questPageNumber)
        try container.encodeIfPresent(questPageTitle, forKey: .questPageTitle)
        try container.encode(totalQuestions, forKey: .totalQuestions)
        try container.encode(correctAnswers, forKey: .correctAnswers)
        try container.encode(newlyMasteredCount, forKey: .newlyMasteredCount)
        try container.encode(weakTopics, forKey: .weakTopics)
        try container.encode(headline, forKey: .headline)
        try container.encode(body, forKey: .body)
        try container.encode(recommendedMissionTitle, forKey: .recommendedMissionTitle)
        try container.encodeIfPresent(placementTopicInsights, forKey: .placementTopicInsights)
        try container.encode(reviewWords, forKey: .reviewWords)
    }

    var accuracyPercent: Int {
        guard totalQuestions > 0 else { return 0 }
        return Int((Double(correctAnswers) / Double(totalQuestions) * 100.0).rounded())
    }

    var pointsEarned: Int {
        (correctAnswers * 10) + (newlyMasteredCount * 25)
    }

    var failedAnswers: Int {
        max(0, totalQuestions - correctAnswers)
    }

    var nextReminderAt: Date? {
        reviewWords.compactMap(\.nextReviewAt).min()
    }
}

struct TrophiesSnapshot: Hashable {
    let totalSessions: Int
    let completedTodayCount: Int
    let averageAccuracyPercent: Int
    let dueReviewCount: Int
    let dailyStreak: Int
    let totalPages: Int
    let questCompletedCount: Int
    let readingCompletedCount: Int
    let pageStatuses: [TrophiesPageStatusSnapshot]
    let memoryWords: [ReviewRescueWordSnapshot]
    let recentSessions: [SessionSummary]
}

struct TrophiesPageStatusSnapshot: Identifiable, Hashable {
    let pageNumber: Int
    let isCurrent: Bool
    let isBaseReady: Bool
    let isQuestEnhanced: Bool
    let isQuestCompleted: Bool
    let isReadingReady: Bool
    let isReadingCompleted: Bool
    let hasReviewDue: Bool

    var id: Int { pageNumber }
}

struct QuestPage: Codable, Identifiable, Hashable {
    let pageNumber: Int
    let title: String
    let questions: [PersistedQuestion]

    var id: Int { pageNumber }
    var wordCount: Int { questions.count }
}

struct ImportedWordPage: Codable, Identifiable, Hashable, Sendable {
    let pageNumber: Int
    let title: String
    let wordIDs: [String]
    let sourceFilename: String

    var id: Int { pageNumber }
    var wordCount: Int { wordIDs.count }
}

struct StudyPageReference: Identifiable, Hashable {
    let pageNumber: Int
    let title: String
    let wordCount: Int
    let isQuestEnhanced: Bool

    var id: Int { pageNumber }
}

struct PlacementTopicInsight: Codable, Hashable {
    let topic: WordTopic
    let correctAnswers: Int
    let totalQuestions: Int

    var accuracyPercent: Int {
        guard totalQuestions > 0 else { return 0 }
        return Int((Double(correctAnswers) / Double(totalQuestions) * 100.0).rounded())
    }
}

struct SessionReviewWordSnapshot: Codable, Identifiable, Hashable {
    let id: String
    let english: String
    let primaryChinese: String
    let topic: WordTopic
    let nextReviewAt: Date?
    let reviewStep: Int
    let retryMissCount: Int
    let memoryTip: String?
    let exampleSentence: String?
    let exampleTranslation: String?

    init(
        id: String = UUID().uuidString,
        english: String,
        primaryChinese: String,
        topic: WordTopic,
        nextReviewAt: Date?,
        reviewStep: Int,
        retryMissCount: Int = 0,
        memoryTip: String? = nil,
        exampleSentence: String? = nil,
        exampleTranslation: String? = nil
    ) {
        self.id = id
        self.english = english
        self.primaryChinese = primaryChinese
        self.topic = topic
        self.nextReviewAt = nextReviewAt
        self.reviewStep = reviewStep
        self.retryMissCount = retryMissCount
        self.memoryTip = memoryTip
        self.exampleSentence = exampleSentence
        self.exampleTranslation = exampleTranslation
    }

    enum CodingKeys: String, CodingKey {
        case id
        case english
        case primaryChinese
        case topic
        case nextReviewAt
        case reviewStep
        case retryMissCount
        case memoryTip
        case exampleSentence
        case exampleTranslation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        english = try container.decode(String.self, forKey: .english)
        primaryChinese = try container.decode(String.self, forKey: .primaryChinese)
        topic = try container.decode(WordTopic.self, forKey: .topic)
        nextReviewAt = try container.decodeIfPresent(Date.self, forKey: .nextReviewAt)
        reviewStep = try container.decodeIfPresent(Int.self, forKey: .reviewStep) ?? 0
        retryMissCount = try container.decodeIfPresent(Int.self, forKey: .retryMissCount) ?? 0
        memoryTip = try container.decodeIfPresent(String.self, forKey: .memoryTip)
        exampleSentence = try container.decodeIfPresent(String.self, forKey: .exampleSentence)
        exampleTranslation = try container.decodeIfPresent(String.self, forKey: .exampleTranslation)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(english, forKey: .english)
        try container.encode(primaryChinese, forKey: .primaryChinese)
        try container.encode(topic, forKey: .topic)
        try container.encodeIfPresent(nextReviewAt, forKey: .nextReviewAt)
        try container.encode(reviewStep, forKey: .reviewStep)
        try container.encode(retryMissCount, forKey: .retryMissCount)
        try container.encodeIfPresent(memoryTip, forKey: .memoryTip)
        try container.encodeIfPresent(exampleSentence, forKey: .exampleSentence)
        try container.encodeIfPresent(exampleTranslation, forKey: .exampleTranslation)
    }
}

enum ReadingSessionStage: String, Hashable {
    case questionPreview
    case passageReading
    case answering
}

struct ReadingQuestChoice: Codable, Identifiable, Hashable {
    let letter: String
    let text: String

    var id: String { letter }
}

struct ReadingQuestQuestion: Codable, Identifiable, Hashable {
    let number: Int
    let prompt: String
    let choices: [ReadingQuestChoice]
    let correctChoiceLetter: String?

    var id: Int { number }
    var isQuizReady: Bool { correctChoiceLetter != nil }
}

struct ReadingQuest: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let pageNumber: Int?
    let passage: String
    let questions: [ReadingQuestQuestion]
    let sourceFilename: String

    var questionCount: Int { questions.count }
    var isQuizReady: Bool { !questions.isEmpty && questions.allSatisfy(\.isQuizReady) }
}

struct ReviewNotificationPreferences: Codable, Hashable {
    var isEnabled: Bool = false
    var permissionDenied: Bool = false
    var lastScheduledAt: Date? = nil
}

enum ActiveWordBankMode: String, Codable, Hashable {
    case bundled
    case imported
}

struct AppStoreData: Codable, Hashable {
    var activeWordBankMode: ActiveWordBankMode = .bundled
    var hasCompletedPlacement: Bool = false
    var progressByWordID: [String: WordProgress] = [:]
    var sessions: [SessionSummary] = []
    var activeSession: ActiveSession?
    var dailyStreak: Int = 0
    var lastCompletedDayKey: String?
    var importedLibrary: WordLibraryMetadata?
    var wordPages: [ImportedWordPage] = []
    var questPages: [QuestPage] = []
    var currentQuestPageNumber: Int?
    var completedQuestPages: [Int] = []
    var completedReadingQuestPages: [Int] = []
    var readingLibrary: ReadingLibraryMetadata?
    var readingQuests: [ReadingQuest] = []
    var reviewNotificationPreferences = ReviewNotificationPreferences()

    enum CodingKeys: String, CodingKey {
        case activeWordBankMode
        case hasCompletedPlacement
        case progressByWordID
        case sessions
        case activeSession
        case dailyStreak
        case lastCompletedDayKey
        case importedLibrary
        case wordPages
        case questPages
        case currentQuestPageNumber
        case completedQuestPages
        case completedReadingQuestPages
        case readingLibrary
        case readingQuests
        case reviewNotificationPreferences
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeWordBankMode = try container.decodeIfPresent(ActiveWordBankMode.self, forKey: .activeWordBankMode) ?? .bundled
        hasCompletedPlacement = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedPlacement) ?? false
        progressByWordID = try container.decodeIfPresent([String: WordProgress].self, forKey: .progressByWordID) ?? [:]
        sessions = try container.decodeIfPresent([SessionSummary].self, forKey: .sessions) ?? []
        activeSession = try container.decodeIfPresent(ActiveSession.self, forKey: .activeSession)
        dailyStreak = try container.decodeIfPresent(Int.self, forKey: .dailyStreak) ?? 0
        lastCompletedDayKey = try container.decodeIfPresent(String.self, forKey: .lastCompletedDayKey)
        importedLibrary = try container.decodeIfPresent(WordLibraryMetadata.self, forKey: .importedLibrary)
        wordPages = try container.decodeIfPresent([ImportedWordPage].self, forKey: .wordPages) ?? []
        questPages = try container.decodeIfPresent([QuestPage].self, forKey: .questPages) ?? []
        currentQuestPageNumber = try container.decodeIfPresent(Int.self, forKey: .currentQuestPageNumber)
        completedQuestPages = try container.decodeIfPresent([Int].self, forKey: .completedQuestPages) ?? []
        completedReadingQuestPages = try container.decodeIfPresent([Int].self, forKey: .completedReadingQuestPages) ?? []
        readingLibrary = try container.decodeIfPresent(ReadingLibraryMetadata.self, forKey: .readingLibrary)
        readingQuests = try container.decodeIfPresent([ReadingQuest].self, forKey: .readingQuests) ?? []
        reviewNotificationPreferences = try container.decodeIfPresent(ReviewNotificationPreferences.self, forKey: .reviewNotificationPreferences) ?? ReviewNotificationPreferences()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeWordBankMode, forKey: .activeWordBankMode)
        try container.encode(hasCompletedPlacement, forKey: .hasCompletedPlacement)
        try container.encode(progressByWordID, forKey: .progressByWordID)
        try container.encode(sessions, forKey: .sessions)
        try container.encodeIfPresent(activeSession, forKey: .activeSession)
        try container.encode(dailyStreak, forKey: .dailyStreak)
        try container.encodeIfPresent(lastCompletedDayKey, forKey: .lastCompletedDayKey)
        try container.encodeIfPresent(importedLibrary, forKey: .importedLibrary)
        try container.encode(wordPages, forKey: .wordPages)
        try container.encode(questPages, forKey: .questPages)
        try container.encodeIfPresent(currentQuestPageNumber, forKey: .currentQuestPageNumber)
        try container.encode(completedQuestPages, forKey: .completedQuestPages)
        try container.encode(completedReadingQuestPages, forKey: .completedReadingQuestPages)
        try container.encodeIfPresent(readingLibrary, forKey: .readingLibrary)
        try container.encode(readingQuests, forKey: .readingQuests)
        try container.encode(reviewNotificationPreferences, forKey: .reviewNotificationPreferences)
    }
}

enum ImportedWordLibrarySource: String, Codable, Hashable, Sendable {
    case pdf
    case json
    case questJSON
    case csv
    case plainText

    var displayName: String {
        switch self {
        case .pdf: return "PDF"
        case .json: return "JSON"
        case .questJSON: return "Quest JSON"
        case .csv: return "CSV"
        case .plainText: return "Text"
        }
    }
}

struct WordLibraryMetadata: Codable, Hashable, Sendable {
    let name: String
    let sourceFilename: String
    let importedAt: Date
    let wordCount: Int
    let source: ImportedWordLibrarySource
}

struct ReadingLibraryMetadata: Codable, Hashable, Sendable {
    let name: String
    let importedAt: Date
    let articleCount: Int
}

struct FeedbackSummary: Hashable {
    let headline: String
    let body: String
    let weakTopics: [WordTopic]
    let recommendedMissionTitle: String
}

struct DashboardStats: Hashable {
    let masteredCount: Int
    let totalWordCount: Int
    let masteryPercent: Int
    let reviewCount: Int
    let dailyTargetWordCount: Int
    let dailyStreak: Int
    let totalPoints: Int
    let rankTitle: String
    let missionTitle: String
    let missionSubtitle: String
    let focusTopics: [WordTopic]
}

struct PlacementEstimate: Hashable {
    let estimatedVocabularySize: Int
    let benchmarkVocabularySize: Int
    let remainingToBenchmark: Int
    let placementBand: String
    let guidance: String
    let dailyGoalWords: Int
    let weeklyGoalWords: Int
}

struct PlacementStudyPlan: Hashable {
    let estimate: PlacementEstimate
    let focusTopics: [WordTopic]
    let nextWeekActions: [String]
    let topicInsights: [PlacementTopicInsight]
}

struct PersonalizedMissionPlan: Hashable {
    let title: String
    let subtitle: String
    let recommendedQuestionCount: Int
    let dueReviewCount: Int
    let freshWordCount: Int
    let focusTopics: [WordTopic]
    let rewardText: String
}

struct DailyStudySnapshot: Hashable {
    let targetWordCount: Int
    let dueReviewCount: Int
    let freshWordCount: Int
    let activeBankTitle: String
    let activeBankBadgeText: String
    let headline: String
    let subtitle: String
    let reminderText: String
    let pageLabel: String?
    let pageProgressText: String?
}

struct ReviewReminderSnapshot: Hashable {
    let dueNowCount: Int
    let scheduledLaterCount: Int
    let retryTrackedCount: Int
    let nextReminderAt: Date?
    let headline: String
    let detail: String
    let strategyText: String
}

enum HomeMissionStepKind: Hashable {
    case todayPage
    case quest
    case reading
    case reminder
    case trophies
}

enum HomeMissionStepStyle: Hashable {
    case page
    case quest
    case reading
    case reminder
    case trophies
}

struct HomeMissionStepSnapshot: Identifiable, Hashable {
    let kind: HomeMissionStepKind
    let numberText: String
    let statusText: String
    let title: String
    let detail: String
    let actionTitle: String?
    let style: HomeMissionStepStyle

    var id: HomeMissionStepKind { kind }
}

struct HomeMissionResourceSnapshot: Identifiable, Hashable {
    let id: String
    let title: String
    let valueText: String
    let detail: String
}

struct HomeMissionSnapshot: Hashable {
    let title: String
    let subtitle: String
    let currentPageLabel: String
    let currentPageCaption: String
    let importActionTitle: String
    let steps: [HomeMissionStepSnapshot]
    let benchmarkTitle: String
    let benchmarkDetail: String
    let benchmarkActionTitle: String
    let resources: [HomeMissionResourceSnapshot]
}

enum CurrentUnitWordStatus: Hashable {
    case placementNeeded
    case ready
    case completed

    var valueText: String {
        switch self {
        case .placementNeeded:
            return "Placement"
        case .ready:
            return "Ready"
        case .completed:
            return "Done"
        }
    }

    var caption: String {
        switch self {
        case .placementNeeded:
            return "Start with the 100-word baseline"
        case .ready:
            return "This unit's word quest is next"
        case .completed:
            return "The word quest for this page is done"
        }
    }
}

enum CurrentUnitReadingState: Hashable {
    case waitingForImport
    case missingForPage
    case previewOnly
    case ready
    case completed

    var valueText: String {
        switch self {
        case .waitingForImport:
            return "Waiting"
        case .missingForPage:
            return "Missing"
        case .previewOnly:
            return "Preview"
        case .ready:
            return "Ready"
        case .completed:
            return "Done"
        }
    }

    var caption: String {
        switch self {
        case .waitingForImport:
            return "Import this page's reading later"
        case .missingForPage:
            return "The current reading pack does not include this page yet"
        case .previewOnly:
            return "This page can be previewed, but not graded yet"
        case .ready:
            return "This page's reading step is ready next"
        case .completed:
            return "The reading step for this page is done"
        }
    }
}

enum CurrentUnitLayerStyle: Hashable {
    case ready
    case enhanced
    case preview
    case waiting
    case missing
    case completed
    case neutral
}

struct CurrentUnitLayerSnapshot: Identifiable, Hashable {
    let id: String
    let title: String
    let valueText: String
    let caption: String
    let style: CurrentUnitLayerStyle

    init(
        id: String,
        title: String,
        valueText: String,
        caption: String,
        style: CurrentUnitLayerStyle
    ) {
        self.id = id
        self.title = title
        self.valueText = valueText
        self.caption = caption
        self.style = style
    }
}

enum CurrentUnitPrimaryAction: Hashable {
    case startPlacement
    case startMission
    case startReadingQuest
    case openReadingHub
    case advanceToNextQuestPage
    case openTrophies
}

struct CurrentUnitSnapshot: Hashable {
    let title: String
    let subtitle: String
    let stageBadgeText: String
    let pageBadgeText: String?
    let progressText: String?
    let layerSnapshots: [CurrentUnitLayerSnapshot]
    let wordStatus: CurrentUnitWordStatus
    let readingState: CurrentUnitReadingState?
    let targetValueText: String
    let targetCaption: String
    let primaryAction: CurrentUnitPrimaryAction
    let primaryActionTitle: String
    let nextHint: String
}

struct ReadingCenterSnapshot: Hashable {
    let title: String
    let subtitle: String
    let statusLabel: String
    let articleCount: Int
    let totalPlannedArticleCount: Int
    let importHint: String
    let quizReadyCount: Int
    let previewOnlyCount: Int
}

struct QuizAnswerFeedback: Hashable {
    let selectedChoice: String
    let correctChoice: String
    let isCorrect: Bool
    let newlyMastered: Bool
    let resultingStreak: Int
    let pointsEarned: Int
    let autoAdvanceDelay: TimeInterval
    let requiresManualAdvance: Bool
    let headline: String
    let detail: String
    let correctMeaning: String
    let correctSpelling: String?
    let correctTranslation: String?
    let revealedSentence: String?
    let revealedTranslation: String?
    let meaningWasCorrect: Bool?
    let spellingWasCorrect: Bool?
    let translationWasCorrect: Bool?
    let pronunciationRating: PronunciationRating?
    let memoryTip: String?
}

struct WordBankSnapshot: Hashable {
    let title: String
    let subtitle: String
    let wordCount: Int
    let badgeText: String
    let isImportedActive: Bool
    let hasSavedImport: Bool
    let savedImportTitle: String?
    let progressText: String?
}

enum ImportLaneKind: Hashable {
    case base
    case quest
    case reading
}

struct ImportLaneSnapshot: Identifiable, Hashable {
    let kind: ImportLaneKind
    let title: String
    let statusText: String
    let detail: String
    let actionTitle: String

    var id: ImportLaneKind { kind }
}

struct ImportPreviewSnapshot: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let tags: [String]
}

struct QuestPagePreviewSnapshot: Hashable {
    let title: String
    let summary: String
    let previewText: String
    let tags: [String]
}

struct StudyTrackSnapshot: Identifiable, Hashable {
    let id: String
    let title: String
    let statusText: String
    let detail: String
    let primaryActionTitle: String
}

struct ActiveReadingSession: Hashable {
    let id: String
    let questID: String
    let questTitle: String
    let pageNumber: Int?
    let passage: String
    let questions: [ReadingQuestQuestion]
    let isPreviewOnly: Bool
    let startedAt: Date
    var stage: ReadingSessionStage
    var currentIndex: Int
    var correctAnswers: Int
    var selectedChoicesByQuestionNumber: [Int: String]

    init(
        id: String = UUID().uuidString,
        questID: String,
        questTitle: String,
        pageNumber: Int?,
        passage: String,
        questions: [ReadingQuestQuestion],
        isPreviewOnly: Bool,
        startedAt: Date = .now,
        stage: ReadingSessionStage = .questionPreview,
        currentIndex: Int = 0,
        correctAnswers: Int = 0,
        selectedChoicesByQuestionNumber: [Int: String] = [:]
    ) {
        self.id = id
        self.questID = questID
        self.questTitle = questTitle
        self.pageNumber = pageNumber
        self.passage = passage
        self.questions = questions
        self.isPreviewOnly = isPreviewOnly
        self.startedAt = startedAt
        self.stage = stage
        self.currentIndex = currentIndex
        self.correctAnswers = correctAnswers
        self.selectedChoicesByQuestionNumber = selectedChoicesByQuestionNumber
    }
}

struct ReadingAnswerFeedback: Hashable {
    let selectedLetter: String
    let correctLetter: String?
    let isCorrect: Bool?
    let selectedText: String
    let correctText: String?
    let headline: String
    let detail: String
}
