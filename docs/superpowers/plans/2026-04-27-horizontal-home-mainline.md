# Horizontal Home Mainline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stacked home cards with a horizontal PET mission-map mainline while preserving imported resources, trophies, and review data.

**Architecture:** Add a read-only `HomeMissionSnapshot` derived from existing `AppModel` state. Update `ThreeFunctionsHomeView` to render that snapshot as a horizontal route: Today Page, Quest, Reading, Reminder, Trophies. Keep Import as secondary resource management and Vocabulary Assessment as a separate benchmark panel.

**Tech Stack:** Swift 6.3, SwiftUI, Swift Testing, existing `AppModel` and `LocalStore`.

---

### Task 1: Add Tested Home Snapshot

**Files:**
- Modify: `Sources/PETVocabularyTrainer/Models.swift`
- Modify: `Sources/PETVocabularyTrainer/AppModel.swift`
- Test: `Tests/PETVocabularyTrainerTests/PETVocabularyTrainerTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that expect `model.homeMissionSnapshot.steps.map(\.kind)` to equal `[.todayPage, .quest, .reading, .reminder, .trophies]`, expect the selected page label to show `P14`, and expect resource counts to remain summaries only.

- [ ] **Step 2: Run targeted tests and verify failure**

Run: `swift test --filter homeMission`
Expected: fail because `homeMissionSnapshot` does not exist yet.

- [ ] **Step 3: Implement snapshot types and AppModel computed property**

Add `HomeMissionStepKind`, `HomeMissionStepSnapshot`, `HomeMissionResourceSnapshot`, and `HomeMissionSnapshot`. Implement `AppModel.homeMissionSnapshot` from existing read-only state only.

- [ ] **Step 4: Re-run targeted tests**

Run: `swift test --filter homeMission`
Expected: pass.

### Task 2: Replace Home Layout With Horizontal Route

**Files:**
- Modify: `Sources/PETVocabularyTrainer/PETVocabularyTrainerApp.swift`

- [ ] **Step 1: Replace `ThreeFunctionsHomeView` internals**

Render `HomeMissionSnapshot` as a horizontal route with compact step cards, a primary Quest action, page chooser, Reading/Reminder/Trophies entries, secondary Benchmark panel, and Resource Status panel.

- [ ] **Step 2: Keep current actions intact**

Use existing methods only: `performCurrentUnitPrimaryAction()`, `resumeCurrentSession()`, `selectQuestPage(_:)`, `openReview()`, `openTrophies()`, `requestQuestImport()`, and resource import methods.

- [ ] **Step 3: Build to verify SwiftUI compiles**

Run: `swift build`
Expected: build succeeds.

### Task 3: Verify Data Safety

**Files:**
- No production data files modified.

- [ ] **Step 1: Run full test suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 2: Package without seed data**

Run: `INCLUDE_INITIAL_DATA=0 ./scripts/package-macos-app.sh`
Expected: package succeeds and prints that no initial import data was embedded.

- [ ] **Step 3: Confirm no real data overwrite path was introduced**

Inspect changed files and verify the home snapshot is computed/read-only and does not call `save()`, reset, import, or backup except through existing explicit user actions.
