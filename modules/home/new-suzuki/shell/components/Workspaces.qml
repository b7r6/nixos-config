pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.config

Item {
    id: root

    readonly property int itemWidth: 6
    readonly property int activeWidth: 24
    readonly property int itemHeight: 6
    readonly property int itemSpacing: 6

    readonly property var parentWindow: QsWindow.window
    readonly property var parentScreen: parentWindow?.screen ?? null

    property var currentMonitor: {
        if (!Hyprland)
            return null;
        return (parentScreen ? Hyprland.monitorFor(parentScreen) : null) ?? Hyprland.focusedMonitor ?? null;
    }

    property var activeWorkspace: currentMonitor?.activeWorkspace ?? null
    property int activeId: (activeWorkspace && activeWorkspace.id > 0) ? activeWorkspace.id : 1

    // Build a list of workspace IDs from Hyprland's actual workspaces,
    // plus the active one if it's not in the list.
    readonly property var workspaceIds: {
        var ids = [];
        if (Hyprland && Hyprland.workspaces) {
            var ws = Hyprland.workspaces.values;
            for (var i = 0; i < ws.length; i++) {
                if (ws[i] && ws[i].id > 0)
                    ids.push(ws[i].id);
            }
        }
        // Ensure active is present
        if (ids.indexOf(activeId) === -1)
            ids.push(activeId);
        ids.sort((a, b) => a - b);
        return ids;
    }

    implicitWidth: row.implicitWidth
    implicitHeight: itemHeight + 4

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.itemSpacing

        Repeater {
            model: root.workspaceIds

            delegate: Item {
                required property int modelData
                required property int index
                readonly property bool isActive: root.activeId === modelData
                width: isActive ? root.activeWidth : root.itemWidth
                height: root.itemHeight

                Rectangle {
                    id: pip

                    readonly property bool isActive: parent.isActive
                    readonly property int wsId: parent.modelData

                    anchors.centerIn: parent
                    width: isActive ? root.activeWidth : root.itemWidth
                    // The active pip grows enough to carry its numeral at the
                    // facility pole; square corners everywhere.
                    height: isActive && Config.facility ? root.itemHeight + 6 : root.itemHeight
                    radius: 0
                    color: isActive ? Config.accentColor : Config.mutedColor

                    Behavior on width {
                        NumberAnimation {
                            duration: Config.animDuration
                            easing.type: Config.animPopupEasing
                        }
                    }
                    Behavior on height {
                        NumberAnimation {
                            duration: Config.animDurationShort
                        }
                    }
                    Behavior on color {
                        ColorAnimation { duration: Config.animDuration }
                    }

                    // Facility: the active workspace is numbered, console-style.
                    Text {
                        anchors.centerIn: parent
                        text: pip.wsId
                        visible: pip.isActive && Config.facility
                        font.family: Config.font
                        font.pixelSize: 8
                        font.bold: true
                        color: Config.backgroundColor
                    }
                }

                TapHandler {
                    onTapped: Hyprland.dispatch("workspace " + modelData)
                }
            }
        }
    }
}
