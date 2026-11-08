import AdaptiveTraining
import SwiftUI

/// Settings → Developer diagnostics → Adaptive training.
struct AdaptiveDebugScreen: View {
    /// "Too Hard", "Okay", "Easy", or "Not rated".
    static func effortLabel(_ effort: EffortFeedback?) -> String {
        switch effort {
        case .tooHard: return "Too Hard"
        case .okay: return "Okay"
        case .easy: return "Easy"
        case nil: return "Not rated"
        }
    }

    @Bindable var viewModel: AdaptiveDebugViewModel

    private var palette: ColorPalette { ColorTokens.palette() }

    var body: some View {
        SettingsSubpage(title: "Adaptive training") {
            if viewModel.isEmpty {
                messageCard("Adaptive training data is unavailable.")
            } else if let snapshot = viewModel.snapshot {
                headerCard(snapshot)
                if let errorMessage = viewModel.errorMessage {
                    messageCard(errorMessage, color: palette.danger)
                }
                if snapshot.families.isEmpty {
                    messageCard("No adaptive training facts have been recorded.")
                } else {
                    ForEach(snapshot.families) { family in
                        familyCard(family)
                    }
                }
                exportControls
            } else if let errorMessage = viewModel.errorMessage {
                messageCard(errorMessage, color: palette.danger)
            } else {
                messageCard("Adaptive training data is loading.")
            }
        }
        .task { await viewModel.refresh() }
    }

    private func headerCard(_ snapshot: AdaptiveSnapshot) -> some View {
        debugCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("Developer data")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                detailLine("Policy", value: snapshot.policyVersion.rawValue)
                detailLine("Ladders", value: snapshot.catalog.version)
                detailLine("Time zone", value: snapshot.timeZone)
                detailLine("Today's Session", value: todayStatus(snapshot.today))
            }
        }
    }

    private func familyCard(_ family: FamilySummary) -> some View {
        debugCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline) {
                    Text(family.debugName)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 8)
                    Text(family.isActive ? "Active" : "Inactive")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(family.isActive ? palette.success : palette.textMuted)
                }
                detailLine("Current", value: family.current?.description ?? "Not set")
                detailLine("Confidence", value: family.confidence.map { $0.rawValue.capitalized } ?? "Not set")
                detailLine("Last performed", value: dateLabel(family.lastPerformedAt))
                detailLine("Last change", value: dateLabel(family.lastChangedAt))

                if let rationale = family.latestRationale {
                    detailLine("Latest rationale", value: rationale)
                }

                Text("Counts")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 2)
                detailLine("Too Hard / Okay / Easy",
                           value: "\(family.effort.tooHard) / \(family.effort.okay) / \(family.effort.easy)")
                detailLine("Bonus offered / accepted / declined",
                           value: "\(family.bonus.offered) / \(family.bonus.accepted) / \(family.bonus.declined)")
                detailLine("Tracking issues", value: "\(family.trackingIssues)")
                detailLine("Sources", value: sourceCounts(family.sources))

                if !family.recentEvidence.isEmpty {
                    Text("Recent evidence")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(family.recentEvidence.enumerated()), id: \.element.id) { index, row in
                            evidenceRow(row)
                            if index < family.recentEvidence.count - 1 {
                                Rectangle()
                                    .fill(palette.borderCard)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("adaptiveDebugFamily_\(family.family.rawValue)")
    }

    private func evidenceRow(_ row: EvidenceSummary) -> some View {
        let trackingIssue = row.isTrackingIssue
        return VStack(alignment: .leading, spacing: 5) {
            Text("\(timeLabel(row.recordedAt)) · \(row.source.rawValue) · \(row.variant.rawValue)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            Text("asked \(row.prescribed?.description ?? "—") · confirmed \(row.confirmed.map(workLabel) ?? "—") (\(confirmationLabel(row.confirmation)))")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(palette.textSecondary)
            Text("tracker \(trackerLabel(row.trackerStatus)) · observed \(row.trackerObserved.map(workLabel) ?? "—")")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(trackingIssue ? palette.warning : palette.textSecondary)
            Text("Effort: \(Self.effortLabel(row.effort)) · Mid-set Too Hard: \(row.midSetTooHard ? "Yes" : "No")")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(palette.textSecondary)
            Text("Bonus: \(bonusLabel(row.bonus)) · Completion: \(completionLabel(row.completion))")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(palette.textSecondary)
            Text("Decision: \(row.decision?.rawValue ?? "none") · Codes: \(row.codes.map(\.rawValue).joined(separator: ", ").ifEmpty("none"))")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(palette.textSecondary)
            if let summary = row.summary {
                Text(summary)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var exportControls: some View {
        HStack(spacing: 12) {
            if let exportURL = viewModel.exportURL {
                ShareLink(item: exportURL) {
                    Label("Share JSON", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .foregroundStyle(palette.tabActive)
                .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("adaptiveDebugShareButton")
            }

            if viewModel.exportedJSON != nil {
                Button(viewModel.didCopy ? "Copied" : "Copy JSON") {
                    viewModel.copyJSON()
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.tabActive)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("adaptiveDebugCopyButton")
            }
        }
    }

    private func messageCard(_ message: String, color: Color? = nil) -> some View {
        debugCard {
            Text(message)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color ?? palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func debugCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func detailLine(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func todayStatus(_ status: TodaySessionStatus) -> String {
        switch status {
        case .needsCalibration:
            "Needs calibration"
        case .ready(let session):
            "\(session.family.rawValue): \(session.main.variant.rawValue) × \(session.main.dose)"
        case .completedToday(let family, _):
            "Done today (\(family.rawValue))"
        case .nothingOffered:
            "Nothing offered on this device"
        }
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }

    private func timeLabel(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func sourceCounts(_ counts: [SourceCount]) -> String {
        guard !counts.isEmpty else { return "None" }
        return counts.map { "\($0.source.rawValue) \($0.count)" }.joined(separator: " · ")
    }

    private func workLabel(_ amount: WorkAmount) -> String {
        amount.isZero ? "0" : amount.description
    }

    private func confirmationLabel(_ confirmation: ConfirmationSource) -> String {
        switch confirmation {
        case .user: "user"
        case .trackerAccepted: "tracker accepted"
        case .none: "none"
        }
    }

    private func trackerLabel(_ status: TrackerStatus) -> String {
        switch status {
        case .tracked: "Tracked"
        case .lowConfidence: "Low confidence"
        case .lost: "Tracking lost"
        case .notTracked: "Not tracked"
        }
    }

    private func bonusLabel(_ bonus: BonusRecord?) -> String {
        guard let bonus else { return "None" }
        return bonus.accepted ? "Accepted (\(bonus.completed.map(workLabel) ?? "no amount"))" : "Declined"
    }

    private func completionLabel(_ completion: CompletionReason) -> String {
        switch completion {
        case .completed: "Completed"
        case .stoppedEarly: "Stopped early"
        case .switchedToEasier: "Switched to easier"
        case .endedWorkout: "Ended workout"
        case .notAttempted: "Not attempted"
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
