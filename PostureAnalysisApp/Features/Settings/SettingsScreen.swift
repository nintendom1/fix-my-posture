import SwiftUI

struct SettingsScreen: View {
    @State private var viewModel: SettingsViewModel

    private let coachPurple = Color(hex: 0x7C4DFF, alpha: 0.9)
    private let workoutOrange = Color(hex: 0xFF8C5A, alpha: 0.9)
    private let cameraBlue = Color(hex: 0x5078FF, alpha: 0.9)
    private let aboutGreen = Color(hex: 0x22C38E, alpha: 0.9)
    private let aboutNeutral = Color.white.opacity(0.14)

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            settingsHome
                .navigationDestination(for: SettingsDestination.self, destination: destination(for:))
        }
        .tint(ColorTokens.palette().tabActive)
        .environment(\.colorScheme, .dark)
        .task { await viewModel.refreshReminderAuthorization() }
    }

    private var settingsHome: some View {
        ZStack {
            AuraBackground(tab: .train)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        Button(action: viewModel.done) {
                            Text("Done")
                                .font(.system(size: 17, weight: .black, design: .rounded))
                                .foregroundStyle(ColorTokens.palette().tabActive)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(width: 44, height: 20)
                                .designAnchor("settings.done")
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityIdentifier("settingsDoneButton")
                    }

                    Text("Settings")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .tracking(-0.5)
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .designAnchor("settings.title")
                        .padding(.top, 8)

                    coachGroup
                    workoutGroup
                    cameraPostureGroup
                    aboutGroup
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .background(ColorTokens.palette().backgroundPrimary)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var coachGroup: some View {
        settingsGroup(
            title: "Coach",
            titleAnchor: "settings.coachingGroup",
            footer: "Coaching briefly lowers your music while it speaks."
        ) {
            SettingsRow(
                icon: "record_voice_over",
                title: "Spoken coaching",
                iconColor: coachPurple,
                toggle: binding(\.spokenCoachingEnabled)
            )
            .designAnchor("settings.spokenCoaching")

            SettingsRow(
                icon: "mic",
                title: "Voice commands",
                iconColor: coachPurple,
                toggle: binding(\.voiceCommandsEnabled),
                showsSeparator: true
            )
            .designAnchor("settings.voiceCommands")

            SettingsRow(
                icon: "help",
                title: "What you can say",
                iconColor: coachPurple,
                showsChevron: true,
                showsSeparator: true,
                action: { viewModel.navigate(to: .voiceCommandsHelp) }
            )
            .designAnchor("settings.voiceHelp")

            SettingsRow(
                icon: "timer",
                title: "Rest between sets",
                iconColor: coachPurple,
                value: viewModel.restPolicyLabel,
                showsChevron: true,
                showsSeparator: true,
                action: { viewModel.navigate(to: .restPolicy) }
            )
            .designAnchor("settings.restBetweenSets")
        }
    }

    private var workoutGroup: some View {
        settingsGroup(title: "Workout", titleAnchor: "settings.workoutGroup") {
            SettingsRow(
                icon: "scale",
                title: "Weight units",
                iconColor: workoutOrange,
                value: viewModel.weightUnitLabel,
                showsChevron: true,
                action: { viewModel.navigate(to: .weightUnit) }
            )
            .designAnchor("settings.weightUnits")

            SettingsRow(
                icon: "play_circle",
                title: "Start by holding position",
                iconColor: workoutOrange,
                toggle: binding(\.startByHoldingEnabled),
                showsSeparator: true
            )
            .designAnchor("settings.startByHolding")

            SettingsRow(
                icon: "notifications",
                title: "Workout reminders",
                iconColor: workoutOrange,
                value: viewModel.workoutRemindersValue,
                valueAnchor: "settings.reminders.value",
                showsChevron: true,
                showsSeparator: true,
                action: { viewModel.navigate(to: .workoutReminders) }
            )
            .designAnchor("settings.reminders")
        }
        .padding(.top, 3)
    }

    private var cameraPostureGroup: some View {
        settingsGroup(title: "Camera & Posture", titleAnchor: "settings.cameraPostureGroup") {
            SettingsRow(
                icon: "photo_camera",
                title: "Camera & framing",
                iconColor: cameraBlue,
                showsChevron: true,
                action: { viewModel.navigate(to: .cameraAndFraming) }
            )
            .designAnchor("settings.cameraFraming")

            SettingsRow(
                icon: "screen_rotation",
                title: "Tilt warnings",
                iconColor: cameraBlue,
                toggle: binding(\.tiltWarningsEnabled),
                showsSeparator: true
            )
            .designAnchor("settings.tiltWarnings")

            SettingsRow(
                icon: "accessibility_new",
                title: "Posture display",
                iconColor: cameraBlue,
                showsChevron: true,
                showsSeparator: true,
                action: { viewModel.navigate(to: .postureDisplay) }
            )
            .designAnchor("settings.postureDisplay")
        }
    }

    private var aboutGroup: some View {
        settingsGroup(
            title: "About",
            titleAnchor: nil,
            footer: "Camera frames are analyzed on this iPhone and never recorded."
        ) {
            SettingsRow(
                icon: "lock",
                title: "Privacy",
                iconColor: aboutGreen,
                value: "On-device",
                showsChevron: true,
                action: { viewModel.navigate(to: .privacy) }
            )
            SettingsRow(
                icon: "info",
                title: "About & medical notice",
                iconColor: aboutNeutral,
                showsChevron: true,
                showsSeparator: true,
                action: { viewModel.navigate(to: .about) }
            )
            SettingsRow(
                icon: "description",
                title: "Acknowledgements",
                iconColor: aboutNeutral,
                showsChevron: true,
                showsSeparator: true,
                action: { viewModel.navigate(to: .acknowledgements) }
            )
            SettingsRow(
                icon: "code",
                title: "Developer diagnostics",
                iconColor: aboutNeutral,
                showsChevron: true,
                showsSeparator: true,
                action: { viewModel.navigate(to: .developerDiagnostics) }
            )
        }
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(
        title: String,
        titleAnchor: String?,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(0.85)
                .textCase(.uppercase)
                .foregroundStyle(ColorTokens.palette().textMuted)
                .modifier(SettingsAnchor(name: titleAnchor))
                .padding(.horizontal, 4)

            VStack(spacing: 0, content: content)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            if let footer {
                Text(footer)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineSpacing(2)
                    .foregroundStyle(ColorTokens.palette().textSubtle)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
    }

    @ViewBuilder
    private func destination(for destination: SettingsDestination) -> some View {
        switch destination {
        case .voiceCommandsHelp:
            VoiceCommandsHelpView(
                sections: VoiceCommandHelp.sections(exercises: ExerciseCatalog.all),
                suggestions: [],
                micStatus: viewModel.voiceCommandsEnabled ? .off : .muted,
                isMicMuted: !viewModel.voiceCommandsEnabled,
                isCoachMuted: !viewModel.spokenCoachingEnabled,
                onSetMicMuted: { viewModel.voiceCommandsEnabled = !$0 },
                onSetCoachMuted: { viewModel.spokenCoachingEnabled = !$0 },
                progressLine: nil,
                onRetry: {},
                onOpenSettings: {},
                onDone: viewModel.popToPreviousPage,
                wrapsInNavigationStack: false,
                isStandaloneHelp: true
            )
        case .restPolicy:
            SettingsRestPolicyPage(viewModel: viewModel)
        case .weightUnit:
            SettingsWeightUnitPage(viewModel: viewModel)
        case .workoutReminders:
            WorkoutRemindersSettingsPage(viewModel: viewModel)
        case .cameraAndFraming:
            SettingsCameraFramingPage(viewModel: viewModel)
        case .postureDisplay:
            SettingsPostureDisplayPage(viewModel: viewModel)
        case .privacy:
            SettingsPrivacyPage()
        case .about:
            SettingsAboutPage()
        case .acknowledgements:
            AcknowledgementsView(wrapsInNavigationStack: false)
        case .developerDiagnostics:
            SettingsDeveloperDiagnosticsPage(viewModel: viewModel)
        case .notificationPreview:
            if let preview = viewModel.notificationPreview {
                NotificationPreviewScreen(viewModel: preview)
            }
        }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsViewModel, Value>) -> Binding<Value> {
        Binding(get: { viewModel[keyPath: keyPath] }, set: { viewModel[keyPath: keyPath] = $0 })
    }
}

private struct WorkoutRemindersSettingsPage: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.scenePhase) private var scenePhase

    private let reminderOrange = Color(hex: 0xFF8C5A, alpha: 0.9)

    var body: some View {
        ZStack {
            AuraBackground(tab: .train)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "notifications",
                            title: "Workout Reminders",
                            iconColor: reminderOrange,
                            toggle: Binding(
                                get: { viewModel.workoutRemindersEnabled },
                                set: { viewModel.workoutRemindersEnabled = $0 }
                            )
                        )

                        if viewModel.workoutRemindersEnabled {
                            settingDivider
                            repeatPicker
                            settingDivider
                            if viewModel.workoutReminderSettings.recurrence == .everyOtherDay {
                                dateRow(title: "Starts", selection: startDateBinding, components: .date)
                                settingDivider
                            } else if viewModel.workoutReminderSettings.recurrence == .weekly {
                                weekdayPicker
                                settingDivider
                            }
                            dateRow(title: "Time", selection: timeBinding, components: .hourAndMinute)
                        }
                    }
                    .background(ColorTokens.palette().backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if viewModel.workoutRemindersEnabled && viewModel.reminderAuthorization == .denied {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notifications are turned off for Fix My Posture.")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(ColorTokens.palette().textMuted)
                            Button("Open Notification Settings", action: viewModel.openNotificationSettings)
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(ColorTokens.palette().tabActive)
                        }
                        .padding(.horizontal, 4)
                    } else if viewModel.workoutRemindersEnabled {
                        Text("Reminders are scheduled on this iPhone and can be changed at any time.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(ColorTokens.palette().textSubtle)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Workout Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color(hex: 0x0E0B16), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await viewModel.refreshReminderAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.refreshReminderAuthorization() }
        }
    }

    private var repeatPicker: some View {
        HStack {
            Text("Repeat")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
            Spacer(minLength: 8)
            Picker("Repeat", selection: Binding(
                get: { viewModel.workoutReminderSettings.recurrence },
                set: { recurrence in viewModel.selectReminderRecurrence(recurrence) }
            )) {
                ForEach(WorkoutReminderRecurrence.allCases) { recurrence in
                    Text(recurrence.title).tag(recurrence)
                }
            }
            .pickerStyle(.menu)
            .tint(ColorTokens.palette().textMuted)
            .accessibilityIdentifier("workoutReminderRecurrencePicker")
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Days")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { weekday in
                    let selected = viewModel.workoutReminderSettings.weekdays.contains(weekday)
                    let label = shortWeekdayLabels[weekday - 1]
                    Button {
                        viewModel.updateReminderSettings { settings in
                            if settings.weekdays.contains(weekday) {
                                guard settings.weekdays.count > 1 else { return }
                                settings.weekdays.remove(weekday)
                            } else {
                                settings.weekdays.insert(weekday)
                            }
                        }
                    } label: {
                        Text(label)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(selected ? Color.white : ColorTokens.palette().textMuted)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                selected ? ColorTokens.palette().tabActive : Color.white.opacity(0.08),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(weekdayNames[weekday - 1])
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityIdentifier("workoutReminderWeekday\(weekday)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func dateRow(title: String, selection: Binding<Date>, components: DatePickerComponents) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
            Spacer(minLength: 8)
            DatePicker(title, selection: selection, displayedComponents: components)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(ColorTokens.palette().tabActive)
                .accessibilityIdentifier(title == "Time" ? "workoutReminderTimePicker" : "workoutReminderStartDatePicker")
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = viewModel.workoutReminderSettings.hour
                components.minute = viewModel.workoutReminderSettings.minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                viewModel.updateReminderSettings {
                    $0.hour = components.hour ?? $0.hour
                    $0.minute = components.minute ?? $0.minute
                }
            }
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.workoutReminderSettings.everyOtherDayStartDate },
            set: { date in viewModel.updateReminderSettings { $0.everyOtherDayStartDate = date } }
        )
    }

    private var settingDivider: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }

    private var shortWeekdayLabels: [String] {
        DateFormatter().veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
    }

    private var weekdayNames: [String] {
        DateFormatter().weekdaySymbols ?? ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    }
}

private struct SettingsAnchor: ViewModifier {
    let name: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let name {
            content.designAnchor(name)
        } else {
            content
        }
    }
}
