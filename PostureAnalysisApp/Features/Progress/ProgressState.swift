import Foundation

struct ProgressState: Equatable {
    let weeklyStats: WeeklyStats
    let postureAssessmentCount: Int
    let latestAssessmentDate: Date?
    let showsChartPlaceholders: Bool

    var recentWorkouts: [WeeklyStats.RecentWorkout] { weeklyStats.recent }

    var postureSummary: String {
        guard let latestAssessmentDate else {
            return postureAssessmentCount == 0 ? "No assessments yet" : "\(postureAssessmentCount) assessments"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        let noun = postureAssessmentCount == 1 ? "assessment" : "assessments"
        return "\(postureAssessmentCount) \(noun) · latest \(formatter.string(from: latestAssessmentDate))"
    }
}

enum ProgressIntent: Equatable {
    case appeared
    case openHistory
    case openPosture
}
