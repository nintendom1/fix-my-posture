import SwiftData
import SwiftUI

struct AppShellView: View {
    let environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    private var router: AppRouter { environment.router }

    var body: some View {
        TabView(selection: selectionBinding) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: pathBinding(for: tab)) {
                    tabRoot(tab)
                        .navigationDestination(for: AppRoute.self, destination: destination(for:))
                }
                .tabItem {
                    Label {
                        Text(tab.title)
                    } icon: {
                        Image(material: tab.materialIcon)
                    }
                }
                .tag(tab)
            }
        }
        .tint(Color(hex: TabBarStyle.design.tintHex(for: router.selectedTab)))
        .fullScreenCover(item: fullScreenRouteBinding) { route in
            fullScreenDestination(for: route)
        }
        .environment(\.appRouter, environment.router)
        .environment(\.preferences, environment.preferences)
        .environment(\.appRepositories, environment.repositories)
        .environment(\.exerciseCatalog, environment.exerciseCatalog)
        .environment(\.workoutCoachFactory, environment.workoutCoachFactory)
        .environment(\.workoutReminderReconciliation, environment.workoutReminderCoordinator)
        .modelContainer(environment.modelContainer!)
        .task {
            environment.workoutReminderCoordinator.reconcile()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            environment.workoutReminderCoordinator.reconcile()
        }
    }

    @ViewBuilder
    private func tabRoot(_ tab: AppTab) -> some View {
        ZStack {
            AuraBackground(tab: auraTab(for: tab))
            switch tab {
            case .train:
                TrainHomeScreen(
                    state: environment.trainHomeViewModel.state,
                    send: environment.trainHomeViewModel.send
                )
            case .routines:
                RoutinesScreen(
                    state: environment.routinesViewModel.state,
                    send: environment.routinesViewModel.send
                )
            case .progress:
                ProgressRouteView(viewModel: environment.progressViewModel)
            case .posture:
                PostureHomeScreen(
                    state: environment.postureHomeViewModel.state,
                    send: environment.postureHomeViewModel.send
                )
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .train:
            TrainHomeScreen(
                state: environment.trainHomeViewModel.state,
                send: environment.trainHomeViewModel.send
            )
        case .routines:
            RoutinesScreen(
                state: environment.routinesViewModel.state,
                send: environment.routinesViewModel.send
            )
        case .routine(let id):
            RoutineDetailRouteView(viewModel: environment.makeRoutineDetailViewModel(id: id))
        case .routineEditor(let id):
            RoutineEditorRouteView(viewModel: environment.makeRoutineEditorViewModel(id: id))
        case .library:
            LibraryRouteView(viewModel: environment.libraryViewModel)
        case .exercise(let id):
            ExerciseDetailRouteView(viewModel: environment.makeExerciseDetailViewModel(id: id))
        case .workout:
            Text("Workout camera is presented full screen.")
        case .workoutComplete:
            Text("Workout complete")
        case .progress:
            ProgressRouteView(viewModel: environment.progressViewModel)
        case .history:
            HistoryRouteView(viewModel: environment.makeHistoryViewModel())
        case .posture:
            PostureHomeScreen(
                state: environment.postureHomeViewModel.state,
                send: environment.postureHomeViewModel.send
            )
        case .postureHistory:
            PostureHistoryScreen(
                state: environment.postureHomeViewModel.state,
                send: environment.postureHomeViewModel.send
            )
        case .assessment(let id):
            AssessmentRouteView(id: id)
        case .livePostureCheck:
            RealtimeCorrectionView()
        case .photoAssessment(let view):
            PhotoAssessmentFlowScreen(initialView: view)
        case .capturePosturePhoto(let view):
            PhotoAssessmentFlowScreen(initialView: view, launchSource: .camera)
        case .importPosturePhoto(let view):
            PhotoAssessmentFlowScreen(initialView: view, launchSource: .library)
        case .settings:
            settingsScreen
        }
    }

    @ViewBuilder
    private func fullScreenDestination(for route: AppRoute) -> some View {
        switch route {
        case .settings:
            settingsScreen
        case .workout(let exerciseID, let routineID):
            WorkoutCoachView(model: environment.workoutCoachFactory.makeWorkout(
                exerciseID: exerciseID,
                routineID: routineID
            ))
        case .livePostureCheck:
            RealtimeCorrectionView()
        default:
            EmptyView()
        }
    }

    private var settingsScreen: some View {
        SettingsScreen(viewModel: SettingsViewModel(
            preferences: environment.preferences,
            router: router,
            reminderManager: environment.workoutReminderCoordinator,
            latestAssessmentID: environment.postureHomeViewModel.state.assessments.first?.id,
            notificationPreview: environment.makeNotificationPreviewViewModel(),
            personaDebug: environment.makePersonaDebugViewModel()
        ))
    }

    private var selectionBinding: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { router.select($0) }
        )
    }

    private func pathBinding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { router.path(for: tab) },
            set: { router.setPath($0, for: tab) }
        )
    }

    private var fullScreenRouteBinding: Binding<AppRoute?> {
        Binding(
            get: { router.presentedFullScreenRoute },
            set: { route in
                if route == nil { router.dismissFullScreen() }
                else if let route { router.open(route) }
            }
        )
    }

    private func auraTab(for tab: AppTab) -> AuraBackground.Tab {
        switch tab {
        case .train: return .train
        case .routines: return .routines
        case .progress: return .progress
        case .posture: return .posture
        }
    }
}

private struct ProgressRouteView: View {
    @State private var viewModel: ProgressViewModel

    init(viewModel: ProgressViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ProgressScreen(viewModel: viewModel)
    }
}

private struct HistoryRouteView: View {
    @State private var viewModel: HistoryViewModel

    init(viewModel: HistoryViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        HistoryScreen(viewModel: viewModel)
    }
}

private struct LibraryRouteView: View {
    @State private var viewModel: LibraryViewModel

    init(viewModel: LibraryViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        LibraryScreen(state: viewModel.state, send: viewModel.send)
    }
}

private struct ExerciseDetailRouteView: View {
    @State private var viewModel: ExerciseDetailViewModel

    init(viewModel: ExerciseDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ExerciseDetailScreen(state: viewModel.state, send: viewModel.send)
    }
}

private struct RoutineEditorRouteView: View {
    @State private var viewModel: RoutineEditorViewModel

    init(viewModel: RoutineEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        RoutineEditorScreen(state: viewModel.state, send: viewModel.send)
    }
}
