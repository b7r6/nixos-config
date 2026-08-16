pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.config

Row {
    spacing: 2

    Text {
        id: hhmm
        text: TimeService.format("hh:mm")

        // The clock wears the display face: Azonix at the facility pole,
        // Cormorant Garamond at the affluent pole.
        font.family: Config.displayFont
        font.pixelSize: Config.facility ? Config.fontSizeNormal : Config.fontSizeLarge
        font.bold: !Config.facility
        font.letterSpacing: Config.facility ? 1.5 : 0

        color: Config.textColor
    }

    // Console seconds — facility only, ticking in the muted register.
    Text {
        visible: Config.facility
        text: ":" + TimeService.format("ss")
        anchors.baseline: hhmm.baseline
        font.family: Config.font
        font.pixelSize: Config.fontSizeSmall
        color: Config.mutedColor
    }
}
