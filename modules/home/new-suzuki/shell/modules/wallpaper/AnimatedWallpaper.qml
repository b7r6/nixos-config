pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// AnimatedWallpaper — the GLSL background layer, one surface per screen.
//
// The shader is the two-axis design space made visible: palette uniforms come
// from ThemeService (wintermute's theme.json), the register scalar morphs the
// field between ambient blooms (affluent) and telemetry/scanline (facility).
// Theme changes EASE — reg and the colors ride Behaviors with the canonical
// easeOutQuint, so dragging the orbital pad sweeps the wallpaper live.
//
// Cost control: 30 fps timer (slow phenomena don't need 120), paused behind
// the lock screen; the compositor withholds frames when occluded so an idle
// desktop costs nothing.
Variants {
    // When the CUDA presenter owns the field (wintermute-field-daemon on its
    // own background layer), the QML wallpaper stands down entirely — two
    // renderers on the same layer would just fight over stacking order.
    model: Quickshell.env("HYPERMODERN_CUDA_FIELD") === "1" ? [] : Quickshell.screens

    PanelWindow {
        id: win

        required property var modelData
        screen: modelData
        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }
        exclusiveZone: -1
        color: "transparent"
        focusable: false
        aboveWindows: false
        WlrLayershell.namespace: "qs_wallpaper"
        WlrLayershell.layer: WlrLayer.Background

        ShaderEffect {
            id: fx

            anchors.fill: parent

            property real time: 0
            property real sweep: -1
            property real reg: ThemeService.register
            property real grain: ThemeService.aestheticProp("grain", 0.02)
            property real aspect: height > 0 ? width / height : 1.777
            property color surface: ThemeService.color("surface", "#191c1f")
            property color paper: ThemeService.color("paper", "#1e2329")
            property color accent: ThemeService.color("accent", "#52a5ff")
            property color accentD: ThemeService.color("accent-d", "#80d2ff")

            Behavior on reg {
                NumberAnimation {
                    duration: 1200
                    easing.type: Easing.OutQuint
                }
            }
            Behavior on surface {
                ColorAnimation { duration: 800 }
            }
            Behavior on paper {
                ColorAnimation { duration: 800 }
            }
            Behavior on accent {
                ColorAnimation { duration: 800 }
            }
            Behavior on accentD {
                ColorAnimation { duration: 800 }
            }

            fragmentShader: Qt.resolvedUrl("wallpaper.frag.qsb")

            Timer {
                interval: 33
                repeat: true
                running: win.visible && !LockService.locked
                onTriggered: fx.time = (fx.time + 0.033) % 86400
            }

            // The reconcile sweep: one pass down the screen per wintermute
            // generation — theme commits are VISIBLE.
            Connections {
                target: ThemeService
                function onGenerationChanged() {
                    sweepAnim.restart();
                }
            }

            NumberAnimation {
                id: sweepAnim
                target: fx
                property: "sweep"
                from: -0.15
                to: 1.15
                duration: 900
                easing.type: Easing.OutQuad
            }
        }
    }
}
