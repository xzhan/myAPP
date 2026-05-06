# Review Rescue Local Notifications Design

## Goal

Turn Review Rescue from a long accumulated word list into a small daily rescue mission, then optionally remind the learner with macOS local notifications when review words become due.

## Non-Negotiable Data Safety

- Do not delete or overwrite imported Base, Quest, or Reading data.
- Do not delete or rewrite trophies, session history, word progress, or review schedule data.
- New persisted fields must decode safely from older `store.json` files.
- Packaging must use `INCLUDE_INITIAL_DATA=0 ./scripts/package-macos-app.sh` and verify `store.json` plus `imported_words.json` timestamps before and after.

## Product Design

Review Rescue will show three buckets:

- `Due Now`: words whose `nextReviewAt` is due or whose review priority makes them immediate. This is the only expanded bucket and the source for the primary `Start Rescue` action.
- `Coming Soon`: scheduled words returning in the next 24 hours.
- `Backlog`: scheduled weak words farther out than 24 hours. It is summarized by default so students are not overwhelmed.

Each word card explains why the word came back: spelling, pronunciation, meaning, translation, or general retry. The current memory stage is shown as a five-step path: `10 min`, `1 day`, `2 days`, `4 days`, `7 days`.

## Local Notification Design

Use macOS `UserNotifications` for a single digest reminder. The app does not create one notification per word.

- Notification permission is requested only when the learner/parent enables reminders.
- The app stores a small notification preference in `AppStoreData`.
- The scheduler removes the old pending request and schedules one new request with a stable identifier.
- If words are due now, schedule a gentle follow-up in 15 minutes.
- If no words are due but the next review has a future `nextReviewAt`, schedule the notification for that time.
- If no review words are scheduled, cancel the pending request.
- Tapping the notification opens Review Rescue.

## Components

- `ReviewRescuePlanner`: pure planner that converts review word progress into bucket snapshots and memory stages.
- `ReviewNotificationScheduler`: wrapper around `UNUserNotificationCenter`.
- `ReviewNotificationPlan`: pure notification digest model for tests.
- `AppModel`: exposes `reviewRescueSnapshot`, persists notification preference, and refreshes notification schedule after saved state changes.
- `ReviewView`: renders the Due Now mission, memory curve cards, Coming Soon summary, Backlog summary, and notification enable/disable control.

## Testing

- Bucket planning separates due, coming soon, and backlog words without mutating progress.
- Memory curve snapshot highlights the current review step.
- Notification plan returns a 15-minute digest when words are due now.
- Notification plan returns the earliest future date when no words are due.
- Legacy `AppStoreData` loads with notifications disabled.
- Enabling notifications with a fake scheduler stores the preference and schedules a plan.
