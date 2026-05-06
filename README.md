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

## User Guides

- 中文使用说明书: `docs/user-guide-zh.md`
- English user guide: `docs/user-guide-en.md`

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

## Share On Another Mac

The project now includes a local packaging script that builds a macOS `.app` bundle and a shareable `.zip`:

```bash
./scripts/package-macos-app.sh
```

That creates:

- `dist/PETVocabularyTrainer.app`
- `dist/PETVocabularyTrainer-macOS.zip`
- a first-launch seed data payload inside the app, if this Mac already has imported learning resources

### Recommended sharing flow

1. Build the app bundle:

```bash
./scripts/package-macos-app.sh
```

2. Send `dist/PETVocabularyTrainer-macOS.zip` to the other Mac user.

3. On the other Mac:

- unzip it
- move `PETVocabularyTrainer.app` into `Applications`
- open it
- the first launch will install the bundled Base / Quest / Reading resources into that user's local app data

The default package embeds imported learning resources from:

`~/Library/Application Support/PETVocabularyTrainer`

It intentionally does not embed your personal trophies, streaks, progress, or review history. If you want a clean app without bundled learning resources, run:

```bash
INCLUDE_INITIAL_DATA=0 ./scripts/package-macos-app.sh
```

The packaging script also creates a local safety backup before it reads your current app data:

`dist/data-backups/<timestamp>/`

This backup is not shipped inside the app. It is there so your own imported data and history can be recovered if you package again or test a new build.
If the local app data looks like a small test fixture instead of a reusable PET seed pack, the script refuses to embed it. Re-import Base / Quest / Reading first, or run the clean build command above.

### Gatekeeper note

By default the script uses ad-hoc signing so the package is easy to build locally.
That is good for internal testing, but macOS may still warn on another machine.
If that happens, the recipient can usually use `Right Click -> Open` once.

For smoother public distribution, use a real Developer ID signature:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-macos-app.sh
```

Then notarize the resulting zip before sharing widely.

### User data on each Mac

Each Mac keeps its own local progress and imported resources under:

`~/Library/Application Support/PETVocabularyTrainer`

That means imported word banks, reading packs, trophies, and review history stay on that user's Mac after they close and reopen the app.
The app also creates timestamped backups under:

`~/Library/Application Support/PETVocabularyTrainer/Backups`

Backups are created before higher-risk operations such as importing a new Base/Quest/Reading resource or switching back to the bundled starter.
