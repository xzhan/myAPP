# Pronunciation Self-Check Plan

## Goal

Add a lightweight "Listen -> Say -> Self-check" step to every word-exercise flow so learners cannot silently skip pronunciation when they understand the meaning.

## Design

- Flow becomes: meaning choice -> pronunciation self-check -> spelling -> translation when present -> feedback.
- Pronunciation is self-rated with three options: need more practice, almost there, clear and confident.
- The rating is stored only on the active session until the word is graded, then appears in the final feedback summary.
- A "need more practice" rating records an Ebbinghaus retry signal, but it does not block the learner from continuing if meaning, spelling, and translation are correct.
- Legacy active sessions that were previously stuck on an invalid pronunciation step still normalize to spelling retry, but newly valid pronunciation steps survive resume.

## Data Safety

- Add one optional active-session field, `pendingPronunciationRating`.
- Decode missing values as `nil` so existing store files remain compatible.
- Do not modify imported word, quest, reading, history, or trophy data during this change.

## Tests

- Meaning submission for a word exercise advances to pronunciation, not spelling.
- Pronunciation self-check advances to spelling without grading the word.
- A weak pronunciation rating creates a retry reminder signal and is carried into final feedback.
- Legacy invalid pronunciation sessions still normalize to spelling retry.
