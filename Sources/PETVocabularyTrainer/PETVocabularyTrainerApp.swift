import SwiftUI
import UniformTypeIdentifiers

enum AppPalette {
    static let window = Color(red: 0.93, green: 0.93, blue: 0.91)
    static let canvas = Color(red: 0.98, green: 0.97, blue: 0.95)
    static let panel = Color(red: 1.00, green: 0.99, blue: 0.98)
    static let border = Color(red: 0.86, green: 0.84, blue: 0.80)
    static let line = Color(red: 0.86, green: 0.84, blue: 0.81)
    static let ink = Color(red: 0.31, green: 0.30, blue: 0.27)
    static let muted = Color(red: 0.55, green: 0.50, blue: 0.47)
    static let terracotta = Color(red: 0.82, green: 0.49, blue: 0.36)
    static let olive = Color(red: 0.41, green: 0.40, blue: 0.28)
    static let oliveSoft = Color(red: 0.92, green: 0.91, blue: 0.86)
    static let blue = Color(red: 0.29, green: 0.43, blue: 0.65)
    static let blueSoft = Color(red: 0.90, green: 0.94, blue: 0.98)
    static let ghost = Color(red: 0.91, green: 0.90, blue: 0.86)
    static let success = Color(red: 0.25, green: 0.54, blue: 0.39)
}

@main
struct PETVocabularyTrainerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.light)
                .task {
                    model.bootstrap()
                }
        }
        .defaultSize(width: 1280, height: 860)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AppPalette.window
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(AppPalette.canvas)
                .overlay(
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .stroke(AppPalette.border, lineWidth: 1.5)
                )
                .padding(12)

            content
                .frame(maxWidth: 1240, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 58)
                .padding(.vertical, 48)
        }
        .alert("Notice", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .fileImporter(
            isPresented: Binding(
                get: { model.isShowingLibraryImporter },
                set: { model.isShowingLibraryImporter = $0 }
            ),
            allowedContentTypes: [.pdf, .json, .commaSeparatedText, .plainText]
        ) { result in
            model.handleVocabularyImportSelection(result)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .loading:
            SurfaceCard {
                VStack(spacing: 18) {
                    Text("Loading vocabulary...")
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundStyle(AppPalette.ink)
                    ProgressView()
                        .tint(AppPalette.olive)
                }
                .frame(maxWidth: 420)
            }
        case .onboarding:
            OnboardingView()
        case .dashboard:
            DashboardView()
        case .quiz:
            QuizView()
        case .summary:
            SummaryView()
        case .review:
            ReviewView()
        case .history:
            HistoryView()
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let hasPlacement = model.data.hasCompletedPlacement
        let primaryTitle = hasPlacement ? "DAILY CHALLENGE" : "100-WORD TEST"
        let secondaryTitle = hasPlacement ? "100-WORD TEST" : "DAILY CHALLENGE"

        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 28) {
                Text("MASTERY PROGRAM")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .tracking(2)
                    .foregroundStyle(AppPalette.terracotta)

                Text("Vocabulary Journey")
                    .font(.system(size: 88, weight: .regular, design: .serif))
                    .foregroundStyle(AppPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Boost your skills with smart, gamified daily training")
                    Text("or a full PET baseline diagnostic.")
                }
                .font(.system(size: 34, weight: .medium, design: .serif))
                .italic()
                .foregroundStyle(AppPalette.muted)

                VStack(alignment: .leading, spacing: 8) {
                    Rectangle()
                        .fill(AppPalette.line)
                        .frame(width: 620, height: 4)
                    Rectangle()
                        .fill(AppPalette.line)
                        .frame(width: 340, height: 4)
                }

                VStack(alignment: .leading, spacing: 18) {
                    Button(primaryTitle) {
                        if hasPlacement {
                            model.startMission()
                        } else {
                            model.startPlacement()
                        }
                    }
                    .buttonStyle(HeroButtonStyle(kind: .filled))
                    .frame(maxWidth: 520)

                    Button {
                        if hasPlacement {
                            model.startPlacement()
                        } else {
                            model.startMission()
                        }
                    } label: {
                        Label(secondaryTitle, systemImage: "trophy")
                    }
                    .buttonStyle(HeroButtonStyle(kind: .outlined))
                    .frame(maxWidth: 560)
                }

                WordBankCard(
                    snapshot: model.wordBankSnapshot,
                    onImport: { model.requestVocabularyImport() },
                    onReset: model.wordBankSnapshot.isImported ? { model.resetToBundledWordBank() } : nil
                )
                .frame(maxWidth: 760)

                Text("Recommendation: start with the 100-word test to set your PET bar, then use daily challenges to keep failed words coming back until they are mastered.")
                    .font(.system(size: 20, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.muted)
                    .frame(maxWidth: 760, alignment: .leading)
            }

            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 18) {
                Text(hasPlacement ? model.dashboardStats.rankTitle.uppercased() : "GO")
                    .font(.system(size: 52, weight: .medium, design: .serif))
                    .foregroundStyle(AppPalette.ghost.opacity(0.75))

                Text(hasPlacement ? "\(model.dashboardStats.masteryPercent)%" : "GO")
                    .font(.system(size: 250, weight: .regular, design: .serif))
                    .foregroundStyle(AppPalette.ghost.opacity(0.78))
                    .minimumScaleFactor(0.7)

                if hasPlacement {
                    VStack(alignment: .trailing, spacing: 14) {
                        MetricTile(
                            title: "Rank",
                            value: model.dashboardStats.rankTitle,
                            caption: "\(model.dashboardStats.masteredCount) words mastered",
                            tint: AppPalette.terracotta
                        )
                        MetricTile(
                            title: "Streak",
                            value: "\(model.dashboardStats.dailyStreak) days",
                            caption: "Come back daily to keep the run alive",
                            tint: AppPalette.blue
                        )
                    }
                    .frame(width: 320)
                }
            }
            .frame(width: 360, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.dashboardStats

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("MASTERY PROGRAM")
                            .font(.system(size: 24, weight: .bold, design: .default))
                            .tracking(2)
                            .foregroundStyle(AppPalette.terracotta)

                        Text("Vocabulary Journey")
                            .font(.system(size: 78, weight: .regular, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(stats.missionSubtitle)
                            .font(.system(size: 30, weight: .medium, design: .serif))
                            .italic()
                            .foregroundStyle(AppPalette.muted)
                            .frame(maxWidth: 760, alignment: .leading)

                        VStack(alignment: .leading, spacing: 16) {
                            Button("DAILY CHALLENGE") { model.startMission() }
                                .buttonStyle(HeroButtonStyle(kind: .filled))
                                .frame(maxWidth: 460)

                            Button {
                                model.startPlacement()
                            } label: {
                                Label("100-WORD TEST", systemImage: "trophy")
                            }
                            .buttonStyle(HeroButtonStyle(kind: .outlined))
                            .frame(maxWidth: 500)
                        }

                        HStack(spacing: 12) {
                            Button("FAILED WORDS") { model.openReview() }
                                .buttonStyle(SecondaryNavButtonStyle())
                            Button("HISTORY") { model.openHistory() }
                                .buttonStyle(SecondaryNavButtonStyle())
                        }
                    }

                    Spacer(minLength: 20)

                    VStack(alignment: .trailing, spacing: 12) {
                        Text(stats.rankTitle.uppercased())
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                            .foregroundStyle(AppPalette.muted)

                        Text(stats.masteryPercent > 0 ? "\(stats.masteryPercent)%" : "GO")
                            .font(.system(size: 220, weight: .regular, design: .serif))
                            .foregroundStyle(AppPalette.ghost.opacity(0.82))
                            .minimumScaleFactor(0.7)

                        Text("\(stats.masteredCount) of \(stats.totalWordCount) words mastered")
                            .font(.system(size: 22, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                    }
                    .frame(width: 340, alignment: .trailing)
                }

                HStack(spacing: 16) {
                    MetricTile(
                        title: "Mastered",
                        value: "\(stats.masteredCount)",
                        caption: "Words already locked in",
                        tint: AppPalette.success
                    )
                    MetricTile(
                        title: "Needs review",
                        value: "\(stats.reviewCount)",
                        caption: "Failed words waiting to return",
                        tint: AppPalette.terracotta
                    )
                    MetricTile(
                        title: "Points",
                        value: "\(stats.totalPoints)",
                        caption: "Correct answers plus mastery bonuses",
                        tint: AppPalette.olive
                    )
                    MetricTile(
                        title: "Streak",
                        value: "\(stats.dailyStreak) days",
                        caption: "Come back to keep momentum",
                        tint: AppPalette.blue
                    )
                }

                WordBankCard(
                    snapshot: model.wordBankSnapshot,
                    onImport: { model.requestVocabularyImport() },
                    onReset: model.wordBankSnapshot.isImported ? { model.resetToBundledWordBank() } : nil
                )

                if let personalizedMissionPlan = model.personalizedMissionPlan {
                    SurfaceCard(title: "Today's Personalized Mission") {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 18) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(personalizedMissionPlan.title)
                                        .font(.system(size: 34, weight: .bold, design: .serif))
                                        .foregroundStyle(AppPalette.ink)
                                    Text(personalizedMissionPlan.subtitle)
                                        .font(.system(size: 20, weight: .medium, design: .default))
                                        .foregroundStyle(AppPalette.muted)
                                }
                                Spacer()
                                MetricTile(
                                    title: "Mission size",
                                    value: "\(personalizedMissionPlan.recommendedQuestionCount)",
                                    caption: "Questions in today's tailored challenge",
                                    tint: AppPalette.olive
                                )
                                .frame(width: 240)
                            }

                            if !personalizedMissionPlan.focusTopics.isEmpty {
                                HStack(spacing: 10) {
                                    ForEach(personalizedMissionPlan.focusTopics, id: \.self) { topic in
                                        TopicChip(topic: topic)
                                    }
                                }
                            }

                            Text(personalizedMissionPlan.rewardText)
                                .font(.system(size: 18, weight: .medium, design: .default))
                                .foregroundStyle(AppPalette.terracotta)
                        }
                    }
                }

                if let plan = model.latestPlacementStudyPlan {
                    SurfaceCard(title: "Latest Placement Estimate") {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .top, spacing: 24) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Estimated PET-style vocabulary")
                                        .font(.system(size: 18, weight: .bold, design: .default))
                                        .foregroundStyle(AppPalette.muted)
                                    Text("\(plan.estimate.estimatedVocabularySize) / \(plan.estimate.benchmarkVocabularySize)")
                                        .font(.system(size: 56, weight: .bold, design: .serif))
                                        .foregroundStyle(AppPalette.ink)
                                    Text(plan.estimate.guidance)
                                        .font(.system(size: 20, weight: .medium, design: .default))
                                        .foregroundStyle(AppPalette.muted)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 10) {
                                    PillLabel(text: plan.estimate.placementBand.uppercased(), tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                                    if let summary = model.latestPlacementSummary {
                                        Text("From \(summary.correctAnswers) / \(summary.totalQuestions) on your latest 100-word placement")
                                            .font(.system(size: 16, weight: .medium, design: .default))
                                            .foregroundStyle(AppPalette.muted)
                                            .multilineTextAlignment(.trailing)
                                            .frame(maxWidth: 280, alignment: .trailing)
                                    }
                                }
                            }

                            HStack(spacing: 16) {
                                MetricTile(
                                    title: "To 3,000",
                                    value: "\(plan.estimate.remainingToBenchmark)",
                                    caption: "Words still needed to reach the PET benchmark",
                                    tint: AppPalette.terracotta
                                )
                                MetricTile(
                                    title: "7-day target",
                                    value: "\(plan.estimate.weeklyGoalWords)",
                                    caption: "\(plan.estimate.dailyGoalWords) words a day this week",
                                    tint: AppPalette.olive
                                )
                            }

                            if !plan.focusTopics.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Weakest topics")
                                        .font(.system(size: 18, weight: .bold, design: .default))
                                        .foregroundStyle(AppPalette.muted)
                                    HStack(spacing: 10) {
                                        ForEach(plan.focusTopics, id: \.self) { topic in
                                            TopicChip(topic: topic)
                                        }
                                    }
                                }
                            }

                            if !plan.topicInsights.isEmpty {
                                PlacementTopicInsightChart(insights: plan.topicInsights)
                            }

                            PlacementActionList(actions: plan.nextWeekActions)
                        }
                    }
                }

                if !stats.focusTopics.isEmpty {
                    SurfaceCard(title: "Focus Topics") {
                        HStack(spacing: 10) {
                            ForEach(stats.focusTopics, id: \.self) { topic in
                                TopicChip(topic: topic)
                            }
                        }
                    }
                }

                if let summary = model.latestSummary ?? model.sessionHistory.first {
                    SurfaceCard(title: "Coach Feedback") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(summary.headline)
                                .font(.system(size: 30, weight: .bold, design: .serif))
                                .foregroundStyle(AppPalette.ink)
                            Text(summary.body)
                                .font(.system(size: 22, weight: .medium, design: .default))
                                .foregroundStyle(AppPalette.muted)
                            HStack(spacing: 14) {
                                PillLabel(text: summary.recommendedMissionTitle, tint: AppPalette.blue, fill: AppPalette.blueSoft)
                                PillLabel(text: "+\(summary.pointsEarned) points", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct WordBankCard: View {
    let snapshot: WordBankSnapshot
    let onImport: () -> Void
    let onReset: (() -> Void)?

    var body: some View {
        SurfaceCard(title: "Active Word Bank") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.title)
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                        Text(snapshot.subtitle)
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 10) {
                        PillLabel(
                            text: snapshot.badgeText,
                            tint: snapshot.isImported ? AppPalette.terracotta : AppPalette.blue,
                            fill: snapshot.isImported ? AppPalette.oliveSoft : AppPalette.blueSoft
                        )
                        Text("\(snapshot.wordCount) words")
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(AppPalette.muted)
                    }
                }

                HStack(spacing: 12) {
                    Button("IMPORT WORD BANK") {
                        onImport()
                    }
                    .buttonStyle(SecondaryNavButtonStyle())

                    if let onReset {
                        Button("USE BUNDLED STARTER") {
                            onReset()
                        }
                        .buttonStyle(SecondaryNavButtonStyle())
                    }
                }
            }
        }
    }
}

struct QuizView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.currentSession,
           let word = model.currentQuestionWord {
            let progress = model.currentWordProgress ?? .fresh(for: word.id)
            let accent = session.mode == .failedReview ? AppPalette.terracotta : AppPalette.olive
            let feedback = model.answerFeedback
            let livePlacementEstimate = model.livePlacementEstimate

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("QUESTION \(model.currentQuestionNumber) / \(session.questions.count)")
                            .font(.system(size: 22, weight: .bold, design: .default))
                            .tracking(1.2)
                            .foregroundStyle(AppPalette.terracotta)
                        Spacer()
                        PillLabel(text: session.mode.title.uppercased(), tint: accent, fill: AppPalette.oliveSoft)
                    }

                    ProgressView(value: Double(model.quizProgressCount), total: Double(session.questions.count))
                        .tint(accent)
                        .scaleEffect(x: 1, y: 1.8, anchor: .center)

                    if session.mode == .placement {
                        PlacementMilestoneTrack(progress: model.quizProgressCount, totalQuestions: session.questions.count)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        SurfaceCard {
                            HStack(alignment: .top, spacing: 24) {
                                VStack(alignment: .leading, spacing: 18) {
                                    TopicChip(topic: word.topic)

                                    Text(word.english)
                                        .font(.system(size: 104, weight: .regular, design: .serif))
                                        .foregroundStyle(AppPalette.ink)

                                    Text("Choose the correct Chinese meaning. A wrong answer resets this word’s streak and pushes it back into review.")
                                        .font(.system(size: 28, weight: .medium, design: .serif))
                                        .italic()
                                        .foregroundStyle(AppPalette.muted)
                                        .frame(maxWidth: 760, alignment: .leading)

                                    if let feedback {
                                        HStack(spacing: 10) {
                                            PillLabel(
                                                text: feedback.isCorrect ? "CORRECT" : "TRY AGAIN LATER",
                                                tint: feedback.isCorrect ? AppPalette.success : AppPalette.terracotta,
                                                fill: feedback.isCorrect ? AppPalette.oliveSoft : Color(red: 0.98, green: 0.92, blue: 0.89)
                                            )
                                            if feedback.newlyMastered {
                                                PillLabel(text: "MASTERED +25", tint: AppPalette.success, fill: AppPalette.oliveSoft)
                                            } else if feedback.pointsEarned > 0 {
                                                PillLabel(text: "+\(feedback.pointsEarned) POINTS", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                                            }
                                        }
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 12) {
                                    MetricTile(title: "Accuracy", value: "\(model.currentAccuracyPercent)%", caption: "Current session", tint: AppPalette.blue)
                                        .frame(width: 230)
                                    if session.mode == .placement, let livePlacementEstimate {
                                        MetricTile(
                                            title: "Projection",
                                            value: "\(livePlacementEstimate.estimatedVocabularySize)",
                                            caption: livePlacementEstimate.placementBand,
                                            tint: AppPalette.terracotta
                                        )
                                        .frame(width: 230)
                                    } else {
                                        MetricTile(title: "Streak", value: "\(progress.currentCorrectStreak) / 3", caption: "Needed for mastery", tint: accent)
                                            .frame(width: 230)
                                    }
                                }
                            }
                        }

                        VStack(spacing: 14) {
                            ForEach(Array(model.currentQuestionChoices.enumerated()), id: \.offset) { index, choice in
                                ChoiceButton(
                                    letter: String(UnicodeScalar(65 + index)!),
                                    text: displayText(for: choice),
                                    accent: accent,
                                    state: choiceState(for: choice, feedback: feedback)
                                ) {
                                    model.submit(choice: choice)
                                }
                                .disabled(feedback != nil)
                            }
                        }

                        if let feedback {
                            AnswerFeedbackCard(feedback: feedback) {
                                model.advanceAfterFeedback()
                            }
                        }

                        if session.mode == .placement,
                           feedback != nil,
                           model.quizProgressCount > 0,
                           model.quizProgressCount % 20 == 0,
                           let livePlacementEstimate {
                            PlacementCheckpointBanner(
                                checkpoint: model.quizProgressCount / 20,
                                totalCheckpoints: max(1, session.questions.count / 20),
                                estimate: livePlacementEstimate
                            )
                        }

                        HStack(spacing: 16) {
                            MetricTile(title: "Correct", value: "\(session.correctAnswers)", caption: "Score in this mission", tint: AppPalette.success)
                            MetricTile(title: "Mistakes", value: "\(progress.totalIncorrect)", caption: "This word has come back this many times", tint: AppPalette.terracotta)
                        }
                    }
                    .id(model.quizStepID)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    .animation(.easeInOut(duration: 0.28), value: model.quizStepID)
                }
                .padding(.vertical, 6)
            }
        } else {
            SurfaceCard {
                VStack(spacing: 18) {
                    Text("Preparing session...")
                        .font(.system(size: 32, weight: .semibold, design: .serif))
                        .foregroundStyle(AppPalette.ink)
                    ProgressView()
                        .tint(AppPalette.olive)
                }
            }
        }
    }

    private func displayText(for choice: String) -> String {
        let trimmed = choice.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Option unavailable" : trimmed
    }

    private func choiceState(for choice: String, feedback: QuizAnswerFeedback?) -> ChoiceButton.VisualState {
        guard let feedback else { return .idle }
        if choice == feedback.correctChoice {
            return .correct
        }
        if choice == feedback.selectedChoice {
            return .incorrect
        }
        return .dimmed
    }
}

struct SummaryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let summary = model.latestSummary
        let placementPlan = summary?.mode == .placement
            ? summary.map { PlacementPlanner.plan(correctAnswers: $0.correctAnswers, totalQuestions: $0.totalQuestions, weakTopics: $0.weakTopics, topicInsights: $0.placementTopicInsights ?? []) }
            : nil

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(summary?.headline ?? "Session complete")
                            .font(.system(size: 54, weight: .regular, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                        Text(summary?.body ?? "Your session has been recorded locally.")
                            .font(.system(size: 24, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                        if let summary {
                            PillLabel(text: summary.recommendedMissionTitle, tint: AppPalette.blue, fill: AppPalette.blueSoft)
                        }
                    }
                }

                if let placementPlan {
                    SurfaceCard(title: "Placement Result") {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .top, spacing: 24) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Estimated PET-style vocabulary")
                                        .font(.system(size: 18, weight: .bold, design: .default))
                                        .foregroundStyle(AppPalette.muted)
                                    Text("\(placementPlan.estimate.estimatedVocabularySize) / \(placementPlan.estimate.benchmarkVocabularySize)")
                                        .font(.system(size: 70, weight: .bold, design: .serif))
                                        .foregroundStyle(AppPalette.ink)
                                    Text(placementPlan.estimate.guidance)
                                        .font(.system(size: 22, weight: .medium, design: .default))
                                        .foregroundStyle(AppPalette.muted)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 14) {
                                    PillLabel(text: placementPlan.estimate.placementBand.uppercased(), tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                                    MetricTile(
                                        title: "Benchmark",
                                        value: "3,000",
                                        caption: "PET-style words in this estimate range",
                                        tint: AppPalette.olive
                                    )
                                    .frame(width: 250)
                                }
                            }

                            HStack(spacing: 16) {
                                MetricTile(
                                    title: "To 3,000",
                                    value: "\(placementPlan.estimate.remainingToBenchmark)",
                                    caption: "Words still needed to reach the benchmark",
                                    tint: AppPalette.terracotta
                                )
                                MetricTile(
                                    title: "7-day target",
                                    value: "\(placementPlan.estimate.weeklyGoalWords)",
                                    caption: "\(placementPlan.estimate.dailyGoalWords) words per day",
                                    tint: AppPalette.blue
                                )
                            }

                            if !placementPlan.focusTopics.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Weakest topics from the placement")
                                        .font(.system(size: 18, weight: .bold, design: .default))
                                        .foregroundStyle(AppPalette.muted)
                                    HStack(spacing: 10) {
                                        ForEach(placementPlan.focusTopics, id: \.self) { topic in
                                            TopicChip(topic: topic)
                                        }
                                    }
                                }
                            }

                            if !placementPlan.topicInsights.isEmpty {
                                PlacementTopicInsightChart(insights: placementPlan.topicInsights)
                            }

                            PlacementActionList(actions: placementPlan.nextWeekActions)
                        }
                    }
                }

                HStack(spacing: 16) {
                    MetricTile(title: "Accuracy", value: "\(summary?.accuracyPercent ?? 0)%", caption: "Correct answers this session", tint: AppPalette.blue)
                    MetricTile(title: "Points", value: "+\(model.latestPointsEarned)", caption: "Added to your running total", tint: AppPalette.terracotta)
                    MetricTile(title: "Mastered", value: "\(summary?.newlyMasteredCount ?? 0)", caption: "New words promoted this round", tint: AppPalette.success)
                }

                if let summary, !summary.weakTopics.isEmpty {
                    SurfaceCard(title: "Topics To Revisit") {
                        HStack(spacing: 10) {
                            ForEach(summary.weakTopics, id: \.self) { topic in
                                TopicChip(topic: topic)
                            }
                        }
                    }
                }

                HStack(spacing: 14) {
                    Button(summary?.mode == .placement ? "START DAILY CHALLENGE" : "RETRY FAILED WORDS") {
                        if summary?.mode == .placement {
                            model.startMission()
                        } else {
                            model.startFailedReview()
                        }
                    }
                        .buttonStyle(HeroButtonStyle(kind: .filled))
                        .frame(maxWidth: 420)
                    Button("BACK TO HOME") { model.openDashboard() }
                        .buttonStyle(HeroButtonStyle(kind: .outlined))
                        .frame(maxWidth: 360)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct ReviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHero(
                    eyebrow: "REVIEW QUEUE",
                    title: "Failed Words",
                    subtitle: "These words will keep returning until you rebuild their 3-correct streak.",
                    trailingText: "\(model.reviewWords.count)"
                )

                if model.reviewWords.isEmpty {
                    SurfaceCard {
                        ContentUnavailableView(
                            "No review words right now",
                            systemImage: "checkmark.circle",
                            description: Text("You cleared the current queue.")
                        )
                    }
                } else {
                    HStack(spacing: 12) {
                        Button("START REVIEW RESCUE") { model.startFailedReview() }
                            .buttonStyle(HeroButtonStyle(kind: .filled))
                            .frame(maxWidth: 380)
                        Button("BACK TO HOME") { model.openDashboard() }
                            .buttonStyle(HeroButtonStyle(kind: .outlined))
                            .frame(maxWidth: 280)
                    }

                    VStack(spacing: 12) {
                        ForEach(model.reviewWords, id: \.word.id) { item in
                            SurfaceCard {
                                HStack(spacing: 18) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(item.word.english)
                                            .font(.system(size: 30, weight: .bold, design: .serif))
                                            .foregroundStyle(AppPalette.ink)
                                        Text(item.word.primaryChinese)
                                            .font(.system(size: 20, weight: .medium, design: .default))
                                            .foregroundStyle(AppPalette.muted)
                                        HStack(spacing: 10) {
                                            TopicChip(topic: item.word.topic)
                                            PillLabel(text: "Streak \(item.progress.currentCorrectStreak)/3", tint: AppPalette.olive, fill: AppPalette.oliveSoft)
                                        }
                                    }

                                    Spacer()

                                    MetricTile(
                                        title: "Priority",
                                        value: "\(item.progress.reviewPriority)",
                                        caption: "Higher means it returns sooner",
                                        tint: AppPalette.terracotta
                                    )
                                    .frame(width: 230)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHero(
                    eyebrow: "SESSION HISTORY",
                    title: "Progress Trail",
                    subtitle: "Track how your placement tests, missions, and review rescues are adding up over time.",
                    trailingText: "\(model.sessionHistory.count)"
                )

                HStack(spacing: 12) {
                    Button("BACK TO HOME") { model.openDashboard() }
                        .buttonStyle(HeroButtonStyle(kind: .outlined))
                        .frame(maxWidth: 280)
                }

                if model.sessionHistory.isEmpty {
                    SurfaceCard {
                        ContentUnavailableView(
                            "No sessions yet",
                            systemImage: "clock",
                            description: Text("Complete a placement test or mission to start building history.")
                        )
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(model.sessionHistory, id: \.id) { summary in
                            SurfaceCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        PillLabel(text: summary.mode.title.uppercased(), tint: AppPalette.blue, fill: AppPalette.blueSoft)
                                        Spacer()
                                        Text(summary.completedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 16, weight: .medium, design: .default))
                                            .foregroundStyle(AppPalette.muted)
                                    }

                                    Text(summary.headline)
                                        .font(.system(size: 32, weight: .bold, design: .serif))
                                        .foregroundStyle(AppPalette.ink)

                                    Text(summary.body)
                                        .font(.system(size: 20, weight: .medium, design: .default))
                                        .foregroundStyle(AppPalette.muted)

                                    HStack(spacing: 14) {
                                        PillLabel(text: "Score \(summary.correctAnswers) / \(summary.totalQuestions)", tint: AppPalette.olive, fill: AppPalette.oliveSoft)
                                        PillLabel(text: "Accuracy \(summary.accuracyPercent)%", tint: AppPalette.blue, fill: AppPalette.blueSoft)
                                        PillLabel(text: "+\(summary.pointsEarned) points", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct SectionHero: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let trailingText: String

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow)
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .tracking(2)
                    .foregroundStyle(AppPalette.terracotta)

                Text(title)
                    .font(.system(size: 58, weight: .regular, design: .serif))
                    .foregroundStyle(AppPalette.ink)

                Text(subtitle)
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(AppPalette.muted)
            }

            Spacer()

            Text(trailingText)
                .font(.system(size: 120, weight: .regular, design: .serif))
                .foregroundStyle(AppPalette.ghost)
        }
    }
}

struct SurfaceCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .tracking(1)
                    .foregroundStyle(AppPalette.muted)
            }

            content
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(AppPalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 8)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .default))
                .tracking(0.8)
                .foregroundStyle(AppPalette.muted)

            Text(value)
                .font(.system(size: 34, weight: .bold, design: .default))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.75)

            Text(caption)
                .font(.system(size: 15, weight: .medium, design: .default))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppPalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.2)
        )
    }
}

struct PillLabel: View {
    let text: String
    let tint: Color
    let fill: Color

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .bold, design: .default))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(tint)
            .background(fill)
            .clipShape(Capsule())
    }
}

struct TopicChip: View {
    let topic: WordTopic

    var body: some View {
        Text(topic.displayName.uppercased())
            .font(.system(size: 14, weight: .bold, design: .default))
            .tracking(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(AppPalette.blue)
            .background(AppPalette.blueSoft)
            .clipShape(Capsule())
    }
}

struct PlacementActionList: View {
    let actions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next 7-day study plan")
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundStyle(AppPalette.muted)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundStyle(AppPalette.terracotta)
                            .frame(width: 24, alignment: .leading)
                        Text(action)
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.1)
        )
    }
}

struct PlacementTopicInsightChart: View {
    let insights: [PlacementTopicInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Topic performance")
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundStyle(AppPalette.muted)

            VStack(spacing: 10) {
                ForEach(insights.prefix(4), id: \.topic) { insight in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(insight.topic.displayName)
                                .font(.system(size: 17, weight: .semibold, design: .default))
                                .foregroundStyle(AppPalette.ink)
                            Spacer()
                            Text("\(insight.accuracyPercent)%")
                                .font(.system(size: 16, weight: .bold, design: .default))
                                .foregroundStyle(AppPalette.terracotta)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(AppPalette.border.opacity(0.4))
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [AppPalette.terracotta, AppPalette.olive],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: proxy.size.width * CGFloat(Double(insight.accuracyPercent) / 100.0))
                            }
                        }
                        .frame(height: 10)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.1)
        )
    }
}

struct PlacementMilestoneTrack: View {
    let progress: Int
    let totalQuestions: Int

    var body: some View {
        let milestones = stride(from: 20, through: totalQuestions, by: 20).map { $0 }

        return HStack(spacing: 10) {
            ForEach(milestones, id: \.self) { milestone in
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(progress >= milestone ? AppPalette.terracotta : AppPalette.border.opacity(0.4))
                            .frame(width: 28, height: 28)
                        Text("\(milestone / 20)")
                            .font(.system(size: 13, weight: .bold, design: .default))
                            .foregroundStyle(progress >= milestone ? Color.white : AppPalette.muted)
                    }
                    Text("\(milestone)")
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(AppPalette.muted)
                }

                if milestone != milestones.last {
                    Rectangle()
                        .fill(progress > milestone ? AppPalette.terracotta.opacity(0.7) : AppPalette.border.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .frame(height: 2)
                }
            }
        }
    }
}

struct PlacementCheckpointBanner: View {
    let checkpoint: Int
    let totalCheckpoints: Int
    let estimate: PlacementEstimate

    var body: some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(AppPalette.terracotta.opacity(0.14))
                        .frame(width: 68, height: 68)
                    Image(systemName: "flag.checkered.2.crossed")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AppPalette.terracotta)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Checkpoint \(checkpoint) of \(totalCheckpoints)")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.ink)
                    Text("Projected vocabulary now: \(estimate.estimatedVocabularySize) / \(estimate.benchmarkVocabularySize)")
                        .font(.system(size: 19, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.muted)
                }

                Spacer()

                PillLabel(text: estimate.placementBand.uppercased(), tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
            }
        }
    }
}

struct AnswerFeedbackCard: View {
    let feedback: QuizAnswerFeedback
    let action: () -> Void

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                if feedback.newlyMastered {
                    MasteryCelebrationBadge()
                }

                HStack(alignment: .center, spacing: 20) {
                    ZStack {
                        Circle()
                            .fill((feedback.isCorrect ? AppPalette.success : AppPalette.terracotta).opacity(0.15))
                            .frame(width: 72, height: 72)

                        Image(systemName: feedback.isCorrect ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(feedback.isCorrect ? AppPalette.success : AppPalette.terracotta)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(feedback.headline)
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                        Text(feedback.detail)
                            .font(.system(size: 20, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                        HStack(spacing: 10) {
                            PillLabel(text: "Correct answer: \(feedback.correctChoice)", tint: AppPalette.blue, fill: AppPalette.blueSoft)
                            if feedback.pointsEarned > 0 {
                                PillLabel(text: "+\(feedback.pointsEarned) points", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                            }
                        }
                    }

                    Spacer()

                    Button("CONTINUE NOW", action: action)
                        .buttonStyle(HeroButtonStyle(kind: .filled))
                        .frame(width: 270)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Continuing automatically...")
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(AppPalette.muted)
                        Spacer()
                        Text(feedback.newlyMastered ? "Hold the moment" : "Short pause")
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                    }
                    AutoAdvanceProgressBar(duration: feedback.autoAdvanceDelay)
                }
            }
        }
    }
}

struct MasteryCelebrationBadge: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .bold))
            Text("MASTERED WORD")
                .font(.system(size: 16, weight: .bold, design: .default))
                .tracking(1.5)
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .bold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .foregroundStyle(AppPalette.success)
        .background(AppPalette.oliveSoft)
        .clipShape(Capsule())
        .scaleEffect(animate ? 1.04 : 0.96)
        .shadow(color: AppPalette.success.opacity(0.15), radius: 16, x: 0, y: 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

struct AutoAdvanceProgressBar: View {
    let duration: TimeInterval
    @State private var fillAmount: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(AppPalette.border.opacity(0.45))
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppPalette.terracotta, AppPalette.olive],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * fillAmount)
            }
        }
        .frame(height: 10)
        .onAppear {
            fillAmount = 0
            withAnimation(.linear(duration: duration)) {
                fillAmount = 1
            }
        }
    }
}

struct ChoiceButton: View {
    enum VisualState {
        case idle
        case correct
        case incorrect
        case dimmed
    }

    let letter: String
    let text: String
    let accent: Color
    let state: VisualState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(circleFill)
                        .frame(width: 50, height: 50)

                    Text(letter)
                        .font(.system(size: 22, weight: .bold, design: .default))
                        .foregroundStyle(letterColor)
                }

                Text(text)
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundStyle(AppPalette.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(borderColor, lineWidth: state == .idle ? 1.2 : 2)
            )
            .overlay(alignment: .trailing) {
                if let symbol = symbolName {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(symbolColor)
                        .padding(.trailing, 22)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(state == .dimmed ? 0.65 : 1.0)
        .shadow(color: Color.black.opacity(0.03), radius: 12, x: 0, y: 6)
        .scaleEffect(state == .correct ? 1.01 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: state)
    }

    private var circleFill: Color {
        switch state {
        case .idle: return accent.opacity(0.14)
        case .correct: return AppPalette.success.opacity(0.14)
        case .incorrect: return AppPalette.terracotta.opacity(0.14)
        case .dimmed: return AppPalette.border.opacity(0.22)
        }
    }

    private var letterColor: Color {
        switch state {
        case .idle: return accent
        case .correct: return AppPalette.success
        case .incorrect: return AppPalette.terracotta
        case .dimmed: return AppPalette.muted
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle: return AppPalette.border
        case .correct: return AppPalette.success
        case .incorrect: return AppPalette.terracotta
        case .dimmed: return AppPalette.border
        }
    }

    private var symbolName: String? {
        switch state {
        case .correct: return "checkmark.circle.fill"
        case .incorrect: return "xmark.circle.fill"
        case .idle, .dimmed: return nil
        }
    }

    private var symbolColor: Color {
        switch state {
        case .correct: return AppPalette.success
        case .incorrect: return AppPalette.terracotta
        case .idle: return AppPalette.ink
        case .dimmed: return AppPalette.muted
        }
    }
}

struct HeroButtonStyle: ButtonStyle {
    enum Kind {
        case filled
        case outlined
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 32, weight: .bold, design: .default))
            .tracking(1)
            .foregroundStyle(kind == .filled ? Color.white : AppPalette.olive)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 26)
            .padding(.vertical, 28)
            .background(background(isPressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(kind == .filled ? AppPalette.olive : AppPalette.olive, lineWidth: kind == .filled ? 0 : 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.02 : 0.08), radius: configuration.isPressed ? 6 : 14, x: 0, y: configuration.isPressed ? 2 : 8)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        switch kind {
        case .filled:
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppPalette.olive.opacity(isPressed ? 0.92 : 1.0))
        case .outlined:
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(isPressed ? 0.92 : 1.0))
        }
    }
}

struct SecondaryNavButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold, design: .default))
            .tracking(1)
            .foregroundStyle(AppPalette.olive)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(AppPalette.oliveSoft)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}
