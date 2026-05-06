# PETVocabularyTrainer Downloads

This folder is the stable place for sharing packaged app builds.

- `PETVocabularyTrainer-macOS.zip` is the current macOS app package.
- The app stores imported words, reading data, trophies, and reminders in the user's local Application Support folder, not inside this download folder.
- Rebuild the app with `INCLUDE_INITIAL_DATA=0 ./scripts/package-macos-app.sh` before replacing the zip, unless you intentionally want to ship bundled seed data.
