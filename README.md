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

This prototype ships with a built-in starter PET-style seed list in `Sources/PETVocabularyTrainer/Resources/pet_words.json`.
It is structured so the list can be expanded to a fuller PET dataset later.

## Run

```bash
swift run PETVocabularyTrainer
```

## Test

```bash
swift test
```
