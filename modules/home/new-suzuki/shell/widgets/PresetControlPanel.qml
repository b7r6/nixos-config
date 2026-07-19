pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services
import "../components/"

// ============================================================================
// PresetControlPanel v2 — the orbital pad, gone the distance.
//
// The pad IS the map: its surface renders the four-corner palette space
// (bilinear blend of the real corner backgrounds from presets.json — the
// same computed math as everything else), so the dot travels over the
// actual destination colors. Drag commits LIVE (throttled through
// wintermute's generation fence); release commits the final vector; the
// dot then settles wherever the reconciler landed (Binding-gated — the
// stale-binding fix stays).
//
// Layout: vector readout | the pad | preset cards. Glass via the
// qs_control_panel layerrule; register-aware typography throughout.
// ============================================================================

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
    color: "transparent"
    visible: shown

    // corner palettes from the computed previews (fallback: sane defaults)
    readonly property var corners: ({
        tl: ThemeService.themePreviews["tessier"]?.palette ?? {},
        tr: ThemeService.themePreviews["bioptic"]?.palette ?? {},
        bl: ThemeService.themePreviews["villa-straylight"]?.palette ?? {},
        br: ThemeService.themePreviews["razorgirl"]?.palette ?? {}
    })

    HyprlandFocusGrab {
        windows: [root]
        active: root.shown
        onCleared: root.hide()
    }

    function show() {
        shown = true;
        Qt.callLater(() => padArea.forceActiveFocus());
    }

    function hide() {
        shown = false;
    }

    // Dim vignette (matches the launcher's)
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.shown ? 0.35 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuint
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.hide()
    }

    Item {
        focus: true
        Keys.onEscapePressed: root.hide()
    }

    // ── The panel ────────────────────────────────────────────────────────
    Rectangle {
        id: panel

        width: 860
        height: 460
        anchors.centerIn: parent
        color: Qt.alpha(Config.backgroundColor, 0.62)
        border.color: Qt.alpha(Config.accentColor, 0.25)
        border.width: 1
        radius: 0
        scale: root.shown ? 1.0 : 0.97
        opacity: root.shown ? 1.0 : 0.0

        Behavior on scale {
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Config.animPopupEasing
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Config.animPopupEasing
            }
        }

        // glass sheen
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha("#ffffff", 0.05) }
                GradientStop { position: 0.25; color: Qt.alpha("#ffffff", 0.015) }
                GradientStop { position: 1.0; color: Qt.alpha("#ffffff", 0.0) }
            }
        }

        CornerBrackets {
            active: true
            outset: 5
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14

            // ── Header ───────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: Config.facility ? "PRESET CONTROL" : "preset control"
                    color: Config.textColor
                    font.family: Config.displayFont
                    font.pixelSize: Config.fontSizeNormal
                    font.letterSpacing: Config.facility ? 3 : 0.5
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: ThemeService.currentThemeName
                    color: Config.accentColor
                    font.family: Config.font
                    font.pixelSize: Config.fontSizeSmall
                    font.letterSpacing: 1.2
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 24

                // ── Vector readout ───────────────────────────────────────
                ColumnLayout {
                    Layout.preferredWidth: 150
                    Layout.fillHeight: true
                    spacing: 9

                    Text {
                        text: "vector"
                        color: Config.mutedColor
                        font.family: Config.font
                        font.pixelSize: 9
                        font.letterSpacing: 1.5
                        font.capitalization: Font.AllUppercase
                        Layout.bottomMargin: 2
                    }

                    Repeater {
                        model: [
                            { k: "slug", v: ThemeService.currentThemeName },
                            { k: "gen", v: String(ThemeService.generation) },
                            { k: "polarity", v: ThemeService.colorScheme },
                            { k: "hero", v: String(ThemeService.base16.heroHue ?? 211) }
                        ]

                        RowLayout {
                            required property var modelData
                            spacing: 6

                            Text {
                                text: modelData.k
                                color: Config.mutedColor
                                font.family: Config.font
                                font.pixelSize: 9
                                font.letterSpacing: 1.2
                                font.capitalization: Font.AllUppercase
                                Layout.preferredWidth: 58
                            }

                            Text {
                                text: modelData.v
                                color: Config.subtextColor
                                font.family: Config.font
                                font.pixelSize: Config.fontSizeSmall
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // register bar — position on the axis, as instrumentation
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 4

                        Text {
                            text: "register " + ThemeService.register.toFixed(2)
                            color: Config.mutedColor
                            font.family: Config.font
                            font.pixelSize: 9
                            font.letterSpacing: 1.2
                            font.capitalization: Font.AllUppercase
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 4
                            color: Qt.alpha(Config.surface1Color, 0.6)

                            Rectangle {
                                width: parent.width * ThemeService.register
                                height: parent.height
                                color: Config.accentColor

                                Behavior on width {
                                    NumberAnimation {
                                        duration: Config.animDuration
                                        easing.type: Easing.OutQuint
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        text: "drag to travel · release commits"
                        color: Config.mutedColor
                        font.family: Config.font
                        font.pixelSize: 9
                        opacity: 0.7
                    }
                }

                // ── The pad: the map itself ──────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        id: padArea

                        width: 420
                        height: 300
                        anchors.centerIn: parent
                        color: "transparent"
                        border.color: Qt.alpha(Config.accentColor, 0.3)
                        border.width: 1
                        radius: 0
                        clip: true

                        focus: true
                        Keys.onEscapePressed: root.hide()

                        // The palette field: bilinear blend of the four
                        // corner backgrounds — the space, made visible.
                        Canvas {
                            id: fieldCanvas
                            anchors.fill: parent
                            anchors.margins: 1

                            function corner(c, fallback) {
                                return c && c.background ? c.background : fallback;
                            }

                            onPaint: {
                                const ctx = getContext("2d");
                                const w = width, h = height;
                                const tl = Qt.color(corner(root.corners.tl, "#ffffff"));
                                const tr = Qt.color(corner(root.corners.tr, "#faf8f5"));
                                const bl = Qt.color(corner(root.corners.bl, "#191c1f"));
                                const br = Qt.color(corner(root.corners.br, "#191c1f"));
                                const rows = 36;
                                for (let i = 0; i < rows; i++) {
                                    const t = i / (rows - 1);
                                    const g = ctx.createLinearGradient(0, 0, w, 0);
                                    g.addColorStop(0, Qt.rgba(
                                        tl.r * (1 - t) + bl.r * t,
                                        tl.g * (1 - t) + bl.g * t,
                                        tl.b * (1 - t) + bl.b * t, 1));
                                    g.addColorStop(1, Qt.rgba(
                                        tr.r * (1 - t) + br.r * t,
                                        tr.g * (1 - t) + br.g * t,
                                        tr.b * (1 - t) + br.b * t, 1));
                                    ctx.fillStyle = g;
                                    ctx.fillRect(0, (h / rows) * i, w, h / rows + 1);
                                }
                                // hairline grid + crosshair
                                ctx.strokeStyle = String(Qt.alpha(Config.accentColor, 0.10));
                                ctx.lineWidth = 1;
                                for (let gx = 1; gx < 8; gx++) {
                                    ctx.beginPath();
                                    ctx.moveTo((w / 8) * gx, 0);
                                    ctx.lineTo((w / 8) * gx, h);
                                    ctx.stroke();
                                }
                                for (let gy = 1; gy < 6; gy++) {
                                    ctx.beginPath();
                                    ctx.moveTo(0, (h / 6) * gy);
                                    ctx.lineTo(w, (h / 6) * gy);
                                    ctx.stroke();
                                }
                                ctx.strokeStyle = String(Qt.alpha(Config.accentColor, 0.25));
                                ctx.beginPath();
                                ctx.moveTo(w / 2, 0); ctx.lineTo(w / 2, h);
                                ctx.moveTo(0, h / 2); ctx.lineTo(w, h / 2);
                                ctx.stroke();
                            }

                            Connections {
                                target: ThemeService
                                function onThemePreviewsChanged() {
                                    fieldCanvas.requestPaint();
                                }
                            }
                        }

                        // corner labels in their own corner's accent
                        Repeater {
                            model: [
                                { name: "tessier", key: "tl", top: true, left: true },
                                { name: "bioptic", key: "tr", top: true, left: false },
                                { name: "villa straylight", key: "bl", top: false, left: true },
                                { name: "razorgirl", key: "br", top: false, left: false }
                            ]

                            Text {
                                required property var modelData
                                text: Config.facility ? modelData.name.toUpperCase() : modelData.name
                                color: root.corners[modelData.key]?.accent ?? Config.mutedColor
                                font.family: Config.font
                                font.pixelSize: 9
                                font.letterSpacing: 1.2
                                anchors.top: modelData.top ? parent.top : undefined
                                anchors.bottom: modelData.top ? undefined : parent.bottom
                                anchors.left: modelData.left ? parent.left : undefined
                                anchors.right: modelData.left ? undefined : parent.right
                                anchors.margins: 7
                            }
                        }

                        // ── The dot ──────────────────────────────────────
                        // Binding-gated position (the stale-binding fix):
                        // follows the reconciled vector except while the
                        // user is driving.
                        Item {
                            id: dot
                            width: 18
                            height: 18

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
                                width: 12
                                height: 12
                                radius: 0
                                color: Config.accentColor
                                border.color: Config.backgroundColor
                                border.width: 2
                            }

                            CornerBrackets {
                                active: dragHandler.active || padMouse.pressed
                                outset: 4
                            }

                            DragHandler {
                                id: dragHandler
                                target: dot
                                xAxis.minimum: 0
                                xAxis.maximum: padArea.width - dot.width
                                yAxis.minimum: 0
                                yAxis.maximum: padArea.height - dot.height
                                onActiveChanged: {
                                    if (!active)
                                        ThemeService.commitPad(ThemeService.polarity, ThemeService.luminance);
                                }
                            }

                            onXChanged: {
                                if (dragHandler.active)
                                    ThemeService.polarity = Math.round((x / (padArea.width - width)) * 100) / 100;
                            }
                            onYChanged: {
                                if (dragHandler.active)
                                    ThemeService.luminance = Math.round((y / (padArea.height - height)) * 100) / 100;
                            }
                        }

                        // live travel: throttled commits WHILE dragging —
                        // the whole desktop morphs under the hand, fenced
                        // by wintermute's generation dedup.
                        Timer {
                            id: liveCommit
                            interval: 200
                            repeat: true
                            running: dragHandler.active || padMouse.pressed
                            property real lastX: -1
                            property real lastY: -1
                            onTriggered: {
                                const px = ThemeService.polarity;
                                const py = ThemeService.luminance;
                                if (px !== lastX || py !== lastY) {
                                    lastX = px;
                                    lastY = py;
                                    ThemeService.commitPad(px, py);
                                }
                            }
                        }

                        MouseArea {
                            id: padMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onPressed: mouse => {
                                dot.x = Math.max(0, Math.min(padArea.width - dot.width, mouse.x - dot.width / 2));
                                dot.y = Math.max(0, Math.min(padArea.height - dot.height, mouse.y - dot.height / 2));
                                ThemeService.polarity = Math.round((dot.x / (padArea.width - dot.width)) * 100) / 100;
                                ThemeService.luminance = Math.round((dot.y / (padArea.height - dot.height)) * 100) / 100;
                            }
                            onPositionChanged: mouse => {
                                dot.x = Math.max(0, Math.min(padArea.width - dot.width, mouse.x - dot.width / 2));
                                dot.y = Math.max(0, Math.min(padArea.height - dot.height, mouse.y - dot.height / 2));
                                ThemeService.polarity = Math.round((dot.x / (padArea.width - dot.width)) * 100) / 100;
                                ThemeService.luminance = Math.round((dot.y / (padArea.height - dot.height)) * 100) / 100;
                            }
                            onReleased: ThemeService.commitPad(ThemeService.polarity, ThemeService.luminance)
                        }
                    }
                }

                // ── Preset cards ─────────────────────────────────────────
                ColumnLayout {
                    Layout.preferredWidth: 190
                    Layout.fillHeight: true
                    spacing: 8

                    Text {
                        text: "presets"
                        color: Config.mutedColor
                        font.family: Config.font
                        font.pixelSize: 9
                        font.letterSpacing: 1.5
                        font.capitalization: Font.AllUppercase
                        Layout.bottomMargin: 2
                    }

                    Repeater {
                        model: ThemeService.availableThemes

                        Rectangle {
                            id: card

                            required property string modelData
                            readonly property var preview: ThemeService.themePreviews[modelData]?.palette ?? {}
                            readonly property bool isCurrent: modelData === ThemeService.currentThemeName
                            readonly property bool hovered: cardMouse.containsMouse

                            Layout.fillWidth: true
                            Layout.preferredHeight: 54
                            radius: 0
                            color: Qt.alpha(Config.surface0Color, hovered ? 0.7 : 0.45)
                            border.width: 1
                            border.color: isCurrent
                                          ? Config.accentColor
                                          : Qt.alpha(Config.surface2Color, 0.5)

                            Behavior on color {
                                ColorAnimation {
                                    duration: Config.animDurationShort
                                }
                            }

                            CornerBrackets {
                                active: card.hovered || card.isCurrent
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 9
                                spacing: 5

                                Text {
                                    text: Config.facility ? card.modelData.toUpperCase() : card.modelData
                                    color: card.isCurrent ? Config.accentColor : Config.textColor
                                    font.family: Config.font
                                    font.pixelSize: Config.fontSizeSmall
                                    font.letterSpacing: 1
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                RowLayout {
                                    spacing: 4

                                    Repeater {
                                        model: [
                                            card.preview.background ?? "#191c1f",
                                            card.preview.accent ?? "#52a5ff",
                                            card.preview.success ?? "#2496ff",
                                            card.preview.error ?? "#f85149"
                                        ]

                                        Rectangle {
                                            required property string modelData
                                            width: 12
                                            height: 12
                                            radius: 0
                                            color: modelData
                                            border.width: 1
                                            border.color: Qt.alpha("#888888", 0.3)
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ThemeService.applyTheme(card.modelData)
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
