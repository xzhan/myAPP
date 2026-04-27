# Pronunciation Speech Cat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn pronunciation from passive playback into a visible speak-aloud test with microphone recognition and cat-coach feedback.

**Architecture:** Keep scoring deterministic and testable in a pure Swift helper. Add a macOS speech-recognition coach that wraps `Speech` and `AVFoundation`, then connect it to the existing pronunciation step UI. The UI records a short spoken attempt, shows cat states for listening/checking/happy/sad, and falls back to manual self-check if speech permission or recognition is unavailable.

**Tech Stack:** SwiftUI, AVFoundation, Speech, Swift Testing, existing `AppModel` and `PronunciationRating`.

---

### Task 1: Pronunciation Scoring Core

**Files:**
- Create: `Sources/PETVocabularyTrainer/PronunciationAssessment.swift`
- Test: `Tests/PETVocabularyTrainerTests/PETVocabularyTrainerTests.swift`

- [ ] **Step 1: Write failing scoring tests**

Add tests for exact, near, and failed spoken results:

```swift
@Test func pronunciationAssessmentRatesRecognizedSpeechAgainstTargetWord() {
    #expect(PronunciationAssessment.rate(spokenText: "influence", targetWord: "influence") == .clear)
    #expect(PronunciationAssessment.rate(spokenText: "influnce", targetWord: "influence") == .almostThere)
    #expect(PronunciationAssessment.rate(spokenText: "teacher", targetWord: "influence") == .needsPractice)
}
```

- [ ] **Step 2: Run failing tests**

Run: `swift test --filter PronunciationAssessment`

- [ ] **Step 3: Implement scoring**

Create a pure helper that normalizes text, finds the closest spoken token, computes edit-distance similarity, and maps to `PronunciationRating`.

- [ ] **Step 4: Run passing tests**

Run: `swift test --filter PronunciationAssessment`

### Task 2: Speech Recognition Coach

**Files:**
- Create: `Sources/PETVocabularyTrainer/PronunciationSpeechCoach.swift`
- Modify: `Package.swift` if required by framework imports
- Modify: `scripts/package-macos-app.sh`

- [ ] **Step 1: Add app privacy strings**

Ensure packaged `Info.plist` includes `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`.

- [ ] **Step 2: Implement coach**

Create an `@MainActor` observable coach with states: idle, requestingPermission, listening, checking, recognized, unavailable. Use `SFSpeechRecognizer`, `AVAudioEngine`, and `SFSpeechAudioBufferRecognitionRequest`.

- [ ] **Step 3: Keep fallback safe**

If authorization fails, expose a readable message and allow manual rating buttons to remain usable.

### Task 3: Cat Pronunciation UI

**Files:**
- Modify: `Sources/PETVocabularyTrainer/PETVocabularyTrainerApp.swift`

- [ ] **Step 1: Replace passive card with active cat coach**

Update `PronunciationSelfCheckCard` so the primary path is:

```text
Play word -> Start Speaking -> recognition result -> cat feedback -> Continue
```

- [ ] **Step 2: Add animated cat view**

Use SwiftUI shapes/text to draw a lightweight cat state. Happy state bounces; sad state droops; listening state pulses.

- [ ] **Step 3: Submit assessed rating**

When speech recognition produces a rating, call existing `model.submitPronunciationRating(rating)`. Manual fallback buttons remain available.

### Task 4: Verification and Rebuild

**Files:**
- No code changes unless verification finds issues.

- [ ] **Step 1: Run tests**

Run: `swift test`

- [ ] **Step 2: Build**

Run: `swift build`

- [ ] **Step 3: Data-safe package**

Capture app-support timestamps, run `INCLUDE_INITIAL_DATA=0 ./scripts/package-macos-app.sh`, verify codesign, and confirm `store.json` / `imported_words.json` timestamps did not change.
