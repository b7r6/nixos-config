pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

Singleton {
    id: root

    function getState(path, fallback) {
        return StateService.get(path, fallback);
    }

    // ========================================================================
    // PALETTE — from ThemeService (palette.json)
    // ========================================================================
    readonly property color backgroundColor: ThemeService.color("surface", "#191c20")
    readonly property real backgroundOpacity: ThemeService.aestheticProp("opacity", 0.9)
    readonly property color backgroundTransparentColor: Qt.alpha(backgroundColor, backgroundOpacity)
    readonly property color surface0Color: ThemeService.color("paper", backgroundColor)
    readonly property color surface1Color: ThemeService.color("border", "#2a3039")
    readonly property color surface2Color: ThemeService.color("ink-faint", "#3a424f")
    readonly property color surface3Color: ThemeService.color("ink-ghost", "#283039")

    readonly property color textColor: ThemeService.color("ink", "#d8e0e7")
    readonly property color textReverseColor: ThemeService.color("surface", "#191c20")
    readonly property color subtextColor: ThemeService.color("ink-muted", "#6b7689")
    readonly property color subtextReverseColor: ThemeService.color("ink-faint", "#3a424f")

    readonly property color accentColor: ThemeService.color("accent", "#54aeff")
    readonly property color successColor: ThemeService.color("success", "#218bff")
    readonly property color warningColor: ThemeService.color("warn", "#54aeff")
    readonly property color errorColor: ThemeService.color("error", "#f85149")

    readonly property color mutedColor: ThemeService.color("ink-faint", "#3a424f")
    readonly property color greyBlueColor: ThemeService.color("border", "#2a3039")
    readonly property color blueDarkColor: ThemeService.color("surface", "#191c20")

    // ========================================================================
    // AESTHETIC PROFILE — from ThemeService (aesthetic properties)
    // ========================================================================
    readonly property string textCase: ThemeService.aestheticProp("textCase", "lowercase")
    readonly property bool uppercase: textCase === "uppercase"
    readonly property int fontCapitalization: uppercase ? Font.AllUppercase : Font.MixedCase

    readonly property string labelPrefix: ThemeService.aestheticProp("label-prefix", "")

    readonly property string kerning: ThemeService.aestheticProp("kerning", "relaxed")
    readonly property real letterSpacing: kerning === "tight" ? -0.5 : (kerning === "normal" ? 0.0 : 0.5)

    // ========================================================================
    // GEOMETRY — driven by aesthetic profile
    // ========================================================================
    readonly property int barHeight: getState("bar.height", 34)
    readonly property bool barAutoHide: getState("bar.autoHide", false)

    readonly property int radiusSmall: 0
    readonly property int radius: 0
    readonly property int radiusLarge: 0

    readonly property int spacing: ThemeService.aestheticProp("gaps-inner", 6)
    readonly property int padding: ThemeService.aestheticProp("gaps-outer", 12)

    // ========================================================================
    // REGISTER AXIS — the affluent ↔ facility scalars (wintermute tokens)
    // ========================================================================
    readonly property real register: ThemeService.register
    readonly property bool facility: ThemeService.facility
    readonly property real bracketScale: ThemeService.tokens.bracketSize ?? 1.0
    readonly property real telemetryDensity: ThemeService.tokens.telemetryDensity ?? 0.0
    readonly property real glassBlur: ThemeService.tokens.glassBlur ?? 0.0

    // ========================================================================
    // TYPOGRAPHY
    // ========================================================================
    readonly property string font: getState("typography.font", "Berkeley Mono")

    // Display face flips with the register: Azonix UPPERCASE at the facility
    // pole, Cormorant Garamond lowercase at the affluent pole.
    readonly property string displayFont: facility ? "Azonix" : "Cormorant Garamond"

    readonly property int fontSizeSmall: getState("typography.sizeSmall", 12)
    readonly property int fontSizeNormal: getState("typography.sizeNormal", 13)
    readonly property int fontSizeLarge: getState("typography.sizeLarge", 15)
    readonly property int fontSizeIconSmall: getState("typography.iconSmall", 16)
    readonly property int fontSizeIcon: getState("typography.icon", 20)
    readonly property int fontSizeIconLarge: getState("typography.iconLarge", 26)

    // ========================================================================
    // ANIMATIONS — driven by aesthetic profile
    // ========================================================================
    readonly property int animDuration: ThemeService.aestheticProp("anim-duration", 400)
    readonly property int animDurationShort: Math.round(animDuration * 0.4)
    readonly property int animDurationLong: Math.round(animDuration * 1.5)

    readonly property string animEasing: ThemeService.aestheticProp("anim-easing", "expo_out")
    readonly property int animPopupEasing: animEasing === "step" ? Easing.Linear : Easing.OutQuint
    readonly property real animPopupFromScale: 0.97

    readonly property string entranceDirection: ThemeService.aestheticProp("entrance-direction", "fade-up")
    readonly property int entranceOffset: ThemeService.aestheticProp("entrance-offset", 10)

    readonly property bool screenshotAnimations: getState("animations.screenshot", true)

    // ========================================================================
    // SCANLINES — idle-triggered, only in facility mode
    // ========================================================================
    readonly property bool scanlinesEnabled: ThemeService.aestheticProp("scanlines", false)
    readonly property int scanlineIdleSeconds: ThemeService.aestheticProp("scanline-idle", 0)

    // ========================================================================
    // BORDERS & SHADOWS — driven by aesthetic profile
    // ========================================================================
    readonly property int borderWeight: ThemeService.aestheticProp("border-weight", 1)
    readonly property real borderAlpha: ThemeService.aestheticProp("border-alpha", 0.13)
    readonly property bool shadowEnabled: ThemeService.aestheticProp("shadow-enabled", true)
    readonly property real shadowAlpha: ThemeService.aestheticProp("shadow-alpha", 0.08)

    // ========================================================================
    // GRAIN — driven by aesthetic profile
    // ========================================================================
    readonly property real grainOpacity: ThemeService.aestheticProp("grain", 0.05)
    readonly property bool grainWarm: ThemeService.aestheticProp("grain-warm", false)

    // ========================================================================
    // WALLPAPER
    // ========================================================================
    readonly property bool dynamicWallpaper: getState("wallpaper.dynamic", false)

    // ========================================================================
    // NOTIFICATIONS
    // ========================================================================
    readonly property int notifWidth: getState("notifications.width", 350)
    readonly property int notifImageSize: getState("notifications.imageSize", 40)
    readonly property int notifTimeout: getState("notifications.timeout", 5000)
    readonly property int notifSpacing: getState("notifications.spacing", 10)
}
