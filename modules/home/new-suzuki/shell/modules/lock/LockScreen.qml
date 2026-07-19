pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

WlSessionLock {
    id: root

    // Set locked on creation — NOT bound to LockService.locked
    // This avoids the race condition where Loader destruction and protocol
    // unlock happen simultaneously
    locked: true

    onLockStateChanged: {
        // Protocol unlock complete → defer LockService.unlock() to the next
        // event loop so surface destruction finishes cleanly before the Loader
        // tries to destroy this component (avoids "invalid context" warning)
        if (!locked)
            Qt.callLater(LockService.unlock);
    }

    WlSessionLockSurface {
        color: Config.backgroundColor

        // ====================================================================
        // BACKDROP — the wallpaper shader at forced full-facility register:
        // locked is the machine's SECURED posture whatever the desktop
        // register. One sweep fires on lock. (The desktop wallpaper's own
        // timer pauses behind the lock, so the GPU renders one field.)
        // ====================================================================
        ShaderEffect {
            id: lockField

            anchors.fill: parent

            property real time: 0
            property real sweep: -1
            property real reg: 1.0
            property real grain: 0.03
            property real aspect: height > 0 ? width / height : 1.777
            property color surface: Config.backgroundColor
            property color paper: Config.surface0Color
            property color accent: Config.accentColor
            property color accentD: ThemeService.color("accent-d", "#80d2ff")

            fragmentShader: Qt.resolvedUrl("../wallpaper/wallpaper.frag.qsb")

            Timer {
                interval: 33
                repeat: true
                running: true
                onTriggered: lockField.time = (lockField.time + 0.033) % 86400
            }

            NumberAnimation {
                id: lockSweep
                target: lockField
                property: "sweep"
                from: -0.15
                to: 1.15
                duration: 1100
                easing.type: Easing.OutQuad
            }

            Component.onCompleted: lockSweep.start()
        }

        // Capture clicks to refocus the hidden password input
        MouseArea {
            anchors.fill: parent
            onClicked: passwordInput.forceActiveFocus()
        }

        // ====================================================================
        // MAIN CONTENT
        // ====================================================================

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
                duration: Config.animDurationLong
                easing.type: Easing.OutCubic
            }

            // Clock — display face, tracked out
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: TimeService.format("HH:mm")
                font.family: Config.displayFont
                font.pixelSize: 64
                font.bold: !Config.facility
                font.letterSpacing: Config.facility ? 6 : 0
                color: Config.accentColor
            }

            // Date
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: TimeService.format("dddd, dd MMMM yyyy")
                font.family: Config.font
                font.pixelSize: Config.fontSizeNormal
                color: Config.subtextColor
            }

            // Posture line
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "▞ SECURED — GEN " + ThemeService.generation
                font.family: Config.font
                font.pixelSize: 9
                font.letterSpacing: 2
                font.capitalization: Font.AllUppercase
                color: Config.mutedColor
                topPadding: 6
            }

            Item {
                width: 1
                height: 24
            }

            // Password field
            Rectangle {
                id: passwordField
                anchors.horizontalCenter: parent.horizontalCenter
                width: 280
                height: 44
                radius: Config.radius
                color: Config.surface0Color
                border.width: 2
                border.color: LockService.failed ? Config.errorColor : passwordInput.activeFocus ? Config.accentColor : Config.surface2Color

                Behavior on border.color {
                    ColorAnimation {
                        duration: Config.animDurationShort
                    }
                }

                // Shake offset (applied via transform to not affect layout)
                property real shakeX: 0
                transform: Translate {
                    x: passwordField.shakeX
                }

                // Password dots
                Row {
                    visible: !LockService.authenticating
                    anchors.centerIn: parent
                    spacing: 6

                    Repeater {
                        model: passwordInput.text.length

                        Rectangle {
                            required property int index
                            readonly property bool isLast: index === passwordInput.text.length - 1
                            width: 10
                            height: 10
                            radius: width / 2
                            color: Config.accentColor
                            scale: isLast ? 0.5 : 1
                            opacity: isLast ? 1.0 : 0.8

                            Component.onCompleted: scale = isLast ? 1.2 : 1

                            Behavior on scale {
                                NumberAnimation {
                                    duration: Config.animDuration
                                    easing.type: Easing.OutBack
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Config.animDuration
                                }
                            }
                        }
                    }
                }

                // Placeholder / status text
                Text {
                    anchors.centerIn: parent
                    visible: (passwordInput.text.length === 0) || (LockService.authenticating)
                    text: LockService.authenticating ? "Verifying..." : "Enter password..."
                    color: LockService.authenticating ? Config.accentColor : Config.mutedColor
                    font.family: Config.font
                    font.pixelSize: Config.fontSizeNormal
                }

                // Shake animation on auth failure
                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation {
                        target: passwordField
                        property: "shakeX"
                        to: 12
                        duration: 40
                    }
                    NumberAnimation {
                        target: passwordField
                        property: "shakeX"
                        to: -10
                        duration: 40
                    }
                    NumberAnimation {
                        target: passwordField
                        property: "shakeX"
                        to: 8
                        duration: 40
                    }
                    NumberAnimation {
                        target: passwordField
                        property: "shakeX"
                        to: -6
                        duration: 40
                    }
                    NumberAnimation {
                        target: passwordField
                        property: "shakeX"
                        to: 0
                        duration: 40
                    }
                }
            }

            // Error text
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: LockService.failed
                text: LockService.failMessage
                color: Config.errorColor
                font.family: Config.font
                font.pixelSize: Config.fontSizeSmall
            }

            // Username
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Quickshell.env("USER")
                color: Config.subtextColor
                font.family: Config.font
                font.pixelSize: Config.fontSizeNormal
            }
        }

        // ====================================================================
        // HIDDEN PASSWORD INPUT
        // ====================================================================

        TextInput {
            id: passwordInput
            width: 1
            height: 1
            opacity: 0
            echoMode: TextInput.Password
            focus: true

            Keys.onReturnPressed: submit()
            Keys.onEnterPressed: submit()

            function submit() {
                if (!LockService.authenticating && text.length > 0)
                    LockService.tryUnlock(text);
            }
        }

        // ====================================================================
        // AUTH EVENT HANDLERS
        // ====================================================================

        Connections {
            id: lockServiceConn
            target: LockService

            function onAuthSucceeded() {
                passwordField.forceActiveFocus();
                fadeOut.start();
            }

            function onFailedChanged() {
                if (LockService.failed) {
                    shakeAnim.start();
                    passwordInput.clear();
                }
            }
        }

        // Fade out → unlock sequence
        SequentialAnimation {
            id: fadeOut

            NumberAnimation {
                target: content
                property: "opacity"
                to: 0
                duration: Config.animDurationLong
                easing.type: Easing.OutCubic
            }

            ScriptAction {
                script: {
                    // Disconnect before unlocking to prevent signal handlers
                    // from firing during surface destruction
                    lockServiceConn.enabled = false;
                    root.locked = false;
                }
            }
        }
    }
}
