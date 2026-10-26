import Foundation

/// Reads a recording one record at a time, without loading the whole file.
enum WorkoutRecordingFile {
    /// Calls `body` with each record as a JSON object's text: the array's brackets and the commas between records
    /// are left out. A last line cut short by a crash is skipped. Older JSON Lines recordings read the same way.
    static func forEachLine(in url: URL, _ body: (String) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        func emit(_ data: Data, isLast: Bool) {
            guard let record = record(String(decoding: data, as: UTF8.self)) else { return }
            // An unterminated last line is used only when it is a whole record.
            if isLast, object(record) == nil { return }
            body(record)
        }
        var pending = Data()
        while let chunk = try? handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                emit(pending[pending.startIndex..<newline], isLast: false)
                pending.removeSubrange(pending.startIndex...newline)
            }
        }
        if !pending.isEmpty { emit(pending, isLast: true) }
    }

    /// One line's record, without the array's brackets or the separating comma; nil for a line with none.
    static func record(_ line: String) -> String? {
        var text = Substring(line).trimmingCharacters(in: .whitespacesAndNewlines)[...]
        if text.hasPrefix(",") { text = text.dropFirst() }
        if text.hasSuffix(",") { text = text.dropLast() }
        guard text.hasPrefix("{") else { return nil }
        return String(text)
    }

    static func object(_ line: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }

    static let framePrefix = "{\"k\":\"f\",\"t\":"

    /// A frame line's recording time, read without parsing the rest of the line.
    static func frameTime(_ line: String) -> TimeInterval? {
        guard line.hasPrefix(framePrefix) else { return nil }
        let rest = line.dropFirst(framePrefix.count)
        return Double(rest.prefix { $0 != "," })
    }
}

/// A compact plain-text report of one recording, sized to paste into a chat: each exercise's tuning, the event
/// timeline, every tracking loss with the joints around it, and the frames around each marker, at 5 Hz.
/// Only frames inside those windows are parsed, so even an hour-long recording reports quickly.
enum WorkoutRecordingReport {
    struct Options {
        /// Frames per second shown in each window.
        var rate: Double = 5
        var lossBefore: TimeInterval = 1
        var lossAfter: TimeInterval = 1
        /// A long loss shows only its start and end, up to this long.
        var lossMaximum: TimeInterval = 3
        var markerBefore: TimeInterval = 8
        var markerAfter: TimeInterval = 2
        var maximumWindows = 12
        var maximumEvents = 250
    }

    private struct Window {
        var start: TimeInterval
        var end: TimeInterval
        var title: String
        var rows: [String] = []
        var lastRowTime: TimeInterval = -.infinity
        var lastReliable: Bool?
    }

    static func make(fileURL: URL, title: String, timeZone: TimeZone = .current, options: Options = Options()) -> String {
        var header: [String: Any] = [:]
        var events: [String] = []
        var droppedEvents = 0
        var losses: [(start: TimeInterval, guidance: String?, end: TimeInterval?)] = []
        var markers: [(id: String, time: TimeInterval, source: String, text: String?)] = []
        var notes: [String: String] = [:]
        var exerciseSegments: [(time: TimeInterval, id: String)] = []
        var end: [String: Any]?
        var frameCount = 0
        var lastTime: TimeInterval = 0
        var reliable = false
        var lastPhase: String?
        var lastReps: Int?

        func add(_ time: TimeInterval, _ text: String) {
            guard events.count < options.maximumEvents else {
                droppedEvents += 1
                return
            }
            events.append("\(clock(time))  \(text)")
        }

        // Pass 1: everything except frames.
        WorkoutRecordingFile.forEachLine(in: fileURL) { line in
            if let time = WorkoutRecordingFile.frameTime(line) {
                frameCount += 1
                lastTime = max(lastTime, time)
                return
            }
            guard let object = WorkoutRecordingFile.object(line), let kind = object["k"] as? String else { return }
            let time = object["t"] as? Double ?? 0
            lastTime = max(lastTime, time)
            switch kind {
            case "header":
                header = object
            case "pipe":
                if object["control"] as? String == "exercise", let id = object["exercise"] as? String {
                    if exerciseSegments.last?.id != id { exerciseSegments.append((time, id)) }
                }
            case "state":
                if let phase = object["phase"] as? String, phase != lastPhase {
                    if lastPhase != nil { add(time, "phase \(phase)") }
                    lastPhase = phase
                }
                if let reps = object["reps"] as? Int, reps != lastReps {
                    if lastReps != nil { add(time, "reps \(reps)") }
                    lastReps = reps
                }
            case "e":
                guard let type = object["type"] as? String else { return }
                if type == "framing", let framing = object["framing"] as? [String: Any] {
                    let ok = framing["ok"] as? Bool ?? false
                    let guidance = framing["g"] as? String
                    guard ok != reliable else { return }
                    reliable = ok
                    if ok {
                        add(time, losses.isEmpty ? "tracking reliable" : "tracking back")
                        if let index = losses.indices.last, losses[index].end == nil { losses[index].end = time }
                    } else {
                        add(time, "TRACKING LOST" + (guidance.map { " (\($0))" } ?? ""))
                        losses.append((time, guidance, nil))
                    }
                } else if let text = eventText(type, object) {
                    add(time, text)
                }
            case "marker":
                let id = object["id"] as? String ?? UUID().uuidString
                let heard = object["heardAt"] as? Double ?? time
                markers.append((id, heard, object["source"] as? String ?? "?", object["text"] as? String))
                add(heard, "MARKER (\(object["source"] as? String ?? "?"))" + ((object["text"] as? String).map { " “\($0)”" } ?? ""))
            case "note":
                if let markerID = object["markerID"] as? String, let text = object["text"] as? String { notes[markerID] = text }
            case "end":
                end = object
            default:
                break
            }
        }

        // Windows around tracking losses and markers, merged where they overlap.
        var windows: [Window] = losses.map { loss in
            let back = loss.end.map { "back at \(clock($0)), \(String(format: "%.1f", $0 - loss.start)) s" } ?? "not regained"
            let regained = min(loss.end ?? lastTime, loss.start + options.lossMaximum)
            return Window(start: loss.start - options.lossBefore, end: regained + options.lossAfter,
                          title: "Tracking lost at \(clock(loss.start))" + (loss.guidance.map { " (\($0))" } ?? "") + ", \(back)")
        }
        windows += markers.map { marker in
            let note = notes[marker.id] ?? marker.text
            return Window(start: marker.time - options.markerBefore, end: marker.time + options.markerAfter,
                          title: "Marker at \(clock(marker.time)) (\(marker.source))" + (note.map { ": “\($0)”" } ?? ""))
        }
        windows.sort { $0.start < $1.start }
        var merged: [Window] = []
        for window in windows {
            if let last = merged.last, window.start <= last.end {
                merged[merged.count - 1].end = max(last.end, window.end)
                merged[merged.count - 1].title += "; " + window.title.prefix(1).lowercased() + window.title.dropFirst()
            } else {
                merged.append(window)
            }
        }
        let omittedWindows = max(0, merged.count - options.maximumWindows)
        merged = Array(merged.prefix(options.maximumWindows))

        // Pass 2: only the frames inside a window.
        let jointOrder = header["jointOrder"] as? [String] ?? []
        let exercises = header["exercises"] as? [String: [String: Any]] ?? [:]
        func exercise(at time: TimeInterval) -> String? {
            exerciseSegments.last { $0.time <= time }?.id ?? exerciseSegments.first?.id
        }
        func focus(for exerciseID: String?) -> [String] {
            let focus = Set((exerciseID.flatMap { exercises[$0]?["focus"] } as? [String]) ?? [])
            return jointOrder.filter { focus.contains($0) }
        }
        if !merged.isEmpty {
            var index = 0
            WorkoutRecordingFile.forEachLine(in: fileURL) { line in
                guard let time = WorkoutRecordingFile.frameTime(line) else { return }
                while index < merged.count, time > merged[index].end { index += 1 }
                guard index < merged.count, time >= merged[index].start,
                      let frame = WorkoutRecordingFile.object(line) else { return }
                let ok = (frame["fr"] as? [String: Any])?["ok"] as? Bool
                let changed = ok != nil && ok != merged[index].lastReliable
                let hasEvent = !((frame["out"] as? [Any]) ?? []).isEmpty
                guard changed || hasEvent || time >= merged[index].lastRowTime + 1 / options.rate - 0.02 else { return }
                if ok != nil { merged[index].lastReliable = ok }
                merged[index].lastRowTime = time
                if merged[index].rows.isEmpty {
                    merged[index].rows.append(columnHeader(focus(for: exercise(at: time))))
                }
                merged[index].rows.append(row(frame, time: time, joints: focus(for: exercise(at: time)), order: jointOrder))
            }
        }

        // Assemble.
        var lines: [String] = []
        let started = (header["startedAt"] as? String).flatMap(Self.date)
        var facts = [title]
        if let started { facts.append(Self.dateLabel(started, timeZone: timeZone)) }
        facts.append(clock(lastTime, tenths: false))
        let frames = end?["frames"] as? Int ?? frameCount
        let gaps = end?["seqGaps"] as? Int ?? 0
        facts.append("\(frames) frames" + (gaps > 0 ? " (\(gaps) more never reached the coach)" : ""))
        facts.append(end == nil ? "incomplete" : "ended: \(end?["reason"] as? String ?? "?")")
        lines.append("FMP workout report · " + facts.joined(separator: " · "))
        lines.append("Recording \(header["id"] as? String ?? "?"); the full file comes over with `make diagnostics`.")
        let framing = header["framing"] as? [String: Any] ?? [:]
        let size = ((header["camera"] as? [String: Any])?["analysisHz"] as? Int).map { "\($0) Hz" } ?? "10 Hz"
        lines.append("Joints: unmirrored image pixels, origin top-left, analyzed at \(size). Cells are confidence then x,y. "
            + "Framing needs required joints at ≥\(number(framing["minimumConfidence"] ?? 0.4)) for "
            + "\(number(framing["reliableAfter"] ?? 0.6)) s and drops after \(number(framing["unreliableAfter"] ?? 0.3)) s "
            + "missing; \"lo\" is a joint under the \(number(header["confidenceFloor"] ?? 0.3)) floor, \"--\" is not seen, "
            + "\"est\" is estimated past the frame edge.")
        for id in Self.unique(exerciseSegments.map(\.id)) {
            guard let definition = exercises[id] else { continue }
            let required = (definition["required"] as? [String] ?? []).map(Self.short).joined(separator: " ")
            let anyOf = (definition["anyOfRequired"] as? [[String]] ?? []).map { $0.map(Self.short).joined(separator: " ") }
            var line = "Exercise \(id) (\(definition["cameraView"] as? String ?? "?")): required \(required.isEmpty ? "none" : required)"
            if !anyOf.isEmpty { line += "; or all of one of [\(anyOf.joined(separator: "] ["))]" }
            lines.append(line)
            if let configuration = definition["configuration"] as? [String: Any] {
                lines.append("  tuning: " + configuration.keys.sorted().map { "\($0)=\(number(configuration[$0] ?? ""))" }
                    .joined(separator: " "))
            }
        }

        lines.append("")
        lines.append("Timeline (\(events.count) events)")
        lines += events.map { "  " + $0 }
        if droppedEvents > 0 { lines.append("  … \(droppedEvents) more events not shown") }

        for window in merged {
            lines.append("")
            lines.append(window.title)
            lines += window.rows.isEmpty ? ["  (no frames)"] : window.rows.map { "  " + $0 }
        }
        if omittedWindows > 0 {
            lines.append("")
            lines.append("… \(omittedWindows) more tracking losses or markers not shown")
        }
        if losses.isEmpty && markers.isEmpty {
            lines.append("")
            lines.append("No tracking losses or markers.")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Pieces

    private static func eventText(_ type: String, _ object: [String: Any]) -> String? {
        switch type {
        case "opened": return "camera opened"
        case "command":
            let command = object["command"] as? String ?? "?"
            let source = object["source"] as? String ?? "?"
            return "command \(command) (\(source)" + ((object["phrase"] as? String).map { ": “\($0)”" } ?? "") + ")"
        case "rep":
            return "rep event, sides " + ((object["sides"] as? [String]) ?? []).joined(separator: "+")
        case "tilt": return (object["tilted"] as? Bool ?? false) ? "phone tilted" : "phone upright"
        case "tip":
            return "tip \(object["cue"] as? String ?? "?")" + ((object["text"] as? String).map { " “\($0)”" } ?? "")
        case "speak":
            let text = object["text"] as? String ?? ""
            return "says" + ((object["muted"] as? Bool ?? false) ? " (muted)" : "") + " “\(text)”"
        case "camera.running", "camera.interrupted", "app.background", "app.foreground",
             "interruptionBegan", "interruptionEnded", "audio.interruptionBegan", "audio.interruptionEnded":
            return type
        case "camera.failed": return "camera failed: \(object["message"] as? String ?? "")"
        case "ui.guide": return (object["shown"] as? Bool ?? false) ? "guide opened" : "guide closed"
        case "ui.help": return (object["shown"] as? Bool ?? false) ? "voice help opened" : "voice help closed"
        case "voiceControl": return (object["active"] as? Bool ?? false) ? "voice control on" : "voice control off"
        default:
            // Start-position flips, tip clears, and the like are too frequent to help here.
            return nil
        }
    }

    private static func columnHeader(_ joints: [String]) -> String {
        let cells = joints.map { pad(short($0)) }
        return "t       frm cnt | " + cells.joined(separator: " | ") + " | readings"
    }

    private static func row(_ frame: [String: Any], time: TimeInterval, joints: [String], order: [String]) -> String {
        let positions = frame["j"] as? [Any] ?? []
        let low = (frame["lo"] as? [[Double]] ?? []).reduce(into: [Int: Double]()) { $0[Int($1[0])] = $1.count > 3 ? $1[3] : 0 }
        let estimated = (frame["est"] as? [[Double]] ?? []).reduce(into: [Int: [Double]]()) { $0[Int($1[0])] = $1 }
        let cells = joints.map { name -> String in
            guard let index = order.firstIndex(of: name) else { return "?" }
            let cell: String
            if let estimate = estimated[index], estimate.count > 2 {
                cell = "est \(Int(estimate[1].rounded())),\(Int(estimate[2].rounded()))"
            } else if index < positions.count, let joint = positions[index] as? [Double], joint.count > 2 {
                cell = "\(confidence(joint[2])) \(Int(joint[0].rounded())),\(Int(joint[1].rounded()))"
            } else if let confidence = low[index] {
                cell = "lo" + Self.confidence(confidence)
            } else {
                cell = "--"
            }
            return pad(cell)
        }
        let framing = frame["fr"] as? [String: Any]
        let ok = framing.map { ($0["ok"] as? Bool ?? false) ? "ok " : "LOST" } ?? "    "
        let counting = (frame["cnt"] as? Bool ?? false) ? "on " : "off"
        var readings: [String] = []
        for (side, value) in (frame["rd"] as? [String: [String: Any]] ?? [:]).sorted(by: { $0.key < $1.key }) {
            let signal = value["signal"] as? Double ?? .nan
            let elbow = value["elbow"] as? Double ?? .nan
            readings.append("\(side.prefix(1).uppercased()) \(String(format: "%+.2f", signal)) \(Int(elbow.rounded()))° "
                + "\(((value["zone"] as? String) ?? "?").prefix(3))")
        }
        if let guidance = framing?["g"] as? String { readings.append("g:\(guidance)") }
        for event in frame["out"] as? [[String: Any]] ?? [] {
            if event["rep"] != nil { readings.append("REP") }
        }
        return String(format: "%6.2f", time) + "  \(ok) \(counting) | " + cells.joined(separator: " | ")
            + " | " + readings.joined(separator: "  ")
    }

    /// Pads a cell to a common width without ever cutting it short.
    private static func pad(_ cell: String, width: Int = 11) -> String {
        cell.count >= width ? cell : cell + String(repeating: " ", count: width - cell.count)
    }

    /// "LS" for left shoulder, "RW" for right wrist, and so on.
    static func short(_ joint: String) -> String {
        let names = ["nose": "Nose", "neck": "Neck", "root": "Root", "leftEye": "LEye", "rightEye": "REye",
                     "leftEar": "LEar", "rightEar": "REar"]
        if let name = names[joint] { return name }
        let side = joint.hasPrefix("left") ? "L" : joint.hasPrefix("right") ? "R" : ""
        let part = joint.replacingOccurrences(of: "left", with: "").replacingOccurrences(of: "right", with: "")
        return side + String(part.prefix(1))
    }

    private static func confidence(_ value: Double) -> String {
        let text = String(format: "%.2f", value)
        return text.hasPrefix("0") ? String(text.dropFirst()) : text
    }

    private static func number(_ value: Any) -> String {
        if let value = value as? Double {
            return value == value.rounded() && abs(value) < 1e9 ? String(Int(value)) : String(format: "%g", value)
        }
        return "\(value)"
    }

    /// "0:13.3", or "0:58" without tenths.
    static func clock(_ seconds: TimeInterval, tenths: Bool = true) -> String {
        let total = max(0, seconds)
        let minutes = Int(total / 60)
        let rest = total - Double(minutes * 60)
        return tenths ? "\(minutes):" + String(format: "%04.1f", rest) : "\(minutes):" + String(format: "%02d", Int(rest))
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func dateLabel(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
