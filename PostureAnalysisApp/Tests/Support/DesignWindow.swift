import UIKit

@MainActor
final class DesignWindow: UIWindow {
    static let fixedSize = CGSize(width: 390, height: 844)

    init() {
        super.init(frame: CGRect(origin: .zero, size: Self.fixedSize))
        overrideUserInterfaceStyle = .dark
        traitOverrides.preferredContentSizeCategory = .large
        traitOverrides.displayScale = 3
        layer.contentsScale = 3
    }

    override var safeAreaInsets: UIEdgeInsets {
        UIEdgeInsets(top: 54, left: 0, bottom: 34, right: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("DesignWindow is created programmatically.")
    }
}
