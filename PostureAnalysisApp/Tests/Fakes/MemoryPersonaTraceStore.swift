import Foundation
@testable import PostureAnalysisApp

final class MemoryPersonaTraceStore: PersonaTraceStoring {
    var state: PersonaTraceState
    private(set) var saveCount = 0

    init(state: PersonaTraceState = .empty) {
        self.state = state
    }

    func load() -> PersonaTraceState { state }

    func save(_ state: PersonaTraceState) {
        self.state = state
        saveCount += 1
    }
}
