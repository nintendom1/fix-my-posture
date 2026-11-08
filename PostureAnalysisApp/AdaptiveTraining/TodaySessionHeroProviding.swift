import AdaptiveTraining
import Foundation

/// What the Train hero needs to show and start Today's Session (#111). Filled in by the today-hero package.
@MainActor
protocol TodaySessionHeroProviding: TodaySessionStarting {
    func status(asOf now: Date) -> TodaySessionStatus
    func displayName(of variant: VariantID) -> String
}
