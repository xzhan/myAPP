# PET Vocabulary Trainer

A native macOS SwiftUI vocabulary trainer prototype focused on English -> Chinese PET-style practice.

## What it does

- first-run placement test
- short adaptive missions after placement
- multiple-choice English -> Chinese questions
- local progress persistence
- failed-word recycling until mastery
- coach-style feedback after each session
- review queue and history views

## Current scope

This prototype now ships with a built-in PET-style core list of 140 words in `Sources/PETVocabularyTrainer/Resources/pet_words.json`.
It is still structured so the list can grow further or later accept custom imports.

## Run

```bash
swift run PETVocabularyTrainer
```

## Test

```bash
swift test
```
