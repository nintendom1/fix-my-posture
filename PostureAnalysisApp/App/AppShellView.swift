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
                WorkoutSelectionView(mode: .train)
            case .routines:
                WorkoutSelectionView(mode: .routines)
            case .progress:
                ProgressTabRootView()
            case .posture:
                ContentView()
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .train:
            WorkoutSelectionView(mode: .train)
        case .routines:
            WorkoutSelectionView(mode: .routines)
        case .routine(let id):
            RoutineRouteView(id: id)
        case .routineEditor(let id):
            RoutineEditorRouteView(id: id)
        case .library:
            ExerciseLibraryView()
        case .exercise(let id):
            ExerciseRouteView(id: id)
        case .workout:
            Text("Workout camera is presented full screen.")
        case .workoutComplete:
            Text("Workout complete")
        case .progress:
            ProgressTabRootView()
        case .history:
            WorkoutHistoryView(exerciseCatalog: environment.exerciseCatalog)
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

private struct ProgressTabRootView: View {
    var body: some View {
        List {
            Section {
                NavigationLink(value: AppRoute.history) {
                    Label("Workout History", systemImage: "clock.arrow.circlepath")
                }
            } footer: {
                Text("Completed workouts, sets, reps, and weight entries are saved on this device.")
            }
        }
        .navigationTitle("Progress")
    }
}

private struct ExerciseLibraryView: View {
    @Environment(\.exerciseCatalog) private var exerciseCatalog

    var body: some View {
        List(exerciseCatalog.all) { exercise in
            NavigationLink(value: AppRoute.exercise(id: exercise.id)) {
                ExerciseSummaryLabel(exercise: exercise)
            }
        }
        .navigationTitle("Library")
    }
}

private struct ExerciseRouteView: View {
    @Environment(\.exerciseCatalog) private var exerciseCatalog
    @Environment(\.appRouter) private var router
    let id: ExerciseID

    private var exercise: ExerciseDefinition? { exerciseCatalog.exercise(id) }

    var body: some View {
        Group {
            if let exercise {
                List {
                    Section(exercise.displayName) {
                        Text(exercise.guide.summary)
                        Text(exercise.setsAndRepsLabel)
                    }
                    Section {
                        Button("Start Workout") {
                            router?.open(.workout(exerciseID: exercise.id, routineID: nil))
                        }
                    }
                }
            } else {
                ContentUnavailableView("Exercise Unavailable", systemImage: "figure.strengthtraining.traditional")
            }
        }
        .navigationTitle(exercise?.displayName ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RoutineRouteView: View {
    @Environment(\.appRepositories) private var appRepositories
    @Environment(\.exerciseCatalog) private var exerciseCatalog
    @Environment(\.appRouter) private var router
    @State private var routine: SavedExerciseSet?
    let id: UUID?

    var body: some View {
        Group {
            if let routine {
                List {
                    Section(routine.name) {
                        ForEach(routine.items) { item in
                            Text(exerciseCatalog.exercise(item.exerciseID)?.displayName ?? "Unavailable exercise")
                                + Text(" · \(item.setsAndRepsLabel)")
                        }
                    }
                    Section {
                        Button("Edit Saved Set") { router?.open(.routineEditor(id: routine.id)) }
                        Button("Start Saved Set") {
                            router?.open(.workout(exerciseID: nil, routineID: routine.id))
                        }
                    }
                }
            } else {
                ContentUnavailableView("Saved Set Unavailable", systemImage: "list.number")
            }
        }
        .navigationTitle(routine?.name ?? "Saved Set")
        .task { loadRoutine() }
    }

    private func loadRoutine() {
        guard let id else { return }
        routine = try? appRepositories?.routines.list().first { $0.id == id }
    }
}

private struct RoutineEditorRouteView: View {
    @Environment(\.appRepositories) private var appRepositories
    @Environment(\.exerciseCatalog) private var exerciseCatalog
    @State private var routine: SavedExerciseSet?
    let id: UUID?

    init(id: UUID?) {
        self.id = id
        _routine = State(initialValue: id == nil ? SavedExerciseSet(name: "New Saved Set", items: []) : nil)
    }

    var body: some View {
        Group {
            if let routine {
                SavedSetEditorView(
                    set: routine,
                    isNew: id == nil,
                    catalog: exerciseCatalog.all,
                    onSave: { try? appRepositories?.routines.save($0) },
                    onDelete: { try? appRepositories?.routines.delete(id: $0.id) },
                    onDuplicate: { _ = try? appRepositories?.routines.duplicate($0) },
                    wrapsInNavigationStack: false
                )
            } else {
                ProgressView()
                    .task { loadRoutine() }
            }
        }
    }

    private func loadRoutine() {
        guard let id else { return }
        routine = try? appRepositories?.routines.list().first { $0.id == id }
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
