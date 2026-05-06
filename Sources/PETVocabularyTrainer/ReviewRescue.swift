import Foundation

enum ReviewRescueBucketKind: Hashable {
    case dueNow
    case comingSoon
    case backlog
}

struct ReviewRescueWordContext: Hashable {
    let exampleSentence: String?
    let exampleTranslation: String?
}

struct ReviewRescueWordSnapshot: Identifiable, Hashable {
    let id: String
    let english: String
    let primaryChinese: String
    let topic: WordTopic
    let reminderCaption: String
    let stageLabel: String
    let stageIndex: Int
    let stageCount: Int
    let weakPointText: String
    let memoryTip: String?
    let isDueNow: Bool
    let exampleSentence: String?
    let exampleTranslation: String?

    var quickListenTitle: String {
        "Play word"
    }
}

struct ReviewRescueBucketSnapshot: Identifiable, Hashable {
    let kind: ReviewRescueBucketKind
    let title: String
    let subtitle: String
    let count: Int
    let words: [ReviewRescueWordSnapshot]
    let isExpanded: Bool

    var id: ReviewRescueBucketKind { kind }
    var isEmpty: Bool { words.isEmpty }
}

struct ReviewRescueSnapshot: Hashable {
    let dueNow: ReviewRescueBucketSnapshot
    let comingSoon: ReviewRescueBucketSnapshot
    let backlog: ReviewRescueBucketSnapshot
    let primaryActionTitle: String
    let headline: String
    let detail: String
    let currentSprintCount: Int
    let waitingDueCount: Int
    let rescuePackTitle: String
    let rescuePackDetail: String

    var totalCount: Int {
        dueNow.count + comingSoon.count + backlog.count
    }
}

enum ReviewRescuePlanner {
    static let rescueSprintSize = 5
    static let comingSoonWindow: TimeInterval = 24 * 60 * 60

    static func snapshot(
        from items: [(word: VocabularyWord, progress: WordProgress)],
        memoryTipProvider: (String) -> String?,
        contextProvider: (String) -> ReviewRescueWordContext? = { _ in nil },
        now: Date = .now
    ) -> ReviewRescueSnapshot {
        let sortedItems = sort(items, now: now)
        let dueItems = sortedItems.filter { ReviewScheduler.isDue($0.progress, now: now) }
        let comingSoonItems = sortedItems.filter { item in
            guard !ReviewScheduler.isDue(item.progress, now: now),
                  let nextReviewAt = item.progress.nextReviewAt else {
                return false
            }
            return nextReviewAt <= now.addingTimeInterval(comingSoonWindow)
        }
        let backlogItems = sortedItems.filter { item in
            !ReviewScheduler.isDue(item.progress, now: now)
                && !comingSoonItems.contains(where: { $0.word.id == item.word.id })
        }

        let dueWords = dueItems.map { wordSnapshot(from: $0, memoryTipProvider: memoryTipProvider, contextProvider: contextProvider, now: now) }
        let comingSoonWords = comingSoonItems.map { wordSnapshot(from: $0, memoryTipProvider: memoryTipProvider, contextProvider: contextProvider, now: now) }
        let backlogWords = backlogItems.map { wordSnapshot(from: $0, memoryTipProvider: memoryTipProvider, contextProvider: contextProvider, now: now) }
        let dueCount = dueWords.count
        let currentSprintCount = min(dueCount, rescueSprintSize)
        let waitingDueCount = max(0, dueCount - currentSprintCount)

        return ReviewRescueSnapshot(
            dueNow: ReviewRescueBucketSnapshot(
                kind: .dueNow,
                title: "Due now",
                subtitle: dueCount == 0 ? "Nothing urgent. The rescue queue is calm." : "Start here before adding new PET words.",
                count: dueCount,
                words: dueWords,
                isExpanded: true
            ),
            comingSoon: ReviewRescueBucketSnapshot(
                kind: .comingSoon,
                title: "Coming soon",
                subtitle: "Words scheduled in the next 24 hours.",
                count: comingSoonWords.count,
                words: comingSoonWords,
                isExpanded: dueCount == 0
            ),
            backlog: ReviewRescueBucketSnapshot(
                kind: .backlog,
                title: "Memory path",
                subtitle: "Later Ebbinghaus steps are waiting quietly.",
                count: backlogWords.count,
                words: backlogWords,
                isExpanded: false
            ),
            primaryActionTitle: primaryActionTitle(forSprintCount: currentSprintCount),
            headline: headline(forDueCount: dueCount, totalCount: sortedItems.count),
            detail: detail(forDueCount: dueCount, totalCount: sortedItems.count),
            currentSprintCount: currentSprintCount,
            waitingDueCount: waitingDueCount,
            rescuePackTitle: rescuePackTitle(forSprintCount: currentSprintCount),
            rescuePackDetail: rescuePackDetail(waitingDueCount: waitingDueCount, totalDueCount: dueCount)
        )
    }

    private static func wordSnapshot(
        from item: (word: VocabularyWord, progress: WordProgress),
        memoryTipProvider: (String) -> String?,
        contextProvider: (String) -> ReviewRescueWordContext?,
        now: Date
    ) -> ReviewRescueWordSnapshot {
        let context = contextProvider(item.word.id)
        return ReviewRescueWordSnapshot(
            id: item.word.id,
            english: item.word.english,
            primaryChinese: item.word.primaryChinese,
            topic: item.word.topic,
            reminderCaption: ReviewScheduler.reminderCaption(for: item.progress, now: now),
            stageLabel: ReviewScheduler.stageLabel(forStep: item.progress.reviewStep),
            stageIndex: min(max(item.progress.reviewStep, 0), ReviewScheduler.spacedIntervals.count - 1),
            stageCount: ReviewScheduler.spacedIntervals.count,
            weakPointText: weakPointText(for: item.progress),
            memoryTip: memoryTipProvider(item.word.id),
            isDueNow: ReviewScheduler.isDue(item.progress, now: now),
            exampleSentence: context?.exampleSentence,
            exampleTranslation: context?.exampleTranslation
        )
    }

    private static func sort(
        _ items: [(word: VocabularyWord, progress: WordProgress)],
        now: Date
    ) -> [(word: VocabularyWord, progress: WordProgress)] {
        items.sorted { lhs, rhs in
            let leftDue = ReviewScheduler.isDue(lhs.progress, now: now)
            let rightDue = ReviewScheduler.isDue(rhs.progress, now: now)
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

            return lhs.word.english.localizedCaseInsensitiveCompare(rhs.word.english) == .orderedAscending
        }
    }

    private static func weakPointText(for progress: WordProgress) -> String {
        if progress.retryMissCount > 0 {
            return "Spelling retry"
        }

        if progress.totalIncorrect > 0 {
            return "Missed answer"
        }

        return "Scheduled review"
    }

    private static func primaryActionTitle(forSprintCount sprintCount: Int) -> String {
        if sprintCount == 1 {
            return "START 1-WORD RESCUE"
        }

        if sprintCount > 1 {
            return "START \(sprintCount)-WORD RESCUE"
        }

        return "START REVIEW RESCUE"
    }

    private static func rescuePackTitle(forSprintCount sprintCount: Int) -> String {
        if sprintCount == 1 {
            return "1 word needs rescue now"
        }

        if sprintCount > 1 {
            return "\(sprintCount) words need rescue now"
        }

        return "No rescue sprint needed"
    }

    private static func rescuePackDetail(waitingDueCount: Int, totalDueCount: Int) -> String {
        if totalDueCount == 0 {
            return "No due words are waiting. Start today's quest when you are ready."
        }

        if waitingDueCount > 0 {
            return "\(waitingDueCount) more are safely waiting. Finish this small sprint, then choose another rescue round or start today's quest."
        }

        return "This is a small warm-up sprint. Clear it, then start today's quest with a warmer memory."
    }

    private static func headline(forDueCount dueCount: Int, totalCount: Int) -> String {
        if dueCount > 0 {
            return "\(dueCount) words need rescue now"
        }

        if totalCount > 0 {
            return "All reminders are scheduled"
        }

        return "No rescue words right now"
    }

    private static func detail(forDueCount dueCount: Int, totalCount: Int) -> String {
        if dueCount > 0 {
            return "Clear these first, then continue the daily quest with a warmer memory path."
        }

        if totalCount > 0 {
            return "Nothing is overdue. Keep the reminder curve visible so the learner knows what is coming back."
        }

        return "Missed spelling, meaning, pronunciation, or translation items will appear here automatically."
    }
}
