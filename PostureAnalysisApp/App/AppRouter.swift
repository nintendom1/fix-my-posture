import Foundation
import Observation

/// Navigation state shared by the four tab stacks. This type has no SwiftUI dependency.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab
    private(set) var paths: [AppTab: [AppRoute]]
    private(set) var presentedFullScreenRoute: AppRoute? {
        // Leaving Settings, by dismissal or by another full-screen route replacing it, ends its calibration.
        didSet { if presentedFullScreenRoute != .settings { isCalibratingInSettings = false } }
    }
    /// True while Settings owns a pushed calibration, so reminder taps leave that flow in place.
    var isCalibratingInSettings = false

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

    /// Presents a full-screen route (settings or the workout camera) over the current tab without switching tabs.
    func present(_ route: AppRoute) {
        guard route.isPresentedFullScreen else { return open(route) }
        presentedFullScreenRoute = route
    }

    func dismissFullScreen() {
        presentedFullScreenRoute = nil
    }
}
