pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// Lounge — the affluent pole's answer to the telemetry cluster, living in
// the same slot: as the register slides toward the villa, the machine
// readouts fade out and the now-playing line fades in. Cormorant lowercase,
// a small accent note, nothing else — hotel-bar energy.
RowLayout {
    id: root

    readonly property real reveal: (1.0 - Config.register) * (MprisService.isPlaying ? 1 : 0)

    visible: reveal > 0.02
    opacity: reveal
    spacing: 6

    Behavior on opacity {
        NumberAnimation {
            duration: Config.animDuration
        }
    }

    Text {
        text: "♪"
        color: Config.accentColor
        font.pixelSize: Config.fontSizeSmall
    }

    Text {
        text: {
            const t = MprisService.title;
            const a = MprisService.artist;
            if (t === "" || t === "Unknown")
                return "";
            return a !== "" && a !== "Unknown" ? t + " — " + a : t;
        }
        visible: text !== ""
        color: Config.subtextColor
        font.family: "Cormorant Garamond"
        font.pixelSize: Config.fontSizeNormal
        font.italic: true
        elide: Text.ElideRight
        Layout.maximumWidth: 320
    }
}
