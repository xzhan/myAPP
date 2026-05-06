# Review Rescue Local Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a student-friendly Review Rescue dashboard with due/soon/backlog buckets and optional macOS local notification reminders.

**Architecture:** Add pure planner models for Review Rescue and notification plans, then connect them through `AppModel` and SwiftUI. Persist only notification preferences as additive fields so existing import/history data remains safe.

**Tech Stack:** Swift 6.1, SwiftUI, Observation, UserNotifications, Swift Testing.

---

### Task 1: Planner and Notification Tests

**Files:**
- Modify: `Tests/PETVocabularyTrainerTests/PETVocabularyTrainerTests.swift`

- [ ] **Step 1: Write failing tests for rescue buckets and notification plans**

Add tests that create due, soon, and later `WordProgress` values, then expect `ReviewRescuePlanner.snapshot` to split them into `Due Now`, `Coming Soon`, and `Backlog`. Add notification plan tests for due-now and future-review cases.

- [ ] **Step 2: Run focused tests**

Run: `swift test --filter reviewRescue`

Expected: FAIL because `ReviewRescuePlanner` and `ReviewNotificationPlanner` do not exist yet.

### Task 2: Pure Models and Scheduler

**Files:**
- Create: `Sources/PETVocabularyTrainer/ReviewRescue.swift`
- Create: `Sources/PETVocabularyTrainer/ReviewNotifications.swift`
- Modify: `Sources/PETVocabularyTrainer/Models.swift`

- [ ] **Step 1: Implement rescue snapshot models**

Create bucket and word snapshot models with no persistence side effects.

- [ ] **Step 2: Implement notification plan models**

Create `ReviewNotificationPlan`, `ReviewNotificationPlanner`, `ReviewNotificationScheduling`, and `SystemReviewNotificationScheduler`.

- [ ] **Step 3: Add safe persisted notification preferences**

Add `ReviewNotificationPreferences` to `AppStoreData` with default decode behavior.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter reviewRescue`

Expected: PASS.

### Task 3: AppModel Integration

**Files:**
- Modify: `Sources/PETVocabularyTrainer/AppModel.swift`
- Modify: `Tests/PETVocabularyTrainerTests/PETVocabularyTrainerTests.swift`

- [ ] **Step 1: Add fake scheduler tests**

Test that enabling notifications stores the preference and schedules a digest plan through an injected scheduler. Test disabling cancels the plan.

- [ ] **Step 2: Add scheduler injection and public actions**

Add an `AppModel` initializer parameter for `ReviewNotificationScheduling`, expose `reviewRescueSnapshot`, `enableReviewNotifications()`, `disableReviewNotifications()`, and refresh scheduling after persistence.

- [ ] **Step 3: Run AppModel-focused tests**

Run: `swift test --filter reviewNotification`

Expected: PASS.

### Task 4: SwiftUI Review Rescue UI

**Files:**
- Modify: `Sources/PETVocabularyTrainer/PETVocabularyTrainerApp.swift`

- [ ] **Step 1: Render the approved mock**

Update `ReviewView` to show Due Now expanded, Coming Soon summarized, Backlog summarized, memory curve stages, and a notification enable/disable control.

- [ ] **Step 2: Add notification tap routing**

Install a `UNUserNotificationCenterDelegate` that opens Review Rescue when the digest notification is clicked.

- [ ] **Step 3: Build**

Run: `swift build`

Expected: PASS.

### Task 5: Verification and Packaging

**Files:**
- No production file changes unless verification exposes a defect.

- [ ] **Step 1: Run full tests**

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 2: Capture live data timestamps**

Run: `stat -f '%m %z %N' "$HOME/Library/Application Support/PETVocabularyTrainer/store.json" "$HOME/Library/Application Support/PETVocabularyTrainer/imported_words.json"`

- [ ] **Step 3: Package without initial data**

Run: `INCLUDE_INITIAL_DATA=0 ./scripts/package-macos-app.sh`

Expected: package succeeds and reports no initial import data embedded.

- [ ] **Step 4: Verify code signature and data timestamps**

Run: `codesign --verify --deep --strict --verbose=2 dist/PETVocabularyTrainer.app`

Run the timestamp `stat` command again and confirm both files match Step 2.
