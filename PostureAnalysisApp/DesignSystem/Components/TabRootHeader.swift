import SwiftUI

struct TabRootHeader<Leading: View, LargeTrailing: View, CompactTrailing: View>: View {
    let title: String
    let height: CGFloat
    let alignment: VerticalAlignment
    let compactBarAnchor: String
    let leading: Leading
    let largeTrailing: LargeTrailing
    let compactTrailing: CompactTrailing

    init(
        title: String,
        height: CGFloat,
        alignment: VerticalAlignment,
        compactBarAnchor: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder largeTrailing: () -> LargeTrailing,
        @ViewBuilder compactTrailing: () -> CompactTrailing
    ) {
        self.title = title
        self.height = height
        self.alignment = alignment
        self.compactBarAnchor = compactBarAnchor
        self.leading = leading()
        self.largeTrailing = largeTrailing()
        self.compactTrailing = compactTrailing()
    }

    var body: some View {
        HStack(alignment: alignment) {
            leading
            Spacer(minLength: 0)
            largeTrailing
        }
        .frame(height: height, alignment: .top)
    }

    var compactBar: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            compactTrailing
        }
        .padding(.horizontal, Metrics.Spacing.screenMargin)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background {
            Rectangle()
                .fill(Color(hex: 0x0E0B16, alpha: 0.72))
                .background(.ultraThinMaterial)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1 / UIScreen.main.scale)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
        .designAnchor(compactBarAnchor)
    }
}

enum TabRootHeaderCollapse {
    /// `titleFrame` is measured in scroll-content coordinates, while `scrollOffset` is the distance
    /// that content has moved up. The compact bar replaces the large title once its bottom reaches
    /// the scroll viewport's top edge.
    static func shouldShowCompactBar(scrollOffset: CGFloat, titleFrame: CGRect) -> Bool {
        titleFrame.maxY - scrollOffset <= 0
    }
}

struct TabRootScrollOffsetPreferenceKey: SwiftUI.PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TabRootTitleFramePreferenceKey: SwiftUI.PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

extension View {
    func tabRootTitleFrame(in coordinateSpace: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TabRootTitleFramePreferenceKey.self,
                    value: proxy.frame(in: .named(coordinateSpace))
                )
            }
        }
    }
}
