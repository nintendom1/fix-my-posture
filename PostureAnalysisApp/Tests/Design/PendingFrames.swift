enum PendingFrames {
    static let ids: Set<String> = [
        "settings",
    ]
}

enum ImplementedDesignFixtures {
    static let ids: Set<String> = Set(["train", "routines", "routine", "editor", "editor-picker", "editor-new", "library", "exercise"])
        .union(WorkoutCameraFixtures.ids)
        .union(WorkoutCompleteFixtures.ids)
        .union(ProgressFixtures.ids)
        .union(HistoryFixtures.ids)
        .union(PostureFixtures.ids)
        .union(AssessmentFixtures.ids)
}
