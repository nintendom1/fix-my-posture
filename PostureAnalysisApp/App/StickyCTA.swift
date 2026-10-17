import SwiftUI

extension View {
    /// Reserves the design's sticky button slot above the native tab bar.
    func stickyCTA<CTA: View>(
        bottomSpacing: CGFloat = Metrics.Spacing.medium,
        @ViewBuilder content: () -> CTA
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            content()
                .frame(height: Metrics.Size.stickyCTA)
                .padding(.horizontal, Metrics.Spacing.large)
                .padding(.bottom, bottomSpacing)
        }
    }
}

#if DEBUG
struct StickyCTALayoutFixture: View {
    var body: some View {
        TabView {
            NavigationStack {
                Color.clear
                    .stickyCTA {
                        Button("Continue") {}
                            .frame(maxWidth: .infinity)
                            .frame(height: Metrics.Size.stickyCTA)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                            .designAnchor("sticky.cta")
                    }
            }
            .tabItem { Label("Train", systemImage: "dumbbell.fill") }
        }
    }
}
#endif
