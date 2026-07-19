pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.services

// ThemeSwitcher — bar widget that shows current preset name.
// Click to open the full PresetControlPanel (2D pad).

Item {
    id: root

    implicitWidth: themeLabel.implicitWidth + 20
    implicitHeight: Config.barHeight - 10

    property string currentName: ThemeService.currentThemeName

    Text {
        id: themeLabel
        anchors.centerIn: parent
        text: (Config.labelPrefix ? Config.labelPrefix + " " : "") + root.currentName
        color: themeMouse.containsMouse ? Config.accentColor : Config.subtextColor
        font.family: Config.font
        font.pixelSize: Config.fontSizeSmall
        font.capitalization: Config.fontCapitalization
        font.letterSpacing: Config.letterSpacing
        font.weight: Font.Medium

        Behavior on color {
            ColorAnimation { duration: Config.animDuration }
        }
    }

    MouseArea {
        id: themeMouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: {
            Quickshell.execDetached(["hyprctl", "dispatch", "global", "quickshell:control_panel"])
        }
    }
}
