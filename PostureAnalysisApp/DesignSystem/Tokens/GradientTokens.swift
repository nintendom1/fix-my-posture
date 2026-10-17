import SwiftUI

struct GradientLayout: Equatable {
    let startPoint: CGPoint
    let endPoint: CGPoint
    /// The CSS gradient line's length relative to its normal 100% length.
    let extent: CGFloat
    let stopLocations: [CGFloat]
}

private struct GradientColorStop {
    let color: Color
    let location: CGFloat?
}

enum GradientTokens {
    static let trainHero = linearGradient(
        angle: 135,
        cssStops: ["#6a3df0 0%", "#a64be0 55%", "#ff7f9e 100%"]
    )
    static let workoutActive = linearGradient(
        angle: 135,
        cssStops: ["#7c4dff 0%", "#c04bd8 100%"]
    )
    static let workoutAttention = linearGradient(
        angle: 135,
        cssStops: ["#ff9f43 0%", "#ffc46b 100%"]
    )
    static let workoutLost = linearGradient(
        angle: 135,
        cssStops: ["#ff5a6e 0%", "#ff9a8a 100%"]
    )
    static let progress = linearGradient(
        angle: 150,
        cssStops: ["#4a2bd8 0%", "#7c4dff 50%", "#2fb8a0 130%"]
    )
    static let posture = linearGradient(
        angle: 150,
        cssStops: ["#3b4fd8 0%", "#6a6cf0 55%", "#56b8d8 120%"]
    )
    static let success = linearGradient(
        angle: 135,
        cssStops: ["#22c38e 0%", "#7be0b4 100%"]
    )
    static let rest = linearGradient(
        angle: 135,
        cssStops: ["#3a8dff 0%", "#6fd6ff 100%"]
    )

    static func linearGradient(from exercise: ExerciseGradient) -> LinearGradient {
        linearGradient(angle: exercise.angle, cssStops: exercise.stops)
    }

    static func linearGradient(angle: Double, cssStops: [String]) -> LinearGradient {
        let parsedStops = parse(cssStops)
        let layout = layout(angle: angle, stops: parsedStops)
        let stops = zip(parsedStops, layout.stopLocations).map { stop, location in
            Gradient.Stop(color: stop.color, location: location)
        }
        return LinearGradient(
            stops: stops,
            startPoint: UnitPoint(x: layout.startPoint.x, y: layout.startPoint.y),
            endPoint: UnitPoint(x: layout.endPoint.x, y: layout.endPoint.y)
        )
    }

    static func layout(from exercise: ExerciseGradient) -> GradientLayout {
        layout(angle: exercise.angle, stops: parse(exercise.stops))
    }

    static func layout(angle: Double, cssStops: [String]) -> GradientLayout {
        layout(angle: angle, stops: parse(cssStops))
    }

    private static func layout(angle: Double, stops: [GradientColorStop]) -> GradientLayout {
        let positioned = positions(for: stops)
        let lastStop = positioned.last?.location ?? 1
        let extent = max(1, lastStop)
        let angleInRadians = angle * .pi / 180
        let directionX = sin(angleInRadians)
        let directionY = -cos(angleInRadians)
        let normalizer = max(max(abs(directionX), abs(directionY)), 0.000001)
        let halfX = directionX / normalizer * 0.5 * extent
        let halfY = directionY / normalizer * 0.5 * extent

        return GradientLayout(
            startPoint: CGPoint(x: 0.5 - halfX, y: 0.5 - halfY),
            endPoint: CGPoint(x: 0.5 + halfX, y: 0.5 + halfY),
            extent: extent,
            stopLocations: positioned.map { ($0.location ?? 0) / extent }
        )
    }

    private static func parse(_ cssStops: [String]) -> [GradientColorStop] {
        guard !cssStops.isEmpty else {
            return [GradientColorStop(color: Color.black, location: 0),
                    GradientColorStop(color: Color.white, location: 1)]
        }

        return cssStops.enumerated().map { index, stop in
            let pieces = stop.split(whereSeparator: \.isWhitespace)
            let locationText = pieces.last.map(String.init)
            let explicitLocation: CGFloat?
            if let locationText, locationText.hasSuffix("%"),
               let percentage = Double(locationText.dropLast()) {
                explicitLocation = CGFloat(max(0, percentage / 100))
            } else {
                explicitLocation = nil
            }

            let colorText: String
            if explicitLocation != nil {
                colorText = pieces.dropLast().joined(separator: " ")
            } else {
                colorText = stop
            }
            let color = Color(hex: colorText) ?? .clear
            let defaultLocation = cssStops.count == 1 ? 0 : CGFloat(index) / CGFloat(cssStops.count - 1)
            return GradientColorStop(color: color, location: explicitLocation ?? defaultLocation)
        }
    }

    private static func positions(for stops: [GradientColorStop]) -> [GradientColorStop] {
        guard stops.count > 1 else {
            return stops.enumerated().map { index, stop in
                GradientColorStop(color: stop.color, location: stop.location ?? CGFloat(index))
            }
        }

        var locations = stops.map(\.location)
        if locations.first == nil { locations[0] = 0 }
        if locations[locations.count - 1] == nil { locations[locations.count - 1] = 1 }

        var index = 0
        while index < locations.count - 1 {
            guard let lower = locations[index] else {
                index += 1
                continue
            }
            var next = index + 1
            while next < locations.count, locations[next] == nil { next += 1 }
            guard next < locations.count, let upper = locations[next] else { break }
            let steps = CGFloat(next - index)
            if next > index + 1 {
                for missing in (index + 1)..<next {
                    locations[missing] = lower + (upper - lower) * CGFloat(missing - index) / steps
                }
            }
            index = next
        }

        let concreteLocations = locations.enumerated().map { index, location in
            location ?? CGFloat(index) / CGFloat(locations.count - 1)
        }
        return zip(stops, concreteLocations).map { stop, location in
            GradientColorStop(color: stop.color, location: location)
        }
    }
}
