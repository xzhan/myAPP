# PET Vocabulary Trainer User Guide

PET Vocabulary Trainer is a native macOS study app for PET / Cambridge B1 Preliminary preparation. It connects vocabulary testing, daily 45-word practice, reading comprehension, missed-word review, pronunciation practice, and progress history into one learning flow.

## Who It Is For

- Junior learners preparing for PET / Cambridge B1 Preliminary.
- Students who need structured PET vocabulary review by page and unit.
- Families who want vocabulary practice to connect directly with reading.
- Parents who want visible progress, missed words, reminders, and history.

## Install And First Launch

1. Unzip `PETVocabularyTrainer-macOS.zip`.
2. Move `PETVocabularyTrainer.app` to `Applications` or another convenient folder.
3. On the first launch, macOS may show a security warning. Right-click the app and choose `Open`.
4. If you want pronunciation practice, allow microphone and speech recognition permissions when macOS asks.

If you are using the clean seed package for a new student, the app installs the bundled Base / Quest / Reading resources on first launch, but it does not include any previous study history.

## Main Learning Flow

The home screen is organized around the learning journey:

1. Import: Manage the three learning resource types. This is usually needed only once.
2. 45-Word Quest: Study or test one PET page with 45 words.
3. Reading Mission: Complete the matching reading task for the same page.
4. Reminder: Review words that were missed before.
5. Trophies: View history, accuracy, page progress, and the memory curve.

## Three Resource Types

### Base PDF

Base is the stable PET word bank, usually imported from `PET全.pdf` and split into 66 pages. It is useful for vocabulary baseline testing and page-based study planning.

### Quest JSON

Quest is the enhanced 45-word practice layer for each page. It can include meaning choices, spelling prompts, sentence translation, example sentences, and Memory Tips. Quest data can be imported in batches. Imported pages appear as Quest Enhanced.

### Reading

Reading resources are page-matched comprehension tasks. After finishing the Quest for a page, the learner can continue directly into the matching Reading Mission. This creates a vocabulary-to-reading loop.

## Daily 45-Word Quest

Each word usually has three core checks:

1. Meaning: Choose the correct Chinese meaning from the sentence context.
2. Spelling: Type the English word from a Chinese prompt and sentence clue.
3. Translation: Understand the Chinese sentence and choose the correct English sentence.

Some pages also include Pronunciation Check. The student listens to the word, says it out loud, and receives gentle feedback such as Almost heard or Heard clearly. Pronunciation does not block the study flow, but weak pronunciation can return in review.

## Spelling Rules

Spelling checks ignore capitalization and diacritic differences. For common PET optional spellings such as `blond(e)`, the app accepts:

- `blond`
- `blonde`
- `Blond`
- `Blonde`
- `blond(e)`

This prevents students from being marked wrong for valid optional-letter forms.

## Reading Mission

The recommended reading flow is:

1. Read the 5 questions first.
2. Read the passage with those questions in mind.
3. Start answering after finishing the passage.
4. Retry the current question if the answer is wrong.

This trains an exam-friendly reading habit: preview the questions, then read with a purpose.

## Review Rescue And Spaced Review

When a student misses meaning, spelling, translation, or pronunciation, the word can enter Review Rescue. The app schedules the word using an Ebbinghaus-style spaced review path:

- 10 minutes
- 1 day
- 2 days
- 4 days
- 7 days

Review Rescue prioritizes small review packs, so the learner does not face a huge boring backlog at once. The goal is not punishment. The goal is to rescue words before they are forgotten.

## Trophies

Trophies is the progress dashboard. It shows:

- Finished sessions today.
- Average accuracy.
- Words due for review.
- Daily streak.
- Page 1-66 Quest / Reading progress.
- Recent practice history.
- Current missed words and Memory Tips.

Parents can quickly see whether the learner studied today, which pages are done, and which words still need review.

## Pronunciation Permissions And Troubleshooting

### Microphone Is Not Available

If the student denied permission the first time:

1. Open `System Settings`.
2. Go to `Privacy & Security`.
3. Open `Microphone` and `Speech Recognition`.
4. Allow `PETVocabularyTrainer`.
5. Return to the app and check again, or restart the app.

### Pronunciation Feels Too Strict

The pronunciation feature is designed as a Gentle Pronunciation Coach. Almost heard still shows the word and gives positive feedback. Treat it as a speaking habit reminder, not as a strict oral exam score.

### A New Student Sees Old Data

Each Mac keeps its local data here:

`~/Library/Application Support/PETVocabularyTrainer`

If that Mac has used the app before, the clean seed package will not overwrite existing local data. Back up or remove that folder before opening the app if the student needs a fresh start.

## Data Safety

Study data is stored locally on the Mac by default. This includes:

- Imported word banks and reading packs.
- Word-level progress.
- Trophies history.
- Review Rescue schedules.

When you share the clean seed package, it includes learning resources only. It does not include your personal history, progress, missed words, or streak.

## Recommended Daily Routine

- Start with Reminder. If only a few words are due, do a small Review Rescue sprint first.
- Complete the current page's 45-Word Quest.
- Continue into the matching Reading Mission.
- Check Trophies to confirm progress and due review words.

A healthy daily rhythm is: rescue missed words, learn new page words, then use reading to reinforce them.
