import XCTest
import SwiftUI
import UIKit
@testable import PostureAnalysisApp

final class DesignSystemTests: XCTestCase {
    func testDarkColorTokensMatchDesignHexValues() {
        let colors = ColorTokens.palette(for: .dark)

        assertRGBA(colors.brand, hex: 0x7C4DFF)
        assertRGBA(colors.accent, hex: 0xFF7F9E)
        assertRGBA(colors.success, hex: 0x6EE7B7)
        assertRGBA(colors.warning, hex: 0xFFC46B)
        assertRGBA(colors.danger, hex: 0xFF7B8A)
        assertRGBA(colors.restInfo, hex: 0x6FD6FF)
        assertRGBA(colors.backgroundPrimary, hex: 0x0E0B16)
        assertRGBA(colors.backgroundCard, hex: 0xFFFFFF, alpha: 0.06)
        assertRGBA(colors.borderCard, hex: 0xFFFFFF, alpha: 0.07)
        assertRGBA(colors.textPrimary, hex: 0xF6F3FB)
        assertRGBA(colors.textSecondary, hex: 0xB9B0CC)
        assertRGBA(colors.textMuted, hex: 0xA49CB8)
        assertRGBA(colors.textSubtle, hex: 0x8A82A0)
        assertRGBA(colors.tabActive, hex: 0xC9B3FF)
        assertRGBA(colors.tabPostureActive, hex: 0x9FB0FF)
        assertRGBA(colors.tabInactive, hex: 0x7D758C)
        assertRGBA(colors.hudToggleOff, hex: 0xFF5A6E, alpha: 0.55)
        assertRGBA(colors.filterSelectedText, hex: 0x1A1226)
        assertRGBA(colors.filterUnselectedBackground, hex: 0xFFFFFF, alpha: 0.08)
        assertRGBA(colors.filterUnselectedText, hex: 0xE4DDF0)
    }

    func testLightPaletteFallsBackToDarkPalette() {
        let dark = ColorTokens.palette(for: .dark)
        let light = ColorTokens.palette(for: .light)
        let darkColors = dark.allColors
        let lightColors = light.allColors

        XCTAssertEqual(darkColors.count, lightColors.count)
        for (darkColor, lightColor) in zip(darkColors, lightColors) {
            assertRGBA(lightColor, matches: darkColor)
        }
    }

    func testColorHexInitializerRoundTripsRGBA() throws {
        let color = try XCTUnwrap(Color(hex: "#12345680"))
        let components = try XCTUnwrap(rgbaComponents(of: color))

        XCTAssertEqual(components.red, 0x12 / 255, accuracy: 0.001)
        XCTAssertEqual(components.green, 0x34 / 255, accuracy: 0.001)
        XCTAssertEqual(components.blue, 0x56 / 255, accuracy: 0.001)
        XCTAssertEqual(components.alpha, 0x80 / 255, accuracy: 0.001)
    }

    func testWorkoutStateColorsMapFromFoundationVisualState() {
        let ready = ColorTokens.workoutColors(for: visualState(.ready))
        let active = ColorTokens.workoutColors(for: visualState(.active))
        let paused = ColorTokens.workoutColors(for: visualState(.paused(.user)))
        let tip = ColorTokens.workoutColors(for: visualState(.tip))
        let rest = ColorTokens.workoutColors(for: visualState(.rest))
        let lost = ColorTokens.workoutColors(for: visualState(.lost))
        let complete = ColorTokens.workoutColors(for: visualState(.complete))

        assertRGBA(ready.tint, hex: 0xB9A2FF)
        assertRGBA(ready.glow, hex: 0x7C4DFF, alpha: 0.5)
        assertRGBA(active.glow, hex: 0x7C4DFF, alpha: 0.45)
        assertRGBA(paused.tint, hex: 0xD8D0E8)
        assertRGBA(paused.glow, hex: 0xC8BEE6, alpha: 0.25)
        assertRGBA(tip.tint, hex: 0xFFC46B)
        assertRGBA(tip.glow, hex: 0xFFB450, alpha: 0.45)
        assertRGBA(rest.tint, hex: 0x6FD6FF)
        assertRGBA(rest.glow, hex: 0x50BEFF, alpha: 0.45)
        assertRGBA(lost.tint, hex: 0xFF7B8A)
        assertRGBA(lost.glow, hex: 0xFF5A6E, alpha: 0.45)
        assertRGBA(complete.tint, hex: 0x6EE7B7)
        assertRGBA(complete.glow, hex: 0x3CDC96, alpha: 0.55)
    }

    func testMetricsMatchTheDesignSystemSpecification() {
        XCTAssertEqual(Metrics.Radius.iconTile, 9)
        XCTAssertEqual(Metrics.Radius.thumbnail, 14)
        XCTAssertEqual(Metrics.Radius.row, 20)
        XCTAssertEqual(Metrics.Radius.card, 20)
        XCTAssertEqual(Metrics.Radius.hero, 28)
        XCTAssertEqual(Metrics.Spacing.xSmall, 4)
        XCTAssertEqual(Metrics.Spacing.small, 8)
        XCTAssertEqual(Metrics.Spacing.medium, 12)
        XCTAssertEqual(Metrics.Spacing.large, 16)
        XCTAssertEqual(Metrics.Spacing.screenMargin, 20)
        XCTAssertEqual(Metrics.Spacing.xLarge, 24)
        XCTAssertEqual(Metrics.Size.tapTarget, 44)
        XCTAssertEqual(Metrics.Size.primaryCTA, 56)
        XCTAssertEqual(Metrics.Size.stickyCTA, 58)
        XCTAssertEqual(Metrics.Size.cameraPrimary, 84)
        XCTAssertEqual(Metrics.Size.repCount, 96)
        XCTAssertEqual(Metrics.Size.progressBar, 10)
        XCTAssertEqual(Metrics.Size.tabBar, 86)
        XCTAssertEqual(Metrics.Size.hudIconButton, 44)
        XCTAssertEqual(Metrics.Size.statusChip, 24)
        XCTAssertEqual(Metrics.Size.filterChipVisual, 36)
    }

    func testTypographyUsesRoundedDesignWeightsAndDynamicType() throws {
        let styles: [(Typography.Style, CGFloat, CGFloat)] = [
            (.largeTitle, 34, UIFont.Weight.black.rawValue),
            (.title, 30, UIFont.Weight.black.rawValue),
            (.title2, 21, UIFont.Weight.black.rawValue),
            (.headline, 16, UIFont.Weight.heavy.rawValue),
            (.body, 15, UIFont.Weight.bold.rawValue),
            (.caption1, 13, UIFont.Weight.bold.rawValue),
            (.caption2, 12, UIFont.Weight.semibold.rawValue),
            (.eyebrow, 11, UIFont.Weight.heavy.rawValue),
            (.repCounter, 96, UIFont.Weight.heavy.rawValue)
        ]

        for (style, pointSize, weight) in styles {
            let largeFont = Typography.uiFont(for: style, contentSizeCategory: .large)
            XCTAssertEqual(largeFont.pointSize, pointSize, accuracy: 0.01, "Unexpected base size for \(style)")
            XCTAssertEqual(try XCTUnwrap(roundedWeight(of: largeFont)), weight, accuracy: 0.01, "Unexpected weight for \(style)")
            XCTAssertNotNil(largeFont.fontDescriptor.withDesign(.rounded), "\(style) should use SF Pro Rounded")

            let accessibilityFont = Typography.uiFont(for: style, dynamicTypeSize: .accessibility3)
            XCTAssertGreaterThan(accessibilityFont.pointSize, largeFont.pointSize, "\(style) should scale at Accessibility 3")
        }
    }

    func testGradientBuilderUsesCSSAngleSemanticsAndExtendsStopsPastOneHundredPercent() {
        let diagonal = GradientTokens.layout(from: ExerciseGradient(token: .press, stops: ["#000000", "#FFFFFF"], angle: 135))
        XCTAssertEqual(diagonal.startPoint.x, 0, accuracy: 0.001)
        XCTAssertEqual(diagonal.startPoint.y, 0, accuracy: 0.001)
        XCTAssertEqual(diagonal.endPoint.x, 1, accuracy: 0.001)
        XCTAssertEqual(diagonal.endPoint.y, 1, accuracy: 0.001)

        let horizontal = GradientTokens.layout(from: ExerciseGradient(token: .curl, stops: ["#000000", "#FFFFFF"], angle: 90))
        XCTAssertEqual(horizontal.startPoint.x, 0, accuracy: 0.001)
        XCTAssertEqual(horizontal.startPoint.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(horizontal.endPoint.x, 1, accuracy: 0.001)
        XCTAssertEqual(horizontal.endPoint.y, 0.5, accuracy: 0.001)

        let extended = GradientTokens.layout(
            angle: 150,
            cssStops: ["#4A2BD8 0%", "#7C4DFF 50%", "#2FB8A0 130%"]
        )
        XCTAssertEqual(extended.extent, 1.3, accuracy: 0.001)
        XCTAssertLessThan(extended.startPoint.y, 0)
        XCTAssertGreaterThan(extended.endPoint.y, 1)
        let expectedLocations: [CGFloat] = [0, 50.0 / 130.0, 1]
        XCTAssertEqual(extended.stopLocations.count, expectedLocations.count)
        for (actual, expected) in zip(extended.stopLocations, expectedLocations) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
    }

    @MainActor
    func testComponentSnapshotFramesMatchDesignMetricsAndMaintainTouchTargets() throws {
        let standardButton = try render(PrimaryButton(title: "Start Exercise", icon: "play.fill", action: {}), id: "ds.primary")
        XCTAssertEqual(standardButton.height, 56, accuracy: 0.5)

        let stickyButton = try render(
            PrimaryButton(title: "Start Routine", icon: "play.fill", variant: .gradient, size: .sticky, action: {}),
            id: "ds.sticky"
        )
        XCTAssertEqual(stickyButton.height, 58, accuracy: 0.5)

        let capsuleButton = try render(CapsuleButton(title: "How to Do It", icon: "info.circle", action: {}), id: "ds.capsule")
        XCTAssertGreaterThanOrEqual(capsuleButton.height, 44)

        let filterChip = try render(
            FilterChip(title: "All", isSelected: true, action: {}),
            id: "ds.filter",
            visualAnchor: "component.filterChip.visual"
        )
        XCTAssertEqual(try XCTUnwrap(filterChip.visualHeight), 36, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(filterChip.height, 44)

        let statusChip = try render(StatusChip(title: "Listening · say “pause”", icon: "mic.fill", tint: ColorTokens.palette().success), id: "ds.status")
        XCTAssertEqual(statusChip.height, 24, accuracy: 0.5)

        let sectionHeader = try render(
            SectionHeader(title: "Quick Start", actionTitle: "All Exercises", action: {}),
            id: "ds.section",
            actionAnchor: "component.sectionHeader.action"
        )
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(sectionHeader.actionHeight), 44)

        let progressBar = try render(ProgressBar(progress: 0.5), id: "ds.progress")
        XCTAssertEqual(progressBar.height, 10, accuracy: 0.5)

        let emptyState = try render(EmptyStateTile(title: "No sets yet", message: "Save a routine to get started.", icon: "dumbbell.fill"), id: "ds.empty")
        XCTAssertGreaterThan(emptyState.height, 44)
    }

    private func visualState(_ primary: WorkoutVisualState.Primary) -> WorkoutVisualState {
        WorkoutVisualState(
            primary: primary,
            badges: [],
            activeTip: nil,
            restRemaining: nil,
            isRepFlashing: false,
            overlay: .none,
            showsCompletionCard: false,
            showsExerciseChooser: false
        )
    }

    @MainActor
    private func render(
        _ view: some View,
        id: String,
        visualAnchor: String? = nil,
        actionAnchor: String? = nil
    ) throws -> ComponentFrames {
        let result = try SnapshotHost.render(view.designAnchor("\(id).root"), frameId: id, testCase: self)
        func height(_ key: String?) -> CGFloat? {
            key.flatMap { result.anchors[$0]?.height }
        }
        return ComponentFrames(
            height: try XCTUnwrap(height("\(id).root"), "Missing layout anchor \(id).root"),
            visualHeight: height(visualAnchor),
            actionHeight: height(actionAnchor)
        )
    }

    private func assertRGBA(_ color: Color, hex: UInt32, alpha: CGFloat = 1, file: StaticString = #filePath, line: UInt = #line) {
        guard let components = rgbaComponents(of: color) else {
            XCTFail("Could not resolve color components", file: file, line: line)
            return
        }
        XCTAssertEqual(components.red, CGFloat((hex >> 16) & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.green, CGFloat((hex >> 8) & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.blue, CGFloat(hex & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.alpha, alpha, accuracy: 0.001, file: file, line: line)
    }

    private func assertRGBA(_ color: Color, matches other: Color, file: StaticString = #filePath, line: UInt = #line) {
        guard let first = rgbaComponents(of: color), let second = rgbaComponents(of: other) else {
            XCTFail("Could not resolve color components", file: file, line: line)
            return
        }
        XCTAssertEqual(first.red, second.red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(first.green, second.green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(first.blue, second.blue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(first.alpha, second.alpha, accuracy: 0.001, file: file, line: line)
    }

    private func rgbaComponents(of color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return (red, green, blue, alpha)
    }

    private func roundedWeight(of font: UIFont) -> CGFloat? {
        guard let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any] else { return nil }
        return (traits[.weight] as? NSNumber).map { CGFloat($0.doubleValue) }
    }
}

private struct ComponentFrames {
    let height: CGFloat
    let visualHeight: CGFloat?
    let actionHeight: CGFloat?
}
