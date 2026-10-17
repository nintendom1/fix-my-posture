import SwiftUI

#if DEBUG
@MainActor
public final class DesignAnchorRegistry {
    public static let shared = DesignAnchorRegistry()

    private var storedFrames: [String: CGRect] = [:]

    private init() {}

    public var frames: [String: CGRect] { storedFrames }

    public func record(_ name: String, frame: CGRect) {
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite else { return }
        storedFrames[name] = frame
    }

    public func reset() {
        storedFrames.removeAll(keepingCapacity: true)
    }
}

private struct DesignAnchorModifier: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .global)
                Color.clear
                    .allowsHitTesting(false)
                    .onAppear { report(frame) }
                    .onChange(of: frame) { _, updatedFrame in report(updatedFrame) }
            }
            .allowsHitTesting(false)
        }
    }

    private func report(_ frame: CGRect) {
        Task { @MainActor in
            DesignAnchorRegistry.shared.record(name, frame: frame)
        }
    }
}

public extension View {
    func designAnchor(_ name: String) -> some View {
        modifier(DesignAnchorModifier(name: name))
    }
}
#else
public extension View {
    func designAnchor(_ name: String) -> some View { self }
}
#endif
