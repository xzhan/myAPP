import Foundation

enum WordTopic: String, Codable, CaseIterable, Identifiable, Hashable {
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

struct VocabularyWord: Codable, Identifiable, Hashable {
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
    var isMastered: Bool
    var lastSeenAt: Date?
    var lastIncorrectAt: Date?
    var reviewPriority: Int

    static func fresh(for wordID: String) -> Self {
        Self(
            wordID: wordID,
            currentCorrectStreak: 0,
            totalCorrect: 0,
            totalIncorrect: 0,
            isMastered: false,
            lastSeenAt: nil,
            lastIncorrectAt: nil,
            reviewPriority: 0
        )
    }

    var totalAttempts: Int { totalCorrect + totalIncorrect }
}

enum SessionMode: String, Codable, Hashable {
    case placement
    case mission
    case failedReview

    var title: String {
        switch self {
        case .placement: return "Placement Test"
        case .mission: return "Daily Mission"
        case .failedReview: return "Retry Failed Words"
        }
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

    init(id: String = UUID().uuidString, wordID: String, choices: [String]) {
        self.id = id
        self.wordID = wordID
        self.choices = choices
    }
}

struct ActiveSession: Codable, Hashable {
    let id: String
    let mode: SessionMode
    let startedAt: Date
    var questions: [PersistedQuestion]
    var currentIndex: Int
    var correctAnswers: Int
    var attempts: [AttemptRecord]
    var newlyMasteredWordIDs: [String]

    init(
        id: String = UUID().uuidString,
        mode: SessionMode,
        startedAt: Date = .now,
        questions: [PersistedQuestion],
        currentIndex: Int = 0,
        correctAnswers: Int = 0,
        attempts: [AttemptRecord] = [],
        newlyMasteredWordIDs: [String] = []
    ) {
        self.id = id
        self.mode = mode
        self.startedAt = startedAt
        self.questions = questions
        self.currentIndex = currentIndex
        self.correctAnswers = correctAnswers
        self.attempts = attempts
        self.newlyMasteredWordIDs = newlyMasteredWordIDs
    }
}

struct SessionSummary: Codable, Identifiable, Hashable {
    let id: String
    let mode: SessionMode
    let startedAt: Date
    let completedAt: Date
    let totalQuestions: Int
    let correctAnswers: Int
    let newlyMasteredCount: Int
    let weakTopics: [WordTopic]
    let headline: String
    let body: String
    let recommendedMissionTitle: String

    init(
        id: String = UUID().uuidString,
        mode: SessionMode,
        startedAt: Date,
        completedAt: Date,
        totalQuestions: Int,
        correctAnswers: Int,
        newlyMasteredCount: Int,
        weakTopics: [WordTopic],
        headline: String,
        body: String,
        recommendedMissionTitle: String
    ) {
        self.id = id
        self.mode = mode
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.totalQuestions = totalQuestions
        self.correctAnswers = correctAnswers
        self.newlyMasteredCount = newlyMasteredCount
        self.weakTopics = weakTopics
        self.headline = headline
        self.body = body
        self.recommendedMissionTitle = recommendedMissionTitle
    }

    var accuracyPercent: Int {
        guard totalQuestions > 0 else { return 0 }
        return Int((Double(correctAnswers) / Double(totalQuestions)) * 100.0)
    }

    var pointsEarned: Int {
        (correctAnswers * 10) + (newlyMasteredCount * 25)
    }
}

struct AppStoreData: Codable, Hashable {
    var hasCompletedPlacement: Bool = false
    var progressByWordID: [String: WordProgress] = [:]
    var sessions: [SessionSummary] = []
    var activeSession: ActiveSession?
    var dailyStreak: Int = 0
    var lastCompletedDayKey: String?
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
    let dailyStreak: Int
    let totalPoints: Int
    let rankTitle: String
    let missionTitle: String
    let missionSubtitle: String
    let focusTopics: [WordTopic]
}
