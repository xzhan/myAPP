# PET Vocabulary Trainer Plan

## Current Next Step

- [ ] Follow the design-first workflow in `design.md` before any new feature work:
  - review the current design focus and confirm the target UX states
  - implement only after the interaction and technical approach are clear
  - finish with both automated tests and one manual user flow

- [ ] Deliver the new daily 45-word exercise flow:
  - keep placement as a fast 100-word meaning diagnostic
  - make daily mission and failed review word-based exercises instead of single-tap questions
  - require both meaning recognition and spelling completion for a word to count as correct
  - show a sentence clue for each daily word and reveal the completed sentence in feedback
  - persist enough session state to leave and resume in the middle of a word exercise

- [ ] Improve macOS usability and action discoverability:
  - make the `TODAY'S 45-WORD PLAN` entry visible much earlier in onboarding and dashboard
  - make onboarding responsive on smaller window sizes instead of relying on a fixed wide hero layout
  - switch file import to a movable macOS open panel instead of a fixed attached sheet

## Recently Completed

- [x] Fix the real PET PDF import path so large imports do not crash or freeze the app:
  - make topic fallback hashing overflow-safe for large imported vocab sets
  - move heavy import work off the main actor
  - show a visible importing overlay instead of leaving the window in a gray blocked state
  - verify the real PDF flow and cover it with regression tests

- [x] Add PET word bank import so the app can test against a real external library:
  - import PDF, CSV, TXT, or JSON vocabulary files
  - parse the provided PET PDF layout with wrapped English/Chinese lines
  - persist the imported word bank locally and switch placement + mission sessions to use it
  - allow returning to the bundled starter list from the UI
