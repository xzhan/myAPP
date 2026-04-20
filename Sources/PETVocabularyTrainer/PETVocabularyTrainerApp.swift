import SwiftUI

@main
struct PETVocabularyTrainerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    model.bootstrap()
                }
        }
        .defaultSize(width: 1180, height: 820)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.95, blue: 0.89), Color(red: 0.90, green: 0.96, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.97, green: 0.72, blue: 0.52).opacity(0.20))
                .frame(width: 360, height: 360)
                .offset(x: 430, y: -280)

            Circle()
                .fill(Color(red: 0.35, green: 0.58, blue: 0.92).opacity(0.16))
                .frame(width: 420, height: 420)
                .offset(x: -420, y: 300)

            content
                .padding(20)
        }
        .alert("Notice", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .loading:
            GlassCard {
                VStack(spacing: 20) {
                    Text("Loading vocabulary...")
                    ProgressView()
                }
                .frame(width: 320)
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
        HStack(alignment: .top, spacing: 24) {
            GlassCard {
                VStack(alignment: .leading, spacing: 22) {
                    Text("PET Vocabulary Trainer")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                    Text("Measure how many PET words you already know, then turn daily review into a game-like practice loop with missions, streaks, and coach feedback.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 14) {
                        featureRow(icon: "chart.line.uptrend.xyaxis", text: "See exactly how many PET words you have mastered")
                        featureRow(icon: "sparkles.rectangle.stack", text: "Start with a placement test to set your baseline")
                        featureRow(icon: "flag.pattern.checkered", text: "Get short missions that mix new words and failed words")
                        featureRow(icon: "person.crop.circle.badge.checkmark", text: "Receive coach-style feedback after each session")
                    }

                    Button("Start placement test") { model.startPlacement() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 18) {
                    PillLabel(text: "How it feels", tint: Color(red: 0.97, green: 0.72, blue: 0.52))
                    Text("Daily momentum")
                        .font(.title.bold())
                    VStack(spacing: 14) {
                        MetricTile(title: "Placement", value: "20 words", caption: "Quick baseline test", tint: Color(red: 0.24, green: 0.44, blue: 0.82))
                        MetricTile(title: "Mission", value: "15 words", caption: "Short daily sprint", tint: Color(red: 0.16, green: 0.58, blue: 0.36))
                        MetricTile(title: "Mastery", value: "3 correct", caption: "Across separate attempts", tint: Color(red: 0.82, green: 0.42, blue: 0.15))
                    }
                }
            }
            .frame(width: 310)
        }
        .frame(maxWidth: 1100, maxHeight: .infinity, alignment: .center)
    }

    private func featureRow(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.headline)
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.dashboardStats

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 22) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Your PET progress")
                                        .font(.system(size: 34, weight: .bold, design: .rounded))
                                    Text("Rank: \(stats.rankTitle)")
                                        .font(.headline)
                                        .foregroundStyle(Color(red: 0.82, green: 0.42, blue: 0.15))
                                }
                                Spacer()
                                Button("History") { model.openHistory() }
                                Button("Needs Review") { model.openReview() }
                            }

                            Text(stats.missionTitle)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text(stats.missionSubtitle)
                                .font(.body)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                if model.data.hasCompletedPlacement {
                                    Button("Start mission") { model.startMission() }
                                        .buttonStyle(.borderedProminent)
                                    Button("Retry failed words") { model.startFailedReview() }
                                        .disabled(stats.reviewCount == 0)
                                } else {
                                    Button("Take placement test") { model.startPlacement() }
                                        .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }

                    GlassCard {
                        HStack(spacing: 18) {
                            ProgressRing(
                                value: Double(stats.masteryPercent) / 100.0,
                                title: "PET mastery",
                                valueText: "\(stats.masteryPercent)%",
                                tint: Color(red: 0.16, green: 0.58, blue: 0.36)
                            )

                            VStack(alignment: .leading, spacing: 12) {
                                MetricTile(title: "Points", value: "\(stats.totalPoints)", caption: "Earned from correct answers + mastery", tint: Color(red: 0.97, green: 0.72, blue: 0.52))
                                MetricTile(title: "Streak", value: "\(stats.dailyStreak) days", caption: "Keep showing up", tint: Color(red: 0.24, green: 0.44, blue: 0.82))
                            }
                        }
                    }
                    .frame(width: 360)
                }

                HStack(spacing: 18) {
                    MetricTile(title: "Mastered", value: "\(stats.masteredCount) / \(stats.totalWordCount)", caption: "Vocabulary already locked in", tint: Color(red: 0.16, green: 0.58, blue: 0.36))
                    MetricTile(title: "Needs review", value: "\(stats.reviewCount)", caption: "Words waiting for rescue", tint: Color(red: 0.82, green: 0.42, blue: 0.15))
                    MetricTile(
                        title: "Coach note",
                        value: model.latestSummary?.headline ?? "Ready",
                        caption: model.latestSummary?.recommendedMissionTitle ?? "Start your next mission",
                        tint: Color(red: 0.24, green: 0.44, blue: 0.82)
                    )
                }

                if !stats.focusTopics.isEmpty {
                    GlassCard(title: "Focus topics") {
                        HStack(spacing: 10) {
                            ForEach(stats.focusTopics, id: \.self) { topic in
                                TopicChip(topic: topic)
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    MissionActionCard(
                        title: "Daily Sprint",
                        subtitle: "Mix new words with unfinished review",
                        detail: "15 fast questions",
                        accent: Color(red: 0.24, green: 0.44, blue: 0.82),
                        buttonTitle: "Launch sprint",
                        action: model.startMission
                    )
                    MissionActionCard(
                        title: "Review Rescue",
                        subtitle: "Push failed words back into memory",
                        detail: "\(max(4, min(10, stats.reviewCount))) review words",
                        accent: Color(red: 0.82, green: 0.42, blue: 0.15),
                        buttonTitle: "Rescue words",
                        action: model.startFailedReview,
                        disabled: stats.reviewCount == 0
                    )
                }

                if let summary = model.sessionHistory.first {
                    GlassCard(title: "Latest coach note") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(summary.headline)
                                .font(.title3.bold())
                            Text(summary.body)
                                .foregroundStyle(.secondary)
                            Text("+\(summary.pointsEarned) points")
                                .font(.headline)
                                .foregroundStyle(Color(red: 0.82, green: 0.42, blue: 0.15))
                        }
                    }
                }
            }
            .padding(6)
        }
    }
}

struct QuizView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.currentSession,
           let word = model.currentQuestionWord {
            let progress = model.currentWordProgress ?? .fresh(for: word.id)
            let accent = session.mode == .failedReview ? Color(red: 0.82, green: 0.42, blue: 0.15) : Color(red: 0.24, green: 0.44, blue: 0.82)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        PillLabel(text: session.mode.title, tint: accent)
                        PillLabel(text: "Accuracy \(model.currentAccuracyPercent)%", tint: Color(red: 0.16, green: 0.58, blue: 0.36))
                        PillLabel(text: "Streak \(progress.currentCorrectStreak)/3", tint: Color(red: 0.97, green: 0.72, blue: 0.52))
                        Spacer()
                        Text("\(model.currentQuestionNumber) / \(session.questions.count)")
                            .font(.headline)
                    }

                    ProgressView(value: Double(session.currentIndex), total: Double(session.questions.count))
                        .tint(accent)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                TopicChip(topic: word.topic)
                                Spacer()
                                Text("Current score: \(session.correctAnswers)")
                                    .foregroundStyle(.secondary)
                            }
                            Text(word.english)
                                .font(.system(size: 60, weight: .bold, design: .rounded))
                            Text("Choose the correct Chinese meaning. Wrong answers reset this word’s mastery streak and push it back into review.")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 14) {
                        ForEach(Array(model.currentQuestionChoices.enumerated()), id: \.offset) { index, choice in
                            Button {
                                model.submit(choice: choice)
                            } label: {
                                HStack(spacing: 16) {
                                    ZStack {
                                        Circle()
                                            .fill(accent.opacity(0.16))
                                            .frame(width: 40, height: 40)
                                        Text(String(UnicodeScalar(65 + index)!))
                                            .font(.headline.bold())
                                            .foregroundStyle(accent)
                                    }
                                    Text(choice)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 18)
                                .padding(.horizontal, 18)
                            }
                            .buttonStyle(.plain)
                            .background(.white.opacity(0.84))
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                        }
                    }

                    GlassCard(title: "Word goal") {
                        HStack(spacing: 18) {
                            MetricTile(title: "Correct streak", value: "\(progress.currentCorrectStreak) / 3", caption: "Needed to mark this word mastered", tint: accent)
                            MetricTile(title: "Errors", value: "\(progress.totalIncorrect)", caption: "Wrong answers bring the word back", tint: Color(red: 0.82, green: 0.42, blue: 0.15))
                        }
                    }
                }
                .padding(6)
            }
        } else {
            GlassCard {
                VStack(spacing: 20) {
                    Text("Preparing session...")
                    ProgressView()
                }
            }
        }
    }
}

struct SummaryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let summary = model.latestSummary

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(summary?.headline ?? "Session complete")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        Text(summary?.body ?? "Your session has been recorded locally.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        if let summary {
                            Label(summary.recommendedMissionTitle, systemImage: "target")
                                .font(.headline)
                                .foregroundStyle(Color(red: 0.24, green: 0.44, blue: 0.82))
                        }
                    }
                }

                HStack(spacing: 18) {
                    MetricTile(title: "Accuracy", value: "\(summary?.accuracyPercent ?? 0)%", caption: "Correct answers this session", tint: Color(red: 0.24, green: 0.44, blue: 0.82))
                    MetricTile(title: "Points", value: "+\(model.latestPointsEarned)", caption: "Added to your total score", tint: Color(red: 0.97, green: 0.72, blue: 0.52))
                    MetricTile(title: "New mastery", value: "\(summary?.newlyMasteredCount ?? 0)", caption: "Words promoted to mastered", tint: Color(red: 0.16, green: 0.58, blue: 0.36))
                }

                if let summary, !summary.weakTopics.isEmpty {
                    GlassCard(title: "Topics to revisit") {
                        HStack(spacing: 10) {
                            ForEach(summary.weakTopics, id: \.self) { topic in
                                TopicChip(topic: topic)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button("Retry failed words") { model.startFailedReview() }
                        .buttonStyle(.borderedProminent)
                    Button("Back to dashboard") { model.openDashboard() }
                }
            }
            .padding(6)
        }
    }
}

struct ReviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Needs Review")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("These words will keep resurfacing until you rebuild their 3-correct streak.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Back") { model.openDashboard() }
                }

                if model.reviewWords.isEmpty {
                    GlassCard {
                        ContentUnavailableView("No review words right now", systemImage: "checkmark.circle", description: Text("You cleared the current queue."))
                    }
                } else {
                    Button("Start review rescue") { model.startFailedReview() }
                        .buttonStyle(.borderedProminent)

                    VStack(spacing: 12) {
                        ForEach(model.reviewWords, id: \.word.id) { item in
                            GlassCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(item.word.english)
                                            .font(.title3.bold())
                                        Text(item.word.primaryChinese)
                                            .foregroundStyle(.secondary)
                                        HStack(spacing: 10) {
                                            TopicChip(topic: item.word.topic)
                                            Text("Streak \(item.progress.currentCorrectStreak)/3")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    MetricTile(title: "Priority", value: "\(item.progress.reviewPriority)", caption: "How soon it returns", tint: Color(red: 0.82, green: 0.42, blue: 0.15))
                                        .frame(width: 170)
                                }
                            }
                        }
                    }
                }
            }
            .padding(6)
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("History")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Track how your placement, missions, and review rescues are adding up over time.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Back") { model.openDashboard() }
                }

                if model.sessionHistory.isEmpty {
                    GlassCard {
                        ContentUnavailableView("No sessions yet", systemImage: "clock", description: Text("Complete a placement test or mission to start building history."))
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(model.sessionHistory, id: \.id) { summary in
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        PillLabel(text: summary.mode.title, tint: Color(red: 0.24, green: 0.44, blue: 0.82))
                                        Spacer()
                                        Text(summary.completedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(summary.headline)
                                        .font(.title3.bold())
                                    Text(summary.body)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 18) {
                                        Text("Score: \(summary.correctAnswers) / \(summary.totalQuestions)")
                                        Text("Accuracy: \(summary.accuracyPercent)%")
                                        Text("+\(summary.pointsEarned) points")
                                            .foregroundStyle(Color(red: 0.82, green: 0.42, blue: 0.15))
                                    }
                                    .font(.headline)
                                }
                            }
                        }
                    }
                }
            }
            .padding(6)
        }
    }
}

struct GlassCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.55), lineWidth: 1)
        )
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
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

struct PillLabel: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.footnote.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(0.16))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

struct TopicChip: View {
    let topic: WordTopic

    var body: some View {
        Text(topic.displayName)
            .font(.footnote.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.24, green: 0.44, blue: 0.82).opacity(0.12))
            .foregroundStyle(Color(red: 0.24, green: 0.44, blue: 0.82))
            .clipShape(Capsule())
    }
}

struct ProgressRing: View {
    let value: Double
    let title: String
    let valueText: String
    let tint: Color

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.16), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: max(0.04, min(value, 1.0)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text(valueText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MissionActionCard: View {
    let title: String
    let subtitle: String
    let detail: String
    let accent: Color
    let buttonTitle: String
    let action: () -> Void
    var disabled: Bool = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                PillLabel(text: title, tint: accent)
                Text(subtitle)
                    .font(.title3.bold())
                Text(detail)
                    .foregroundStyle(.secondary)
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .disabled(disabled)
            }
        }
    }
}
