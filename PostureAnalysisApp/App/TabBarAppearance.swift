import SwiftUI
import UIKit

enum TabBarAppearance {
    @MainActor
    static func configure() {
        let style = TabBarStyle.design
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemMaterialDark)
        appearance.backgroundColor = UIColor(
            red: style.background.red,
            green: style.background.green,
            blue: style.background.blue,
            alpha: style.background.alpha
        )
        appearance.shadowColor = UIColor(
            red: style.hairlineColor.red,
            green: style.hairlineColor.green,
            blue: style.hairlineColor.blue,
            alpha: style.hairlineColor.alpha
        )

        let titleFont = UIFont.systemFont(ofSize: style.titleFont.pointSize, weight: .heavy)
        let roundedDescriptor = titleFont.fontDescriptor.withDesign(.rounded) ?? titleFont.fontDescriptor
        let roundedTitleFont = UIFont(descriptor: roundedDescriptor, size: style.titleFont.pointSize)
        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = UIColor(
            red: style.inactiveColor.red,
            green: style.inactiveColor.green,
            blue: style.inactiveColor.blue,
            alpha: style.inactiveColor.alpha
        )
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(
                red: style.inactiveColor.red,
                green: style.inactiveColor.green,
                blue: style.inactiveColor.blue,
                alpha: style.inactiveColor.alpha
            ),
            .font: roundedTitleFont
        ]
        itemAppearance.selected.titleTextAttributes = [.font: roundedTitleFont]

        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }
}
