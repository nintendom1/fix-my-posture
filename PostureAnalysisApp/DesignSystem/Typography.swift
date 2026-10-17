import SwiftUI
import UIKit

enum Typography {
    enum Style: CaseIterable, Hashable {
        case largeTitle
        case title
        case title2
        case headline
        case body
        case caption1
        case caption2
        case eyebrow
        case repCounter

        var pointSize: CGFloat {
            switch self {
            case .largeTitle: return 34
            case .title: return 30
            case .title2: return 21
            case .headline: return 16
            case .body: return 15
            case .caption1: return 13
            case .caption2: return 12
            case .eyebrow: return 11
            case .repCounter: return Metrics.Size.repCount
            }
        }

        var weight: UIFont.Weight {
            switch self {
            case .largeTitle, .title, .title2: return .black
            case .headline, .eyebrow: return .heavy
            case .body, .caption1: return .bold
            case .caption2: return .semibold
            case .repCounter: return .heavy
            }
        }

        var dynamicTypeStyle: UIFont.TextStyle {
            switch self {
            case .largeTitle, .repCounter: return .largeTitle
            case .title: return .title1
            case .title2: return .title2
            case .headline: return .headline
            case .body: return .body
            case .caption1: return .caption1
            case .caption2, .eyebrow: return .caption2
            }
        }

        var tracking: CGFloat {
            switch self {
            case .largeTitle, .title: return -0.5
            case .eyebrow: return 1
            case .repCounter: return -3
            default: return 0
            }
        }
    }

    static var largeTitle: Font { font(for: .largeTitle) }
    static var title: Font { font(for: .title) }
    static var title2: Font { font(for: .title2) }
    static var headline: Font { font(for: .headline) }
    static var body: Font { font(for: .body) }
    static var caption1: Font { font(for: .caption1) }
    static var caption2: Font { font(for: .caption2) }
    static var eyebrow: Font { font(for: .eyebrow) }
    static var repCounter: Font { font(for: .repCounter) }

    static func font(for style: Style, dynamicTypeSize: DynamicTypeSize = .large) -> Font {
        Font(uiFont(for: style, contentSizeCategory: contentSizeCategory(for: dynamicTypeSize)))
    }

    static func uiFont(for style: Style, contentSizeCategory: UIContentSizeCategory = .large) -> UIFont {
        let systemFont = UIFont.systemFont(ofSize: style.pointSize, weight: style.weight)
        let roundedDescriptor = systemFont.fontDescriptor.withDesign(.rounded) ?? systemFont.fontDescriptor
        let roundedFont = UIFont(descriptor: roundedDescriptor, size: style.pointSize)
        let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        return UIFontMetrics(forTextStyle: style.dynamicTypeStyle)
            .scaledFont(for: roundedFont, compatibleWith: traits)
    }

    static func uiFont(for style: Style, dynamicTypeSize: DynamicTypeSize) -> UIFont {
        uiFont(for: style, contentSizeCategory: contentSizeCategory(for: dynamicTypeSize))
    }

    private static func contentSizeCategory(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

private struct TextStyleModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let style: Typography.Style

    @ViewBuilder
    func body(content: Content) -> some View {
        if style == .repCounter {
            content
                .font(Typography.font(for: style, dynamicTypeSize: dynamicTypeSize))
                .tracking(style.tracking)
                .monospacedDigit()
        } else {
            content
                .font(Typography.font(for: style, dynamicTypeSize: dynamicTypeSize))
                .tracking(style.tracking)
                .textCase(style == .eyebrow ? .uppercase : nil)
        }
    }
}

extension View {
    func textStyle(_ style: Typography.Style) -> some View {
        modifier(TextStyleModifier(style: style))
    }
}
