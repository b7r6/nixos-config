pragma ComponentBehavior: Bound

import QtQuick
import qs.config

// CornerBrackets — the razorgirl geo-hover: four L-marks that snap onto a
// hovered element's corners. Presence and arm length ride the register
// axis (bracketSize token): full facility gets crisp targeting marks,
// the affluent pole gets nothing at all.
//
// Usage: place inside any Item, set `active` from its hover state.
Item {
    id: root

    property bool active: false
    property color bracketColor: Config.accentColor
    property int thickness: 1
    property real outset: 2
    readonly property real arm: 3 + 4 * Config.bracketScale

    anchors.fill: parent
    anchors.margins: -outset
    visible: Config.bracketScale > 0.01
    opacity: (active ? 1 : 0) * Math.min(1, Config.bracketScale * 1.4)

    Behavior on opacity {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutQuint
        }
    }

    Repeater {
        model: 4

        // 0 = top-left, 1 = top-right, 2 = bottom-left, 3 = bottom-right
        Item {
            id: corner

            required property int index
            readonly property bool onRight: index === 1 || index === 3
            readonly property bool onBottom: index >= 2

            x: onRight ? root.width - root.arm : 0
            y: onBottom ? root.height - root.arm : 0
            width: root.arm
            height: root.arm

            Rectangle {
                width: root.arm
                height: root.thickness
                y: corner.onBottom ? root.arm - root.thickness : 0
                color: root.bracketColor
            }

            Rectangle {
                width: root.thickness
                height: root.arm
                x: corner.onRight ? root.arm - root.thickness : 0
                color: root.bracketColor
            }
        }
    }
}
