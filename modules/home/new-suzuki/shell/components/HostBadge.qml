pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// HostBadge — the machine's name in the corner, console-style. On a fleet
// (multiple Sparks driving the same panels) this is which-console-am-I.
// Hostname via /etc/hostname (no subprocess).
Item {
    id: root

    property string hostname: ""

    implicitWidth: badge.implicitWidth + 8
    implicitHeight: badge.implicitHeight

    FileView {
        path: "/etc/hostname"
        preload: true
        onLoaded: root.hostname = text().trim()
    }

    Row {
        id: badge
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        Text {
            text: "▞"
            color: Config.accentColor
            font.family: Config.font
            font.pixelSize: 9
        }

        Text {
            text: root.hostname
            visible: root.hostname !== ""
            color: Config.mutedColor
            font.family: Config.font
            font.pixelSize: 9
            font.letterSpacing: 2
            font.capitalization: Font.AllUppercase
        }
    }
}
