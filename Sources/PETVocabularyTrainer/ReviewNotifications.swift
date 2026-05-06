import Foundation
import UserNotifications

struct ReviewNotificationPlan: Hashable {
    static let identifier = "pet.review-rescue.next-due"

    let identifier: String
    let title: String
    let body: String
    let fireDate: Date

    init(
        identifier: String = Self.identifier,
        title: String,
        body: String,
        fireDate: Date
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireDate = fireDate
    }
}

enum ReviewNotificationPlanner {
    static let dueNowGraceInterval: TimeInterval = 15 * 60

    static func plan(from snapshot: ReviewReminderSnapshot, now: Date = .now) -> ReviewNotificationPlan? {
        if snapshot.dueNowCount > 0 {
            return ReviewNotificationPlan(
                title: "Review Rescue is ready",
                body: "\(snapshot.dueNowCount) PET words are due. Rescue them before starting new words.",
                fireDate: now.addingTimeInterval(dueNowGraceInterval)
            )
        }

        guard snapshot.scheduledLaterCount > 0,
              let nextReminderAt = snapshot.nextReminderAt,
              nextReminderAt > now else {
            return nil
        }

        return ReviewNotificationPlan(
            title: "Review Rescue is coming back",
            body: "\(snapshot.scheduledLaterCount) PET words are coming back. Review them while memory is still warm.",
            fireDate: nextReminderAt
        )
    }
}

@MainActor
protocol ReviewNotificationScheduling {
    func requestAuthorization() async -> Bool
    func apply(plan: ReviewNotificationPlan?) async
}

struct SystemReviewNotificationScheduler: ReviewNotificationScheduling {
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func apply(plan: ReviewNotificationPlan?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [ReviewNotificationPlan.identifier])
        guard let plan else { return }

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.userInfo = ["route": "reviewRescue"]

        let interval = max(60, plan.fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}

@MainActor
final class ReviewNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReviewNotificationRouter()

    private var openReview: (() -> Void)?

    func install(openReview: @escaping () -> Void) {
        self.openReview = openReview
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.content.userInfo["route"] as? String == "reviewRescue" else {
            return
        }

        await MainActor.run {
            self.openReview?()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
