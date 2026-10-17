import CoreGraphics

enum Metrics {
    enum Radius {
        static let iconTile: CGFloat = 9
        static let thumbnail: CGFloat = 14
        static let row: CGFloat = 20
        static let card: CGFloat = 20
        static let hero: CGFloat = 28
        static let capsule: CGFloat = 999
    }

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let screenMargin: CGFloat = 20
        static let xLarge: CGFloat = 24
    }

    enum Size {
        static let tapTarget: CGFloat = 44
        static let primaryCTA: CGFloat = 56
        static let stickyCTA: CGFloat = 58
        static let cameraPrimary: CGFloat = 84
        static let repCount: CGFloat = 96
        static let progressBar: CGFloat = 10
        static let tabBar: CGFloat = 86
        static let hudIconButton: CGFloat = 44
        static let statusChip: CGFloat = 24
        static let filterChipVisual: CGFloat = 36
        static let capsuleButtonVisual: CGFloat = 40
    }
}
