pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.config
import "../../components/"

PanelWindow {
    id: root

    // Always visible while the outer Loader (shell.qml) keeps this component alive.
    // The outer Loader uses a keepAlive timer so exit animations finish before
    // this PanelWindow is destroyed.
    visible: true

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Own namespace: hyprland layerrule gives this surface REAL backdrop
    // blur (see new-suzuki default.nix) — the panel is genuine glass over
    // the wallpaper field, not a painted imitation.
    WlrLayershell.namespace: "qs_launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Release exclusive keyboard grab as soon as the service hides, so the exit
    // animation doesn't block other windows from receiving input.
    WlrLayershell.keyboardFocus: LauncherService.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    color: "transparent"

    function hide() {
        // Move focus away from the TextField before hiding to avoid the Wayland
        // text-input warning: "Try to disable surface X with focusing surface Y"
        launcherPanel.forceActiveFocus();
        LauncherService.hide();
    }

    // Dim vignette behind the panel — pulls the desktop back while the
    // picker is up; fades with the popup.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: LauncherService.visible ? 0.35 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuint
            }
        }
    }

    // Click on background closes
    MouseArea {
        anchors.fill: parent
        onClicked: root.hide()
    }

    // AnimatedPopup drives the entry/exit scale+opacity animation.
    // The content Rectangle is rebuilt fresh every open because the outer
    // Loader (shell.qml) destroys and recreates the whole window.
    AnimatedPopup {
        id: launcherAnim
        anchors.centerIn: parent
        width: 520
        // Follow the content's animated height so the popup frame matches exactly
        height: launcherPanel.height
        shown: LauncherService.visible

        Rectangle {
            id: launcherPanel
            width: 520

            // Dynamic height based on content
            property int listHeight: Math.min(420, appList.contentHeight + 12)
            property int totalHeight: listHeight + searchBar.height + 32

            height: totalHeight
            radius: Config.radiusLarge
            // Deep translucency — the compositor blur underneath carries
            // legibility, so the panel can be genuinely see-through.
            color: Qt.alpha(Config.backgroundColor, 0.62)
            border.color: Qt.alpha(Config.accentColor, 0.25)
            border.width: 1

            // Glass sheen: a whisper of light falling off from the top edge.
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

            // Smooth height animation as the app list grows/shrinks
            Behavior on height {
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutCubic
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Config.spacing + 4
                spacing: Config.spacing

                // Search bar
                Rectangle {
                    id: searchBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: Config.radius
                    color: Qt.alpha(Config.surface0Color, 0.55)

                    // Focus underline: accent sweeps in from the left.
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        height: 2
                        width: searchInput.activeFocus ? parent.width : 0
                        color: Config.accentColor

                        Behavior on width {
                            NumberAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuint
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Config.spacing + 6
                        anchors.rightMargin: Config.spacing + 6
                        spacing: Config.spacing

                        Text {
                            text: ""
                            font.family: Config.font
                            font.pixelSize: Config.fontSizeNormal
                            color: searchInput.activeFocus ? Config.accentColor : Config.subtextColor

                            Behavior on color {
                                ColorAnimation {
                                    duration: Config.animDurationShort
                                }
                            }
                        }

                        TextField {
                            id: searchInput
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            color: Config.textColor
                            font.family: Config.font
                            font.pixelSize: Config.fontSizeLarge
                            verticalAlignment: TextInput.AlignVCenter
                            selectByMouse: true
                            placeholderText: "Search apps..."
                            placeholderTextColor: Config.mutedColor
                            background: null

                            onTextChanged: LauncherService.query = text

                            Keys.onEscapePressed: root.hide()

                            Keys.onReturnPressed: {
                                launcherPanel.forceActiveFocus();
                                LauncherService.launchSelected();
                            }

                            Keys.onUpPressed: {
                                if (LauncherService.selectedIndex > 0)
                                    LauncherService.selectedIndex--;
                            }

                            Keys.onDownPressed: {
                                if (LauncherService.selectedIndex < LauncherService.filteredApps.length - 1)
                                    LauncherService.selectedIndex++;
                            }

                            Keys.onTabPressed: event => {
                                if (LauncherService.selectedIndex < LauncherService.filteredApps.length - 1)
                                    LauncherService.selectedIndex++;
                                event.accepted = true;
                            }

                            Keys.onPressed: event => {
                                const isBacktab = event.key === Qt.Key_Backtab;
                                const isShiftTab = event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier);

                                if (isBacktab || isShiftTab) {
                                    if (LauncherService.selectedIndex > 0)
                                        LauncherService.selectedIndex--;
                                    event.accepted = true;
                                }
                            }

                            Component.onCompleted: {
                                LauncherService.query = "";
                                LauncherService.selectedIndex = 0;
                                Qt.callLater(() => {
                                    if (LauncherService.visible) {
                                        forceActiveFocus();
                                    }
                                });
                            }
                        }

                        // Results counter
                        Rectangle {
                            visible: LauncherService.filteredApps.length > 0
                            Layout.preferredWidth: countText.implicitWidth + 12
                            Layout.preferredHeight: 22
                            radius: height / 2
                            color: Config.surface1Color

                            Text {
                                id: countText
                                anchors.centerIn: parent
                                text: LauncherService.filteredApps.length
                                font.family: Config.font
                                font.pixelSize: Config.fontSizeSmall
                                color: Config.subtextColor
                            }
                        }

                        // Clear button
                        Rectangle {
                            visible: searchInput.text
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: height / 2
                            color: clearMouse.containsMouse ? Config.surface2Color : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: Config.animDurationShort
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                font.family: Config.font
                                font.pixelSize: Config.fontSizeSmall
                                color: Config.subtextColor
                            }

                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchInput.text = "";
                                    searchInput.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                // Separator
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Config.surface1Color
                }

                // App list
                ListView {
                    id: appList
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    clip: true
                    spacing: 4
                    model: LauncherService.filteredApps
                    currentIndex: LauncherService.selectedIndex

                    // Add/remove item animations
                    add: Transition {
                        NumberAnimation {
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: Config.animDurationShort
                        }
                        NumberAnimation {
                            property: "scale"
                            from: 0.8
                            to: 1
                            duration: Config.animDurationShort
                            easing.type: Easing.OutBack
                        }
                    }

                    remove: Transition {
                        NumberAnimation {
                            property: "opacity"
                            to: 0
                            duration: Config.animDurationShort
                        }
                        NumberAnimation {
                            property: "scale"
                            to: 0.8
                            duration: Config.animDurationShort
                        }
                    }

                    displaced: Transition {
                        NumberAnimation {
                            property: "y"
                            duration: Config.animDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    // Custom highlight: accent glass sliding between rows,
                    // with a rail on the left edge and brackets at the
                    // facility register.
                    highlightFollowsCurrentItem: false
                    highlight: Item {
                        width: appList.width
                        height: 56

                        y: appList.currentItem ? appList.currentItem.y : 0

                        Behavior on y {
                            NumberAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuint
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Config.radius
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.alpha(Config.accentColor, 0.16) }
                                GradientStop { position: 1.0; color: Qt.alpha(Config.accentColor, 0.04) }
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: parent.height - 16
                            color: Config.accentColor
                        }

                        CornerBrackets {
                            active: true
                        }
                    }

                    delegate: Item {
                        id: delegateItem
                        required property int index
                        required property var modelData

                        width: appList.width
                        height: 56

                        property bool isSelected: index === LauncherService.selectedIndex
                        property bool isHovered: delegateMouse.containsMouse

                        // Cascade entrance: each visible row fades and slides
                        // in with an index-staggered delay. The outer Loader
                        // recreates the window per open, so this fires fresh
                        // every time the picker appears.
                        opacity: 0
                        transform: Translate {
                            id: slide
                            x: -16
                        }

                        SequentialAnimation {
                            id: cascade
                            running: true

                            PauseAnimation {
                                duration: Math.min(delegateItem.index, 10) * 24
                            }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: delegateItem
                                    property: "opacity"
                                    to: 1
                                    duration: Config.animDuration
                                    easing.type: Easing.OutQuint
                                }
                                NumberAnimation {
                                    target: slide
                                    property: "x"
                                    to: 0
                                    duration: Config.animDuration
                                    easing.type: Easing.OutQuint
                                }
                            }
                        }

                        // Hover glass under everything but the highlight
                        Rectangle {
                            anchors.fill: parent
                            radius: Config.radius
                            color: Qt.alpha(Config.surface1Color, delegateItem.isHovered && !delegateItem.isSelected ? 0.45 : 0)

                            Behavior on color {
                                ColorAnimation {
                                    duration: Config.animDurationShort
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 14

                            // Icon tile — translucent, pops on selection
                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                radius: Config.radiusSmall
                                color: Qt.alpha(Config.surface0Color, 0.5)
                                scale: delegateItem.isSelected ? 1.1 : 1.0

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Config.animDurationShort
                                        easing.type: Easing.OutBack
                                    }
                                }

                                Image {
                                    anchors.centerIn: parent
                                    width: 32
                                    height: 32
                                    source: {
                                        const icon = delegateItem.modelData?.icon ?? "";
                                        return icon ? "image://icon/" + icon : "image://icon/application-x-executable";
                                    }
                                    sourceSize: Qt.size(32, 32)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }
                            }

                            // Texts
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: delegateItem.modelData?.name ?? ""
                                    color: delegateItem.isSelected ? Config.textColor : Config.textColor
                                    font.family: Config.font
                                    font.pixelSize: Config.fontSizeNormal
                                    font.weight: delegateItem.isSelected ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: delegateItem.modelData?.comment || delegateItem.modelData?.genericName || ""
                                    color: Config.subtextColor
                                    font.family: Config.font
                                    font.pixelSize: Config.fontSizeSmall
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }
                            }

                            // Selection indicator
                            Text {
                                visible: delegateItem.isSelected
                                text: "󰌑"
                                color: Config.accentColor
                                font.family: Config.font
                                font.pixelSize: Config.fontSizeSmall
                            }
                        }

                        MouseArea {
                            id: delegateMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (delegateItem.isSelected) {
                                    // Second click: opens the app
                                    launcherPanel.forceActiveFocus();
                                    LauncherService.launch(delegateItem.modelData);
                                } else {
                                    // First click: selects
                                    LauncherService.selectedIndex = delegateItem.index;
                                }
                            }
                        }
                    }

                    // Empty state
                    Column {
                        anchors.centerIn: parent
                        spacing: Config.spacing
                        visible: appList.count === 0
                        opacity: visible ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Config.animDurationShort
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: LauncherService.query ? "󰅖" : "󰑓"
                            font.family: Config.font
                            font.pixelSize: Config.fontSizeIconLarge
                            color: Config.mutedColor

                            RotationAnimator on rotation {
                                from: 0
                                to: 360
                                duration: 1000
                                loops: Animation.Infinite
                                running: !LauncherService.query && appList.count === 0
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: LauncherService.query ? "No results" : "Loading..."
                            color: Config.subtextColor
                            font.family: Config.font
                            font.pixelSize: Config.fontSizeNormal
                        }
                    }

                    // Auto-scroll when navigating (no animation to avoid affecting mouse)
                    onCurrentIndexChanged: {
                        positionViewAtIndex(currentIndex, ListView.Contain);
                    }

                    // Smooth scroll
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded

                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: Config.surface2Color
                            opacity: parent.active ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Config.animDurationShort
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Focus grab — deactivated as soon as the service hides (not tied to window
    // visibility) so the exit animation doesn't keep stealing keyboard focus.
    HyprlandFocusGrab {
        windows: [root]
        active: LauncherService.visible
        onCleared: {
            if (LauncherService.visible)
                root.hide();
        }
    }
}
