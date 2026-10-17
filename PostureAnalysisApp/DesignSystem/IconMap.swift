import SwiftUI

enum IconMap {
    /// Material Symbols names from the design bundle mapped to iOS 17 SF Symbols.
    static let materialToSFSymbol: [String: String] = [
        "accessibility_new": "figure.stand",
        "add": "plus",
        "add_circle": "plus.circle.fill",
        "arrow_downward": "arrow.down",
        "arrow_upward": "arrow.up",
        "battery_full": "battery.100percent",
        "check": "checkmark",
        "check_circle": "checkmark.circle.fill",
        "chevron_left": "chevron.left",
        "chevron_right": "chevron.right",
        "close": "xmark",
        "code": "chevron.left.forwardslash.chevron.right",
        "content_copy": "doc.on.doc",
        "delete": "trash",
        "description": "doc.text.fill",
        "drag_indicator": "circle.grid.2x2.fill",
        "edit": "pencil",
        "expand_less": "chevron.up",
        "favorite": "heart.fill",
        "fitness_center": "dumbbell.fill",
        "format_list_numbered": "list.number",
        "graphic_eq": "waveform",
        "help": "questionmark.circle.fill",
        "info": "info.circle.fill",
        "ios_share": "square.and.arrow.up",
        "lock": "lock.fill",
        "menu_book": "book.closed.fill",
        "mic": "mic.fill",
        "mic_off": "mic.slash.fill",
        "monitoring": "chart.xyaxis.line",
        "more_horiz": "ellipsis",
        "notifications": "bell.fill",
        "pause": "pause.fill",
        "pause_circle": "pause.circle.fill",
        "photo_camera": "camera.fill",
        "photo_camera_front": "camera.rotate",
        "photo_library": "photo.stack.fill",
        "play_arrow": "play.fill",
        "play_circle": "play.circle.fill",
        "record_voice_over": "person.wave.2.fill",
        "remove": "minus",
        "restart_alt": "arrow.counterclockwise",
        "scale": "scalemass.fill",
        "screen_rotation": "rotate.right",
        "search": "magnifyingglass",
        "self_improvement": "figure.mind.and.body",
        "settings": "gearshape.fill",
        "signal_cellular_alt": "antenna.radiowaves.left.and.right",
        "skip_next": "forward.end.fill",
        "straighten": "ruler",
        "swap_horiz": "arrow.left.arrow.right",
        "timer": "timer",
        "tips_and_updates": "lightbulb.max.fill",
        "tune": "slider.horizontal.3",
        "videocam": "video.fill",
        "visibility": "eye.fill",
        "visibility_off": "eye.slash.fill",
        "volume_off": "speaker.slash.fill",
        "volume_up": "speaker.wave.2.fill",
        "wifi": "wifi"
    ]

    /// No duplicate assignments are needed by the current design icon list.
    static let duplicateAllowlist: [String: String] = [:]

    static func symbol(for materialName: String) -> String? {
        materialToSFSymbol[materialName]
    }
}

extension Image {
    init(material name: String) {
        self.init(systemName: IconMap.symbol(for: name) ?? "questionmark")
    }
}
