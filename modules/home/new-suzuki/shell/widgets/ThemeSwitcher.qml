pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.services
import "../components/"

// ThemeSwitcher v2 — the bar's window into the preset space: a miniature
// pad showing WHERE in the two-axis space the desktop currently sits (dot
// at register × luminance), beside the slug. Click opens the full orbital
// pad via ThemeService.togglePanel (in-process).

Item {
    id: root

    implicitWidth: row.implicitWidth + 16
    implicitHeight: Config.barHeight - 10

    readonly property bool hovered: themeMouse.containsMouse

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        // the mini-map
        Rectangle {
            id: miniPad
            width: 18
            height: 12
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.alpha(Config.surface1Color, 0.5)
            border.width: 1
            border.color: root.hovered
                          ? Qt.alpha(Config.accentColor, 0.7)
                          : Qt.alpha(Config.surface2Color, 0.8)
            radius: 0

            Behavior on border.color {
                ColorAnimation {
                    duration: Config.animDurationShort
                }
            }

            // crosshair hairlines
            Rectangle {
                x: parent.width / 2
                width: 1
                height: parent.height
                color: Qt.alpha(Config.accentColor, 0.2)
            }
            Rectangle {
                y: parent.height / 2
                width: parent.width
                height: 1
                color: Qt.alpha(Config.accentColor, 0.2)
            }

            // the position dot
            Rectangle {
                width: 3
                height: 3
                radius: 0
                color: Config.accentColor
                x: ThemeService.polarity * (miniPad.width - width - 2) + 1
                y: ThemeService.luminance * (miniPad.height - height - 2) + 1

                Behavior on x {
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuint
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuint
                    }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ThemeService.currentThemeName
            color: root.hovered ? Config.accentColor : Config.subtextColor
            font.family: Config.font
            font.pixelSize: Config.fontSizeSmall
            font.capitalization: Config.fontCapitalization
            font.letterSpacing: Config.letterSpacing

            Behavior on color {
                ColorAnimation {
                    duration: Config.animDuration
                }
            }
        }
    }

    CornerBrackets {
        active: root.hovered
    }

    MouseArea {
        id: themeMouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: ThemeService.togglePanel()
    }
}
