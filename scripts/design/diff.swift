#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO

struct RectMask {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ object: [String: Any]) throws {
        guard let x = object["x"] as? Double,
              let y = object["y"] as? Double,
              let width = object["width"] as? Double,
              let height = object["height"] as? Double else {
            throw DiffError.invalid("Invalid mask rectangle: \(object)")
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    func contains(pixelX: Int, pixelY: Int, scale: Double) -> Bool {
        let x = Double(pixelX) / scale
        let y = Double(pixelY) / scale
        return x >= self.x && y >= self.y && x < self.x + width && y < self.y + height
    }
}

struct PixelImage {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    var pixelCount: Int { width * height }
}

struct Comparison {
    let comparedPixels: Int
    let mismatchedPixels: Int
    let heatmap: PixelImage

    var mismatchPercent: Double {
        guard comparedPixels > 0 else { return 0 }
        return Double(mismatchedPixels) / Double(comparedPixels) * 100
    }
}

enum DiffError: Error, CustomStringConvertible {
    case invalid(String)
    case image(String)

    var description: String {
        switch self {
        case .invalid(let message), .image(let message): return message
        }
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let referenceDir = root.appendingPathComponent("build/design/reference", isDirectory: true)
let actualDir = root.appendingPathComponent("build/design/actual", isDirectory: true)
let diffDir = root.appendingPathComponent("build/design/diff", isDirectory: true)
let masksURL = root.appendingPathComponent("scripts/design/masks.json")
let framesURL = root.appendingPathComponent("scripts/design/frames.json")
let metricsURL = root.appendingPathComponent("Design/Metrics/design-metrics.json")

func decodeObject(_ url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw DiffError.invalid("Expected a JSON object at \(url.path)")
    }
    return object
}

func loadImage(_ url: URL) throws -> PixelImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw DiffError.image("Could not decode PNG: \(url.path)")
    }
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
    bytes.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return PixelImage(width: width, height: height, bytes: bytes)
}

func makeCGImage(_ image: PixelImage) throws -> CGImage {
    let data = Data(image.bytes) as CFData
    guard let provider = CGDataProvider(data: data) else { throw DiffError.image("Could not allocate PNG provider.") }
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
    guard let result = CGImage(
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else { throw DiffError.image("Could not create CGImage.") }
    return result
}

func writePNG(_ image: PixelImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw DiffError.image("Could not write PNG: \(url.path)")
    }
    CGImageDestinationAddImage(destination, try makeCGImage(image), nil)
    guard CGImageDestinationFinalize(destination) else { throw DiffError.image("Could not finish PNG: \(url.path)") }
}

func compare(_ reference: PixelImage, _ actual: PixelImage, masks: [RectMask], scale: Double, tolerance: UInt8) throws -> Comparison {
    guard reference.width == actual.width && reference.height == actual.height else {
        throw DiffError.image("Image sizes differ: \(reference.width)×\(reference.height) and \(actual.width)×\(actual.height).")
    }
    var heat = [UInt8](repeating: 0, count: reference.bytes.count)
    var compared = 0
    var mismatched = 0
    for y in 0..<reference.height {
        for x in 0..<reference.width {
            let offset = (y * reference.width + x) * 4
            if masks.contains(where: { $0.contains(pixelX: x, pixelY: y, scale: scale) }) {
                heat[offset + 3] = 0
                continue
            }
            compared += 1
            let channelDiffs = (0..<3).map { abs(Int(reference.bytes[offset + $0]) - Int(actual.bytes[offset + $0])) }
            let difference = channelDiffs.max() ?? 0
            if difference > Int(tolerance) {
                mismatched += 1
                heat[offset] = UInt8(min(255, max(48, difference * 4)))
                heat[offset + 1] = 0
                heat[offset + 2] = 0
                heat[offset + 3] = 255
            } else {
                let luminance = UInt8((Int(reference.bytes[offset]) + Int(reference.bytes[offset + 1]) + Int(reference.bytes[offset + 2])) / 12)
                heat[offset] = luminance
                heat[offset + 1] = luminance
                heat[offset + 2] = luminance
                heat[offset + 3] = 255
            }
        }
    }
    return Comparison(comparedPixels: compared, mismatchedPixels: mismatched,
                      heatmap: PixelImage(width: reference.width, height: reference.height, bytes: heat))
}

func sideBySide(_ left: PixelImage, _ right: PixelImage) -> PixelImage {
    var bytes = [UInt8](repeating: 0, count: left.width * 2 * left.height * 4)
    for y in 0..<left.height {
        let leftStart = y * left.width * 4
        let outputStart = y * left.width * 2 * 4
        bytes.replaceSubrange(outputStart..<(outputStart + left.width * 4), with: left.bytes[leftStart..<(leftStart + left.width * 4)])
        bytes.replaceSubrange((outputStart + left.width * 4)..<(outputStart + left.width * 8), with: right.bytes[leftStart..<(leftStart + left.width * 4)])
    }
    return PixelImage(width: left.width * 2, height: left.height, bytes: bytes)
}

func rectangles(_ values: [Any]?) throws -> [RectMask] {
    try (values ?? []).map { value in
        guard let object = value as? [String: Any] else { throw DiffError.invalid("Mask item must be an object.") }
        return try RectMask(object)
    }
}

func masksFor(frameID: String, config: [String: Any], metrics: [String: Any], scale: Double) throws -> [RectMask] {
    var result = try rectangles(config["defaults"] as? [Any])
    let tabbed = Set(config["tabbedFrames"] as? [String] ?? [])
    let cameras = Set(config["cameraFrames"] as? [String] ?? [])
    if cameras.contains(frameID), let preview = config["cameraPreview"] as? [String: Any] {
        result.append(try RectMask(preview))
    }
    let anchorMasks = config["anchorMasks"] as? [String: [String]] ?? [:]
    let frameMetrics = metrics["frames"] as? [String: Any] ?? [:]
    let anchors = ((frameMetrics[frameID] as? [String: Any])?["anchors"] as? [String: Any]) ?? [:]
    if tabbed.contains(frameID) {
        let name = config["tabBarAnchor"] as? String ?? "tabbar"
        if let tab = anchors[name] as? [String: Any] {
            result.append(try RectMask(tab))
        } else if let fallback = config["tabBar"] as? [String: Any] {
            result.append(try RectMask(fallback))
        }
    }
    for name in anchorMasks[frameID] ?? [] {
        guard let box = anchors[name] as? [String: Any] else { continue }
        result.append(try RectMask(box))
    }
    return result
}

func selfTest() throws {
    let width = 16
    let height = 16
    var base = [UInt8](repeating: 0, count: width * height * 4)
    for index in 0..<(width * height) { base[index * 4 + 3] = 255 }
    let identical = try compare(PixelImage(width: width, height: height, bytes: base),
                                PixelImage(width: width, height: height, bytes: base), masks: [], scale: 1, tolerance: 0)
    guard identical.mismatchedPixels == 0 else { throw DiffError.invalid("Self-test failed: identical images differed.") }
    var shifted = base
    shifted[(5 * width + 5) * 4] = 255
    shifted[(5 * width + 5) * 4 + 3] = 255
    let changed = try compare(PixelImage(width: width, height: height, bytes: base),
                              PixelImage(width: width, height: height, bytes: shifted), masks: [], scale: 1, tolerance: 0)
    guard changed.mismatchedPixels == 1 else { throw DiffError.invalid("Self-test failed: shifted image was not detected.") }
    print("Pixel diff self-test passed (identical: 0 mismatches; shifted: 1 mismatch).")
}

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.contains("--self-test") { try selfTest(); return }
    var tolerance = 0
    for index in arguments.indices where arguments[index] == "--tolerance" || arguments[index] == "--channel-tolerance" {
        guard arguments.indices.contains(index + 1), let value = Int(arguments[index + 1]), value >= 0, value <= 255 else {
            throw DiffError.invalid("--tolerance requires an integer from 0 to 255.")
        }
        tolerance = value
    }

    let config = try decodeObject(masksURL)
    let metrics = try decodeObject(metricsURL)
    let frameListData = try Data(contentsOf: framesURL)
    guard let frameList = try JSONSerialization.jsonObject(with: frameListData) as? [[String: Any]] else {
        throw DiffError.invalid("Frame list must be a JSON array.")
    }
    let scale = config["scale"] as? Double ?? 3
    var results: [String: Any] = [:]
    var skipped: [String] = []
    for frame in frameList {
        guard let frameID = frame["id"] as? String else { continue }
        let referenceURL = referenceDir.appendingPathComponent("\(frameID).png")
        let actualURL = actualDir.appendingPathComponent("\(frameID).png")
        guard FileManager.default.fileExists(atPath: referenceURL.path),
              FileManager.default.fileExists(atPath: actualURL.path) else {
            skipped.append(frameID)
            continue
        }
        let reference = try loadImage(referenceURL)
        let actual = try loadImage(actualURL)
        let masks = try masksFor(frameID: frameID, config: config, metrics: metrics, scale: scale)
        let result = try compare(reference, actual, masks: masks, scale: scale, tolerance: UInt8(tolerance))
        try writePNG(result.heatmap, to: diffDir.appendingPathComponent("\(frameID)-heatmap.png"))
        try writePNG(sideBySide(reference, actual), to: diffDir.appendingPathComponent("\(frameID)-side-by-side.png"))
        results[frameID] = [
            "mismatchPercent": (result.mismatchPercent * 1000).rounded() / 1000,
            "comparedPixels": result.comparedPixels,
            "mismatchedPixels": result.mismatchedPixels,
            "channelTolerance": tolerance,
        ]
        print(String(format: "%@: %.3f%% mismatch (%d / %d pixels)", frameID, result.mismatchPercent, result.mismatchedPixels, result.comparedPixels))
    }
    let summary: [String: Any] = [
        "version": 1,
        "channelTolerance": tolerance,
        "frames": results,
        "skipped": skipped,
    ]
    try FileManager.default.createDirectory(at: diffDir, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: diffDir.appendingPathComponent("summary.json"), options: .atomic)
    if !skipped.isEmpty { print("Skipped without both PNGs: \(skipped.joined(separator: ", "))") }
    print("Wrote diff review files to \(diffDir.path).")
}

do {
    try run()
} catch {
    fputs("design diff: \(error)\n", stderr)
    exit(1)
}
