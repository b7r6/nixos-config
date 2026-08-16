import QtQuick

// ============================================================================
// hypermodern SDDM theme — frame zero, done properly this time.
//
// The same wallpaper shader as the desktop, lock screen, and quickshell
// layers (wallpaper.frag.qsb, compiled at build), the Azonix clock, the
// IDENTIFY posture line, and a password field driving sddm.login directly.
// Palette and identity arrive via theme.conf (the `config` context object),
// generated at build time from lib.nix — the same math the parity gate pins.
//
// SDDM owns the seat, the VTs, and session lifecycle — the parts the
// hand-rolled greetd compositor chain got wrong.
// ============================================================================

Rectangle {
    id: root

    width: Screen.width
    height: Screen.height
    color: config.base00 || "#191c1f"

    property bool authBusy: false

    // ── The field ────────────────────────────────────────────────────────
    ShaderEffect {
        id: field

        anchors.fill: parent

        property real time: 0
        property real sweep: -1
        property real reg: 1.0
        property real grain: 0.03
        property real aspect: height > 0 ? width / height : 1.777
        property color surface: config.base00 || "#191c1f"
        property color paper: config.base01 || "#1e2329"
        property color accent: config.base0A || "#52a5ff"
        property color accentD: config.base09 || "#80d2ff"

        fragmentShader: Qt.resolvedUrl("wallpaper.frag.qsb")

        Timer {
            interval: 33
            repeat: true
            running: true
            onTriggered: field.time = (field.time + 0.033) % 86400
        }

        NumberAnimation {
            id: entrySweep
            target: field
            property: "sweep"
            from: -0.15
            to: 1.15
            duration: 1100
            easing.type: Easing.OutQuad
        }

        Component.onCompleted: entrySweep.start()
    }

    // ── The card ─────────────────────────────────────────────────────────
    Column {
        id: content

        anchors.centerIn: parent
        spacing: 8
        opacity: 0

        Component.onCompleted: fadeIn.start()

        NumberAnimation {
            id: fadeIn
            target: content
            property: "opacity"
            from: 0
            to: 1
            duration: 600
            easing.type: Easing.OutCubic
        }

        Timer {
            id: clockTick
            interval: 1000
            repeat: true
            running: true
            onTriggered: clockText.text = Qt.formatTime(new Date(), "HH:mm")
        }

        Text {
            id: clockText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(new Date(), "HH:mm")
            font.family: "Azonix"
            font.pixelSize: 64
            font.letterSpacing: 6
            color: config.base0A || "#52a5ff"
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (config.hostName || "") !== ""
                  ? "▞ IDENTIFY — " + config.hostName.toUpperCase()
                  : "▞ IDENTIFY"
            font.family: "Berkeley Mono"
            font.pixelSize: 9
            font.letterSpacing: 2
            color: config.base04 || "#6c7a89"
            topPadding: 6
        }

        Item {
            width: 1
            height: 24
        }

        Rectangle {
            id: passwordField

            anchors.horizontalCenter: parent.horizontalCenter
            width: 280
            height: 44
            radius: 0
            color: config.base01 || "#1e2329"
            border.width: 2
            border.color: passwordInput.activeFocus
                          ? (config.base0A || "#52a5ff")
                          : (config.base02 || "#283039")

            property real shakeX: 0
            transform: Translate {
                x: passwordField.shakeX
            }

            SequentialAnimation {
                id: shaker
                NumberAnimation { target: passwordField; property: "shakeX"; to: -10; duration: 40 }
                NumberAnimation { target: passwordField; property: "shakeX"; to: 10; duration: 70 }
                NumberAnimation { target: passwordField; property: "shakeX"; to: -6; duration: 60 }
                NumberAnimation { target: passwordField; property: "shakeX"; to: 0; duration: 50 }
            }

            Row {
                anchors.centerIn: parent
                spacing: 6

                Repeater {
                    model: passwordInput.text.length

                    Rectangle {
                        width: 10
                        height: 10
                        color: config.base0A || "#52a5ff"
                    }
                }
            }

            TextInput {
                id: passwordInput
                anchors.fill: parent
                opacity: 0
                echoMode: TextInput.Password
                focus: true
                enabled: !root.authBusy
                onAccepted: {
                    if (text.length === 0 || root.authBusy)
                        return;
                    root.authBusy = true;
                    statusText.text = "identifying";
                    sddm.login(config.loginUser || userModel.lastUser,
                               text, sessionModel.lastIndex);
                }
            }
        }

        Text {
            id: statusText
            anchors.horizontalCenter: parent.horizontalCenter
            text: ""
            font.family: "Berkeley Mono"
            font.pixelSize: 10
            font.letterSpacing: 1
            color: config.base04 || "#6c7a89"
            topPadding: 8
            opacity: text === "" ? 0 : 1
        }
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.authBusy = false;
            statusText.text = "denied";
            passwordInput.text = "";
            shaker.restart();
        }

        function onLoginSucceeded() {
            statusText.text = "engaged";
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: passwordInput.forceActiveFocus()
    }
}
