import SwiftUI

/// One coaching line, large enough to read from where the user stands. Corrective tips carry the
/// amber used for their joints; reminders stay neutral. The compact style wraps into the narrow space
/// beside the body when the user stands close.
struct WorkoutTipBubble: View {
    let cue: CoachingCue
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !compact {
                Image(systemName: cue.kind == .corrective ? "figure.strengthtraining.traditional" : "lightbulb.fill")
                    .foregroundStyle(accent)
            }
            Text(cue.text)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(compact ? .headline : .title3.weight(.semibold))
        .multilineTextAlignment(.leading)
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 8 : 10)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.9), lineWidth: 2))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var accent: Color {
        cue.kind == .corrective ? WorkoutJointOverlayView.cueColor : .white.opacity(0.7)
    }
}

/// Places the active tip with `WorkoutTipLayout`, clear of the body, the exercise's motion envelope,
/// and the HUD. The tip is measured on one line and wrapped narrow; with no room it isn't shown,
/// and a corrective cue is still spoken. Fades in and out, instantly with Reduce Motion.
struct WorkoutTipOverlayView: View {
    let tip: CoachingTip?
    /// Body and motion envelope, in the workout overlay coordinate space.
    let protectedRects: [CGRect]
    /// HUD regions, in the same space.
    let hudRects: [CGRect]

    static let wideWidth: CGFloat = 320
    static let narrowWidth: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measured: MeasuredTip?
    @State private var placed: PlacedTip?
    /// The last slot used, kept while it stays valid so tips don't hop around.
    @State private var lastFrame: CGRect?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let tip {
                    measuring(tip, width: Self.wideWidth, isWide: true)
                    measuring(tip, width: Self.narrowWidth, isWide: false)
                }
                if let tip, let placed, placed.id == tip.id {
                    WorkoutTipBubble(cue: tip.cue, compact: placed.isCompact)
                        .frame(width: placed.frame.width, height: placed.frame.height)
                        .position(x: placed.frame.midX, y: placed.frame.midY)
                        .transition(.opacity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Tip: \(tip.cue.text)")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .onPreferenceChange(MeasuredTipKey.self) { measured = $0 }
            .onChange(of: LayoutInput(measured: measured, tipID: tip?.id, protected: protectedRects,
                                      reserved: hudRects, size: geometry.size), initial: true) { _, input in
                place(input)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: visibleTipID)
        .allowsHitTesting(false)
    }

    private var visibleTipID: Int? {
        guard let tip, let placed, placed.id == tip.id else { return nil }
        return tip.id
    }

    /// An invisible copy that reports the tip's size when offered `width`.
    private func measuring(_ tip: CoachingTip, width: CGFloat, isWide: Bool) -> some View {
        WorkoutTipBubble(cue: tip.cue, compact: !isWide)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: MeasuredTipKey.self, value: MeasuredTip(
                    id: tip.id, wide: isWide ? proxy.size : nil, narrow: isWide ? nil : proxy.size))
            })
            .frame(width: width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private func place(_ input: LayoutInput) {
        guard let measured = input.measured, measured.id == input.tipID,
              let wide = measured.wide, let narrow = measured.narrow else {
            placed = nil
            return
        }
        let frame = WorkoutTipLayout.placement(sizes: [wide, narrow], container: CGRect(origin: .zero, size: input.size),
                                               protected: input.protected, reserved: input.reserved, previous: lastFrame)
        // A kept slot can differ from the fresh measurement by a point.
        placed = frame.map { PlacedTip(id: measured.id, frame: $0,
                                       isCompact: abs($0.width - wide.width) > 1 || abs($0.height - wide.height) > 1) }
        if let frame { lastFrame = frame }
    }
}

private struct MeasuredTip: Equatable {
    var id: Int
    var wide: CGSize?
    var narrow: CGSize?
}

private struct PlacedTip: Equatable {
    var id: Int
    var frame: CGRect
    var isCompact: Bool
}

private struct LayoutInput: Equatable {
    var measured: MeasuredTip?
    var tipID: Int?
    var protected: [CGRect]
    var reserved: [CGRect]
    var size: CGSize
}

/// Both measurements of the current tip, merged.
private struct MeasuredTipKey: SwiftUI.PreferenceKey {
    static var defaultValue: MeasuredTip?

    static func reduce(value: inout MeasuredTip?, nextValue: () -> MeasuredTip?) {
        guard let next = nextValue() else { return }
        guard var current = value, current.id == next.id else {
            value = next
            return
        }
        current.wide = next.wide ?? current.wide
        current.narrow = next.narrow ?? current.narrow
        value = current
    }
}
