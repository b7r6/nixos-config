pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.config
import qs.services

// PresetControlPanel — the 2D pad for browsing the affluent↔facility ×
// day↔night space. Opens via global shortcut "control_panel" or clicking
// the theme switcher label.
//
// Layout:
//   ┌─────────────────────────────────────────────┐
//   │  // PRESET CONTROL                           │
//   │                                               │
//   │  ┌───────────────────────────┐  ┌──────────┐ │
//   │  │  villa-straylight     ●    │  │ yorha    │ │
//   │  │                   ◦       │  │ bunker   │ │
//   │  │                           │  │ chiba    │ │
//   │  │  razorgirl    bunker      │  │ onsen    │ │
//   │  │       ●          ◦        │  │ razorgirl│ │
//   │  │                           │  │ villa... │ │
//   │  │  day ←─────────→ night    │  └──────────┘ │
//   │  └───────────────────────────┘               │
//   │                                               │
//   │  polarity: 0.40  luminance: 0.80              │
//   └─────────────────────────────────────────────┘
//
// Drag the dot on the pad to move through the space.
// Click a preset name to snap to it.

PanelWindow {
    id: root

    property bool shown: false

    WlrLayershell.namespace: "qs_control_panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    color: Qt.alpha(Config.backgroundColor, 0.85)
    visible: shown

    HyprlandFocusGrab {
        windows: [root]
        active: root.shown
        onCleared: root.hide()
    }

    function show() {
        shown = true
        Qt.callLater(() => { padArea.forceActiveFocus() })
    }

    function hide() {
        shown = false
    }

    // Close on Escape
    Item {
        focus: true
        Keys.onEscapePressed: root.hide()
    }

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.hide()
    }

    // ── Centered panel ───────────────────────────────────────────────────
    Rectangle {
        id: panel
        width: 640
        height: 420
        anchors.centerIn: parent
        color: Config.backgroundTransparentColor
        border.color: Config.surface2Color
        border.width: 1
        radius: 0
        scale: root.shown ? 1.0 : 0.97
        opacity: root.shown ? 1.0 : 0.0

        Behavior on scale {
            NumberAnimation { duration: Config.animDuration; easing.type: Config.animPopupEasing }
        }
        Behavior on opacity {
            NumberAnimation { duration: Config.animDuration; easing.type: Config.animPopupEasing }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            // ── Header ────────────────────────────────────────────────────
            Text {
                text: Config.labelPrefix + " PRESET CONTROL"
                color: Config.subtextColor
                font.family: Config.font
                font.pixelSize: Config.fontSizeSmall
                font.capitalization: Config.fontCapitalization
                font.letterSpacing: Config.letterSpacing
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 24

                // ── 2D Pad ────────────────────────────────────────────────
                Item {
                    id: padContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    property real padW: 400
                    property real padH: 300

                    Rectangle {
                        id: padArea
                        width: padContainer.padW
                        height: padContainer.padH
                        anchors.centerIn: parent
                        color: Qt.alpha(Config.surface1Color, 0.3)
                        border.color: Config.surface2Color
                        border.width: 1
                        radius: 0
                        clip: true

                        // Focus for keyboard
                        focus: true
                        Keys.onEscapePressed: root.hide()

                        // Grid lines
                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = Qt.alpha(Config.surface2Color, 0.3)
                                ctx.lineWidth = 1
                                // Crosshair
                                ctx.beginPath()
                                ctx.moveTo(width / 2, 0)
                                ctx.lineTo(width / 2, height)
                                ctx.moveTo(0, height / 2)
                                ctx.lineTo(width, height / 2)
                                ctx.stroke()
                            }
                        }

                        // Corner labels — the four canonical corners of the
                        // preset space: x = affluent → facility, y = day → night.
                        Text {
                            text: "tessier"
                            color: Config.mutedColor
                            font.family: Config.font
                            font.pixelSize: 9
                            font.capitalization: Font.MixedCase
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: 6
                        }
                        Text {
                            text: "bioptic"
                            color: Config.mutedColor
                            font.family: Config.font
                            font.pixelSize: 9
                            font.capitalization: Font.MixedCase
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                        }
                        Text {
                            text: "villa straylight"
                            color: Config.mutedColor
                            font.family: Config.font
                            font.pixelSize: 9
                            font.capitalization: Font.MixedCase
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.margins: 6
                        }
                        Text {
                            text: "razorgirl"
                            color: Config.mutedColor
                            font.family: Config.font
                            font.pixelSize: 9
                            font.capitalization: Font.MixedCase
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.margins: 6
                        }

                        // Axis labels
                        Text {
                            text: "day"
                            color: Config.mutedColor
                            font.family: Config.font
                            font.pixelSize: 9
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: -14
                        }
                        Text {
                            text: "night"
                            color: Config.mutedColor
                            font.family: Config.font
                            font.pixelSize: 9
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: -14
                        }
                        Text {
                            text: "affluent"
                            color: Config.mutedColor
                            font.family: Config.font
                            font.pixelSize: 9
                            rotation: -90
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: -14
                        }
                        Text {
                            text: "facility"
                            color: Config.mutedColor
                            font.family: Config.font
                            font.pixelSize: 9
                            rotation: 90
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: -14
                        }

                        // The draggable dot.
                        //
                        // Position comes from Binding elements with `when`
                        // guards, NOT plain bindings: the drag handlers write
                        // x/y imperatively, which severs a plain binding on
                        // first touch — the reason the dot stopped tracking
                        // wintermute round-trips after one drag.
                        Item {
                            id: dot
                            width: 16
                            height: 16

                            Binding {
                                target: dot
                                property: "x"
                                value: ThemeService.polarity * (padArea.width - dot.width)
                                when: !dragHandler.active && !padMouse.pressed
                                restoreMode: Binding.RestoreNone
                            }

                            Binding {
                                target: dot
                                property: "y"
                                value: ThemeService.luminance * (padArea.height - dot.height)
                                when: !dragHandler.active && !padMouse.pressed
                                restoreMode: Binding.RestoreNone
                            }

                            Behavior on x {
                                enabled: !dragHandler.active && !padMouse.pressed
                                NumberAnimation {
                                    duration: Config.animDuration
                                    easing.type: Easing.OutQuint
                                }
                            }
                            Behavior on y {
                                enabled: !dragHandler.active && !padMouse.pressed
                                NumberAnimation {
                                    duration: Config.animDuration
                                    easing.type: Easing.OutQuint
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                radius: 0
                                color: Config.accentColor
                                border.color: Config.backgroundColor
                                border.width: 2
                            }

                            // Drag handle — commits the vector to wintermute
                            // on release; the theme.json round-trip settles
                            // the dot at the reconciled position.
                            DragHandler {
                                id: dragHandler
                                target: dot
                                xAxis.enabled: true
                                yAxis.enabled: true
                                xAxis.minimum: 0
                                xAxis.maximum: padArea.width - dot.width
                                yAxis.minimum: 0
                                yAxis.maximum: padArea.height - dot.height
                                onActiveChanged: {
                                    if (!active)
                                        ThemeService.commitPad(ThemeService.polarity, ThemeService.luminance)
                                }
                            }

                            // Update polarity/luminance on drag
                            onXChanged: {
                                if (dragHandler.active) {
                                    var p = x / (padArea.width - width)
                                    ThemeService.polarity = Math.round(p * 100) / 100
                                }
                            }
                            onYChanged: {
                                if (dragHandler.active) {
                                    var l = y / (padArea.height - height)
                                    ThemeService.luminance = Math.round(l * 100) / 100
                                }
                            }
                        }

                        // Click-to-move (in addition to drag)
                        MouseArea {
                            id: padMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onPressed: mouse => {
                                dot.x = mouse.x - dot.width / 2
                                dot.y = mouse.y - dot.height / 2
                                ThemeService.polarity = Math.round((dot.x / (padArea.width - dot.width)) * 100) / 100
                                ThemeService.luminance = Math.round((dot.y / (padArea.height - dot.height)) * 100) / 100
                            }
                            onPositionChanged: mouse => {
                                dot.x = Math.max(0, Math.min(padArea.width - dot.width, mouse.x - dot.width / 2))
                                dot.y = Math.max(0, Math.min(padArea.height - dot.height, mouse.y - dot.height / 2))
                                ThemeService.polarity = Math.round((dot.x / (padArea.width - dot.width)) * 100) / 100
                                ThemeService.luminance = Math.round((dot.y / (padArea.height - dot.height)) * 100) / 100
                            }
                            onReleased: ThemeService.commitPad(ThemeService.polarity, ThemeService.luminance)
                        }
                    }
                }

                // ── Preset list ───────────────────────────────────────────
                ColumnLayout {
                    Layout.preferredWidth: 160
                    Layout.fillHeight: true
                    spacing: 2

                    Text {
                        text: "presets"
                        color: Config.mutedColor
                        font.family: Config.font
                        font.pixelSize: 9
                        font.capitalization: Font.MixedCase
                        Layout.bottomMargin: 4
                    }

                    Repeater {
                        model: ThemeService.availableThemes

                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            readonly property bool isActive: ThemeService.currentThemeName === modelData
                            Layout.fillWidth: true
                            height: 28
                            color: isActive ? Qt.alpha(Config.accentColor, 0.12) : "transparent"
                            radius: 0

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.isActive ? Config.labelPrefix + " " + modelData : modelData
                                color: parent.isActive ? Config.accentColor : Config.textColor
                                font.family: Config.font
                                font.pixelSize: Config.fontSizeSmall
                                font.capitalization: Config.fontCapitalization
                                font.weight: parent.isActive ? Font.Medium : Font.Normal
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ThemeService.applyTheme(modelData)
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // ── Values readout ─────────────────────────────────────
                    Text {
                        text: "polarity: " + ThemeService.polarity.toFixed(2)
                        color: Config.subtextColor
                        font.family: Config.font
                        font.pixelSize: 10
                    }
                    Text {
                        text: "luminance: " + ThemeService.luminance.toFixed(2)
                        color: Config.subtextColor
                        font.family: Config.font
                        font.pixelSize: 10
                    }
                    Text {
                        text: "current: " + ThemeService.currentThemeName
                        color: Config.subtextColor
                        font.family: Config.font
                        font.pixelSize: 10
                    }
                }
            }

            // ── Footer ──────────────────────────────────────────────────
            Text {
                text: "drag the pad or click a preset  ·  esc to close"
                color: Config.mutedColor
                font.family: Config.font
                font.pixelSize: 9
                font.capitalization: Font.MixedCase
                Layout.fillWidth: true
            }
        }
    }
}
