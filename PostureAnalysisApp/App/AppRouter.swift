import Foundation
import Observation

/// Navigation state shared by the four tab stacks. This type has no SwiftUI dependency.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab
    private(set) var paths: [AppTab: [AppRoute]]
    private(set) var presentedFullScreenRoute: AppRoute?

    init(selectedTab: AppTab = .train) {
        self.selectedTab = selectedTab
        paths = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, []) })
    }

    func path(for tab: AppTab) -> [AppRoute] {
        paths[tab, default: []]
    }

    func setPath(_ path: [AppRoute], for tab: AppTab) {
        paths[tab] = path
    }

    /// Selecting the current tab again returns that stack to its root.
    func select(_ tab: AppTab) {
        guard selectedTab == tab else {
            selectedTab = tab
            return
        }
        paths[tab] = []
    }

    /// Pushes into the route's owning stack, or presents settings and the workout camera full screen.
    func open(_ route: AppRoute) {
        selectedTab = route.owningTab
        if route.isPresentedFullScreen {
            presentedFullScreenRoute = route
        } else {
            paths[route.owningTab, default: []].append(route)
        }
    }

    func dismissFullScreen() {
        presentedFullScreenRoute = nil
    }
}
