# PET Vocabulary Trainer Design

## Working Mode

We use a design-first workflow for every meaningful product change.

Sequence:

1. Define the user problem and the target experience.
2. Describe the UI states, copy, and interaction rules.
3. Describe the technical approach and risk areas.
4. Implement only after the design is clear.
5. Validate with automated tests and one real-user manual flow.

This file is the lightweight source of truth before we start the next round of coding.

## Product Direction

PET Vocabulary Trainer should feel calm, legible, and trustworthy.
The app is not just a parser for vocabulary files. It is a guided study tool that should always make the next action obvious:

- choose a word bank
- start the placement test
- continue with daily missions
- recover gracefully from import or session issues

## Current Design Focus

### Feature

Imported PET word-bank flow, onboarding clarity, the daily study loop, page-based quest JSON content, richer session history, stronger feedback visuals, celebration polish, and a reading-comprehension scaffold.

### User Problem

Users can import a large PET PDF successfully, but the next steps are still too ambiguous:

- the top-right import surface can clip on smaller window widths
- users are not warned before replacing an already imported bank
- the placement test does not make the active PDF bank obvious enough
- daily study still behaves like a short generic mission instead of a predictable 45-word learning routine
- failed words are only ranked by a simple priority score instead of following a recognizable spaced-review rhythm
- the daily mission tests only one dimension of a word, so users do not practise spelling or sentence context
- the launch entry for `TODAY'S 45-WORD PLAN` can get buried below oversized hero content on smaller window sizes
- the file import picker behaves like a fixed sheet, which feels awkward on macOS because users expect to move the file window around
- the new LLM-generated quest JSON is richer than a plain word list, but the app currently throws away page boundaries, curated sentence prompts, sentence translations, and memory tips
- users want to study one PET page at a time, not just a generic shuffled 45-word block
- users who have already finished one page need a direct way to jump to the next target page, such as moving from page 13 to page 14, without relying only on automatic advancement
- session history is too generic, so learners cannot quickly see which attempts succeeded, which failed, which words still need review, and when those reminders come back
- the app says `History`, but users expect a more rewarding, collectible feeling from this area, closer to `Trophies`
- answer results are correct logically, but the correct and wrong choices are not visually obvious enough for children or fast review
- finishing a practice session feels static; the app needs a playful reward moment
- there is no reading-comprehension entry yet, even though the product will later receive a 66-article reading pack

### Design Goal

After choosing a PET file, the user should always understand one of these states:

- the app is importing now
- the import finished and the new bank is ready
- the import failed and the user can try again

The placement-test CTA must remain the obvious next step once import finishes.
After placement, the app should present a stable 45-word daily study plan with clear review pressure from missed words.
Each daily word should feel like a complete mini-exercise instead of a single shallow multiple-choice tap.
The main learning CTA should stay discoverable even when the app window is narrower or shorter than our default design size.
When a quest JSON is imported, the app should shift from “generic word bank” language to “today's page” language and preserve the curated learning content from that file.
When a session ends, the learner should feel both informed and rewarded: they should see what they achieved, what failed, what comes back for review, and a short playful celebration.

## UX Specification

### Word Bank States

#### 1. Bundled State

- Show the built-in bank name and word count.
- Primary action: `IMPORT WORD BANK`
- Secondary action: none unless an imported bank already exists.
- On onboarding and dashboard, the main word-bank surface should live in the normal content flow, not depend on a cramped floating shortcut tray.

#### 2. Import In Progress

- Dim the background to indicate temporary busy state.
- Show a centered loading card.
- Copy should explain that large PDFs can take a moment.
- Disable repeated import attempts while the current import is running.
- Do not present a blocking success alert when the import completes.
- The file selection UI itself should open as a movable macOS panel rather than a window-attached sheet.

#### 3. Imported Ready State

- Show the imported bank name and word count in the word-bank surface.
- Keep `100-WORD TEST` as the main next action on first run.
- Explicitly state that the placement test is using the imported PDF bank.
- Do not use `RESET` language for switching back to bundled.
- The bundled-switch action should behave like `Use Bundled Starter`, not like destructive deletion.
- Switching back to bundled must not erase the saved imported bank file.
- Switching back to bundled must not erase Trophies or other readable session history.
- If progress must reset because the active word list changes, the copy should say that explicitly while still reassuring the user that the saved import remains available.
- If the imported file is a quest JSON, show how many pages are available now and which page is next.

#### 4. Import Failed State

- Show an alert with the failure reason.
- Return the UI to an interactive state immediately.
- Preserve the previously active word bank if the new import fails.

### Session Start Rules

- If the user opens the importer during a quiz, we leave the quiz cleanly first.
- If the user already has an imported bank, tapping import again should first warn that replacing the bank will reset placement and mission progress.
- Replacing the current bank should preserve Trophies and other readable completed-session records even when active progress resets.
- Importing a new bank resets prior progress because placement, missions, and review queues depend on the active bank.
- After a successful import, the app returns to onboarding so the next step is clear.
- The user should not have to dismiss an extra success modal before tapping `100-WORD TEST`.
- The primary study CTA should appear above the fold on onboarding and dashboard whenever possible.
- The daily-plan card itself should also expose the launch action so users can start from the place where they read today's plan.
- Quest JSON imports should set the current learning unit to the next available page automatically.
- Quest JSON mode should also expose a manual page selector so the learner can jump directly to an imported page.
- Changing the selected quest page must not erase completed-page history; it only changes the current launch target.
- The selected quest page should persist across relaunch so the app reopens on the page the learner intentionally chose.

### Page Mainline Rules

- Once a quest JSON is active, the app should stop behaving like a feature menu and start behaving like a page-by-page learning journey.
- The real backbone of that journey is `Page 1 ... 66`, not whichever import happened most recently.
- The app should treat the three PET data types as layered content around the same page index:
  - `PET全.pdf` is the stable base word skeleton
  - `Vocab_quests` is an optional page-level enhancement layer
  - `Reading` is the matching page-level reading layer
- If all three sources exist for `Page 14`, the learner should still feel like they are doing one page, not entering three unrelated tools.
- If only the base PDF exists for a page, that page should still be fully usable as the current unit.
- Quest overlays should strengthen a page, not replace the whole word-bank identity.
- The home screen must have one dominant surface named `Current Unit`.
- `Current Unit` should always tell the learner:
  - which page is active now
  - whether the word quest for that page is done
  - whether the reading step for that same page is waiting, preview-only, ready, or done
  - what the next primary action is
- `Current Unit` should also expose the three data layers in plain language so the learner can see, at a glance:
  - `Base Ready`
  - `Quest Enhanced` or `Quest Pending`
  - `Reading Ready`, `Reading Preview`, `Reading Waiting`, or `Reading Missing`
- These three layer labels should appear as visible status tiles, not only inside paragraph copy.
- The primary CTA progression for quest mode should be:
  - `START WORD QUEST` when the page word quest is not done yet
  - `OPEN READING STEP` or `OPEN READING PREVIEW` after the word quest is done
  - `GO TO NEXT PAGE` only after both page steps are done, or when the user intentionally chooses to move on manually
- Finishing the word quest for a page must no longer auto-advance the current page immediately.
- After the word quest ends, the same page should remain the `Current Unit` so the learner can clearly see that Reading is the next step.
- Manual page selection still needs to exist, but it should become a secondary surface instead of competing with the main CTA.
- Word Bank import, Review Reminder, and Trophies should become secondary supporting surfaces around the mainline, not parallel first-class entry points on the home screen.
- If Reading content for the current page is missing, the home screen should say that clearly instead of implying the page is fully complete.
- If Reading content exists but has no answer keys yet, the home screen should call it `preview` rather than `ready`.
- When the final Reading exam flow lands later, it should plug into this existing page mainline instead of creating a separate study loop.
- The home screen should no longer hide all imports behind one generic vocabulary button.
- The product should expose three distinct import lanes:
  - `Import Base PDF`
  - `Import Quest JSON`
  - `Import Reading`
- These import lanes should live together in one supporting surface so the learner understands they are three aligned data layers for the same `Page 1 ... 66` spine.
- The learner should never have to guess whether a button is replacing the base bank, adding a quest overlay, or updating Reading.

### Two Mainlines

- The product should explicitly support two top-level study intentions:
  - `Base Assessment`
  - `Daily Quest Loop`
- `Base Assessment` exists to estimate a child's PET vocabulary size using the stable `PET全.pdf` base bank.
- `Daily Quest Loop` exists to move page by page through `Quest 45 -> Reading`.
- The home screen should keep `Daily Quest Loop` dominant when quest pages exist, but it should still show `Base Assessment` as a separate, always-understandable path.
- `Base Assessment` should not feel like it disappears just because page quests are imported later.
- `Daily Quest Loop` should not require the learner to mentally translate a generic word-bank import into the idea of page study.
- The supporting copy should make the division clear:
  - Base PDF = benchmark vocabulary layer
  - Quest JSON = richer page practice layer
  - Reading = matching page comprehension layer

### Simplified Home Surface

- The home screen and dashboard should now be simplified to only three primary product surfaces:
  - `Import`
  - `Quest`
  - `Vocabulary Assessment`
- `Import` is one unified surface that contains the three aligned data actions:
  - import Base
  - import Quest
  - import Reading
- Once Base and Reading are already imported, the `Import` surface should visually step back and behave like a lightweight `Resources` shelf instead of a daily first-stop card.
- In that quieter state, the learner should mainly see:
  - whether Base is ready
  - how many Quest pages are already enhanced
  - whether Reading is ready
- The shelf should keep one quick action for `Add Quest Pages`, because Quest JSON is the only layer expected to grow repeatedly over time.
- Full import lanes and detailed previews can live behind a small `Manage Imports` / `Hide Details` toggle.
- `Quest` is one unified surface that contains:
  - the current page
  - page selection
  - the next quest-or-reading action
- `Quest` should also show a compact page preview block so the learner can immediately see the current page's key word, prompt style, and Reading status without opening a separate chooser screen.
- `Reading` should not appear as a separate top-level home card anymore because it belongs inside the Quest flow.
- `Trophies`, `Review Reminder`, `Word Bank`, and other secondary management surfaces should no longer sit on the first screen as competing primary cards.
- The learner should be able to understand the whole app from the first screen without scanning a long stack of unrelated cards.
- The unified `Import` surface should still preview real imported content inline:
  - Base should preview a matched page and a few imported words
  - Quest should preview a matched page and one imported quest prompt
  - Reading should preview a matched page and a short passage excerpt
- Import should never feel blind. A successful import must immediately show what landed without making the learner hunt through another screen.

### Import Safety Rules

- Quest JSON import must tolerate duplicate normalized words instead of crashing.
- Duplicate `originalVocab` entries inside one quest session should merge safely and prefer the richer non-empty fields.
- Topic lookups built from imported or seed words must not rely on `Dictionary(uniqueKeysWithValues:)` when duplicate normalized keys are possible.
- Import failure copy should stay plain and reassuring instead of implying the learner picked the wrong file when the app can actually recover by merging duplicates.

### Closed Loop Rules

- When a page word quest finishes and matching Reading for that same page is already imported, the app should continue directly into Reading instead of stopping at a disconnected hub.
- If the matching Reading page is quiz-ready, the continuation should say `Start Reading Now`.
- If the matching Reading page is preview-only, the continuation should still say that Reading is next, but it should label the step as preview instead of exam-ready.
- If the matching Reading page is missing, the summary should say that clearly and keep the user on the same page instead of implying the unit is finished.
- The page should count as a fully closed daily loop only after the word quest is done and the matching Reading step has been opened or completed for that same page.

### Responsive Layout Rules

- On narrower widths, hero content should stack instead of forcing a wide two-column composition.
- The launch CTA should move upward in the reading order instead of remaining below long explanatory cards.
- On shorter heights, onboarding content must remain scrollable so the study CTA never becomes inaccessible.
- Decorative oversized typography must shrink or move below the main action content before it hides critical controls.

### Daily Study Flow

- The placement test remains a 100-word diagnostic.
- After placement, the app should guide the user into a daily 45-word plan.
- The 45-word plan should combine:
  - review words that are due now
  - partially learned words that still need reinforcement
  - fresh words to fill the remaining capacity
- The dashboard should clearly show how many review words are due today.
- The review screen should explain that missed words return on a spaced schedule instead of using an opaque numeric priority.
- If the active import is a quest JSON, the primary mission flow should switch from a generic 45-word mix to a page-based unit.
- The page-based unit should tell the learner which page is current and how many quest pages are currently imported.
- The onboarding and dashboard surfaces should both show a clear `Choose Page` control for quest imports.
- The page selector should list only pages that actually exist in the current layered import state.
- The current page, completed pages, and not-yet-completed pages should be visually distinguishable in the selector copy.
- The selector should also make it obvious whether a page is only using the base PDF or already has a quest enhancement layer.
- The page selector summary counts should prefer the same language as the mainline:
  - `Base Ready`
  - `Quest Enhanced`
  - `Completed`

### Daily Word Exercise Flow

- The daily 45-word plan and failed-word review should use a word-based exercise, not a single-tap question list.
- Each word exercise should have three learning elements:
  - an English-to-Chinese multiple-choice check for meaning
  - a sentence clue built around the target word
  - a spelling check where the learner types the English word
- To keep the session count honest, one word remains one unit of progress even though it has multiple steps.
- The daily screen should still say `45 words`, not `90 questions` or `135 questions`.
- The placement test stays simpler and faster:
  - keep the 100-word placement diagnostic as multiple-choice meaning questions only
  - do not add spelling or sentence typing to placement in this version
- If the imported content already includes curated prompts, translations, and memory tips, prefer that content over fallback templates.

### Pronunciation Support

- Pronunciation should support the moments where learners usually get stuck, not just act as decoration.
- The app should provide one-tap speech playback for:
  - the English sentence clue
  - the Chinese translation prompt on the translation step
  - the corrected English word after a mistake
  - the revealed English sentence after a mistake
  - the revealed Chinese sentence meaning after a mistake
- Reading should also allow passage playback from inside the Reading flow.
- English playback should prefer an English voice, and Chinese playback should prefer a Chinese voice.
- Pronunciation controls should look lightweight and friendly so younger learners feel invited to tap them, not overwhelmed by another large CTA.
- Pronunciation support for word learning should live inside the Spelling step itself.
- If a learner misses the Chinese-to-English spelling:
  - keep them on the Spelling step
  - let them replay the word, sentence, and Chinese meaning
  - let them retry the spelling immediately in the same place
- The first failed spelling attempt must be persisted immediately as a retry-tracked review signal.
- That retry signal should enter the spaced-review database even before the learner finishes the rest of the word flow, so daily reminders can still surface the word later if the learner leaves mid-session.
- Do not add a separate pronunciation-rating page after translation; that extra branch slows the flow down too much for younger learners.

### Final-Step Feedback Timing

- In three-step word exercises, the final translation result should not auto-advance to the next word.
- At that moment the learner needs time to absorb:
  - whether meaning was right
  - whether spelling was right
  - whether translation was right
  - the revealed sentence and sentence meaning
- The final feedback card should therefore stay on screen until the learner taps `Continue`.
- Earlier, faster checks can still auto-advance so the session pace remains lively.

### Word Exercise Interaction Rules

- Step 1:
  - for generic banks, show the English word prominently and ask for the correct Chinese meaning
  - for quest JSON pages, show the imported sentence prompt and ask for the correct Chinese meaning using the imported answer options
  - show the imported `Memory Tip` at the start of the word test when one exists
- Step 2:
  - ask the learner to type the English spelling from a Chinese-to-English prompt
  - if they miss it, keep them on the same Spelling step and let them retry there directly
  - the Spelling step should include pronunciation playback helpers for the target word, sentence, and Chinese meaning when the learner is retrying
- Feedback:
  - if the quest JSON includes a sentence-translation question, add a final Step 3 where the learner chooses the correct English sentence
  - reveal the full example sentence and the sentence meaning after the final step
  - explain whether the learner missed meaning, spelling, translation, or multiple parts
  - show the imported memory tip when available
  - only after the final step finishes do we advance to the next word
- Scoring:
  - a quest-page word counts as correct only if meaning, spelling, and translation are all correct
  - the whole bundle still settles as one pass/fail result in mastery logic

### Spaced Review Rules

- A missed word enters the spaced-review queue immediately.
- A spelling retry miss also enters the spaced-review queue immediately and should remain tagged as a retry-triggered reminder word.
- The review schedule follows an Ebbinghaus-style cadence with increasingly wider gaps.
- The first version will use in-app reminders and due counts, not background system notifications.
- When a review word is answered incorrectly again, its schedule resets to the first interval.
- When a review word is answered correctly across the full mastery loop, it can leave the scheduled queue.
- The reminder UI should say exactly when the word comes back next and also show the full strategy in plain language.

### Trophies Rules

- Rename the current `History` destination to `Trophies`.
- Every completed placement, mission, and review rescue should appear in Trophies.
- Each Trophy card should show:
  - the session type
  - date/time
  - success count
  - failure count
  - accuracy
  - points earned
  - which words still need review
- The words-to-review list must remain readable even after the active bank changes, so the session record should store readable word labels, not just live IDs.
- Trophies should visually feel more rewarding than a plain log, but still stay easy to scan.

### Accuracy Rules

- Session accuracy should reflect word-level grading, not sub-step count inflation.
- Quest-page bundles still count as one word passed or failed after all required steps finish.
- Accuracy percentages should round consistently instead of truncating downward.
- The UI should show both successes and failures so accuracy is explainable at a glance.

### Result Highlight Rules

- After the learner answers a multiple-choice question, the correct option should get a strong success treatment.
- The chosen wrong option should get a distinct error treatment.
- Other options should visibly fade back so the result reads instantly.
- The feedback card should repeat the correct answer content in a high-contrast way for meaning, spelling, and translation.

### Celebration Rules

- Finishing any full practice session should trigger a short playful celebration on the summary screen.
- The celebration should be lightweight, local, and not block the next action.
- The visual direction should feel child-friendly and cat-themed without depending on external image assets.
- The first version should use a native SwiftUI animation instead of imported GIFs or remote media.

### Reading Rules

- Add a first-class `Reading` entry in the main product navigation now, even before the article pack exists.
- The first version can ship as a scaffold:
  - an empty-state reading hub
  - copy explaining that a 66-article reading pack can be imported later
  - a persistent place in the app architecture for future reading content
- Do not guess the final article JSON schema too aggressively before the user provides it.
- Support a plain-text reading schema now so the user can import one article or a whole folder of articles before the final JSON format exists.
- Support PDF reading imports now because the current reading source is organized as PDF pages.
- The text schema should accept:
  - `Reading Quest: <title>`
  - `--- READING PASSAGE ---`
  - the full passage text
  - `--- QUESTIONS ---`
  - numbered questions such as `1. ...`
  - four answer options such as `A) ...`
- Import should work in two modes:
  - one selected `.txt` or `.pdf` file
  - a batch import from multiple supported files or one folder that contains supported files
- For Reading PDFs, the first import rule should be page-first:
  - one PDF page becomes one Reading item
  - the Reading item page number should come from the PDF page index when the file itself does not provide a better page label
- Reading should also work as a standalone surface:
  - the learner must be able to enter Reading without being forced to stay on the current Quest page
  - the Reading hub must provide a clear `Back to Main` path
- Reading preview should be page-selectable:
  - the learner should be able to choose one imported page index and preview only that page
  - the hub should not require a full long list of every imported article to understand what is available
  - the selected reading page can differ from the current Quest unit, and that should be okay
  - this page number must match the imported word-bank page number 1:1 whenever the source PDFs are aligned
- When a Reading PDF page has no explicit quiz structure, import it as preview-only instead of forcing fake questions.
- If a Reading PDF page already contains the explicit text markers used by the txt schema, the importer may preserve those richer sections.
- Batch imports should sort by page number when the title contains `Page_<n>` or `Page <n>`, then fall back to title order.
- Because the current example schema does not include answer keys, the first reading import should produce preview-ready reading quests, not graded quizzes.
- If a future reading file adds an answer section, the parser should be able to preserve it without redesigning the hub.
- The Reading hub should clearly tell the learner whether an imported article is:
  - preview-ready only
  - quiz-ready with answer keys
- The Reading hub should also make the page relationship obvious, so learners understand that `Reading page 14` is meant to follow `Word page 14`.

## Technical Design

### Architecture Rules

- Heavy import work must not run on the main actor.
- UI state updates must happen on the main actor.
- Persist imported words before switching the app to the new active library.
- Imported-word parsing must tolerate large PDFs and unusual vocabulary strings without crashing.
- Daily exercise state must survive a pause/resume in the middle of a word.
- File import presentation should use a native macOS open panel that can move independently from the main window.

### Current Technical Decisions

- Run PDF import and persistence in a detached background task.
- Track in-progress state with a dedicated `isImportingWordBank` flag.
- Keep the import overlay in SwiftUI instead of depending on a modal alert.
- Persist the stable imported word list separately from the page-layer metadata so the app can reopen either the bundled starter or the saved PET import safely.
- Store PET base PDF pages separately from quest overlay pages so the app can:
  - launch a page even when no quest overlay exists yet
  - merge later quest imports into only the matching page numbers
  - preserve progress and history while the enhancement layer grows over time
- Warn only when the selected import would truly replace the saved base bank. Do not show the destructive warning for incremental quest-overlay imports.
- Use overflow-safe hashing for topic fallback classification.
- Mark import models as `Sendable` so concurrency boundaries are explicit and safe.
- Use a date-based spaced-review schedule in `WordProgress` instead of relying only on `reviewPriority`.
- Keep a compact word-bank shortcut only on secondary screens; onboarding and dashboard should use a full-width, readable bank card in the normal layout.
- Add a persisted question style for fast placement questions versus multi-step daily word exercises.
- Persist the current word-exercise step so the learner can leave and resume without losing their place in the current word.
- Grade mastery once per word exercise, not once per sub-step.
- Use lightweight sentence templates for now so every imported PET word can produce a clue without needing a separate corpus.
- Recognize quest-style JSON exports and preserve their page boundaries, bundled 3-step questions, example translations, and memory tips.
- Treat quest JSON as a page-based study mode with sequential page advancement after completion.
- Store the learner-selected quest page number in the same persisted app state that already tracks completed quest pages.
- Replace SwiftUI `fileImporter` with an injected open-panel presenter so the import flow remains testable while using a movable macOS panel.
- Use the platform-native single-line text field path for spelling entry so keyboard input, focus, and IME behavior stay predictable inside the SwiftUI quiz flow.
- When the app is launched from Terminal, it must explicitly activate its own window before text-entry steps so typing lands in the study app instead of the launch terminal.
- Persist review-word labels alongside each completed session so the Trophies view can explain what still needs review even after later imports.
- Add a lightweight reading-center state now so future article-pack imports do not need a navigation redesign.
- Keep reminder strategy text centralized in the review scheduler so Trophies, Review, and Summary all explain the same cadence.
- Reading imports should stay independent from word-bank imports; replacing a vocabulary bank must not wipe the Reading pack, and replacing a Reading pack must not reset vocabulary placement or review history.
- When a learner intentionally switches to a different study page, any paused daily mission from another page should stop being the main resume target so the newly selected page can start fresh immediately.
- Reading quiz-ready pages should use a three-stage flow: preview all questions first, then read the passage, then answer one question at a time.
- Wrong reading answers should retry in-place without immediately revealing the answer key, so the learner rereads before moving on.
- Review reminders should surface the same quest memory tips that the learner saw during the original word exercise whenever those tips exist.

### Risks

- Very large PDFs may still feel slow if PDF text extraction itself is expensive.
- Topic classification is heuristic and may assign imperfect categories for rare words.
- Resetting all progress on bank swap is correct for now, but the confirmation copy has to be very clear.
- A 45-word plan may feel heavy for some users, so the UI should explain the split between due review and fresh words.
- Template-generated sentences may feel generic for some words until we add a richer sentence source later.
- Spelling normalization has to handle case and surrounding whitespace so correct answers are not marked wrong for trivial formatting.
- Quest JSON files may contain incomplete page coverage, duplicate page variants, or partial sessions, so the importer must choose the best page variant without crashing.
- If Trophies only store live word IDs, older session cards will become unreadable after bank swaps, so session review items must carry human-readable text.
- A celebration overlay can feel noisy if it blocks navigation or repeats forever, so it should stay short and dismiss itself naturally.
- Reading scaffolding should avoid locking us into the wrong import schema before the article pack is ready.

## Validation Plan

### Automated

- unit test for wrapped PET PDF parsing
- unit test for long unknown words so topic fallback hashing cannot overflow
- async app-model test proving import finishes and the UI leaves the blocking state
- app-model test for re-import confirmation
- session-planner test proving due review words outrank fresh words in the 45-word daily plan
- session-planner test proving daily mission questions are generated as word exercises
- app-model test proving a daily word only updates mastery after the spelling step finishes
- app-model test proving a word exercise records failure when meaning or spelling is wrong
- app-model test proving the import presenter is called directly when the user requests a new import
- quest-json parser test proving standard page sessions become page bundles with 3-step questions
- app-model test proving quest-page words do not settle until the translation step finishes
- app-model test proving finishing one quest page advances the current page pointer
- app-model test proving manually selecting page 14 updates and persists the current quest page without clearing completed-page history
- app-model test proving selecting a new page clears a paused mission from another page so the new page can start fresh
- session-summary test proving accuracy rounds correctly and failed words are stored for reminder display
- app-model test proving selecting a missing page leaves the current quest page unchanged
- reading-session test proving the flow is question preview -> passage reading -> answering
- reading-session test proving a wrong reading answer retries the same question before advancing
- review snapshot test proving memory tips reach the reminder/review surface
- full `swift test` pass before closing the task

### Manual

Primary manual flow:

1. Launch the app.
2. Import `/Users/aistudio/PET/PET全.pdf`.
3. Confirm the import surface is fully visible and readable.
4. Confirm the loading overlay appears instead of a frozen gray screen.
5. Wait for import completion.
6. Confirm the onboarding copy makes it clear the 100-word test is using the imported PDF bank.
7. Tap import again and confirm the app warns before replacing the bank.
8. Import `/Users/aistudio/vocab/Quests/vocab_quests 38.json`.
9. Confirm onboarding now shows the current page unit instead of the generic placement-first copy.
10. Use the page selector to change the current unit to a later imported page, such as page 14.
11. Confirm the UI updates immediately to show the newly selected page as today's unit.
12. Restart the app and confirm the selected page is still the current launch target.
13. Start `TEST 45`.
14. Confirm the flow for one word is:
   - sentence meaning multiple choice
   - Chinese-to-English spelling
   - sentence translation
15. Confirm the final feedback shows the sentence meaning and the imported memory tip.
16. Finish a mission and confirm the summary shows a short cat-themed celebration.
17. Open `Trophies` and confirm the session card shows successes, failures, accuracy, and review words with reminder timing.
18. Open `Reading` and confirm the empty state explains that the 66-article pack can be imported later.

Secondary manual flow:

1. Finish placement.
2. Start the daily 45-word plan.
3. Confirm each word begins with a meaning multiple-choice prompt.
4. Confirm the next step asks for spelling from a sentence clue rather than showing the word again as the large title.
5. Submit one fully correct word and confirm the streak updates once.
6. Submit one word with a spelling mistake and confirm the feedback explains the miss and schedules the word for review.

## Next Design Candidate

The next design pass should focus on the longer-term review experience:

- whether we add OS-level notifications for due review words
- whether users should be able to tune the fixed 45-word daily plan
- whether the review screen should show a full future schedule for each missed word
