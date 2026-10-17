import SwiftData
import SwiftUI

struct AppShellView: View {
    let environment: AppEnvironment

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
        .modelContainer(environment.modelContainer!)
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
                ContentView()
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
            ContentView()
        case .postureHistory:
            HistoryView()
        case .assessment(let id):
            AssessmentRouteView(id: id)
        case .livePostureCheck:
            RealtimeCorrectionView()
        case .photoAssessment:
            ContentView()
        case .settings:
            Text("Settings are presented full screen.")
        }
    }

    @ViewBuilder
    private func fullScreenDestination(for route: AppRoute) -> some View {
        switch route {
        case .settings:
            TemporarySettingsView(onDone: router.dismissFullScreen)
        case .workout(let exerciseID, let routineID):
            WorkoutCoachView(model: environment.workoutCoachFactory.makeWorkout(
                exerciseID: exerciseID,
                routineID: routineID
            ))
        default:
            EmptyView()
        }
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

private struct TemporarySettingsView: View {
    @AppStorage(PreferenceKey.cameraTiltCompensationEnabled) private var cameraTiltCompensationEnabled = true
    @State private var showAcknowledgements = false
    @State private var showDiagnosticsHelp = false
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Posture") {
                    Toggle("Compensate camera tilt", isOn: $cameraTiltCompensationEnabled)
                }
                Section("About") {
                    Button("Acknowledgements") { showAcknowledgements = true }
                }
                Section("Developer") {
                    Button {
                        showDiagnosticsHelp = true
                    } label: {
                        Label("Developer diagnostics", systemImage: "ladybug")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                    }
                }
            }
            .sheet(isPresented: $showAcknowledgements) {
                AcknowledgementsView()
            }
            .alert("Developer diagnostics", isPresented: $showDiagnosticsHelp) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Open an assessment report and tap the Developer Diagnostics button.")
            }
        }
    }
}
