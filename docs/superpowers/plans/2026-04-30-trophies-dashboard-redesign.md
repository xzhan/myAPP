# Trophies Dashboard Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Trophies from a simple session list into a learner-friendly dashboard with overview metrics, Page 1-66 progress, practice history, memory-curve words, and clear next actions.

**Architecture:** Add a read-only `TrophiesSnapshot` derived from existing `AppStoreData`, `SessionSummary`, quest pages, reading pages, and review rescue data. Keep persistence unchanged so imported data and history records remain compatible and safe.

**Tech Stack:** Swift, SwiftUI, Swift Testing, existing PETVocabularyTrainer local JSON store.

---

### Task 1: Add Trophies Snapshot

**Files:**
- Modify: `Sources/PETVocabularyTrainer/Models.swift`
- Modify: `Sources/PETVocabularyTrainer/AppModel.swift`
- Test: `Tests/PETVocabularyTrainerTests/PETVocabularyTrainerTests.swift`

- [ ] **Step 1: Write the failing test**

Add `@MainActor @Test func trophiesSnapshotSummarizesOverviewPageMapAndMemoryPath()` to `PETVocabularyTrainerTests.swift`. The test should create an `AppModel`, seed two words, two page layers, completed Quest/Reading page data, two sessions, and one due review word. Assert:

```swift
let snapshot = model.trophiesSnapshot
#expect(snapshot.totalSessions == 2)
#expect(snapshot.completedTodayCount == 1)
#expect(snapshot.averageAccuracyPercent == 75)
#expect(snapshot.dueReviewCount == 1)
#expect(snapshot.dailyStreak == 4)
#expect(snapshot.questCompletedCount == 1)
#expect(snapshot.readingCompletedCount == 1)
#expect(snapshot.pageStatuses.first(where: { $0.pageNumber == 14 })?.isCurrent == true)
#expect(snapshot.pageStatuses.first(where: { $0.pageNumber == 14 })?.isQuestEnhanced == true)
#expect(snapshot.pageStatuses.first(where: { $0.pageNumber == 14 })?.isQuestCompleted == true)
#expect(snapshot.pageStatuses.first(where: { $0.pageNumber == 14 })?.isReadingCompleted == true)
#expect(snapshot.pageStatuses.first(where: { $0.pageNumber == 14 })?.hasReviewDue == true)
#expect(snapshot.memoryWords.first?.english == "borrow")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter trophiesSnapshotSummarizesOverviewPageMapAndMemoryPath
```

Expected: FAIL because `trophiesSnapshot` and related snapshot types do not exist yet.

- [ ] **Step 3: Add snapshot models**

Add non-Codable, read-only UI snapshot structs to `Models.swift`:

```swift
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
```

- [ ] **Step 4: Implement `AppModel.trophiesSnapshot`**

In `AppModel.swift`, derive the snapshot without mutating `data`:

```swift
var trophiesSnapshot: TrophiesSnapshot {
    let pageStatuses = trophiesPageStatuses
    let sessions = sessionHistory
    let completedTodayCount = sessions.filter { Calendar.current.isDateInToday($0.completedAt) }.count
    let averageAccuracy = sessions.isEmpty ? 0 : Int((Double(sessions.map(\.accuracyPercent).reduce(0, +)) / Double(sessions.count)).rounded())
    let rescueSnapshot = reviewRescueSnapshot

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
```

Add helpers to derive page status and due-review page numbers from existing word/page mappings.

- [ ] **Step 5: Run targeted test to verify it passes**

Run:

```bash
swift test --filter trophiesSnapshotSummarizesOverviewPageMapAndMemoryPath
```

Expected: PASS.

### Task 2: Redesign Trophies UI

**Files:**
- Modify: `Sources/PETVocabularyTrainer/PETVocabularyTrainerApp.swift`

- [ ] **Step 1: Replace `TrophiesView` layout**

Use `model.trophiesSnapshot` and render:

```swift
TrophyMetricStrip(snapshot: snapshot)
TrophyPageMapCard(snapshot: snapshot)
TrophyMemoryPathCard(snapshot: snapshot)
TrophyHistoryList(sessions: snapshot.recentSessions)
TrophyActionRow(...)
```

Keep empty-state handling for no sessions, but still show page map and review actions when imported/review data exists.

- [ ] **Step 2: Add compact helper views**

Add local SwiftUI helper views near `TrophiesView`:

```swift
struct TrophyMetricStrip: View { ... }
struct TrophyOverviewMetricCard: View { ... }
struct TrophyPageMapCard: View { ... }
struct TrophyPageCell: View { ... }
struct TrophyMemoryPathCard: View { ... }
struct TrophyHistoryList: View { ... }
struct TrophyActionRow: View { ... }
```

Use existing `SurfaceCard`, `MetricTile`, `PillLabel`, `HeroButtonStyle`, and palette tokens.

- [ ] **Step 3: Build to catch SwiftUI issues**

Run:

```bash
swift build
```

Expected: PASS.

### Task 3: Verification And Packaging

**Files:**
- No source files beyond Tasks 1-2.

- [ ] **Step 1: Run full tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Package without overwriting user data**

Run:

```bash
INCLUDE_INITIAL_DATA=0 ./scripts/package-macos-app.sh
```

Expected: package completes and backs up existing user store/import data under `dist/data-backups/<timestamp>/`.

- [ ] **Step 3: Verify packaged artifact**

Run:

```bash
codesign --verify --deep --strict dist/PETVocabularyTrainer.app
unzip -t dist/PETVocabularyTrainer-macOS.zip
mkdir -p downloads
cp dist/PETVocabularyTrainer-macOS.zip downloads/PETVocabularyTrainer-macOS.zip
```

Expected: all verification commands pass and the downloads zip is refreshed.

---

## Self-Review

Spec coverage: The plan covers the approved Trophies IA: overview, page map, practice history, memory curve words, and actions. It explicitly preserves imported/history data by deriving from existing fields only.

Placeholder scan: No TBD placeholders remain.

Type consistency: Snapshot names are introduced in Task 1 and reused by UI in Task 2.
