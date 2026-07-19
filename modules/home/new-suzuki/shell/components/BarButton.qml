pragma ComponentBehavior: Bound
import QtQuick
import qs.config

Rectangle {
    id: root

    property bool active: false
    property Item contentItem: null
    readonly property bool hovered: mouseArea.containsMouse

    signal clicked
    signal rightClicked

    implicitWidth: (contentItem?.implicitWidth ?? 0) + (Config.padding * 2)
    implicitHeight: Config.barHeight - 10
    // Square. Both poles of the design language are rectilinear — the pill
    // was the blande.
    radius: Config.radius

    color: (active || hovered) ? Config.surface1Color : Qt.alpha(Config.surface1Color, 0)

    Behavior on color {
        ColorAnimation {
            duration: Config.animDuration
        }
    }

    CornerBrackets {
        active: root.hovered || root.active
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else
                root.clicked();
        }
    }
}
