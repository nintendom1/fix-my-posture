import SwiftUI

/// The guide's full figure, shown at its ideal position until it can be fitted to the user's body.
struct WorkoutGhostOverlayView: View {
    let liveOverlay: WorkoutOverlayState?
    let fitOverlay: WorkoutOverlayState?
    let metrics: GuideMetrics?
    let motion: ArmMotion
    var cameraView: ExerciseCameraView = .front

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glideStart: Date?
    @State private var lastFit: WorkoutOverlayState?

    static let ghostColor = Color(red: 0.76, green: 0.59, blue: 1)

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
            GeometryReader { geometry in
                let size = geometry.size
                let now = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    if reduceMotion {
                        figureLayer(sample: motion.topSample,
                                    size: size, now: now, opacity: 0.3)
                        figureLayer(sample: motion.startSample,
                                    size: size, now: now, opacity: 0.6)
                    } else {
                        let sample = motion.sample(at: now)
                        figureLayer(sample: sample,
                                    size: size, now: now, opacity: 0.6)
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .onChange(of: fitOverlay != nil) { oldValue, newValue in
            if oldValue != newValue {
                glideStart = Date()
            }
        }
        .onChange(of: fitOverlay, initial: true) { _, newValue in
            if let newValue {
                lastFit = newValue
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func figureLayer(sample: ArmMotionSample, size: CGSize,
                             now: TimeInterval, opacity: Double) -> some View {
        let figure = figure(sample: sample, size: size, now: now)
        let imageSize = liveOverlay?.imageSize ?? fitOverlay?.imageSize ?? WorkoutGhostGeometry.defaultImageSize
        if !figure.isEmpty, imageSize.width > 0, imageSize.height > 0 {
            let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: size)
            ZStack {
                AlignmentReferenceOverlayView(
                    referencePose: ReferencePose(jointLocations: imagePixelJoints(figure.joints,
                                                                                   imageSize: imageSize,
                                                                                   fit: fit)),
                    imageSize: imageSize,
                    containerSize: size,
                    style: .silhouette,
                    strokeColor: Self.ghostColor,
                    fillColor: Self.ghostColor.opacity(0.5),
                    proportionWidth: ExerciseDemoFigureView.canvasSize.width * figure.bodyScale
                )
                .opacity(opacity)

                Canvas { context, _ in
                    guard fit.width > 0, fit.height > 0 else { return }
                    var clipped = context
                    clipped.clip(to: Path(fit))
                    for dumbbell in figure.dumbbells {
                        DumbbellDrawing.draw(in: clipped,
                                             elbow: dumbbell.elbow,
                                             wrist: dumbbell.wrist,
                                             forearmLength: figure.forearmLength)
                    }
                }
                .opacity(opacity + 0.2)
            }
        }
    }

    private func figure(sample: ArmMotionSample, size: CGSize, now: TimeInterval)
        -> WorkoutGhostGeometry.Figure {
        let ideal = WorkoutGhostGeometry.ideal(overlay: liveOverlay, motion: motion, cameraView: cameraView,
                                               containerSize: size, sample: sample)
        let progress = WorkoutGhostGeometry.glideProgress(
            since: glideStart?.timeIntervalSinceReferenceDate,
            now: now,
            reduceMotion: reduceMotion
        )
        if let fitOverlay {
            guard let calibrated = WorkoutGhostGeometry.calibrated(fitOverlay: fitOverlay, metrics: metrics,
                                                                   motion: motion, cameraView: cameraView,
                                                                   containerSize: size, sample: sample) else {
                return ideal
            }
            return WorkoutGhostGeometry.blended(from: ideal, to: calibrated, progress: progress)
        }
        if progress < 1, let lastFit,
           let calibrated = WorkoutGhostGeometry.calibrated(fitOverlay: lastFit, metrics: metrics,
                                                            motion: motion, cameraView: cameraView,
                                                            containerSize: size, sample: sample) {
            return WorkoutGhostGeometry.blended(from: calibrated, to: ideal, progress: progress)
        }
        return ideal
    }

    private func imagePixelJoints(_ joints: [LandmarkType: CGPoint], imageSize: CGSize,
                                  fit: CGRect) -> [LandmarkType: CGPoint] {
        guard fit.width > 0, fit.height > 0 else { return [:] }
        return joints.mapValues { point in
            CGPoint(x: (point.x - fit.minX) * imageSize.width / fit.width,
                    y: (point.y - fit.minY) * imageSize.height / fit.height)
        }
    }
}
