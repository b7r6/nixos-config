pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.config

Text {
    text: TimeService.format("hh:mm")

    // The clock wears the display face: Azonix at the facility pole,
    // Cormorant Garamond at the affluent pole.
    font.family: Config.displayFont
    font.pixelSize: Config.facility ? Config.fontSizeNormal : Config.fontSizeLarge
    font.bold: !Config.facility
    font.letterSpacing: Config.facility ? 1.5 : 0

    color: Config.textColor
}
