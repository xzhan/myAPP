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
        .defaultSize(width: 1120, height: 760)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.96, blue: 0.90), Color(red: 0.93, green: 0.97, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            switch model.screen {
            case .loading:
                ProgressView("Loading vocabulary...")
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
        .alert("Notice", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("PET Vocabulary Trainer")
                .font(.system(size: 42, weight: .bold, design: .rounded))
            Text("Measure how many PET words you already know, then keep learning with adaptive missions that recycle failed words until they stick.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "chart.line.uptrend.xyaxis", text: "See how many words you have mastered")
                featureRow(icon: "target", text: "Start with a PET placement test")
                featureRow(icon: "arrow.triangle.2.circlepath", text: "Failed words return in future missions")
                featureRow(icon: "sparkles", text: "Get coach-style feedback after every session")
            }

            Button("Start placement test") { model.startPlacement() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: 780, maxHeight: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your PET progress")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Build vocabulary with short missions, streaks, and instant review loops.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("History") { model.openHistory() }
                Button("Needs Review") { model.openReview() }
            }

            HStack(spacing: 18) {
                statCard(title: "Mastered", value: "\(stats.masteredCount) / \(stats.totalWordCount)", tint: Color(red: 0.16, green: 0.55, blue: 0.35))
                statCard(title: "Needs review", value: "\(stats.reviewCount)", tint: Color(red: 0.84, green: 0.39, blue: 0.12))
                statCard(title: "Daily streak", value: "\(stats.dailyStreak)", tint: Color(red: 0.24, green: 0.44, blue: 0.82))
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Today's mission")
                    .font(.headline)
                Text(stats.missionTitle)
                    .font(.title2.bold())
                HStack {
                    if model.data.hasCompletedPlacement {
                        Button("Start mission") { model.startMission() }
                            .buttonStyle(.borderedProminent)
                        Button("Retry failed words") { model.startFailedReview() }
                    } else {
                        Button("Take placement test") { model.startPlacement() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.76))
            .clipShape(RoundedRectangle(cornerRadius: 28))

            if let summary = model.sessionHistory.first {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Latest coach note")
                        .font(.headline)
                    Text(summary.headline)
                        .font(.title3.bold())
                    Text(summary.body)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }

            Spacer()
        }
        .padding(32)
    }

    private func statCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct QuizView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        guard let session = model.currentSession,
              let word = model.currentQuestionWord else {
            return AnyView(
                VStack(spacing: 20) {
                    Text("Preparing session...")
                    ProgressView()
                }
            )
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Text(session.mode.title)
                        .font(.headline)
                    Spacer()
                    Text("\(session.currentIndex + 1) / \(session.questions.count)")
                        .font(.headline)
                }

                ProgressView(value: Double(session.currentIndex), total: Double(session.questions.count))
                    .tint(Color(red: 0.22, green: 0.46, blue: 0.82))

                Spacer(minLength: 10)

                Text(word.english)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                Text("Choose the correct Chinese meaning")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(spacing: 14) {
                    ForEach(model.currentQuestionChoices, id: \.self) { choice in
                        Button {
                            model.submit(choice: choice)
                        } label: {
                            HStack {
                                Text(choice)
                                    .font(.title3.bold())
                                Spacer()
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal, 18)
                        }
                        .buttonStyle(.plain)
                        .background(.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                }

                Spacer()

                Text("Wrong answers reset the streak and push the word back into review.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        )
    }
}

struct SummaryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let summary = model.latestSummary
        VStack(alignment: .leading, spacing: 24) {
            Text(summary?.headline ?? "Session complete")
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text(summary?.body ?? "Your session has been recorded locally.")
                .font(.title3)
                .foregroundStyle(.secondary)

            if let summary {
                Label(summary.recommendedMissionTitle, systemImage: "target")
                    .font(.headline)
                if !summary.weakTopics.isEmpty {
                    Text("Weak topics: \(summary.weakTopics.map(\.displayName).joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Retry failed words") { model.startFailedReview() }
                    .buttonStyle(.borderedProminent)
                Button("Back to dashboard") { model.openDashboard() }
            }
            Spacer()
        }
        .padding(32)
    }
}

struct ReviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Needs Review")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Spacer()
                Button("Back") { model.openDashboard() }
            }

            if model.reviewWords.isEmpty {
                ContentUnavailableView("No review words right now", systemImage: "checkmark.circle", description: Text("You cleared the current queue."))
            } else {
                List(model.reviewWords, id: \.word.id) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.word.english)
                            .font(.headline)
                        Text(item.word.primaryChinese)
                            .foregroundStyle(.secondary)
                        Text("Streak: \(item.progress.currentCorrectStreak)  •  Errors: \(item.progress.totalIncorrect)  •  Priority: \(item.progress.reviewPriority)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(32)
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("History")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Spacer()
                Button("Back") { model.openDashboard() }
            }

            if model.sessionHistory.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "clock", description: Text("Complete a placement test or mission to start building history."))
            } else {
                List(model.sessionHistory, id: \.id) { summary in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(summary.mode.title)
                                .font(.headline)
                            Spacer()
                            Text(summary.completedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("Score: \(summary.correctAnswers) / \(summary.totalQuestions)")
                        Text("Newly mastered: \(summary.newlyMasteredCount)")
                            .foregroundStyle(.secondary)
                        Text(summary.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(32)
    }
}
