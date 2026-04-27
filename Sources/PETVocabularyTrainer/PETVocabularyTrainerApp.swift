import AppKit
import SwiftUI

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
    static let successSoft = Color(red: 0.90, green: 0.95, blue: 0.90)
    static let error = Color(red: 0.77, green: 0.34, blue: 0.28)
    static let errorSoft = Color(red: 0.98, green: 0.91, blue: 0.88)
    static let catGold = Color(red: 0.88, green: 0.63, blue: 0.27)
    static let catCream = Color(red: 0.99, green: 0.95, blue: 0.88)
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
                    activateApplicationWindow()
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

            VStack(alignment: .leading, spacing: model.showsCompactWordBankBar ? 22 : 0) {
                if model.showsCompactWordBankBar {
                    HStack {
                        Spacer()
                        GlobalActionBar()
                    }
                }

                content
                    .frame(maxWidth: 1240, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 58)
            .padding(.vertical, 48)

            if model.isImportingWordBank || model.isImportingReadingPack {
                Color.white.opacity(0.52)
                    .ignoresSafeArea()

                SurfaceCard {
                    VStack(spacing: 18) {
                        ProgressView()
                            .tint(AppPalette.olive)
                            .scaleEffect(1.15)

                        Text(
                            model.isImportingReadingPack
                                ? "Importing Reading Pack"
                                : (model.pendingVocabularyImportIntent == .questJSON
                                    ? "Importing Quest JSON"
                                    : "Importing Base PET PDF")
                        )
                            .font(.system(size: 30, weight: .semibold, design: .serif))
                            .foregroundStyle(AppPalette.ink)

                        Text(
                            model.isImportingReadingPack
                                ? "Reading TXT files are being parsed now. Single files and whole folders both import here."
                                : (model.pendingVocabularyImportIntent == .questJSON
                                    ? "Quest overlay pages are being merged onto the current PET index now."
                                    : "Large PET PDF files can take a moment. The app will unlock automatically when the import finishes.")
                        )
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppPalette.muted)
                            .frame(maxWidth: 420)
                    }
                    .frame(maxWidth: 460)
                }
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
        .confirmationDialog(
            "Replace Current Word Bank?",
            isPresented: Binding(
                get: { model.isShowingReimportConfirmation },
                set: { if !$0 { model.dismissPendingVocabularyReplacement() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Continue Import", role: .destructive) {
                model.confirmVocabularyReimport()
            }
            Button("Cancel", role: .cancel) {
                model.dismissPendingVocabularyReplacement()
            }
        } message: {
            Text(model.reimportConfirmationMessage)
        }
        .confirmationDialog(
            "Replace Current Reading Pack?",
            isPresented: Binding(
                get: { model.isShowingReadingReimportConfirmation },
                set: { model.isShowingReadingReimportConfirmation = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Continue Import", role: .destructive) {
                model.confirmReadingReimport()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.readingReimportConfirmationMessage)
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
        case .readingQuiz:
            ReadingQuizView()
        case .summary:
            SummaryView()
        case .review:
            ReviewView()
        case .history:
            TrophiesView()
        case .reading:
            ReadingView()
        }
    }
}

struct GlobalActionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                bankSummary
                actionButtons(isCompact: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                bankSummary
                actionButtons(isCompact: false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppPalette.panel.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var bankSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WORD BANK")
                .font(.system(size: 13, weight: .bold, design: .default))
                .tracking(1.4)
                .foregroundStyle(AppPalette.terracotta)
            Text(model.wordBankSnapshot.title)
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(model.wordBankSnapshot.wordCount) words ready")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionButtons(isCompact: Bool) -> some View {
        let snapshot = model.wordBankSnapshot
        let importTitle = snapshot.isImportedActive ? "IMPORT BASE PDF" : "IMPORT BASE PDF"

        if isCompact {
            HStack(spacing: 12) {
                if snapshot.hasSavedImport && !snapshot.isImportedActive {
                    Button("USE SAVED IMPORT") {
                        model.activateSavedImportedWordBank()
                    }
                    .buttonStyle(CompactActionButtonStyle(kind: .outlined))
                }

                Button(importTitle) {
                    model.requestBaseImport()
                }
                .buttonStyle(CompactActionButtonStyle(kind: .filled))

                if snapshot.isImportedActive {
                    Button("USE BUNDLED") {
                        model.resetToBundledWordBank()
                    }
                    .buttonStyle(CompactActionButtonStyle(kind: .outlined))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if snapshot.hasSavedImport && !snapshot.isImportedActive {
                    Button("USE SAVED IMPORT") {
                        model.activateSavedImportedWordBank()
                    }
                    .buttonStyle(CompactActionButtonStyle(kind: .outlined))
                }

                Button(importTitle) {
                    model.requestBaseImport()
                }
                .buttonStyle(CompactActionButtonStyle(kind: .filled))

                if snapshot.isImportedActive {
                    Button("USE BUNDLED STARTER") {
                        model.resetToBundledWordBank()
                    }
                    .buttonStyle(CompactActionButtonStyle(kind: .outlined))
                }
            }
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ThreeFunctionsHomeView()
    }

    @ViewBuilder
    private func onboardingMainColumn(
        compact: Bool,
        usesQuestPages: Bool,
        hasPlacement: Bool,
        hasPausedSession: Bool,
        primaryTitle: String,
        secondaryTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 24 : 28) {
            Text("MASTERY PROGRAM")
                .font(.system(size: compact ? 24 : 28, weight: .bold, design: .default))
                .tracking(2)
                .foregroundStyle(AppPalette.terracotta)

            Text("Vocabulary Journey")
                .font(.system(size: compact ? 72 : 88, weight: .regular, design: .serif))
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Text("Boost your skills with smart, gamified daily training")
                Text("or a full PET baseline diagnostic.")
            }
            .font(.system(size: compact ? 28 : 34, weight: .medium, design: .serif))
            .italic()
            .foregroundStyle(AppPalette.muted)

            LaunchActionCard(
                title: usesQuestPages
                    ? ((model.currentQuestPageLabel.map { "\($0) is ready" }) ?? "Today's page is ready")
                    : (hasPlacement ? "Today's 45-word plan is ready" : "Start with your 100-word test"),
                subtitle: usesQuestPages
                    ? "Start here first. The selected imported page is now the main unit. PET base pages stay stable, and quest overlays can enrich specific pages later without changing the page index."
                    : (hasPlacement
                    ? "Start here first. Your daily study flow is ready and today's plan already knows how many review words are due."
                    : "Take the placement test first, then the app will guide you into the daily 45-word study flow."),
                resumeTitle: hasPausedSession ? model.resumeSessionTitle : nil,
                onResume: hasPausedSession ? { model.resumeCurrentSession() } : nil,
                primaryTitle: primaryTitle,
                primaryKind: hasPausedSession ? .outlined : .filled,
                onPrimary: {
                    if usesQuestPages {
                        model.startMission()
                    } else if hasPlacement {
                        model.startMission()
                    } else {
                        model.startPlacement()
                    }
                },
                secondaryTitle: secondaryTitle,
                secondarySystemImage: usesQuestPages ? "square.and.arrow.down" : (hasPlacement ? "trophy" : "sparkles"),
                onSecondary: {
                    if usesQuestPages {
                        model.requestQuestImport()
                    } else if hasPlacement {
                        model.startPlacement()
                    } else {
                        model.startMission()
                    }
                },
                supportingText: hasPausedSession
                    ? "Your current session is saved locally. You can resume it now or start a fresh study path."
                    : nil
            )
            .frame(maxWidth: 760)

            StudyTracksCard()
                .frame(maxWidth: 760)

            VStack(alignment: .leading, spacing: 8) {
                Rectangle()
                    .fill(AppPalette.line)
                    .frame(maxWidth: compact ? .infinity : 620)
                    .frame(height: 4)
                Rectangle()
                    .fill(AppPalette.line)
                    .frame(maxWidth: compact ? 340 : 340)
                    .frame(height: 4)
            }

            ImportLayersCard()
                .frame(maxWidth: 760)

            WordBankCard(
                snapshot: model.wordBankSnapshot,
                onImport: { model.requestBaseImport() },
                onRestoreImport: model.wordBankSnapshot.hasSavedImport && !model.wordBankSnapshot.isImportedActive
                    ? { model.activateSavedImportedWordBank() }
                    : nil,
                onReset: model.wordBankSnapshot.isImportedActive ? { model.resetToBundledWordBank() } : nil
            )
            .frame(maxWidth: 760)

            if usesQuestPages {
                QuestPageSelectionCard()
                    .frame(maxWidth: 760)
            }

            DailyStudyPlanCard(
                snapshot: model.dailyStudySnapshot,
                primaryActionTitle: usesQuestPages ? "START TEST 45" : (hasPlacement ? "START TODAY'S 45-WORD PLAN" : "START 100-WORD TEST"),
                onPrimaryAction: {
                    if usesQuestPages {
                        model.startMission()
                    } else if hasPlacement {
                        model.startMission()
                    } else {
                        model.startPlacement()
                    }
                }
            )
            .frame(maxWidth: 760)

            ReadingPreviewCard(
                snapshot: model.readingCenterSnapshot,
                onOpen: { model.openReading() }
            )
            .frame(maxWidth: 760)

            Text(usesQuestPages
                    ? "Recommendation: move page by page. If you already finished an earlier unit, use the page selector to jump straight to the next target page."
                    : "Recommendation: start with the 100-word test to set your PET bar, then use daily challenges to keep failed words coming back until they are mastered.")
                .font(.system(size: 20, weight: .medium, design: .default))
                .foregroundStyle(AppPalette.muted)
                .frame(maxWidth: 760, alignment: .leading)
        }
    }

    @ViewBuilder
    private func onboardingProgressColumn(hasPlacement: Bool) -> some View {
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
    }

    @ViewBuilder
    private func onboardingCompactProgressCard(hasPlacement: Bool) -> some View {
        if hasPlacement {
            SurfaceCard(title: "Study Progress") {
                HStack(spacing: 16) {
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
            }
        }
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ThreeFunctionsHomeView()
    }

    @ViewBuilder
    private func dashboardHeaderColumn(stats: DashboardStats, hasPausedSession: Bool, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("MASTERY PROGRAM")
                .font(.system(size: 24, weight: .bold, design: .default))
                .tracking(2)
                .foregroundStyle(AppPalette.terracotta)

            Text("Vocabulary Journey")
                .font(.system(size: compact ? 66 : 78, weight: .regular, design: .serif))
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(stats.missionSubtitle)
                .font(.system(size: compact ? 24 : 30, weight: .medium, design: .serif))
                .italic()
                .foregroundStyle(AppPalette.muted)
                .frame(maxWidth: 760, alignment: .leading)

            LaunchActionCard(
                title: model.hasQuestPages
                    ? ((model.currentQuestPageLabel.map { "\($0) quest is ready" }) ?? "Start today's page quest")
                    : "Start today's 45-word plan",
                subtitle: model.hasQuestPages
                    ? "This launches the page you selected below. You can jump directly to page 14 or any other imported page without clearing completed-page history."
                    : "This is the main entrance to today's study. It launches the due-review words first, then fills the rest with fresh vocabulary.",
                resumeTitle: hasPausedSession ? model.resumeSessionTitle : nil,
                onResume: hasPausedSession ? { model.resumeCurrentSession() } : nil,
                primaryTitle: model.hasQuestPages ? "START TEST 45" : "TODAY'S 45-WORD PLAN",
                primaryKind: hasPausedSession ? .outlined : .filled,
                onPrimary: { model.startMission() },
                secondaryTitle: model.hasQuestPages ? "IMPORT QUEST JSON" : "100-WORD TEST",
                secondarySystemImage: model.hasQuestPages ? "square.and.arrow.down" : "trophy",
                onSecondary: {
                    if model.hasQuestPages {
                        model.requestQuestImport()
                    } else {
                        model.startPlacement()
                    }
                },
                supportingText: hasPausedSession
                    ? "Current session progress is saved. Resume it now, or start a new mission when you are ready."
                    : nil
            )
            .frame(maxWidth: 760)

            HStack(spacing: 12) {
                Button("FAILED WORDS") { model.openReview() }
                    .buttonStyle(SecondaryNavButtonStyle())
                Button("TROPHIES") { model.openTrophies() }
                    .buttonStyle(SecondaryNavButtonStyle())
                Button("READING") { model.openReading() }
                    .buttonStyle(SecondaryNavButtonStyle())
            }
        }
    }

    private func dashboardProgressColumn(stats: DashboardStats) -> some View {
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
    }
}

struct ThreeFunctionsHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isShowingResourceManager = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                let snapshot = model.homeMissionSnapshot

                HStack(alignment: .top, spacing: 18) {
                    if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
                       let icon = NSImage(contentsOf: iconURL) {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 70, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("HOME MAINLINE")
                            .font(.system(size: 18, weight: .bold, design: .default))
                            .tracking(4)
                            .foregroundStyle(AppPalette.terracotta)
                        Text(snapshot.title)
                            .font(.system(size: 64, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer()

                    Button(snapshot.importActionTitle) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isShowingResourceManager.toggle()
                        }
                    }
                    .buttonStyle(HorizontalMainlineSecondaryButtonStyle())
                }

                Text(snapshot.subtitle)
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HomeMissionRouteCard(snapshot: snapshot)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        BenchmarkTestPanel(snapshot: snapshot)
                        ResourceStatusPanel(
                            snapshot: snapshot,
                            isShowingManager: isShowingResourceManager,
                            onAddQuest: { model.requestQuestImport() },
                            onToggleManager: {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    isShowingResourceManager.toggle()
                                }
                            }
                        )
                    }

                    VStack(spacing: 20) {
                        BenchmarkTestPanel(snapshot: snapshot)
                        ResourceStatusPanel(
                            snapshot: snapshot,
                            isShowingManager: isShowingResourceManager,
                            onAddQuest: { model.requestQuestImport() },
                            onToggleManager: {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    isShowingResourceManager.toggle()
                                }
                            }
                        )
                    }
                }

                if isShowingResourceManager {
                    ImportHubCard()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct HomeMissionRouteCard: View {
    @Environment(AppModel.self) private var model
    let snapshot: HomeMissionSnapshot

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today's Route")
                            .font(.system(size: 40, weight: .bold, design: .default))
                            .foregroundStyle(AppPalette.ink)
                        Text("Horizontal mainline: one page, one path, one obvious next action.")
                            .font(.system(size: 20, weight: .semibold, design: .default))
                            .foregroundStyle(AppPalette.muted)
                    }

                    Spacer()

                    VStack(spacing: 5) {
                        Text(snapshot.currentPageLabel)
                            .font(.system(size: 42, weight: .bold, design: .default))
                            .foregroundStyle(Color.white)
                        Text(snapshot.currentPageCaption)
                            .font(.system(size: 15, weight: .bold, design: .default))
                            .tracking(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                    .background(AppPalette.olive)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 7)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(snapshot.steps) { step in
                            HomeMissionStepCard(step: step)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(snapshot.steps) { step in
                                HomeMissionStepCard(step: step)
                                    .frame(width: 190)
                            }
                        }
                        .padding(.bottom, 2)
                    }
                }
            }
        }
    }
}

struct HomeMissionStepCard: View {
    @Environment(AppModel.self) private var model
    let step: HomeMissionStepSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step.numberText)
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(Color.white)
                .frame(width: 62, height: 62)
                .background(tint)
                .clipShape(Circle())
                .shadow(color: tint.opacity(0.22), radius: 10, x: 0, y: 6)

            PillLabel(text: step.statusText, tint: tint, fill: tint.opacity(0.13))

            Text(step.title)
                .font(.system(size: 23, weight: .bold, design: .default))
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(step.detail)
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            actionView
        }
        .padding(18)
        .frame(minHeight: 258, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppPalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.2)
        )
    }

    @ViewBuilder
    private var actionView: some View {
        switch step.kind {
        case .todayPage:
            if model.questPageChooserPages.count > 1 {
                pageMenu
            } else if let actionTitle = step.actionTitle {
                Button(actionTitle) {
                    if model.currentQuestPage == nil {
                        model.requestBaseImport()
                    }
                }
                .buttonStyle(HorizontalMainlineActionButtonStyle(tint: tint))
            }
        case .quest:
            if let actionTitle = step.actionTitle {
                Button(model.currentSession?.mode != nil && model.currentSession?.mode != .placement ? model.resumeSessionTitle : actionTitle) {
                    if model.currentSession?.mode != nil && model.currentSession?.mode != .placement {
                        model.resumeCurrentSession()
                    } else {
                        model.performCurrentUnitPrimaryAction()
                    }
                }
                .buttonStyle(HorizontalMainlineActionButtonStyle(tint: tint))
            }
        case .reading:
            if let actionTitle = step.actionTitle {
                Button(actionTitle) {
                    model.performCurrentUnitPrimaryAction()
                }
                .buttonStyle(HorizontalMainlineActionButtonStyle(tint: tint))
            }
        case .reminder:
            if let actionTitle = step.actionTitle {
                Button(actionTitle) {
                    model.openReview()
                }
                .buttonStyle(HorizontalMainlineActionButtonStyle(tint: tint))
            }
        case .trophies:
            Button(step.actionTitle ?? "OPEN TROPHIES") {
                model.openTrophies()
            }
            .buttonStyle(HorizontalMainlineActionButtonStyle(tint: tint))
        }
    }

    private var pageMenu: some View {
        Menu {
            ForEach(model.questPageChooserPages) { page in
                Button(model.questPageMenuLabel(for: page)) {
                    model.selectQuestPage(page.pageNumber)
                }
            }
        } label: {
            Label(step.actionTitle ?? "GO TO PAGE", systemImage: "list.bullet")
        }
        .buttonStyle(HorizontalMainlineActionButtonStyle(tint: tint))
    }

    private var tint: Color {
        switch step.style {
        case .page:
            return AppPalette.blue
        case .quest:
            return AppPalette.terracotta
        case .reading:
            return AppPalette.success
        case .reminder:
            return AppPalette.olive
        case .trophies:
            return AppPalette.catGold
        }
    }
}

struct BenchmarkTestPanel: View {
    @Environment(AppModel.self) private var model
    let snapshot: HomeMissionSnapshot

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(snapshot.benchmarkTitle)
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .foregroundStyle(AppPalette.ink)

                Text(snapshot.benchmarkDetail)
                    .font(.system(size: 19, weight: .semibold, design: .default))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Button(snapshot.benchmarkActionTitle) {
                    if model.currentSession?.mode == .placement {
                        model.resumeCurrentSession()
                    } else {
                        model.startPlacement()
                    }
                }
                .buttonStyle(HorizontalMainlineActionButtonStyle(tint: AppPalette.olive))
                .frame(maxWidth: 340)
            }
        }
    }
}

struct ResourceStatusPanel: View {
    let snapshot: HomeMissionSnapshot
    let isShowingManager: Bool
    let onAddQuest: () -> Void
    let onToggleManager: () -> Void

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Resource Status")
                            .font(.system(size: 32, weight: .bold, design: .default))
                            .foregroundStyle(AppPalette.ink)
                        Text("Import stays quiet unless setup is missing or Quest pages need adding.")
                            .font(.system(size: 19, weight: .semibold, design: .default))
                            .foregroundStyle(AppPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(isShowingManager ? "HIDE" : "MANAGE") {
                        onToggleManager()
                    }
                    .buttonStyle(SecondaryNavButtonStyle())
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        ForEach(snapshot.resources) { resource in
                            resourceTile(resource)
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(snapshot.resources) { resource in
                            resourceTile(resource)
                        }
                    }
                }

                Button("ADD QUEST PAGES", action: onAddQuest)
                    .buttonStyle(SecondaryNavButtonStyle())
            }
        }
    }

    private func resourceTile(_ resource: HomeMissionResourceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(resource.valueText)
                .font(.system(size: 30, weight: .bold, design: .default))
                .foregroundStyle(AppPalette.ink)
            Text(resource.title)
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundStyle(AppPalette.muted)
            Text(resource.detail)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(AppPalette.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.0)
        )
    }
}

struct HorizontalMainlineActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .default))
            .tracking(1)
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
            .background(tint.opacity(configuration.isPressed ? 0.88 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
    }
}

struct HorizontalMainlineSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold, design: .default))
            .tracking(1.6)
            .foregroundStyle(AppPalette.olive)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(AppPalette.panel.opacity(configuration.isPressed ? 0.82 : 0.96))
            .overlay(
                Capsule()
                    .stroke(AppPalette.olive, lineWidth: 2)
            )
            .clipShape(Capsule())
    }
}

struct QuestFeatureCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SurfaceCard(title: "Daily Quest") {
            if model.hasQuestPages, let currentPage = model.currentQuestPage {
                let snapshot = model.currentUnitSnapshot
                let preview = model.currentQuestPagePreviewSnapshot

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Page \(currentPage.pageNumber) Quest")
                                .font(.system(size: 44, weight: .bold, design: .serif))
                                .foregroundStyle(AppPalette.ink)
                            Text("One page at a time works best for junior learners: finish the 45-word quest first, then continue straight into the matching Reading step.")
                                .font(.system(size: 20, weight: .medium, design: .default))
                                .foregroundStyle(AppPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            PillLabel(text: snapshot.stageBadgeText, tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                            PillLabel(text: model.questPageStatusText(for: currentPage), tint: AppPalette.blue, fill: AppPalette.blueSoft)
                        }
                    }

                    if !snapshot.layerSnapshots.isEmpty {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 14) {
                                ForEach(snapshot.layerSnapshots) { layer in
                                    MetricTile(
                                        title: layer.title,
                                        value: layer.valueText,
                                        caption: layer.caption,
                                        tint: tint(for: layer.style)
                                    )
                                }
                            }

                            VStack(spacing: 14) {
                                ForEach(snapshot.layerSnapshots) { layer in
                                    MetricTile(
                                        title: layer.title,
                                        value: layer.valueText,
                                        caption: layer.caption,
                                        tint: tint(for: layer.style)
                                    )
                                }
                            }
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            primaryQuestButton(snapshot: snapshot)
                            if model.sortedQuestPages.count > 1 {
                                pageMenu
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            primaryQuestButton(snapshot: snapshot)
                            if model.sortedQuestPages.count > 1 {
                                pageMenu
                            }
                        }
                    }

                    if let progressText = snapshot.progressText {
                        Text(progressText)
                            .font(.system(size: 17, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.terracotta)
                    }

                    if let preview {
                        pagePreview(preview)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quest is waiting for page data")
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.ink)
                    Text("Import the PET page data first. Once pages are available, this card becomes the one daily flow: Quest 45 followed by the matching Reading page.")
                        .font(.system(size: 20, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("OPEN IMPORT") {
                        model.requestBaseImport()
                    }
                    .buttonStyle(HeroButtonStyle(kind: .filled))
                    .frame(maxWidth: 260)
                }
            }
        }
    }

    @ViewBuilder
    private func primaryQuestButton(snapshot: CurrentUnitSnapshot) -> some View {
        if let session = model.currentSession, session.mode != .placement {
            Button(model.resumeSessionTitle) {
                model.resumeCurrentSession()
            }
            .buttonStyle(HeroButtonStyle(kind: .outlined))
            .frame(maxWidth: 320)
        } else {
            Button(snapshot.primaryActionTitle) {
                model.performCurrentUnitPrimaryAction()
            }
            .buttonStyle(HeroButtonStyle(kind: .filled))
            .frame(maxWidth: 340)
        }
    }

    private var pageMenu: some View {
        Menu {
            ForEach(model.questPageChooserPages) { page in
                Button(model.questPageMenuLabel(for: page)) {
                    model.selectQuestPage(page.pageNumber)
                }
            }
        } label: {
            Label("CHOOSE PAGE", systemImage: "list.bullet")
        }
        .buttonStyle(HeroButtonStyle(kind: .outlined))
        .frame(maxWidth: 260)
    }

    private func tint(for style: CurrentUnitLayerStyle) -> Color {
        switch style {
        case .ready:
            return AppPalette.blue
        case .enhanced:
            return AppPalette.terracotta
        case .preview:
            return AppPalette.blue
        case .waiting, .missing:
            return AppPalette.error
        case .completed:
            return AppPalette.success
        case .neutral:
            return AppPalette.olive
        }
    }

    @ViewBuilder
    private func pagePreview(_ preview: QuestPagePreviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("PAGE PREVIEW")
                    .font(.system(size: 13, weight: .bold, design: .default))
                    .tracking(1.1)
                    .foregroundStyle(AppPalette.muted)
                Spacer()
                FlowLayout(spacing: 8) {
                    ForEach(Array(preview.tags.enumerated()), id: \.offset) { _, tag in
                        PillLabel(text: tag, tint: AppPalette.blue, fill: AppPalette.blueSoft)
                    }
                }
            }

            Text(preview.title)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.ink)

            Text(preview.summary)
                .font(.system(size: 17, weight: .semibold, design: .default))
                .foregroundStyle(AppPalette.terracotta)

            Text(preview.previewText)
                .font(.system(size: 18, weight: .medium, design: .default))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.1)
        )
    }
}

struct VocabularyAssessmentCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let baseSnapshot = model.importLaneSnapshots.first(where: { $0.kind == .base })
        let latestEstimate = model.latestPlacementEstimate
        let latestPlacementSummary = model.latestPlacementSummary

        SurfaceCard(title: "Vocabulary Assessment") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("100-Word Check")
                            .font(.system(size: 40, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                        Text("Use the stable base PET bank to estimate a child's current vocabulary size. This track stays separate from Quest practice.")
                            .font(.system(size: 20, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if let baseSnapshot {
                        PillLabel(text: baseSnapshot.statusText.uppercased(), tint: AppPalette.blue, fill: AppPalette.blueSoft)
                    }
                }

                if let latestEstimate, let latestPlacementSummary {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            MetricTile(
                                title: "Latest Estimate",
                                value: "\(latestEstimate.estimatedVocabularySize)",
                                caption: latestEstimate.placementBand,
                                tint: AppPalette.terracotta
                            )
                            MetricTile(
                                title: "Latest Score",
                                value: "\(latestPlacementSummary.correctAnswers)/\(latestPlacementSummary.totalQuestions)",
                                caption: "Most recent vocabulary assessment",
                                tint: AppPalette.success
                            )
                        }

                        VStack(spacing: 16) {
                            MetricTile(
                                title: "Latest Estimate",
                                value: "\(latestEstimate.estimatedVocabularySize)",
                                caption: latestEstimate.placementBand,
                                tint: AppPalette.terracotta
                            )
                            MetricTile(
                                title: "Latest Score",
                                value: "\(latestPlacementSummary.correctAnswers)/\(latestPlacementSummary.totalQuestions)",
                                caption: "Most recent vocabulary assessment",
                                tint: AppPalette.success
                            )
                        }
                    }
                }

                Button(model.currentSession?.mode == .placement ? model.resumeSessionTitle : "START 100-WORD TEST") {
                    if model.currentSession?.mode == .placement {
                        model.resumeCurrentSession()
                    } else {
                        model.startPlacement()
                    }
                }
                .buttonStyle(HeroButtonStyle(kind: .filled))
                .frame(maxWidth: 340)
            }
        }
    }
}

struct ImportHubCard: View {
    @Environment(AppModel.self) private var model
    @State private var manuallyExpanded: Bool? = nil

    private var isExpanded: Bool {
        manuallyExpanded ?? !model.shouldDeemphasizeImportSurface
    }

    var body: some View {
        let snapshots = model.importLaneSnapshots

        SurfaceCard(title: "Resources") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.shouldDeemphasizeImportSurface ? "Setup stays saved" : "Finish setup once")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)

                        Text(model.shouldDeemphasizeImportSurface
                                ? "Base and Reading usually only need importing once. Later, this shelf mostly stays here for adding Quest pages or checking what is already saved."
                                : "Import Base and Reading first. After that, learners should spend most of their time in Quest or Vocabulary Assessment instead of managing files.")
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 10) {
                        if model.shouldDeemphasizeImportSurface {
                            Button("ADD QUEST PAGES") {
                                model.requestQuestImport()
                            }
                            .buttonStyle(SecondaryNavButtonStyle())
                        }

                        Button(isExpanded ? "HIDE DETAILS" : "MANAGE IMPORTS") {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                manuallyExpanded = !isExpanded
                            }
                        }
                        .buttonStyle(SecondaryNavButtonStyle())
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        resourceTile(
                            title: "Base",
                            value: snapshots.first(where: { $0.kind == .base })?.statusText ?? "Waiting",
                            caption: model.importedBasePageCount > 0 ? "\(model.importedBasePageCount) base pages" : "Stable benchmark layer",
                            tint: AppPalette.blue,
                            fill: AppPalette.blueSoft
                        )
                        resourceTile(
                            title: "Quest",
                            value: snapshots.first(where: { $0.kind == .quest })?.statusText ?? "Pending",
                            caption: model.importedQuestPageCount > 0 ? "\(model.importedQuestPageCount) enhanced pages" : "Add pages over time",
                            tint: AppPalette.terracotta,
                            fill: AppPalette.oliveSoft
                        )
                        resourceTile(
                            title: "Reading",
                            value: snapshots.first(where: { $0.kind == .reading })?.statusText ?? "Waiting",
                            caption: model.importedReadingPageCount > 0 ? "\(model.importedReadingPageCount) reading pages" : "Page-matched reading layer",
                            tint: AppPalette.success,
                            fill: AppPalette.successSoft
                        )
                    }

                    VStack(spacing: 12) {
                        resourceTile(
                            title: "Base",
                            value: snapshots.first(where: { $0.kind == .base })?.statusText ?? "Waiting",
                            caption: model.importedBasePageCount > 0 ? "\(model.importedBasePageCount) base pages" : "Stable benchmark layer",
                            tint: AppPalette.blue,
                            fill: AppPalette.blueSoft
                        )
                        resourceTile(
                            title: "Quest",
                            value: snapshots.first(where: { $0.kind == .quest })?.statusText ?? "Pending",
                            caption: model.importedQuestPageCount > 0 ? "\(model.importedQuestPageCount) enhanced pages" : "Add pages over time",
                            tint: AppPalette.terracotta,
                            fill: AppPalette.oliveSoft
                        )
                        resourceTile(
                            title: "Reading",
                            value: snapshots.first(where: { $0.kind == .reading })?.statusText ?? "Waiting",
                            caption: model.importedReadingPageCount > 0 ? "\(model.importedReadingPageCount) reading pages" : "Page-matched reading layer",
                            tint: AppPalette.success,
                            fill: AppPalette.successSoft
                        )
                    }
                }

                if !isExpanded, let compactPreview = compactPinnedPreview {
                    compactPreviewCard(preview: compactPreview.preview, kind: compactPreview.kind)
                }

                if isExpanded {
                    VStack(spacing: 16) {
                        ForEach(snapshots) { snapshot in
                            importLane(snapshot)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    @ViewBuilder
    private func importLane(_ snapshot: ImportLaneSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.title)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.ink)
                    Text(snapshot.detail)
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                PillLabel(text: snapshot.statusText.uppercased(), tint: tint(for: snapshot.kind), fill: fill(for: snapshot.kind))
            }

            Button(actionLabel(for: snapshot.kind)) {
                switch snapshot.kind {
                case .base:
                    model.requestBaseImport()
                case .quest:
                    model.requestQuestImport()
                case .reading:
                    model.requestReadingImport()
                }
            }
            .buttonStyle(SecondaryNavButtonStyle())
            .frame(maxWidth: 220)

            if let preview = model.importPreviewSnapshot(for: snapshot.kind) {
                importPreview(preview, kind: snapshot.kind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.1)
        )
    }

    private var compactPinnedPreview: (kind: ImportLaneKind, preview: ImportPreviewSnapshot)? {
        if let preview = model.importPreviewSnapshot(for: .quest) {
            return (.quest, preview)
        }
        if let preview = model.importPreviewSnapshot(for: .reading) {
            return (.reading, preview)
        }
        if let preview = model.importPreviewSnapshot(for: .base) {
            return (.base, preview)
        }
        return nil
    }

    @ViewBuilder
    private func compactPreviewCard(preview: ImportPreviewSnapshot, kind: ImportLaneKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CURRENT PREVIEW")
                .font(.system(size: 13, weight: .bold, design: .default))
                .tracking(1)
                .foregroundStyle(AppPalette.muted)

            Text(preview.title)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.ink)

            Text(preview.subtitle)
                .font(.system(size: 17, weight: .medium, design: .default))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(fill(for: kind).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tint(for: kind).opacity(0.24), lineWidth: 1.1)
        )
    }

    @ViewBuilder
    private func importPreview(_ preview: ImportPreviewSnapshot, kind: ImportLaneKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IMPORTED PREVIEW")
                .font(.system(size: 13, weight: .bold, design: .default))
                .tracking(1)
                .foregroundStyle(AppPalette.muted)

            Text(preview.title)
                .font(.system(size: 23, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.ink)

            Text(preview.subtitle)
                .font(.system(size: 17, weight: .medium, design: .default))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    previewTags(preview.tags, kind: kind)
                }

                VStack(alignment: .leading, spacing: 8) {
                    previewTags(preview.tags, kind: kind)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(fill(for: kind).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tint(for: kind).opacity(0.24), lineWidth: 1.1)
        )
    }

    @ViewBuilder
    private func previewTags(_ tags: [String], kind: ImportLaneKind) -> some View {
        ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
            PillLabel(text: tag, tint: tint(for: kind), fill: fill(for: kind))
        }
    }

    @ViewBuilder
    private func resourceTile(
        title: String,
        value: String,
        caption: String,
        tint: Color,
        fill: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .bold, design: .default))
                .tracking(1)
                .foregroundStyle(AppPalette.muted)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(caption)
                .font(.system(size: 15, weight: .medium, design: .default))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(fill.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1.0)
        )
    }

    private func actionLabel(for kind: ImportLaneKind) -> String {
        switch kind {
        case .base:
            return model.importedBasePageCount > 0 ? "Replace Base PDF" : "Import Base PDF"
        case .quest:
            return model.importedQuestPageCount > 0 ? "Add Quest Pages" : "Import Quest JSON"
        case .reading:
            return model.importedReadingPageCount > 0 ? "Update Reading" : "Import Reading"
        }
    }

    private func tint(for kind: ImportLaneKind) -> Color {
        switch kind {
        case .base:
            return AppPalette.blue
        case .quest:
            return AppPalette.terracotta
        case .reading:
            return AppPalette.success
        }
    }

    private func fill(for kind: ImportLaneKind) -> Color {
        switch kind {
        case .base:
            return AppPalette.blueSoft
        case .quest:
            return AppPalette.oliveSoft
        case .reading:
            return AppPalette.successSoft
        }
    }
}

struct PageMainlineHomeView: View {
    @Environment(AppModel.self) private var model

    let showProgressMetrics: Bool

    var body: some View {
        let snapshot = model.currentUnitSnapshot
        let reminderSnapshot = model.reviewReminderSnapshot

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHero(
                    eyebrow: "PAGE MAINLINE",
                    title: "Current Unit",
                    subtitle: "Finish the page word step first, then continue into the matching Reading step before you move on. Later quest overlays should strengthen the same page instead of replacing the path.",
                    trailingText: model.currentQuestPage.map { "\($0.pageNumber)" } ?? "GO"
                )

                CurrentUnitCard(
                    snapshot: snapshot,
                    resumeTitle: model.currentUnitResumeSessionTitle,
                    onResume: model.currentUnitResumeSessionTitle != nil ? { model.resumeCurrentSession() } : nil,
                    onPrimary: { model.performCurrentUnitPrimaryAction() }
                )

                StudyTracksCard()

                if showProgressMetrics {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            MetricTile(
                                title: "Word pages",
                                value: "\(model.completedQuestPagesList.count)/\(model.sortedQuestPages.count)",
                                caption: "Word quests finished so far",
                                tint: AppPalette.success
                            )
                            MetricTile(
                                title: "Reading ready",
                                value: "\(model.readingCenterSnapshot.quizReadyCount)",
                                caption: "Imported pages that can become graded Reading",
                                tint: AppPalette.blue
                            )
                            MetricTile(
                                title: "Trophies",
                                value: "\(model.sessionHistory.count)",
                                caption: "Completed sessions already recorded",
                                tint: AppPalette.terracotta
                            )
                        }

                        VStack(spacing: 16) {
                            HStack(spacing: 16) {
                                MetricTile(
                                    title: "Word pages",
                                    value: "\(model.completedQuestPagesList.count)/\(model.sortedQuestPages.count)",
                                    caption: "Word quests finished so far",
                                    tint: AppPalette.success
                                )
                                MetricTile(
                                    title: "Reading ready",
                                    value: "\(model.readingCenterSnapshot.quizReadyCount)",
                                    caption: "Imported pages that can become graded Reading",
                                    tint: AppPalette.blue
                                )
                            }

                            MetricTile(
                                title: "Trophies",
                                value: "\(model.sessionHistory.count)",
                                caption: "Completed sessions already recorded",
                                tint: AppPalette.terracotta
                            )
                        }
                    }
                }

                ImportLayersCard()

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        QuestPageSelectionCard()
                        TrophiesPreviewCard(
                            latestSummary: model.latestSummary ?? model.sessionHistory.first,
                            totalSessions: model.sessionHistory.count,
                            onOpen: { model.openTrophies() }
                        )
                        .frame(width: 360)
                    }

                    VStack(spacing: 16) {
                        QuestPageSelectionCard()
                        TrophiesPreviewCard(
                            latestSummary: model.latestSummary ?? model.sessionHistory.first,
                            totalSessions: model.sessionHistory.count,
                            onOpen: { model.openTrophies() }
                        )
                    }
                }

                WordBankCard(
                    snapshot: model.wordBankSnapshot,
                    onImport: { model.requestBaseImport() },
                    onRestoreImport: model.wordBankSnapshot.hasSavedImport && !model.wordBankSnapshot.isImportedActive
                        ? { model.activateSavedImportedWordBank() }
                        : nil,
                    onReset: model.wordBankSnapshot.isImportedActive ? { model.resetToBundledWordBank() } : nil
                )

                if reminderSnapshot.dueNowCount > 0 || reminderSnapshot.scheduledLaterCount > 0 {
                    ReminderOverviewCard(
                        snapshot: reminderSnapshot,
                        reviewWords: model.reviewWordSnapshots,
                        title: "Review Reminder"
                    )
                }

                HStack(spacing: 12) {
                    Button("READING HUB") { model.openReading() }
                        .buttonStyle(SecondaryNavButtonStyle())
                    Button("REVIEW REMINDERS") { model.openReview() }
                        .buttonStyle(SecondaryNavButtonStyle())
                    Button("TROPHIES") { model.openTrophies() }
                        .buttonStyle(SecondaryNavButtonStyle())
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct CurrentUnitCard: View {
    let snapshot: CurrentUnitSnapshot
    let resumeTitle: String?
    let onResume: (() -> Void)?
    let onPrimary: () -> Void

    var body: some View {
        SurfaceCard(title: "Current Unit") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(snapshot.title)
                            .font(.system(size: 38, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                        Text(snapshot.subtitle)
                            .font(.system(size: 20, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 10) {
                        PillLabel(text: snapshot.stageBadgeText, tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                        if let pageBadgeText = snapshot.pageBadgeText {
                            PillLabel(text: pageBadgeText, tint: AppPalette.blue, fill: AppPalette.blueSoft)
                        }
                    }
                }

                if snapshot.layerSnapshots.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            MetricTile(
                                title: "Word Step",
                                value: snapshot.wordStatus.valueText,
                                caption: snapshot.wordStatus.caption,
                                tint: wordStatusTint(snapshot.wordStatus)
                            )
                            if let readingState = snapshot.readingState {
                                MetricTile(
                                    title: "Reading Step",
                                    value: readingState.valueText,
                                    caption: readingState.caption,
                                    tint: readingStateTint(readingState)
                                )
                            }
                            MetricTile(
                                title: "Target",
                                value: snapshot.targetValueText,
                                caption: snapshot.targetCaption,
                                tint: AppPalette.olive
                            )
                        }

                        VStack(spacing: 16) {
                            HStack(spacing: 16) {
                                MetricTile(
                                    title: "Word Step",
                                    value: snapshot.wordStatus.valueText,
                                    caption: snapshot.wordStatus.caption,
                                    tint: wordStatusTint(snapshot.wordStatus)
                                )
                                if let readingState = snapshot.readingState {
                                    MetricTile(
                                        title: "Reading Step",
                                        value: readingState.valueText,
                                        caption: readingState.caption,
                                        tint: readingStateTint(readingState)
                                    )
                                }
                            }

                            MetricTile(
                                title: "Target",
                                value: snapshot.targetValueText,
                                caption: snapshot.targetCaption,
                                tint: AppPalette.olive
                            )
                        }
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            ForEach(snapshot.layerSnapshots) { layer in
                                MetricTile(
                                    title: layer.title,
                                    value: layer.valueText,
                                    caption: layer.caption,
                                    tint: layerTint(layer.style)
                                )
                            }
                            MetricTile(
                                title: "Target",
                                value: snapshot.targetValueText,
                                caption: snapshot.targetCaption,
                                tint: AppPalette.olive
                            )
                        }

                        VStack(spacing: 16) {
                            ForEach(snapshot.layerSnapshots) { layer in
                                MetricTile(
                                    title: layer.title,
                                    value: layer.valueText,
                                    caption: layer.caption,
                                    tint: layerTint(layer.style)
                                )
                            }

                            MetricTile(
                                title: "Target",
                                value: snapshot.targetValueText,
                                caption: snapshot.targetCaption,
                                tint: AppPalette.olive
                            )
                        }
                    }
                }

                if let progressText = snapshot.progressText {
                    Text(progressText)
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(AppPalette.ink)
                }

                Text(snapshot.nextHint)
                    .font(.system(size: 17, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.terracotta)

                if let resumeTitle, let onResume {
                    Button(resumeTitle, action: onResume)
                        .buttonStyle(HeroButtonStyle(kind: .outlined))
                        .frame(maxWidth: 520)
                }

                Button(snapshot.primaryActionTitle, action: onPrimary)
                    .buttonStyle(HeroButtonStyle(kind: .filled))
                    .frame(maxWidth: 540)
            }
        }
    }

    private func wordStatusTint(_ status: CurrentUnitWordStatus) -> Color {
        switch status {
        case .placementNeeded:
            return AppPalette.blue
        case .ready:
            return AppPalette.terracotta
        case .completed:
            return AppPalette.success
        }
    }

    private func readingStateTint(_ state: CurrentUnitReadingState) -> Color {
        switch state {
        case .waitingForImport, .missingForPage:
            return AppPalette.error
        case .previewOnly:
            return AppPalette.blue
        case .ready:
            return AppPalette.terracotta
        case .completed:
            return AppPalette.success
        }
    }

    private func layerTint(_ style: CurrentUnitLayerStyle) -> Color {
        switch style {
        case .ready:
            return AppPalette.blue
        case .enhanced:
            return AppPalette.terracotta
        case .preview:
            return AppPalette.blue
        case .waiting, .missing:
            return AppPalette.error
        case .completed:
            return AppPalette.success
        case .neutral:
            return AppPalette.olive
        }
    }
}

struct TrophiesPreviewCard: View {
    let latestSummary: SessionSummary?
    let totalSessions: Int
    let onOpen: () -> Void

    var body: some View {
        SurfaceCard(title: "Trophies") {
            VStack(alignment: .leading, spacing: 16) {
                if let latestSummary {
                    Text("Latest trophy")
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .foregroundStyle(AppPalette.muted)

                    Text(latestSummary.headline)
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(latestSummary.body)
                        .font(.system(size: 18, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        PillLabel(text: "Accuracy \(latestSummary.accuracyPercent)%", tint: AppPalette.blue, fill: AppPalette.blueSoft)
                        PillLabel(text: "Review \(latestSummary.failedAnswers)", tint: AppPalette.error, fill: AppPalette.errorSoft)
                    }
                } else {
                    Text("No trophies yet")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.ink)
                    Text("Complete the current unit to start building a visible history of wins, misses, and reminder words.")
                        .font(.system(size: 18, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.muted)
                }

                MetricTile(
                    title: "Total",
                    value: "\(totalSessions)",
                    caption: "Finished sessions recorded",
                    tint: AppPalette.terracotta
                )

                Button("OPEN TROPHIES", action: onOpen)
                    .buttonStyle(SecondaryNavButtonStyle())
                    .frame(maxWidth: 220)
            }
        }
    }
}

struct StudyTracksCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SurfaceCard(title: "Two Mainlines") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(model.studyTrackSnapshots) { snapshot in
                        trackTile(snapshot)
                    }
                }

                VStack(spacing: 16) {
                    ForEach(model.studyTrackSnapshots) { snapshot in
                        trackTile(snapshot)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trackTile(_ snapshot: StudyTrackSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.title)
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.ink)
                    Text(snapshot.detail)
                        .font(.system(size: 18, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                PillLabel(
                    text: snapshot.statusText.uppercased(),
                    tint: snapshot.id == "base-assessment" ? AppPalette.blue : AppPalette.terracotta,
                    fill: snapshot.id == "base-assessment" ? AppPalette.blueSoft : AppPalette.oliveSoft
                )
            }

            Button(snapshot.primaryActionTitle) {
                handlePrimaryAction(for: snapshot)
            }
            .buttonStyle(HeroButtonStyle(kind: .filled))
            .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.1)
        )
    }

    private func handlePrimaryAction(for snapshot: StudyTrackSnapshot) {
        switch snapshot.id {
        case "base-assessment":
            if snapshot.primaryActionTitle.contains("IMPORT") {
                model.requestBaseImport()
            } else {
                model.startPlacement()
            }
        default:
            let title = snapshot.primaryActionTitle
            if title.contains("START READING") {
                model.startCurrentReadingQuest()
            } else if title.contains("OPEN READING PREVIEW") || title.contains("OPEN READING HUB") {
                model.openReading()
            } else if title.contains("IMPORT READING") {
                model.requestReadingImport()
            } else if title.contains("IMPORT QUEST") {
                model.requestQuestImport()
            } else if title.contains("VIEW TROPHIES") {
                model.openTrophies()
            } else if title.contains("GO TO PAGE") {
                model.advanceToNextQuestPage()
            } else {
                model.startMission()
            }
        }
    }
}

struct ImportLayersCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SurfaceCard(title: "Import Sources") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Keep Base, Quest, and Reading as three aligned data layers. Import each one from its own lane so the same PET page index stays clear.")
                    .font(.system(size: 18, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(model.importLaneSnapshots) { snapshot in
                            importTile(snapshot)
                        }
                    }

                    VStack(spacing: 16) {
                        ForEach(model.importLaneSnapshots) { snapshot in
                            importTile(snapshot)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func importTile(_ snapshot: ImportLaneSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.title)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.ink)
                    Text(snapshot.detail)
                        .font(.system(size: 17, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                PillLabel(
                    text: snapshot.statusText.uppercased(),
                    tint: tint(for: snapshot.kind),
                    fill: fill(for: snapshot.kind)
                )
            }

            Button(snapshot.actionTitle) {
                switch snapshot.kind {
                case .base:
                    model.requestBaseImport()
                case .quest:
                    model.requestQuestImport()
                case .reading:
                    model.requestReadingImport()
                }
            }
            .buttonStyle(HeroButtonStyle(kind: .outlined))
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.1)
        )
    }

    private func tint(for kind: ImportLaneKind) -> Color {
        switch kind {
        case .base:
            return AppPalette.blue
        case .quest:
            return AppPalette.terracotta
        case .reading:
            return AppPalette.success
        }
    }

    private func fill(for kind: ImportLaneKind) -> Color {
        switch kind {
        case .base:
            return AppPalette.blueSoft
        case .quest:
            return AppPalette.oliveSoft
        case .reading:
            return AppPalette.successSoft
        }
    }
}

struct WordBankCard: View {
    let snapshot: WordBankSnapshot
    let onImport: () -> Void
    let onRestoreImport: (() -> Void)?
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
                            tint: snapshot.isImportedActive ? AppPalette.terracotta : AppPalette.blue,
                            fill: snapshot.isImportedActive ? AppPalette.oliveSoft : AppPalette.blueSoft
                        )
                        if let progressText = snapshot.progressText {
                            Text(progressText)
                                .font(.system(size: 16, weight: .semibold, design: .default))
                                .foregroundStyle(AppPalette.ink)
                        }
                        Text("\(snapshot.wordCount) words")
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(AppPalette.muted)
                    }
                }

                HStack(spacing: 12) {
                    if let onRestoreImport, snapshot.hasSavedImport, !snapshot.isImportedActive {
                        Button("USE SAVED IMPORT") {
                            onRestoreImport()
                        }
                        .buttonStyle(SecondaryNavButtonStyle())
                    }

                    Button(snapshot.isImportedActive ? "IMPORT NEW BASE PDF" : "IMPORT BASE PDF") {
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

                if snapshot.isImportedActive {
                    Text("Switching back to bundled now only resets active word-bank progress. Your saved import and Trophies remain.")
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.terracotta)
                } else if snapshot.hasSavedImport, let savedImportTitle = snapshot.savedImportTitle {
                    Text("Saved import ready: \(savedImportTitle). You can restore it without re-importing.")
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.terracotta)
                }
            }
        }
    }
}

struct QuestPageSelectionCard: View {
    @Environment(AppModel.self) private var model
    @State private var pageInput = ""
    @State private var jumpFeedback = ""
    @State private var jumpFeedbackIsError = false

    var body: some View {
        if let currentPage = model.currentQuestPage {
            let preview = model.currentQuestPagePreviewSnapshot
            let chooserPages = model.questPageChooserPages
            let chooserTitle = model.allQuestEnhancedPages.isEmpty ? "Imported Pages" : "Quest Enhanced"

            SurfaceCard(title: "Choose Study Page") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current unit: Page \(currentPage.pageNumber)")
                                .font(.system(size: 28, weight: .bold, design: .serif))
                                .foregroundStyle(AppPalette.ink)
                            Text(model.allQuestEnhancedPages.isEmpty
                                ? "Jump between imported pages here. Once richer quest overlays arrive, this chooser can stay focused on that stronger page sequence."
                                : "This chooser now stays focused on the Quest Enhanced sequence, so the learner sees the richer page path first instead of every status bucket.")
                                .font(.system(size: 18, weight: .medium, design: .default))
                                .foregroundStyle(AppPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            PillLabel(text: "PAGE \(currentPage.pageNumber)", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                            Text(model.questPageStatusText(for: currentPage))
                                .font(.system(size: 16, weight: .semibold, design: .default))
                                .foregroundStyle(AppPalette.ink)
                            Text("\(currentPage.wordCount) words")
                                .font(.system(size: 17, weight: .semibold, design: .default))
                                .foregroundStyle(AppPalette.muted)
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            MetricTile(
                                title: "Selected",
                                value: "Page \(currentPage.pageNumber)",
                                caption: "The launch target right now",
                                tint: AppPalette.terracotta
                            )
                            MetricTile(
                                title: chooserTitle,
                                value: "\(chooserPages.count)",
                                caption: model.allQuestEnhancedPages.isEmpty
                                    ? "Imported pages available now"
                                    : "Richer quest pages available now",
                                tint: AppPalette.blue
                            )
                            MetricTile(
                                title: "Reading",
                                value: model.readingState(forPageNumber: currentPage.pageNumber).valueText,
                                caption: model.readingState(forPageNumber: currentPage.pageNumber).caption,
                                tint: AppPalette.success
                            )
                        }

                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                MetricTile(
                                    title: "Selected",
                                    value: "Page \(currentPage.pageNumber)",
                                    caption: "The launch target right now",
                                    tint: AppPalette.terracotta
                                )
                                MetricTile(
                                    title: chooserTitle,
                                    value: "\(chooserPages.count)",
                                    caption: model.allQuestEnhancedPages.isEmpty
                                        ? "Imported pages available now"
                                        : "Richer quest pages available now",
                                    tint: AppPalette.blue
                                )
                            }

                            MetricTile(
                                title: "Reading",
                                value: model.readingState(forPageNumber: currentPage.pageNumber).valueText,
                                caption: model.readingState(forPageNumber: currentPage.pageNumber).caption,
                                tint: AppPalette.success
                            )
                        }
                    }

                    HStack(spacing: 12) {
                        Menu {
                            Section(chooserTitle) {
                                ForEach(chooserPages) { page in
                                    Button(model.questPageMenuLabel(for: page)) {
                                        model.selectQuestPage(page.pageNumber)
                                        syncSelectionState(
                                            with: page.pageNumber,
                                            message: page.isQuestEnhanced
                                                ? "Page \(page.pageNumber) is ready with the quest overlay."
                                                : "Page \(page.pageNumber) is selected."
                                        )
                                    }
                                }
                            }
                        } label: {
                            Label("CHOOSE PAGE", systemImage: "book.closed")
                        }
                        .buttonStyle(SecondaryNavButtonStyle())

                        HStack(spacing: 10) {
                            TextField("14", text: $pageInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: 18, weight: .semibold, design: .default))
                                .foregroundStyle(AppPalette.ink)
                                .frame(width: 88)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.white.opacity(0.72))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(AppPalette.border, lineWidth: 1.1)
                                )
                                .onSubmit {
                                    jumpToTypedPage()
                                }

                            Button("GO TO PAGE") {
                                jumpToTypedPage()
                            }
                            .buttonStyle(SecondaryNavButtonStyle())
                        }

                        Button("START NEW TEST") {
                            model.startMission()
                        }
                        .buttonStyle(SecondaryNavButtonStyle())
                    }

                    if !jumpFeedback.isEmpty {
                        Text(jumpFeedback)
                            .font(.system(size: 16, weight: .medium, design: .default))
                            .foregroundStyle(jumpFeedbackIsError ? AppPalette.terracotta : AppPalette.success)
                    }

                    if let preview {
                        pagePreview(preview)
                    }
                }
            }
            .onAppear {
                syncSelectionState(with: currentPage.pageNumber, message: "")
            }
            .onChange(of: currentPage.pageNumber) { _, newValue in
                syncSelectionState(with: newValue, message: "")
            }
        }
    }

    private func jumpToTypedPage() {
        let trimmed = pageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageNumber = Int(trimmed) else {
            jumpFeedback = model.allQuestEnhancedPages.isEmpty
                ? "Enter a valid imported page number, such as 14."
                : "Enter a valid Quest Enhanced page number, such as 14."
            jumpFeedbackIsError = true
            return
        }

        guard model.questPageChooserPages.contains(where: { $0.pageNumber == pageNumber }) else {
            jumpFeedback = model.allQuestEnhancedPages.isEmpty
                ? "Page \(pageNumber) is not in the current import. Choose one of the imported pages instead."
                : "Page \(pageNumber) is not in the Quest Enhanced sequence yet."
            jumpFeedbackIsError = true
            return
        }

        model.selectQuestPage(pageNumber)
        syncSelectionState(with: pageNumber, message: "Page \(pageNumber) is now the current unit.")
    }

    private func syncSelectionState(with pageNumber: Int, message: String) {
        pageInput = "\(pageNumber)"
        jumpFeedback = message
        jumpFeedbackIsError = false
    }

    @ViewBuilder
    private func pagePreview(_ preview: QuestPagePreviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PAGE PREVIEW")
                .font(.system(size: 13, weight: .bold, design: .default))
                .tracking(1)
                .foregroundStyle(AppPalette.muted)

            Text(preview.title)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.ink)

            Text(preview.summary)
                .font(.system(size: 17, weight: .semibold, design: .default))
                .foregroundStyle(AppPalette.terracotta)

            Text(preview.previewText)
                .font(.system(size: 18, weight: .medium, design: .default))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                ForEach(Array(preview.tags.enumerated()), id: \.offset) { _, tag in
                    PillLabel(text: tag, tint: AppPalette.blue, fill: AppPalette.blueSoft)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.1)
        )
    }
}

struct DailyStudyPlanCard: View {
    let snapshot: DailyStudySnapshot
    var primaryActionTitle: String? = nil
    var onPrimaryAction: (() -> Void)? = nil

    var body: some View {
        SurfaceCard(title: "Today's Study Flow") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.headline)
                            .font(.system(size: 30, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                        Text(snapshot.subtitle)
                            .font(.system(size: 19, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 10) {
                        PillLabel(text: snapshot.activeBankBadgeText, tint: AppPalette.blue, fill: AppPalette.blueSoft)
                        if let pageLabel = snapshot.pageLabel {
                            PillLabel(text: pageLabel, tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                        }
                        Text(snapshot.activeBankTitle)
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(AppPalette.ink)
                            .multilineTextAlignment(.trailing)
                        if let pageProgressText = snapshot.pageProgressText {
                            Text(pageProgressText)
                                .font(.system(size: 15, weight: .medium, design: .default))
                                .foregroundStyle(AppPalette.muted)
                        }
                    }
                    .frame(maxWidth: 220, alignment: .trailing)
                }

                HStack(spacing: 14) {
                    MetricTile(
                        title: "Target",
                        value: "\(snapshot.targetWordCount)",
                        caption: "Words in today's plan",
                        tint: AppPalette.olive
                    )
                    MetricTile(
                        title: "Due now",
                        value: "\(snapshot.dueReviewCount)",
                        caption: "Scheduled review words",
                        tint: AppPalette.terracotta
                    )
                    MetricTile(
                        title: "Fresh fill",
                        value: "\(snapshot.freshWordCount)",
                        caption: "New words if space remains",
                        tint: AppPalette.blue
                    )
                }

                Text(snapshot.reminderText)
                    .font(.system(size: 17, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.terracotta)

                if let primaryActionTitle, let onPrimaryAction {
                    Button(primaryActionTitle, action: onPrimaryAction)
                        .buttonStyle(HeroButtonStyle(kind: .filled))
                        .frame(maxWidth: 520)
                }
            }
        }
    }
}

struct LaunchActionCard: View {
    let title: String
    let subtitle: String
    let resumeTitle: String?
    let onResume: (() -> Void)?
    let primaryTitle: String
    let primaryKind: HeroButtonStyle.Kind
    let onPrimary: () -> Void
    let secondaryTitle: String
    let secondarySystemImage: String
    let onSecondary: () -> Void
    let supportingText: String?

    var body: some View {
        SurfaceCard(title: "Start Here") {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.ink)

                Text(subtitle)
                    .font(.system(size: 20, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let resumeTitle, let onResume {
                    Button(resumeTitle, action: onResume)
                        .buttonStyle(HeroButtonStyle(kind: .filled))
                        .frame(maxWidth: 560)
                }

                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(HeroButtonStyle(kind: primaryKind))
                    .frame(maxWidth: 540)

                Button {
                    onSecondary()
                } label: {
                    Label(secondaryTitle, systemImage: secondarySystemImage)
                }
                .buttonStyle(HeroButtonStyle(kind: .outlined))
                .frame(maxWidth: 560)

                if let supportingText {
                    Text(supportingText)
                        .font(.system(size: 18, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.terracotta)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct QuizView: View {
    @Environment(AppModel.self) private var model
    @State private var spellingAnswer = ""
    @StateObject private var pronunciationSpeechCoach = PronunciationSpeechCoach()
    @FocusState private var isSpellingFieldFocused: Bool

    var body: some View {
        if let session = model.currentSession,
           let word = model.currentQuestionWord {
            let progress = model.currentWordProgress ?? .fresh(for: word.id)
            let accent = session.mode == .failedReview ? AppPalette.terracotta : AppPalette.olive
            let feedback = model.answerFeedback
            let livePlacementEstimate = model.livePlacementEstimate
            let isExercise = model.isCurrentWordExercise
            let isSpellingStep = model.isOnSpellingStep
            let isTranslationStep = model.isOnTranslationStep
            let isPronunciationStep = model.isOnPronunciationStep
            let isRetryingSpelling = model.isRetryingSpelling
            let hasTranslationStep = model.currentQuestionHasTranslationStep
            let totalExerciseSteps = hasTranslationStep ? 4 : 3
            let currentExerciseStepNumber = isTranslationStep ? 4 : (isSpellingStep ? 3 : (isPronunciationStep ? 2 : 1))

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center, spacing: 14) {
                        Button(model.quizExitTitle) {
                            model.leaveQuiz()
                        }
                        .buttonStyle(SecondaryNavButtonStyle())

                        Text(model.quizProgressLabel)
                            .font(.system(size: 22, weight: .bold, design: .default))
                            .tracking(1.2)
                            .foregroundStyle(AppPalette.terracotta)
                        Spacer()
                        if isExercise {
                            PillLabel(
                                text: "STEP \(currentExerciseStepNumber) OF \(totalExerciseSteps)",
                                tint: AppPalette.terracotta,
                                fill: AppPalette.oliveSoft
                            )
                        }
                        PillLabel(text: model.activeSessionWordBankBadgeText, tint: AppPalette.blue, fill: AppPalette.blueSoft)
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

                                    if isExercise && isTranslationStep {
                                        Text("Translate the sentence")
                                            .font(.system(size: 82, weight: .regular, design: .serif))
                                            .foregroundStyle(AppPalette.ink)

                                        if let translationPrompt = model.currentTranslationPrompt {
                                            Text(translationPrompt)
                                                .font(.system(size: 52, weight: .semibold, design: .default))
                                                .foregroundStyle(AppPalette.blue)
                                                .fixedSize(horizontal: false, vertical: true)

                                            PronunciationButton(title: "Play Chinese prompt", tint: AppPalette.blue) {
                                                model.speakChinese(translationPrompt)
                                            }
                                        }

                                        Text("Choose the English sentence that matches the Chinese translation.")
                                            .font(.system(size: 26, weight: .medium, design: .serif))
                                            .italic()
                                            .foregroundStyle(AppPalette.muted)
                                            .frame(maxWidth: 760, alignment: .leading)
                                    } else if isExercise && isPronunciationStep {
                                        Text("Say the word")
                                            .font(.system(size: 82, weight: .regular, design: .serif))
                                            .foregroundStyle(AppPalette.ink)

                                        Text(word.primaryChinese)
                                            .font(.system(size: 56, weight: .semibold, design: .default))
                                            .foregroundStyle(AppPalette.blue)
                                            .fixedSize(horizontal: false, vertical: true)

                                        if let targetWord = model.currentPronunciationTargetWord {
                                            PronunciationButton(title: "Play word", tint: AppPalette.blue) {
                                                model.speakEnglish(targetWord)
                                            }
                                        }

                                        Text("Step 2: listen, say it aloud once, then self-check before spelling.")
                                            .font(.system(size: 26, weight: .medium, design: .serif))
                                            .italic()
                                            .foregroundStyle(AppPalette.muted)
                                            .frame(maxWidth: 760, alignment: .leading)
                                    } else if isExercise && isSpellingStep {
                                        Text("Spell the word")
                                            .font(.system(size: 82, weight: .regular, design: .serif))
                                            .foregroundStyle(AppPalette.ink)

                                        Text(word.primaryChinese)
                                            .font(.system(size: 56, weight: .semibold, design: .default))
                                            .foregroundStyle(AppPalette.blue)
                                            .fixedSize(horizontal: false, vertical: true)

                                        if isRetryingSpelling {
                                            Text("Listen and retry the spelling.")
                                                .font(.system(size: 24, weight: .medium, design: .serif))
                                                .italic()
                                                .foregroundStyle(AppPalette.muted)
                                                .frame(maxWidth: 760, alignment: .leading)
                                        }
                                    } else if isExercise, let meaningPrompt = model.currentMeaningPrompt {
                                        Text("Choose the meaning")
                                            .font(.system(size: 82, weight: .regular, design: .serif))
                                            .foregroundStyle(AppPalette.ink)

                                        Text(meaningPrompt)
                                            .font(.system(size: 52, weight: .semibold, design: .default))
                                            .foregroundStyle(AppPalette.blue)
                                            .fixedSize(horizontal: false, vertical: true)

                                        PronunciationButton(title: "Play sentence clue", tint: AppPalette.blue) {
                                            model.speakEnglish(meaningPrompt)
                                        }

                                        Text("Step 1: use the sentence to choose the correct Chinese meaning before pronunciation, spelling, and translation.")
                                            .font(.system(size: 26, weight: .medium, design: .serif))
                                            .italic()
                                            .foregroundStyle(AppPalette.muted)
                                            .frame(maxWidth: 760, alignment: .leading)
                                    } else {
                                        Text(word.english)
                                            .font(.system(size: 104, weight: .regular, design: .serif))
                                            .foregroundStyle(AppPalette.ink)

                                        Text(isExercise
                                             ? "Step 1: choose the correct Chinese meaning before pronunciation and spelling."
                                             : "Choose the correct Chinese meaning. A wrong answer resets this word’s streak and pushes it back into review.")
                                            .font(.system(size: 28, weight: .medium, design: .serif))
                                            .italic()
                                            .foregroundStyle(AppPalette.muted)
                                            .frame(maxWidth: 760, alignment: .leading)
                                    }

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
                                    } else if isExercise {
                                        MetricTile(
                                            title: "Exercise",
                                            value: "\(currentExerciseStepNumber) / \(totalExerciseSteps)",
                                            caption: isTranslationStep
                                                ? "Finish translation to settle this word"
                                                : (isPronunciationStep
                                                    ? "Listen, say it aloud, then self-check"
                                                    : (isSpellingStep
                                                    ? (isRetryingSpelling
                                                        ? "Listen, retry, then continue"
                                                        : (hasTranslationStep ? "Spelling first, then translation" : "Finish spelling to settle this word"))
                                                    : (hasTranslationStep
                                                        ? "Meaning first, then pronunciation, spelling, and translation"
                                                        : "Meaning first, then pronunciation and spelling"))),
                                            tint: accent
                                        )
                                        .frame(width: 230)
                                    } else {
                                        MetricTile(title: "Streak", value: "\(progress.currentCorrectStreak) / 3", caption: "Needed for mastery", tint: accent)
                                            .frame(width: 230)
                                    }
                                }
                            }
                        }

                        if isExercise,
                           !isSpellingStep,
                           !isTranslationStep,
                           feedback == nil,
                           let memoryTip = model.currentMemoryTip {
                            SurfaceCard(title: "Memory Tip") {
                                Text(memoryTip)
                                    .font(.system(size: 24, weight: .medium, design: .default))
                                    .foregroundStyle(AppPalette.terracotta)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if isExercise && isPronunciationStep {
                            PronunciationSelfCheckCard(
                                targetWord: model.currentPronunciationTargetWord ?? word.english,
                                coach: pronunciationSpeechCoach,
                                onPlayWord: {
                                    if let targetWord = model.currentPronunciationTargetWord {
                                        model.speakEnglish(targetWord)
                                    }
                                },
                                onRate: { rating in
                                    model.submitPronunciationRating(rating)
                                }
                            )
                        } else if isExercise && isSpellingStep {
                            VStack(alignment: .leading, spacing: 16) {
                                if let sentencePrompt = model.currentSpellingPrompt {
                                    SentenceCueCard(
                                        prompt: sentencePrompt,
                                        buttonTitle: "Play word",
                                        onSpeak: {
                                            if let targetWord = model.currentPronunciationTargetWord {
                                                model.speakEnglish(targetWord)
                                            }
                                        }
                                    )
                                }

                                if isRetryingSpelling, let memoryTip = model.currentMemoryTip {
                                    SurfaceCard {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Memory Tip")
                                                .font(.system(size: 16, weight: .bold, design: .default))
                                                .tracking(0.8)
                                                .foregroundStyle(AppPalette.muted)

                                            Text(memoryTip)
                                                .font(.system(size: 21, weight: .medium, design: .default))
                                                .foregroundStyle(AppPalette.terracotta)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }

                                SurfaceCard {
                                    VStack(alignment: .leading, spacing: 16) {
                                        Text(hasTranslationStep
                                                ? (isRetryingSpelling ? "Retry the English word." : "Type the English word.")
                                                : (isRetryingSpelling ? "Retry the missing English word." : "Type the missing English word."))
                                            .font(.system(size: 20, weight: .medium, design: .default))
                                            .foregroundStyle(AppPalette.muted)

                                        TextField(
                                            "",
                                            text: $spellingAnswer,
                                            prompt: Text("Type the English spelling here")
                                                .foregroundStyle(AppPalette.muted.opacity(0.8))
                                        )
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 28, weight: .semibold, design: .default))
                                        .foregroundStyle(AppPalette.ink)
                                        .focused($isSpellingFieldFocused)
                                        .onSubmit {
                                            if feedback == nil {
                                                model.submitSpelling(answer: spellingAnswer)
                                            }
                                        }
                                        .onAppear {
                                            if feedback == nil {
                                                DispatchQueue.main.async {
                                                    activateApplicationWindow()
                                                    isSpellingFieldFocused = true
                                                }
                                            }
                                        }
                                        .frame(minHeight: 72)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 18)
                                        .background(
                                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                .fill(Color.white)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                .stroke(AppPalette.border, lineWidth: 1.2)
                                        )
                                        .allowsHitTesting(feedback == nil)

                                        Button(isRetryingSpelling ? "RETRY SPELLING" : "SUBMIT WORD") {
                                            model.submitSpelling(answer: spellingAnswer)
                                        }
                                        .buttonStyle(HeroButtonStyle(kind: .filled))
                                        .frame(maxWidth: 320)
                                        .disabled(feedback != nil || spellingAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                }
                            }
                        } else if isExercise && isTranslationStep {
                            SurfaceCard(title: "Sentence Translation") {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("Choose the English sentence that best matches the Chinese meaning.")
                                        .font(.system(size: 20, weight: .medium, design: .default))
                                        .foregroundStyle(AppPalette.muted)

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
                                }
                            }
                        } else {
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
                        }

                        if let feedback {
                            AnswerFeedbackCard(
                                feedback: feedback,
                                onSpeak: { text, language in
                                    model.speak(text, language: language)
                                }
                            ) {
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
                            MetricTile(
                                title: isExercise ? "Words passed" : "Correct",
                                value: "\(session.correctAnswers)",
                                caption: isExercise ? "Word cycles cleared so far" : "Score in this mission",
                                tint: AppPalette.success
                            )
                            MetricTile(title: "Mistakes", value: "\(progress.totalIncorrect)", caption: "This word has come back this many times", tint: AppPalette.terracotta)
                        }
                    }
                    .id(model.quizStepID)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    .animation(.easeInOut(duration: 0.28), value: model.quizStepID)
                }
                .padding(.vertical, 6)
            }
            .onChange(of: model.quizStepID) { _, _ in
                spellingAnswer = ""
                isSpellingFieldFocused = false
                if !model.isOnPronunciationStep {
                    pronunciationSpeechCoach.reset()
                }
                if model.isOnSpellingStep, model.answerFeedback == nil {
                    DispatchQueue.main.async {
                        activateApplicationWindow()
                        isSpellingFieldFocused = true
                    }
                }
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

@MainActor
func activateApplicationWindow() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    for window in NSApp.windows {
        window.makeKeyAndOrderFront(nil)
    }
}

struct SentenceCueCard: View {
    let prompt: String
    let buttonTitle: String
    let onSpeak: (() -> Void)?

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                if let onSpeak {
                    PronunciationButton(title: buttonTitle, tint: AppPalette.blue, action: onSpeak)
                }

                Text(prompt)
                    .font(.system(size: 28, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(AppPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PronunciationButton: View {
    let title: String
    var tint: Color = AppPalette.blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "speaker.wave.2.fill")
        }
        .buttonStyle(.plain)
        .font(.system(size: 15, weight: .bold, design: .default))
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

struct PronunciationSelfCheckCard: View {
    let targetWord: String
    @ObservedObject var coach: PronunciationSpeechCoach
    let onPlayWord: () -> Void
    let onRate: (PronunciationRating) -> Void

    var body: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 24) {
                PronunciationCatView(mood: catMood)
                    .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SAY IT OUT LOUD")
                            .font(.system(size: 17, weight: .black, design: .default))
                            .tracking(1.8)
                            .foregroundStyle(AppPalette.terracotta)

                        Text("Pronunciation Check")
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)

                        Text(coach.message)
                            .font(.system(size: 20, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FlowLayout(spacing: 10) {
                        PronunciationButton(title: "Play word", tint: AppPalette.blue, action: onPlayWord)

                        Button(primarySpeechButtonTitle) {
                            if coach.state == .listening {
                                coach.finish(targetWord: targetWord)
                            } else {
                                coach.start(targetWord: targetWord)
                            }
                        }
                        .buttonStyle(CompactFilledButtonStyle(tint: coach.state == .listening ? AppPalette.terracotta : AppPalette.olive))
                        .disabled(coach.state == .requestingPermission || coach.state == .checking)
                    }

                    if !coach.transcript.isEmpty {
                        RecognizedSpeechStrip(transcript: coach.transcript, rating: coach.rating)
                    }

                    if coach.state == .result, let rating = coach.rating {
                        HStack(spacing: 12) {
                            if rating != .clear {
                                Button("TRY SPEAKING AGAIN") {
                                    coach.start(targetWord: targetWord)
                                }
                                .buttonStyle(CompactOutlineButtonStyle(tint: AppPalette.terracotta))
                            }

                            Button(rating == .clear ? "CONTINUE TO SPELLING" : "CONTINUE WITH REMINDER") {
                                onRate(rating)
                            }
                            .buttonStyle(CompactFilledButtonStyle(tint: rating.countsAsStrong ? AppPalette.olive : AppPalette.terracotta))
                        }
                    }

                    if coach.state == .unavailable {
                        Text("Fallback: choose honestly after saying the word out loud.")
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(AppPalette.muted)
                    }

                    DisclosureGroup("Manual self-check") {
                        VStack(spacing: 10) {
                            ForEach(PronunciationRating.allCases, id: \.self) { rating in
                                Button {
                                    onRate(rating)
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: rating.countsAsStrong ? "speaker.wave.2.fill" : "ear.badge.waveform")
                                            .font(.system(size: 18, weight: .semibold))
                                        Text(rating.displayTitle)
                                            .font(.system(size: 18, weight: .bold, design: .default))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(rating == .needsPractice ? AppPalette.terracotta : AppPalette.olive)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(rating == .needsPractice ? AppPalette.errorSoft : AppPalette.oliveSoft)
                                )
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 16, weight: .bold, design: .default))
                    .foregroundStyle(AppPalette.muted)
                }
            }
        }
    }

    private var primarySpeechButtonTitle: String {
        switch coach.state {
        case .requestingPermission:
            return "CHECKING PERMISSION"
        case .listening:
            return "CHECK NOW"
        case .checking:
            return "CAT IS CHECKING"
        case .result:
            return "START AGAIN"
        case .idle, .unavailable:
            return "START SPEAKING"
        }
    }

    private var catMood: PronunciationCatView.Mood {
        switch coach.state {
        case .requestingPermission, .checking:
            return .thinking
        case .listening:
            return .listening
        case .result:
            switch coach.rating {
            case .clear:
                return .happy
            case .almostThere:
                return .encouraging
            case .needsPractice, nil:
                return .sad
            }
        case .unavailable:
            return .encouraging
        case .idle:
            return .ready
        }
    }
}

struct RecognizedSpeechStrip: View {
    let transcript: String
    let rating: PronunciationRating?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppPalette.blue)
            Text("Cat heard:")
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundStyle(AppPalette.muted)
            Text(transcript)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(AppPalette.ink)
            Spacer()
            if let rating {
                PillLabel(
                    text: rating.feedbackLabel.uppercased(),
                    tint: rating.countsAsStrong ? AppPalette.success : AppPalette.terracotta,
                    fill: rating.countsAsStrong ? AppPalette.successSoft : AppPalette.errorSoft
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.blueSoft.opacity(0.7))
        )
    }
}

struct PronunciationCatView: View {
    enum Mood {
        case ready
        case listening
        case thinking
        case happy
        case encouraging
        case sad
    }

    let mood: Mood
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundFill)
                .shadow(color: AppPalette.ink.opacity(0.08), radius: 12, x: 0, y: 8)
                .scaleEffect(mood == .listening && animate ? 1.08 : 1.0)

            CatEar()
                .fill(faceFill)
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-26))
                .offset(x: -42, y: -48)
                .rotationEffect(.degrees(mood == .sad ? -12 : 0))

            CatEar()
                .fill(faceFill)
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(26))
                .offset(x: 42, y: -48)
                .rotationEffect(.degrees(mood == .sad ? 12 : 0))

            Circle()
                .fill(faceFill)
                .frame(width: 108, height: 98)

            HStack(spacing: 28) {
                eye
                eye
            }
            .offset(y: -12)

            CatMouth(mood: mood)
                .stroke(AppPalette.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 42, height: 24)
                .offset(y: 22)

            if mood == .listening {
                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppPalette.blue)
                    .offset(x: 62, y: -54)
                    .opacity(animate ? 1 : 0.35)
            }
        }
        .offset(y: mood == .happy && animate ? -8 : 0)
        .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: animate)
        .onAppear { animate = true }
        .onChange(of: mood) { _, _ in
            animate = false
            DispatchQueue.main.async {
                animate = true
            }
        }
    }

    private var backgroundFill: Color {
        switch mood {
        case .happy:
            return AppPalette.successSoft
        case .sad:
            return AppPalette.errorSoft
        case .listening:
            return AppPalette.blueSoft
        default:
            return AppPalette.oliveSoft
        }
    }

    private var faceFill: Color {
        switch mood {
        case .sad:
            return Color(red: 0.93, green: 0.74, blue: 0.67)
        case .happy:
            return Color(red: 0.99, green: 0.84, blue: 0.55)
        default:
            return Color(red: 0.96, green: 0.82, blue: 0.62)
        }
    }

    private var eye: some View {
        Group {
            if mood == .happy {
                Capsule(style: .continuous)
                    .frame(width: 20, height: 6)
                    .rotationEffect(.degrees(12))
            } else if mood == .sad {
                Capsule(style: .continuous)
                    .frame(width: 18, height: 6)
                    .rotationEffect(.degrees(-16))
            } else {
                Circle()
                    .frame(width: 13, height: 13)
            }
        }
        .foregroundStyle(AppPalette.ink)
    }
}

struct CatEar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct CatMouth: Shape {
    let mood: PronunciationCatView.Mood

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: CGPoint(x: center.x, y: rect.minY))
        path.addLine(to: center)

        switch mood {
        case .sad:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY))
        default:
            path.move(to: center)
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.midX - 9, y: rect.maxY))
            path.move(to: center)
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.midX + 9, y: rect.maxY))
        }

        return path
    }
}

struct SpellingInputField: View {
    let placeholder: String
    @Binding var text: String
    let isFirstResponder: Bool
    let onSubmit: () -> Void

    var body: some View {
        EditableSpellingTextField(
            placeholder: placeholder,
            text: $text,
            isFirstResponder: isFirstResponder,
            onSubmit: onSubmit
        )
    }
}

struct EditableSpellingTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isFirstResponder: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> SpellingTextFieldContainer {
        let container = SpellingTextFieldContainer()
        let textField = makeSpellingTextField(placeholder: placeholder, delegate: context.coordinator)
        textField.stringValue = text

        context.coordinator.textField = textField
        container.install(textField: textField)
        return container
    }

    func updateNSView(_ nsView: SpellingTextFieldContainer, context: Context) {
        guard let textField = context.coordinator.textField else { return }

        if shouldSyncSpellingFieldFromBinding(textField: textField, bindingText: text) {
            textField.stringValue = text
        }

        if isFirstResponder {
            DispatchQueue.main.async {
                guard !context.coordinator.hasAppliedInitialFocus,
                      let window = nsView.window else {
                    return
                }

                context.coordinator.hasAppliedInitialFocus = true
                window.makeFirstResponder(textField)
            }
        } else {
            context.coordinator.hasAppliedInitialFocus = false
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private let onSubmit: () -> Void
        var hasAppliedInitialFocus = false
        weak var textField: SubmitTextField?

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            text = currentSpellingEditorText(textField: textField, notification: notification)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            text = currentSpellingEditorText(textField: textField, notification: notification)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                onSubmit()
                return true
            }
            return false
        }
    }
}

@MainActor
func currentSpellingEditorText(textField: NSTextField?, notification: Notification? = nil) -> String {
    if let fieldEditor = textField?.currentEditor() {
        return fieldEditor.string
    }

    if let fieldEditor = notification?.userInfo?["NSFieldEditor"] as? NSTextView {
        return fieldEditor.string
    }

    if let field = notification?.object as? NSTextField {
        return field.currentEditor()?.string ?? field.stringValue
    }

    return textField?.stringValue ?? ""
}

@MainActor
func shouldSyncSpellingFieldFromBinding(textField: NSTextField, bindingText: String) -> Bool {
    guard textField.currentEditor() == nil else {
        return false
    }
    return textField.stringValue != bindingText
}

@MainActor
func makeSpellingTextField(placeholder: String, delegate: NSTextFieldDelegate?) -> SubmitTextField {
    let textField = SubmitTextField(frame: .zero)
    textField.delegate = delegate
    textField.isEditable = true
    textField.isSelectable = true
    textField.isBezeled = false
    textField.isBordered = false
    textField.drawsBackground = false
    textField.focusRingType = .none
    textField.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
    textField.textColor = NSColor(AppPalette.ink)
    textField.placeholderAttributedString = NSAttributedString(
        string: placeholder,
        attributes: [
            .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: NSColor(AppPalette.muted).withAlphaComponent(0.8)
        ]
    )
    textField.lineBreakMode = .byClipping
    textField.maximumNumberOfLines = 1
    textField.cell?.wraps = false
    textField.cell?.isScrollable = true
    textField.cell?.usesSingleLineMode = true
    textField.translatesAutoresizingMaskIntoConstraints = false
    return textField
}

@MainActor
final class SpellingTextFieldContainer: NSView {
    private(set) weak var textField: SubmitTextField?

    func install(textField: SubmitTextField) {
        self.textField = textField
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

@MainActor
final class SubmitTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        currentEditor()?.selectedRange = NSRange(location: stringValue.count, length: 0)
        return didBecomeFirstResponder
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
                CatCelebrationCard()

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

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        MetricTile(title: "Accuracy", value: "\(summary?.accuracyPercent ?? 0)%", caption: "Word-level score this session", tint: AppPalette.blue)
                        MetricTile(title: "Success", value: "\(summary?.correctAnswers ?? 0)", caption: "Words cleared this round", tint: AppPalette.success)
                        MetricTile(title: "Needs review", value: "\(summary?.failedAnswers ?? 0)", caption: "Words sent back to reminders", tint: AppPalette.error)
                        MetricTile(title: "Points", value: "+\(model.latestPointsEarned)", caption: "Added to your running total", tint: AppPalette.terracotta)
                    }

                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            MetricTile(title: "Accuracy", value: "\(summary?.accuracyPercent ?? 0)%", caption: "Word-level score this session", tint: AppPalette.blue)
                            MetricTile(title: "Success", value: "\(summary?.correctAnswers ?? 0)", caption: "Words cleared this round", tint: AppPalette.success)
                        }
                        HStack(spacing: 16) {
                            MetricTile(title: "Needs review", value: "\(summary?.failedAnswers ?? 0)", caption: "Words sent back to reminders", tint: AppPalette.error)
                            MetricTile(title: "Points", value: "+\(model.latestPointsEarned)", caption: "Added to your running total", tint: AppPalette.terracotta)
                        }
                    }
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

                if let summary, !summary.reviewWords.isEmpty {
                    ReminderOverviewCard(
                        snapshot: model.reviewReminderSnapshot,
                        reviewWords: summary.reviewWords,
                        title: "Reminder plan"
                    )
                }

                HStack(spacing: 14) {
                    Button(model.hasQuestPages
                                ? model.currentUnitSnapshot.primaryActionTitle
                                : (summary?.mode == .placement ? "START TODAY'S 45-WORD PLAN" : "RETRY FAILED WORDS")) {
                        if model.hasQuestPages {
                            model.performCurrentUnitPrimaryAction()
                        } else if summary?.mode == .placement {
                            model.startMission()
                        } else {
                            model.startFailedReview()
                        }
                    }
                    .buttonStyle(HeroButtonStyle(kind: .filled))
                    .frame(maxWidth: 420)

                    Button("VIEW TROPHIES") { model.openTrophies() }
                        .buttonStyle(HeroButtonStyle(kind: .outlined))
                        .frame(maxWidth: 320)

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
        let reminderSnapshot = model.reviewReminderSnapshot

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHero(
                    eyebrow: "REVIEW REMINDERS",
                    title: "Review Rescue",
                    subtitle: "These words already have reminder times. Clear the due ones first, then the later reminders will spread out again.",
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
                    ReminderOverviewCard(
                        snapshot: reminderSnapshot,
                        reviewWords: model.reviewWordSnapshots,
                        title: "Reminder strategy"
                    )

                    HStack(spacing: 12) {
                        Button("START REVIEW RESCUE") { model.startFailedReview() }
                            .buttonStyle(HeroButtonStyle(kind: .filled))
                            .frame(maxWidth: 380)
                        Button("TROPHIES") { model.openTrophies() }
                            .buttonStyle(HeroButtonStyle(kind: .outlined))
                            .frame(maxWidth: 280)
                        Button("BACK TO HOME") { model.openDashboard() }
                            .buttonStyle(HeroButtonStyle(kind: .outlined))
                            .frame(maxWidth: 280)
                    }

                    VStack(spacing: 12) {
                        ForEach(model.reviewWords, id: \.word.id) { item in
                            SurfaceCard {
                                VStack(alignment: .leading, spacing: 16) {
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
                                                PillLabel(
                                                    text: ReviewScheduler.stageLabel(forStep: item.progress.reviewStep),
                                                    tint: AppPalette.terracotta,
                                                    fill: AppPalette.errorSoft
                                                )
                                            }
                                        }

                                        Spacer()

                                        MetricTile(
                                            title: "Reminder",
                                            value: "\(item.progress.reviewStep + 1)/\(ReviewScheduler.spacedIntervals.count)",
                                            caption: reviewCaption(for: item.progress),
                                            tint: AppPalette.terracotta
                                        )
                                        .frame(width: 230)
                                    }

                                    if let memoryTip = model.memoryTip(forWordID: item.word.id) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Memory Tip")
                                                .font(.system(size: 15, weight: .bold, design: .default))
                                                .tracking(0.8)
                                                .foregroundStyle(AppPalette.muted)
                                            Text(memoryTip)
                                                .font(.system(size: 18, weight: .medium, design: .default))
                                                .foregroundStyle(AppPalette.terracotta)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(18)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                .fill(Color.white.opacity(0.72))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                .stroke(AppPalette.border, lineWidth: 1.1)
                                        )
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

    private func reviewCaption(for progress: WordProgress) -> String {
        ReviewScheduler.reminderCaption(for: progress)
    }
}

struct TrophiesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHero(
                    eyebrow: "TROPHIES",
                    title: "Trophy Shelf",
                    subtitle: "Every finished session becomes a trophy with score, misses, reminder words, and the next review strategy.",
                    trailingText: "\(model.sessionHistory.count)"
                )

                HStack(spacing: 12) {
                    Button("BACK TO HOME") { model.openDashboard() }
                        .buttonStyle(HeroButtonStyle(kind: .outlined))
                        .frame(maxWidth: 280)
                    Button("REVIEW") { model.openReview() }
                        .buttonStyle(HeroButtonStyle(kind: .outlined))
                        .frame(maxWidth: 240)
                }

                if model.sessionHistory.isEmpty {
                    SurfaceCard {
                        ContentUnavailableView(
                            "No trophies yet",
                            systemImage: "trophy",
                            description: Text("Complete a placement test, mission, or review rescue to start filling the trophy shelf.")
                        )
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(model.sessionHistory, id: \.id) { summary in
                            TrophySessionCard(summary: summary)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct ReadingPreviewCard: View {
    let snapshot: ReadingCenterSnapshot
    let onOpen: () -> Void

    var body: some View {
        SurfaceCard(title: "Reading") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.title)
                            .font(.system(size: 30, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                        Text(snapshot.subtitle)
                            .font(.system(size: 19, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 10) {
                        PillLabel(text: snapshot.statusLabel, tint: AppPalette.blue, fill: AppPalette.blueSoft)
                        Text("\(snapshot.articleCount) / \(snapshot.totalPlannedArticleCount) articles ready")
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundStyle(AppPalette.ink)
                        if snapshot.articleCount > 0 {
                            Text("\(snapshot.quizReadyCount) quiz-ready · \(snapshot.previewOnlyCount) preview-only")
                                .font(.system(size: 14, weight: .medium, design: .default))
                                .foregroundStyle(AppPalette.muted)
                        }
                    }
                }

                Text(snapshot.importHint)
                    .font(.system(size: 17, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.terracotta)

                Button("OPEN READING HUB", action: onOpen)
                    .buttonStyle(SecondaryNavButtonStyle())
                    .frame(maxWidth: 320)
            }
        }
    }
}

struct ReminderOverviewCard: View {
    let snapshot: ReviewReminderSnapshot
    let reviewWords: [SessionReviewWordSnapshot]
    let title: String

    var body: some View {
        SurfaceCard(title: title) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.headline)
                            .font(.system(size: 30, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                        Text(snapshot.detail)
                            .font(.system(size: 19, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        MetricTile(
                            title: "Due now",
                            value: "\(snapshot.dueNowCount)",
                            caption: "Immediate reminders",
                            tint: AppPalette.error
                        )
                        .frame(width: 220)
                    }
                }

                HStack(spacing: 16) {
                    MetricTile(
                        title: "Scheduled later",
                        value: "\(snapshot.scheduledLaterCount)",
                        caption: "Already spaced out",
                        tint: AppPalette.blue
                    )
                    MetricTile(
                        title: "Retry tracked",
                        value: "\(snapshot.retryTrackedCount)",
                        caption: "Flagged during spelling retry",
                        tint: AppPalette.terracotta
                    )
                    MetricTile(
                        title: "Next reminder",
                        value: snapshot.nextReminderAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Clear",
                        caption: snapshot.nextReminderAt == nil ? "Nothing waiting later" : "Earliest upcoming return",
                        tint: AppPalette.terracotta
                    )
                }

                Text(snapshot.strategyText)
                    .font(.system(size: 17, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.terracotta)

                if !reviewWords.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Words on this reminder path")
                            .font(.system(size: 17, weight: .bold, design: .default))
                            .foregroundStyle(AppPalette.muted)
                        FlowLayout(spacing: 10) {
                            ForEach(reviewWords.prefix(8)) { word in
                                TrophyReviewWordChip(word: word)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TrophySessionCard: View {
    let summary: SessionSummary

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    HStack(spacing: 10) {
                        PillLabel(text: summary.mode.title.uppercased(), tint: AppPalette.blue, fill: AppPalette.blueSoft)
                        if let questPageNumber = summary.questPageNumber {
                            PillLabel(text: "PAGE \(questPageNumber)", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                        }
                    }

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

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        PillLabel(text: "Success \(summary.correctAnswers)", tint: AppPalette.success, fill: AppPalette.successSoft)
                        PillLabel(text: "Failure \(summary.failedAnswers)", tint: AppPalette.error, fill: AppPalette.errorSoft)
                        PillLabel(text: "Accuracy \(summary.accuracyPercent)%", tint: AppPalette.blue, fill: AppPalette.blueSoft)
                        PillLabel(text: "+\(summary.pointsEarned) points", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            PillLabel(text: "Success \(summary.correctAnswers)", tint: AppPalette.success, fill: AppPalette.successSoft)
                            PillLabel(text: "Failure \(summary.failedAnswers)", tint: AppPalette.error, fill: AppPalette.errorSoft)
                        }
                        HStack(spacing: 14) {
                            PillLabel(text: "Accuracy \(summary.accuracyPercent)%", tint: AppPalette.blue, fill: AppPalette.blueSoft)
                            PillLabel(text: "+\(summary.pointsEarned) points", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                        }
                    }
                }

                if !summary.reviewWords.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Words still on reminder")
                            .font(.system(size: 17, weight: .bold, design: .default))
                            .foregroundStyle(AppPalette.muted)

                        FlowLayout(spacing: 10) {
                            ForEach(summary.reviewWords.prefix(8)) { word in
                                TrophyReviewWordChip(word: word)
                            }
                        }

                        Text(
                            summary.nextReminderAt.map { "Next reminder: \($0.formatted(date: .abbreviated, time: .shortened))" }
                            ?? ReviewScheduler.strategyDescription
                        )
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.terracotta)
                    }
                }
            }
        }
    }
}

struct TrophyReviewWordChip: View {
    let word: SessionReviewWordSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(word.english)
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundStyle(AppPalette.ink)
            Text(word.primaryChinese)
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(AppPalette.muted)
            Text(ReviewScheduler.stageLabel(forStep: word.reviewStep))
                .font(.system(size: 13, weight: .bold, design: .default))
                .foregroundStyle(AppPalette.terracotta)
            if word.retryMissCount > 0 {
                Text("Retry x\(word.retryMissCount)")
                    .font(.system(size: 12, weight: .bold, design: .default))
                    .foregroundStyle(AppPalette.error)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1.0)
        )
    }
}

struct ReadingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let snapshot = model.readingCenterSnapshot
        let selectedQuest = model.selectedReadingPreviewQuest

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Button("BACK TO MAIN") { model.openMainSurface() }
                        .buttonStyle(SecondaryNavButtonStyle())

                    Spacer()

                    if let currentPage = model.currentQuestPage {
                        PillLabel(text: "CURRENT UNIT PAGE \(currentPage.pageNumber)", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                    }
                }

                SectionHero(
                    eyebrow: "READING",
                    title: "Reading Adventure",
                    subtitle: "Reading can be used on its own. Preview one imported page at a time, switch page indexes directly, then start only the page you want.",
                    trailingText: "\(snapshot.articleCount)"
                )

                if !model.sortedReadingQuests.isEmpty {
                    ReadingPageSelectionCard()
                }

                SurfaceCard(title: "Reading Status") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 16) {
                            MetricTile(
                                title: "Imported",
                                value: "\(snapshot.articleCount)",
                                caption: "Articles currently available",
                                tint: AppPalette.blue
                            )
                            MetricTile(
                                title: "Target",
                                value: "\(snapshot.totalPlannedArticleCount)",
                                caption: "Planned PET reading passages",
                                tint: AppPalette.terracotta
                            )
                        }

                        HStack(spacing: 16) {
                            MetricTile(
                                title: "Quiz-ready",
                                value: "\(snapshot.quizReadyCount)",
                                caption: "Articles with answer keys",
                                tint: AppPalette.success
                            )
                            MetricTile(
                                title: "Preview-only",
                                value: "\(snapshot.previewOnlyCount)",
                                caption: "Articles missing answer keys",
                                tint: AppPalette.blue
                            )
                        }

                        Text(snapshot.importHint)
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.terracotta)

                        HStack(spacing: 12) {
                            Button("IMPORT READING TXT / PDF") {
                                model.requestReadingImport()
                            }
                            .buttonStyle(HeroButtonStyle(kind: .filled))
                            .frame(maxWidth: 360)

                            if snapshot.articleCount > 0 {
                                Button("RESET READING PACK") {
                                    model.resetReadingLibrary()
                                }
                                .buttonStyle(HeroButtonStyle(kind: .outlined))
                                .frame(maxWidth: 320)
                            }
                        }
                    }
                }

                if model.sortedReadingQuests.isEmpty {
                    SurfaceCard {
                        ContentUnavailableView(
                            "Reading pack not imported yet",
                            systemImage: "book.closed",
                            description: Text("Import one txt article, one PDF, or a folder of supported Reading files to build the Reading hub.")
                        )
                    }
                } else {
                    if let selectedQuest {
                        SelectedReadingPreviewCard(
                            quest: selectedQuest,
                            matchesCurrentUnit: selectedQuest.pageNumber == model.currentQuestPage?.pageNumber,
                            onStart: selectedQuest.questionCount > 0 ? { model.startSelectedReadingPreview() } : nil
                        )
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct ReadingPageSelectionCard: View {
    @Environment(AppModel.self) private var model
    @State private var pageInput = ""
    @State private var jumpFeedback = ""
    @State private var jumpFeedbackIsError = false

    var body: some View {
        if let selectedQuest = model.selectedReadingPreviewQuest {
            SurfaceCard(title: "Choose Reading Page") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(selectedPageTitle(for: selectedQuest))
                                .font(.system(size: 28, weight: .bold, design: .serif))
                                .foregroundStyle(AppPalette.ink)
                            Text("Preview one reading page at a time. You can jump to another imported page without loading the whole reading pack into one long screen.")
                                .font(.system(size: 18, weight: .medium, design: .default))
                                .foregroundStyle(AppPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            if let pageNumber = selectedQuest.pageNumber {
                                PillLabel(text: "PAGE \(pageNumber)", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                            }
                            PillLabel(
                                text: selectedQuest.isQuizReady ? "QUIZ READY" : (selectedQuest.questionCount > 0 ? "PREVIEW ONLY" : "PASSAGE ONLY"),
                                tint: selectedQuest.isQuizReady ? AppPalette.success : AppPalette.blue,
                                fill: selectedQuest.isQuizReady ? AppPalette.successSoft : AppPalette.blueSoft
                            )
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            MetricTile(
                                title: "Selected",
                                value: selectedQuest.pageNumber.map { "Page \($0)" } ?? "Article",
                                caption: "The reading preview target right now",
                                tint: AppPalette.terracotta
                            )
                            MetricTile(
                                title: "Imported",
                                value: "\(model.sortedReadingQuests.count)",
                                caption: "Reading pages currently available",
                                tint: AppPalette.blue
                            )
                            MetricTile(
                                title: "Quiz-ready",
                                value: "\(model.readingCenterSnapshot.quizReadyCount)",
                                caption: "Pages with answer keys",
                                tint: AppPalette.success
                            )
                        }

                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                MetricTile(
                                    title: "Selected",
                                    value: selectedQuest.pageNumber.map { "Page \($0)" } ?? "Article",
                                    caption: "The reading preview target right now",
                                    tint: AppPalette.terracotta
                                )
                                MetricTile(
                                    title: "Imported",
                                    value: "\(model.sortedReadingQuests.count)",
                                    caption: "Reading pages currently available",
                                    tint: AppPalette.blue
                                )
                            }

                            MetricTile(
                                title: "Quiz-ready",
                                value: "\(model.readingCenterSnapshot.quizReadyCount)",
                                caption: "Pages with answer keys",
                                tint: AppPalette.success
                            )
                        }
                    }

                    HStack(spacing: 12) {
                        Menu {
                            if let currentReading = model.currentReadingQuest {
                                Section("Current Unit") {
                                    Button(model.readingPreviewMenuLabel(for: currentReading)) {
                                        model.selectReadingPreviewQuest(id: currentReading.id)
                                        syncSelectionState(with: currentReading, message: "\(selectedPageTitle(for: currentReading)) is selected.")
                                    }
                                }
                            }

                            Section("Imported Reading Pages") {
                                ForEach(model.sortedReadingQuests) { quest in
                                    Button(model.readingPreviewMenuLabel(for: quest)) {
                                        model.selectReadingPreviewQuest(id: quest.id)
                                        syncSelectionState(with: quest, message: "\(selectedPageTitle(for: quest)) is ready to preview.")
                                    }
                                }
                            }
                        } label: {
                            Label("CHOOSE READING PAGE", systemImage: "book.pages")
                        }
                        .buttonStyle(SecondaryNavButtonStyle())

                        if model.sortedReadingQuests.contains(where: { $0.pageNumber != nil }) {
                            HStack(spacing: 10) {
                                TextField("14", text: $pageInput)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 18, weight: .semibold, design: .default))
                                    .foregroundStyle(AppPalette.ink)
                                    .frame(width: 88)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.white.opacity(0.72))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(AppPalette.border, lineWidth: 1.1)
                                    )
                                    .onSubmit {
                                        jumpToTypedPage()
                                    }

                                Button("GO TO PAGE") {
                                    jumpToTypedPage()
                                }
                                .buttonStyle(SecondaryNavButtonStyle())
                            }
                        }

                        if selectedQuest.questionCount > 0 {
                            Button(selectedQuest.isQuizReady ? "START SELECTED READING" : "OPEN SELECTED PREVIEW") {
                                model.startSelectedReadingPreview()
                            }
                            .buttonStyle(SecondaryNavButtonStyle())
                        }
                    }

                    if !jumpFeedback.isEmpty {
                        Text(jumpFeedback)
                            .font(.system(size: 16, weight: .medium, design: .default))
                            .foregroundStyle(jumpFeedbackIsError ? AppPalette.terracotta : AppPalette.success)
                    }
                }
            }
            .onAppear {
                syncSelectionState(with: selectedQuest, message: "")
            }
            .onChange(of: selectedQuest.id) { _, _ in
                syncSelectionState(with: selectedQuest, message: "")
            }
        }
    }

    private func selectedPageTitle(for quest: ReadingQuest) -> String {
        if let pageNumber = quest.pageNumber {
            return "Selected reading: Page \(pageNumber)"
        }
        return quest.title
    }

    private func jumpToTypedPage() {
        let trimmed = pageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageNumber = Int(trimmed) else {
            jumpFeedback = "Enter a valid imported reading page number, such as 14."
            jumpFeedbackIsError = true
            return
        }

        guard let quest = model.sortedReadingQuests.first(where: { $0.pageNumber == pageNumber }) else {
            jumpFeedback = "Page \(pageNumber) is not in the imported Reading pack yet."
            jumpFeedbackIsError = true
            return
        }

        model.selectReadingPreviewQuest(id: quest.id)
        syncSelectionState(with: quest, message: "Page \(pageNumber) is now the active reading preview.")
    }

    private func syncSelectionState(with quest: ReadingQuest, message: String) {
        if let pageNumber = quest.pageNumber {
            pageInput = "\(pageNumber)"
        }
        jumpFeedback = message
        jumpFeedbackIsError = false
    }
}

struct SelectedReadingPreviewCard: View {
    let quest: ReadingQuest
    let matchesCurrentUnit: Bool
    let onStart: (() -> Void)?

    var body: some View {
        SurfaceCard(title: "Selected Reading Preview") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(quest.title)
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                        Text(matchesCurrentUnit
                            ? "This preview matches the current Quest unit, so you can continue directly from words into reading."
                            : "This reading page is being previewed independently from the current Quest unit."
                        )
                        .font(.system(size: 18, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        if let pageNumber = quest.pageNumber {
                            PillLabel(text: "PAGE \(pageNumber)", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                        }
                        PillLabel(
                            text: quest.isQuizReady ? "QUIZ READY" : (quest.questionCount > 0 ? "PREVIEW ONLY" : "PASSAGE ONLY"),
                            tint: quest.isQuizReady ? AppPalette.success : AppPalette.blue,
                            fill: quest.isQuizReady ? AppPalette.successSoft : AppPalette.blueSoft
                        )
                    }
                }

                Text(quest.passage)
                    .font(.system(size: 20, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        MetricTile(
                            title: "Questions",
                            value: "\(quest.questionCount)",
                            caption: quest.questionCount > 0 ? "Imported for this page" : "Passage preview only",
                            tint: AppPalette.olive
                        )
                        MetricTile(
                            title: "Answer keys",
                            value: quest.isQuizReady ? "Ready" : "Missing",
                            caption: quest.isQuizReady ? "This page can be graded now" : "Preview first, grading later",
                            tint: quest.isQuizReady ? AppPalette.success : AppPalette.blue
                        )
                    }

                    VStack(spacing: 14) {
                        MetricTile(
                            title: "Questions",
                            value: "\(quest.questionCount)",
                            caption: quest.questionCount > 0 ? "Imported for this page" : "Passage preview only",
                            tint: AppPalette.olive
                        )
                        MetricTile(
                            title: "Answer keys",
                            value: quest.isQuizReady ? "Ready" : "Missing",
                            caption: quest.isQuizReady ? "This page can be graded now" : "Preview first, grading later",
                            tint: quest.isQuizReady ? AppPalette.success : AppPalette.blue
                        )
                    }
                }

                if !quest.questions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Question Preview")
                            .font(.system(size: 17, weight: .bold, design: .default))
                            .tracking(0.8)
                            .foregroundStyle(AppPalette.muted)

                        ForEach(quest.questions.prefix(2)) { question in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(question.number). \(question.prompt)")
                                    .font(.system(size: 19, weight: .semibold, design: .default))
                                    .foregroundStyle(AppPalette.ink)
                                Text(question.choices.map { "\($0.letter)) \($0.text)" }.joined(separator: "   "))
                                    .font(.system(size: 16, weight: .medium, design: .default))
                                    .foregroundStyle(AppPalette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.72))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppPalette.border, lineWidth: 1.1)
                            )
                        }
                    }
                }

                HStack(spacing: 12) {
                    if let onStart {
                        Button(quest.isQuizReady ? "START THIS READING" : "OPEN THIS PREVIEW") {
                            onStart()
                        }
                        .buttonStyle(HeroButtonStyle(kind: .filled))
                        .frame(maxWidth: 320)
                    }

                    Text("Source: \(quest.sourceFilename)")
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.muted)
                }
            }
        }
    }
}

struct ReadingQuestCard: View {
    let quest: ReadingQuest

    var body: some View {
        let sourceExtension = URL(fileURLWithPath: quest.sourceFilename).pathExtension.lowercased()
        let sourceCaption = sourceExtension == "pdf" ? "Imported from PDF page" : "Imported from txt"
        let answerCaption = quest.isQuizReady
            ? "This article can be graded later"
            : (quest.questionCount > 0 ? "Add `--- ANSWERS ---` later for grading" : "Preview text only for now")

        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(quest.title)
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                        Text(quest.passage)
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                            .lineLimit(4)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        if let pageNumber = quest.pageNumber {
                            PillLabel(text: "PAGE \(pageNumber)", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                        }
                        PillLabel(
                            text: quest.isQuizReady ? "QUIZ READY" : "PREVIEW ONLY",
                            tint: quest.isQuizReady ? AppPalette.success : AppPalette.blue,
                            fill: quest.isQuizReady ? AppPalette.successSoft : AppPalette.blueSoft
                        )
                    }
                }

                HStack(spacing: 14) {
                    MetricTile(
                        title: "Questions",
                        value: "\(quest.questionCount)",
                        caption: sourceCaption,
                        tint: AppPalette.olive
                    )
                    MetricTile(
                        title: "Answer keys",
                        value: quest.isQuizReady ? "Ready" : "Missing",
                        caption: answerCaption,
                        tint: quest.isQuizReady ? AppPalette.success : AppPalette.blue
                    )
                }

                Text("Source: \(quest.sourceFilename)")
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.muted)
            }
        }
    }
}

struct ReadingQuizView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.activeReadingSession {
            let feedback = model.readingAnswerFeedback

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(for: session)

                    if session.stage == .answering {
                        ProgressView(value: Double(model.readingProgressCount), total: Double(max(session.questions.count, 1)))
                            .tint(AppPalette.success)
                            .scaleEffect(x: 1, y: 1.8, anchor: .center)
                    }

                    switch session.stage {
                    case .questionPreview:
                        questionPreview(for: session)
                    case .passageReading:
                        passageReading(for: session)
                    case .answering:
                        if let question = model.currentReadingQuestion {
                            answeringStage(for: session, question: question, feedback: feedback)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        } else {
            SurfaceCard {
                ContentUnavailableView(
                    "No reading step is active",
                    systemImage: "book.closed",
                    description: Text("Open the Reading hub and start the current page when it is ready.")
                )
            }
        }
    }

    @ViewBuilder
    private func header(for session: ActiveReadingSession) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Button("BACK TO READING") {
                model.leaveReadingQuiz()
            }
            .buttonStyle(SecondaryNavButtonStyle())

            Text(model.readingProgressLabel)
                .font(.system(size: 22, weight: .bold, design: .default))
                .tracking(1.2)
                .foregroundStyle(AppPalette.terracotta)

            Spacer()

            if let pageNumber = session.pageNumber {
                PillLabel(text: "PAGE \(pageNumber)", tint: AppPalette.blue, fill: AppPalette.blueSoft)
            }
            PillLabel(text: "READING QUEST", tint: AppPalette.success, fill: AppPalette.successSoft)
        }
    }

    @ViewBuilder
    private func questionPreview(for session: ActiveReadingSession) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                Text(session.questTitle)
                    .font(.system(size: 54, weight: .regular, design: .serif))
                    .foregroundStyle(AppPalette.ink)

                Text("Look through all 5 questions first. Then read the passage with the questions in mind before you start answering.")
                    .font(.system(size: 22, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 14) {
                    ForEach(session.questions) { question in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(question.number). \(question.prompt)")
                                .font(.system(size: 26, weight: .bold, design: .serif))
                                .foregroundStyle(AppPalette.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(question.choices) { choice in
                                    Text("\(choice.letter)) \(choice.text)")
                                        .font(.system(size: 18, weight: .medium, design: .default))
                                        .foregroundStyle(AppPalette.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(AppPalette.border, lineWidth: 1.1)
                        )
                    }
                }

                Button("READ THE PASSAGE") {
                    model.advanceReadingQuestionPreview()
                }
                .buttonStyle(HeroButtonStyle(kind: .filled))
                .frame(maxWidth: 320)
            }
        }
    }

    @ViewBuilder
    private func passageReading(for session: ActiveReadingSession) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    Text(session.questTitle)
                        .font(.system(size: 54, weight: .regular, design: .serif))
                        .foregroundStyle(AppPalette.ink)

                    Spacer()

                    PronunciationButton(title: "Play passage", tint: AppPalette.success) {
                        model.speakEnglish(session.passage)
                    }
                }

                Text("Now read the passage carefully. After that, start the questions and answer them one by one.")
                    .font(.system(size: 22, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Text(session.passage)
                    .font(.system(size: 22, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Button("START QUESTIONS") {
                    model.startReadingQuestions()
                }
                .buttonStyle(HeroButtonStyle(kind: .filled))
                .frame(maxWidth: 320)
            }
        }
    }

    @ViewBuilder
    private func answeringStage(
        for session: ActiveReadingSession,
        question: ReadingQuestQuestion,
        feedback: ReadingAnswerFeedback?
    ) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    Text(session.questTitle)
                        .font(.system(size: 54, weight: .regular, design: .serif))
                        .foregroundStyle(AppPalette.ink)

                    Spacer()

                    PronunciationButton(title: "Play passage", tint: AppPalette.success) {
                        model.speakEnglish(session.passage)
                    }
                }

                Text(session.passage)
                    .font(.system(size: 22, weight: .medium, design: .default))
                    .foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        SurfaceCard(title: "Question \(question.number)") {
            VStack(alignment: .leading, spacing: 18) {
                Text(question.prompt)
                    .font(.system(size: 36, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 14) {
                    ForEach(question.choices) { choice in
                        ChoiceButton(
                            letter: choice.letter,
                            text: choice.text,
                            accent: AppPalette.success,
                            state: readingChoiceState(for: choice, feedback: feedback)
                        ) {
                            model.submitReadingChoice(letter: choice.letter)
                        }
                        .disabled(feedback != nil)
                    }
                }
            }
        }

        if let feedback {
            SurfaceCard(title: "Reading Feedback") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        PillLabel(
                            text: feedback.isCorrect == true ? "CORRECT" : "CHECK AGAIN",
                            tint: feedback.isCorrect == true ? AppPalette.success : AppPalette.terracotta,
                            fill: feedback.isCorrect == true ? AppPalette.successSoft : AppPalette.errorSoft
                        )
                        if let correctLetter = feedback.correctLetter {
                            PillLabel(
                                text: "ANSWER \(correctLetter)",
                                tint: AppPalette.blue,
                                fill: AppPalette.blueSoft
                            )
                        }
                    }

                    Text(feedback.headline)
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.ink)

                    Text(feedback.detail)
                        .font(.system(size: 20, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if feedback.isCorrect == false {
                        Button("RETRY QUESTION") {
                            model.retryCurrentReadingQuestion()
                        }
                        .buttonStyle(HeroButtonStyle(kind: .filled))
                        .frame(maxWidth: 320)
                    } else {
                        Button(model.activeReadingSession?.currentIndex == session.questions.count - 1 ? "FINISH READING" : "NEXT QUESTION") {
                            model.advanceReadingAfterFeedback()
                        }
                        .buttonStyle(HeroButtonStyle(kind: .filled))
                        .frame(maxWidth: 320)
                    }
                }
            }
        }
    }

    private func readingChoiceState(for choice: ReadingQuestChoice, feedback: ReadingAnswerFeedback?) -> ChoiceButton.VisualState {
        guard let feedback else { return .idle }
        if feedback.selectedLetter == choice.letter {
            return feedback.isCorrect == true ? .correct : .incorrect
        }
        if feedback.correctLetter == choice.letter {
            return .correct
        }
        return .idle
    }
}

struct CatCelebrationCard: View {
    @State private var animate = false

    var body: some View {
        SurfaceCard(title: "Celebration") {
            HStack(alignment: .center, spacing: 24) {
                ZStack {
                    Circle()
                        .fill(AppPalette.catCream)
                        .frame(width: 132, height: 132)
                        .shadow(color: AppPalette.catGold.opacity(0.18), radius: 20, x: 0, y: 10)

                    Text("🐱")
                        .font(.system(size: 74))
                        .scaleEffect(animate ? 1.08 : 0.92)
                        .rotationEffect(.degrees(animate ? 4 : -4))

                    HStack(spacing: 42) {
                        Text("🐾")
                            .font(.system(size: 24))
                            .offset(y: animate ? -26 : -10)
                        Text("🐾")
                            .font(.system(size: 20))
                            .offset(y: animate ? 30 : 12)
                    }
                    .offset(x: 72, y: -8)
                    .opacity(0.9)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Cat cheer unlocked")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.ink)
                    Text("A playful cat now celebrates every finished practice session so the ending feels rewarding, not abrupt.")
                        .font(.system(size: 20, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.muted)
                    Text("The animation stays local, lightweight, and non-blocking.")
                        .font(.system(size: 17, weight: .medium, design: .default))
                        .foregroundStyle(AppPalette.terracotta)
                }

                Spacer()
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
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
    let onSpeak: (String, SpeechLanguageHint) -> Void
    let action: () -> Void

    var body: some View {
        let isFullQuestSuccess = feedback.correctTranslation != nil && feedback.isCorrect
        let primaryActionTitle = isFullQuestSuccess
            ? "NEXT WORD"
            : (feedback.requiresManualAdvance ? "CONTINUE WHEN READY" : "CONTINUE NOW")
        let footerLeadingText = isFullQuestSuccess
            ? "Great work. Move to the next word when you're ready."
            : (feedback.requiresManualAdvance ? "Take a moment, then continue." : "Continuing automatically...")
        let footerTrailingText = isFullQuestSuccess
            ? "Next challenge"
            : (feedback.requiresManualAdvance ? "Tap when ready" : (feedback.newlyMastered ? "Hold the moment" : "Short pause"))

        SurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                if feedback.newlyMastered {
                    MasteryCelebrationBadge()
                }

                HStack(alignment: .center, spacing: 20) {
                    ZStack {
                        Circle()
                            .fill((feedback.isCorrect ? AppPalette.success : AppPalette.error).opacity(0.15))
                            .frame(width: 72, height: 72)

                        Image(systemName: feedback.isCorrect ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(feedback.isCorrect ? AppPalette.success : AppPalette.error)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(feedback.headline)
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink)
                        Text(feedback.detail)
                            .font(.system(size: 20, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                        if feedback.pointsEarned > 0 {
                            PillLabel(text: "+\(feedback.pointsEarned) points", tint: AppPalette.terracotta, fill: AppPalette.oliveSoft)
                        }
                    }

                    Spacer()

                    Button(primaryActionTitle, action: action)
                        .buttonStyle(HeroButtonStyle(kind: .filled))
                        .frame(width: 270)
                }

                VStack(alignment: .leading, spacing: 10) {
                    FeedbackResultRow(
                        title: "Meaning",
                        correctAnswer: feedback.correctMeaning,
                        isCorrect: feedback.meaningWasCorrect ?? feedback.isCorrect
                    )

                    if let correctSpelling = feedback.correctSpelling,
                       let spellingWasCorrect = feedback.spellingWasCorrect,
                       spellingWasCorrect {
                        FeedbackResultRow(
                            title: "Spelling",
                            correctAnswer: correctSpelling,
                            isCorrect: spellingWasCorrect
                        )
                    }

                    if let correctTranslation = feedback.correctTranslation,
                       let translationWasCorrect = feedback.translationWasCorrect {
                        FeedbackResultRow(
                            title: "Translation",
                            correctAnswer: correctTranslation,
                            isCorrect: translationWasCorrect
                        )
                    }

                    if let pronunciationRating = feedback.pronunciationRating {
                        FeedbackResultRow(
                            title: "Pronunciation",
                            correctAnswer: pronunciationRating.feedbackLabel,
                            isCorrect: pronunciationRating.countsAsStrong
                        )
                    }
                }

                if feedback.correctSpelling != nil || feedback.revealedSentence != nil || feedback.revealedTranslation != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Listen again")
                            .font(.system(size: 17, weight: .bold, design: .default))
                            .tracking(0.8)
                            .foregroundStyle(AppPalette.muted)

                        FlowLayout(spacing: 10) {
                            if let correctSpelling = feedback.correctSpelling {
                                PronunciationButton(title: "Word", tint: AppPalette.blue) {
                                    onSpeak(correctSpelling, .english)
                                }
                            }

                            if let revealedSentence = feedback.revealedSentence {
                                PronunciationButton(title: "Sentence", tint: AppPalette.blue) {
                                    onSpeak(revealedSentence, .english)
                                }
                            }

                            if let revealedTranslation = feedback.revealedTranslation {
                                PronunciationButton(title: "Meaning", tint: AppPalette.terracotta) {
                                    onSpeak(revealedTranslation, .chinese)
                                }
                            }
                        }
                    }
                }

                if feedback.correctSpelling != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        if let revealedSentence = feedback.revealedSentence {
                            Text("Full sentence")
                                .font(.system(size: 17, weight: .bold, design: .default))
                                .tracking(0.8)
                                .foregroundStyle(AppPalette.muted)

                            Text(revealedSentence)
                                .font(.system(size: 22, weight: .medium, design: .serif))
                                .foregroundStyle(AppPalette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let revealedTranslation = feedback.revealedTranslation {
                            Text("Sentence meaning")
                                .font(.system(size: 17, weight: .bold, design: .default))
                                .tracking(0.8)
                                .foregroundStyle(AppPalette.muted)

                            Text(revealedTranslation)
                                .font(.system(size: 22, weight: .medium, design: .serif))
                                .foregroundStyle(AppPalette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let memoryTip = feedback.memoryTip {
                    SurfaceCard(title: "Memory Tip") {
                        Text(memoryTip)
                            .font(.system(size: 24, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.terracotta)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(footerLeadingText)
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(AppPalette.muted)
                        Spacer()
                        Text(footerTrailingText)
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundStyle(AppPalette.muted)
                    }

                    if !feedback.requiresManualAdvance {
                        AutoAdvanceProgressBar(duration: feedback.autoAdvanceDelay)
                    }
                }
            }
        }
    }
}

struct FeedbackResultRow: View {
    let title: String
    let correctAnswer: String
    let isCorrect: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(isCorrect ? AppPalette.success : AppPalette.error)

            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 15, weight: .bold, design: .default))
                    .tracking(1)
                    .foregroundStyle(isCorrect ? AppPalette.success : AppPalette.error)

                Text(correctAnswer)
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundStyle(AppPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            PillLabel(
                text: isCorrect ? "PASS" : "REVIEW",
                tint: isCorrect ? AppPalette.success : AppPalette.error,
                fill: isCorrect ? AppPalette.successSoft : AppPalette.errorSoft
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isCorrect ? AppPalette.successSoft : AppPalette.errorSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isCorrect ? AppPalette.success : AppPalette.error, lineWidth: 1.1)
        )
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

struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widthLimit = proposal.width ?? 1_000
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x + size.width > widthLimit, cursor.x > 0 {
                cursor.x = 0
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }

            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, cursor.x + size.width)
            cursor.x += size.width + spacing
        }

        return CGSize(width: maxWidth, height: cursor.y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var cursor = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x + size.width > bounds.maxX, cursor.x > bounds.minX {
                cursor.x = bounds.minX
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: cursor.x, y: cursor.y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
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
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(borderColor, lineWidth: state == .idle ? 1.2 : 2)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(stripeColor)
                    .frame(width: state == .idle ? 0 : 10)
                    .padding(.vertical, 10)
                    .padding(.leading, 10)
            }
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
        .opacity(state == .dimmed ? 0.45 : 1.0)
        .shadow(color: Color.black.opacity(state == .idle ? 0.03 : 0.06), radius: 12, x: 0, y: 6)
        .scaleEffect(state == .correct ? 1.015 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: state)
    }

    private var circleFill: Color {
        switch state {
        case .idle: return accent.opacity(0.14)
        case .correct: return AppPalette.success.opacity(0.22)
        case .incorrect: return AppPalette.error.opacity(0.18)
        case .dimmed: return AppPalette.border.opacity(0.22)
        }
    }

    private var letterColor: Color {
        switch state {
        case .idle: return accent
        case .correct: return AppPalette.success
        case .incorrect: return AppPalette.error
        case .dimmed: return AppPalette.muted
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle: return AppPalette.border
        case .correct: return AppPalette.success
        case .incorrect: return AppPalette.error
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
        case .incorrect: return AppPalette.error
        case .idle: return AppPalette.ink
        case .dimmed: return AppPalette.muted
        }
    }

    private var backgroundFill: Color {
        switch state {
        case .idle: return Color.white
        case .correct: return AppPalette.successSoft
        case .incorrect: return AppPalette.errorSoft
        case .dimmed: return Color.white.opacity(0.72)
        }
    }

    private var stripeColor: Color {
        switch state {
        case .idle, .dimmed: return .clear
        case .correct: return AppPalette.success
        case .incorrect: return AppPalette.error
        }
    }

    private var textColor: Color {
        switch state {
        case .dimmed: return AppPalette.muted
        default: return AppPalette.ink
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

struct CompactActionButtonStyle: ButtonStyle {
    enum Kind {
        case filled
        case outlined
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .default))
            .tracking(0.8)
            .foregroundStyle(kind == .filled ? Color.white : AppPalette.olive)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(background(isPressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppPalette.olive, lineWidth: kind == .filled ? 0 : 1.6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        switch kind {
        case .filled:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.terracotta.opacity(isPressed ? 0.92 : 1.0))
        case .outlined:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(isPressed ? 0.92 : 1.0))
        }
    }
}

struct CompactFilledButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .black, design: .default))
            .tracking(0.9)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.88 : 1.0))
            )
            .shadow(color: tint.opacity(configuration.isPressed ? 0.08 : 0.18), radius: configuration.isPressed ? 4 : 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct CompactOutlineButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .black, design: .default))
            .tracking(0.9)
            .foregroundStyle(tint)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.88 : 1.0))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.7), lineWidth: 1.4)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
