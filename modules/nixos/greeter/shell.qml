pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

// ============================================================================
// The hypermodern greeter — frame zero wears the SECURED posture.
//
// Runs under cage as the greetd greeter: the same wallpaper shader as the
// desktop/lock at forced full-facility register, the display-face clock, and
// a password field that drives greetd directly (createSession → authMessage →
// respond → launch). Palette + user + session command arrive in config.json,
// generated at build time from the same lib.nix math the parity gate pins.
//
// Auth flow is deliberately dumb: enter password, submit, respond to the
// first response-required prompt. Failure shakes, clears, cancels, retries.
// ============================================================================

ShellRoot {
    id: root

    property var conf: ({})
    property string pal: ""
    property bool authBusy: false
    property string statusText: ""

    function c(key, fallback) {
        return (conf.palette && conf.palette[key]) || fallback;
    }

    FileView {
        path: Quickshell.shellDir + "/config.json"
        preload: true
        onLoaded: {
            try {
                root.conf = JSON.parse(text());
            } catch (e) {
                console.error("[greeter] bad config.json:", e);
            }
        }
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                // The password prompt: answer with what the user typed.
                Greetd.respond(root.pendingPassword);
            } else {
                root.statusText = message;
            }
        }

        function onAuthFailure(message) {
            root.statusText = message.toLowerCase();
            root.authBusy = false;
            root.shakeAll();
            Greetd.cancelSession();
        }

        function onReadyToLaunch() {
            root.statusText = "launching";
            Greetd.launch([root.conf.session || "start-hyprland"], [], true);
        }
    }

    property string pendingPassword: ""
    signal shakeAll

    function submit(password) {
        if (root.authBusy || password.length === 0)
            return;
        root.authBusy = true;
        root.statusText = "identifying";
        root.pendingPassword = password;
        Greetd.createSession(root.conf.user || "b7r6");
    }

    Variants {
        model: Quickshell.screens

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
            exclusionMode: ExclusionMode.Ignore
            color: root.c("base00", "#191c1f")
            WlrLayershell.namespace: "qs_greeter"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // ── The field ────────────────────────────────────────────────
            ShaderEffect {
                id: field

                anchors.fill: parent

                property real time: 0
                property real sweep: -1
                property real reg: 1.0
                property real grain: 0.03
                property real aspect: height > 0 ? width / height : 1.777
                property color surface: root.c("base00", "#191c1f")
                property color paper: root.c("base01", "#1e2329")
                property color accent: root.c("base0A", "#52a5ff")
                property color accentD: root.c("base09", "#80d2ff")

                fragmentShader: Qt.resolvedUrl("wallpaper.frag.qsb")

                Timer {
                    interval: 33
                    repeat: true
                    running: win.visible
                    onTriggered: field.time = (field.time + 0.033) % 86400
                }

                NumberAnimation {
                    id: greetSweep
                    target: field
                    property: "sweep"
                    from: -0.15
                    to: 1.15
                    duration: 1100
                    easing.type: Easing.OutQuad
                }

                Component.onCompleted: greetSweep.start()
            }

            // ── The card ─────────────────────────────────────────────────
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

                SystemClock {
                    id: clock
                    precision: SystemClock.Minutes
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(clock.date, "HH:mm")
                    font.family: "Azonix"
                    font.pixelSize: 64
                    font.letterSpacing: 6
                    color: root.c("base0A", "#52a5ff")
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (root.conf.host || "") !== ""
                          ? "▞ IDENTIFY — " + root.conf.host : "▞ IDENTIFY"
                    font.family: "Berkeley Mono"
                    font.pixelSize: 9
                    font.letterSpacing: 2
                    font.capitalization: Font.AllUppercase
                    color: root.c("base04", "#6c7a89")
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
                    color: root.c("base01", "#1e2329")
                    border.width: 2
                    border.color: passwordInput.activeFocus
                                  ? root.c("base0A", "#52a5ff")
                                  : root.c("base02", "#283039")

                    property real shakeX: 0
                    transform: Translate {
                        x: passwordField.shakeX
                    }

                    Connections {
                        target: root
                        function onShakeAll() {
                            shaker.restart();
                            passwordInput.text = "";
                        }
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
                                color: root.c("base0A", "#52a5ff")
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
                        onAccepted: root.submit(text)
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.statusText
                    font.family: "Berkeley Mono"
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    color: root.c("base04", "#6c7a89")
                    topPadding: 8
                    opacity: root.statusText === "" ? 0 : 1
                }
            }
        }
    }
}
