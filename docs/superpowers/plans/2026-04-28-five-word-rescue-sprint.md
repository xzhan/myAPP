# Five-Word Rescue Sprint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make large Review Rescue backlogs feel small by presenting only a 5-word sprint while keeping the full due count visible as safely waiting.

**Architecture:** Add sprint metadata to `ReviewRescueSnapshot`, keep the full due bucket for priority sorting, and make `AppModel.startFailedReview()` start only the sprint-sized pack. The UI uses the new metadata for reassuring copy and limits visible due cards to the current pack.

**Tech Stack:** Swift, SwiftUI, Swift Testing, existing `ReviewScheduler`, `ReviewRescuePlanner`, and `SessionPlanner.failedReviewQuestions`.

---

### Task 1: Planner Sprint Metadata

**Files:**
- Modify: `Sources/PETVocabularyTrainer/ReviewRescue.swift`
- Test: `Tests/PETVocabularyTrainerTests/PETVocabularyTrainerTests.swift`

- [ ] **Step 1: Write failing planner test**

Add a test that creates 8 due words and expects:
- `dueNow.count == 8`
- `currentSprintCount == 5`
- `waitingDueCount == 3`
- `primaryActionTitle == "START 5-WORD RESCUE"`
- friendly headline/detail copy.

- [ ] **Step 2: Run focused test**

Run: `swift test --filter reviewRescuePlannerTurnsLargeDueBacklogIntoFiveWordSprint`

Expected: compile failure because sprint metadata does not exist yet.

- [ ] **Step 3: Implement metadata**

Add `ReviewRescuePlanner.rescueSprintSize = 5` and snapshot fields for `currentSprintCount`, `waitingDueCount`, `rescuePackTitle`, and `rescuePackDetail`.

- [ ] **Step 4: Run focused test**

Run: `swift test --filter reviewRescuePlannerTurnsLargeDueBacklogIntoFiveWordSprint`

Expected: pass.

### Task 2: AppModel Starts Only One Sprint

**Files:**
- Modify: `Sources/PETVocabularyTrainer/AppModel.swift`
- Test: `Tests/PETVocabularyTrainerTests/PETVocabularyTrainerTests.swift`

- [ ] **Step 1: Write failing AppModel test**

Add a test with 8 due review words, call `startFailedReview()`, and assert the active failed-review session has 5 questions.

- [ ] **Step 2: Run focused test**

Run: `swift test --filter appModelStartsOnlyFiveDueWordsForReviewRescue`

Expected: fail because `startFailedReview()` currently requests 10 questions.

- [ ] **Step 3: Implement count change**

Change `startFailedReview()` to call `SessionPlanner.failedReviewQuestions(..., count: ReviewRescuePlanner.rescueSprintSize)`.

- [ ] **Step 4: Run focused test**

Run: `swift test --filter appModelStartsOnlyFiveDueWordsForReviewRescue`

Expected: pass.

### Task 3: Review Rescue UI Copy

**Files:**
- Modify: `Sources/PETVocabularyTrainer/PETVocabularyTrainerApp.swift`

- [ ] **Step 1: Update mission card**

Show `rescuePackTitle` and `rescuePackDetail` as the main message, with wording like “5 words need rescue now” and “30 more are safely waiting.”

- [ ] **Step 2: Limit due bucket cards**

In the due-now bucket, show only the sprint words and a hidden-count message. Keep coming-soon/backlog compact.

- [ ] **Step 3: Run full tests**

Run: `swift test`

Expected: all tests pass.

### Task 4: Data-Safe Package

**Files:**
- Output: `dist/PETVocabularyTrainer.app`
- Output: `downloads/PETVocabularyTrainer-macOS.zip`

- [ ] **Step 1: Snapshot data metadata**

Capture `store.json` and `imported_words.json` timestamps and sizes before packaging.

- [ ] **Step 2: Package without embedding local data**

Run: `INCLUDE_INITIAL_DATA=0 ./scripts/package-macos-app.sh`

- [ ] **Step 3: Verify data unchanged**

Compare before/after metadata for:
- `~/Library/Application Support/PETVocabularyTrainer/store.json`
- `~/Library/Application Support/PETVocabularyTrainer/imported_words.json`

- [ ] **Step 4: Verify app and zip**

Run `codesign --verify --deep --strict --verbose=2 dist/PETVocabularyTrainer.app` and `unzip -t downloads/PETVocabularyTrainer-macOS.zip`.
