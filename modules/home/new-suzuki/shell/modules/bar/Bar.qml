pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services
import "../../components/"
import "../quickSettings/"
import "../notifications/"
import "../systemMonitor/"
import "../calendar/"
import "../../widgets/"

Scope {
    id: root

    readonly property int gapIn: 5
    readonly property int gapOut: 15

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            property bool enableAutoHide: Config.barAutoHide

            // Floating ↔ flush morph: the bar is a detached glass island at
            // the affluent pole (inset margins) and a flush console strip at
            // the facility pole. Drag the pad and the bar physically
            // reshapes — the register axis expressed in geometry.
            readonly property int floatInset: Math.round(12 * (1.0 - Config.register))
            readonly property int floatTop: Math.round(8 * (1.0 - Config.register))

            // NameSpace
            WlrLayershell.namespace: "qs_modules"

            // --- BAR CONFIGURATION ---
            implicitHeight: StateService.get("bar.height", 30)
            color: "transparent"
            screen: modelData

            // Overlay ensures it stays above games/fullscreen
            // WlrLayershell.layer: WlrLayer.Overlay

            // Set the exclusion mode
            exclusionMode: enableAutoHide ? ExclusionMode.Ignore : ExclusionMode.Normal

            // Ensure reserved area size when in Normal mode
            exclusiveZone: enableAutoHide ? 0 : height + floatTop

            anchors {
                top: true
                left: true
                right: true
            }

            margins.left: floatInset
            margins.right: floatInset

            Behavior on margins.left {
                NumberAnimation {
                    duration: Config.animDurationLong
                    easing.type: Easing.OutQuint
                }
            }
            Behavior on margins.right {
                NumberAnimation {
                    duration: Config.animDurationLong
                    easing.type: Easing.OutQuint
                }
            }

            // --- AUTOHIDE LOGIC ---
            // If mouse is hovering, margin is floatTop (show everything).
            // Otherwise, hide off-screen leaving 1px to catch the mouse.
            margins.top: {
                if (WindowManagerService.anyModuleOpen || !enableAutoHide || mouseSensor.hovered)
                    return floatTop;

                return (-1 * (height - 1));
            }

            // Smooth window movement animation
            Behavior on margins.top {
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutExpo
                }
            }

            // --- MOUSE SENSOR ---
            // Covers the entire window. Since the window never "disappears" (only moves off-screen),
            // the remaining 1px still detects the mouse.
            HoverHandler {
                id: mouseSensor
            }

            Rectangle {
                id: barContent
                anchors.fill: parent
                color: Config.backgroundTransparentColor
                // Island edge grows in as the bar detaches
                border.width: 1
                border.color: Qt.alpha(Config.accentColor, 0.15 * (1.0 - Config.register))

                // ── The rail ─────────────────────────────────────────────
                // Bottom accent line: soft gradient fade at the affluent
                // pole; hard line with a slow scanner blip at the facility
                // pole (8s period — phase-family of the wallpaper's drift).
                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 2
                    clip: true

                    // affluent: gradient whisper
                    Rectangle {
                        anchors.fill: parent
                        opacity: 1.0 - Config.register
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: Qt.alpha(Config.accentColor, 0.35) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    // facility: hard rail
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.alpha(Config.accentColor, 0.22)
                        opacity: Config.register
                    }

                    // the scanner blip
                    Rectangle {
                        id: blip
                        width: 90
                        height: parent.height
                        opacity: Config.register
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.7; color: Qt.alpha(Config.accentColor, 0.9) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }

                        NumberAnimation on x {
                            from: -90
                            to: barContent.width
                            duration: 8000
                            loops: Animation.Infinite
                            running: Config.facility && barContent.visible
                        }
                    }

                    // Generation echo: a wintermute commit fires one fast
                    // bright pass along the rail — the bar's answer to the
                    // wallpaper's reconcile sweep, at BOTH poles.
                    Rectangle {
                        id: echoBlip
                        width: 140
                        height: parent.height
                        x: -140
                        opacity: 0
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: Config.accentColor }
                            GradientStop { position: 1.0; color: "transparent" }
                        }

                        Connections {
                            target: ThemeService
                            function onGenerationChanged() {
                                echoAnim.restart();
                            }
                        }

                        SequentialAnimation {
                            id: echoAnim

                            PropertyAction { target: echoBlip; property: "opacity"; value: 1 }
                            NumberAnimation {
                                target: echoBlip
                                property: "x"
                                from: -140
                                to: barContent.width
                                duration: 450
                                easing.type: Easing.OutQuad
                            }
                            PropertyAction { target: echoBlip; property: "opacity"; value: 0 }
                        }
                    }
                }

                // --- LEFT ---
                RowLayout {
                    anchors.left: parent.left
                    anchors.leftMargin: root.gapOut
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.gapIn

                    // Machine identity — facility register only. On a fleet
                    // of Sparks, which console is this?
                    HostBadge {
                        opacity: Config.register
                        visible: Config.register > 0.05
                    }

                    CalendarButton {}
                    SystemMonitorButton {}
                    ActiveWindow {}
                }

                // --- CENTER ---
                RowLayout {
                    anchors.centerIn: parent
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.gapIn

                    Workspaces {}
                }

                // --- RIGHT ---
                RowLayout {
                    anchors.right: parent.right
                    anchors.rightMargin: root.gapOut
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.gapIn

                    // Same slot, opposite poles: telemetry fades out toward
                    // the villa, the lounge fades in.
                    Lounge {
                        Layout.rightMargin: 8
                    }

                    Telemetry {
                        Layout.rightMargin: 8
                    }

                    TrayWidget {}
                    ThemeSwitcher {}
                    QuickSettingsButton {}
                    NotificationButton {}
                }
            }
        }
    }
}
