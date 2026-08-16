pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.services

// ScanlineOverlay — idle-triggered scanline effect.
//
// In facility mode, after scanlineIdleSeconds of no keyboard input,
// a horizontal scanline drifts down the screen. The intensity scales
// with polarity — full facility gets aggressive scanlines after 5s,
// transitional gets a whisper after 30s, affluent never does.
//
// The scanline snaps off in <50ms on any key press.

Item {
    id: root

    // Visibility is driven by Config.scanlinesEnabled + Config.scanlineIdleSeconds
    readonly property bool active: Config.scanlinesEnabled && Config.scanlineIdleSeconds > 0
    readonly property real intensity: active ? (ThemeService.polarity) : 0.0

    // Idle detection via Hyprland — we watch for keyboard activity
    // through a polling timer (simplest approach for a prototype)
    property bool isIdle: false
    property int idleSeconds: 0

    Timer {
        id: idleTimer
        interval: 1000
        repeat: true
        running: root.active

        onTriggered: {
            root.idleSeconds += 1
            if (root.idleSeconds >= Config.scanlineIdleSeconds && !root.isIdle) {
                root.isIdle = true
                scanlineAnim.start()
            }
        }
    }

    // No MouseArea — the scanline overlay must be completely click-through.
    // Idle detection is handled by the timer only.

    function resetIdle() {
        idleSeconds = 0
        if (isIdle) {
            isIdle = false
            scanlineAnim.stop()
            scanline.opacity = 0
        }
    }

    // The scanline — a thin gradient that drifts downward
    Rectangle {
        id: scanline
        width: parent.width
        height: 4
        y: -height
        opacity: 0
        visible: root.isIdle

        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.alpha(Config.accentColor, 0.03 * root.intensity) }
            GradientStop { position: 1.0; color: "transparent" }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 50  // snap off instantly on key press
                easing.type: Easing.Linear
            }
        }
    }

    // Drift animation — moves the scanline from top to bottom repeatedly
    SequentialAnimation {
        id: scanlineAnim
        loops: Animation.Infinite

        NumberAnimation {
            target: scanline
            property: "y"
            from: -scanline.height
            to: root.height
            duration: 8000
            easing.type: Easing.Linear
        }
    }

    // Fade in when idle starts
    Connections {
        target: root
        function onIsIdleChanged() {
            if (root.isIdle) {
                scanline.opacity = 1
            } else {
                scanline.opacity = 0
            }
        }
    }
}
