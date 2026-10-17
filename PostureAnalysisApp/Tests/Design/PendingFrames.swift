enum PendingFrames {
    static let ids: Set<String> = [
        "complete", "progress", "history",
        "posture", "assessment", "settings",
    ]
}

enum ImplementedDesignFixtures {
    static let ids: Set<String> = Set(["train", "routines", "routine", "editor", "editor-picker", "editor-new", "library", "exercise"])
        .union(WorkoutCameraFixtures.ids)
}
