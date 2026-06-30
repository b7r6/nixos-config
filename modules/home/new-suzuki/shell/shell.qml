pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services
import qs.config
import "./modules/bar/"
import "./modules/power/"
import "./modules/screenshot/"
import "./components/"
import "./widgets/"

ShellRoot {
    id: root

    property bool screenshotActive: false
    property bool _idleReady: IdleService.caffeineEnabled

    // Ensure GrainOverlay is always present
    property QtObject theme: ThemeService

    // ── Scanline Overlay (idle-triggered in facility mode) ─────────────────
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; left: true; right: true; bottom: true }
            exclusiveZone: -1
            color: "transparent"
            focusable: false
            aboveWindows: false
            WlrLayershell.namespace: "qs_scanlines"
            WlrLayershell.layer: WlrLayer.Overlay

            ScanlineOverlay {
                anchors.fill: parent
            }
        }
    }

    // ── Idle Monitors ──────────────────────────────────────────────────────
    IdleMonitor {
        timeout: IdleService.lockTimeout
        enabled: !IdleService.caffeineEnabled && !IdleService.mediaPlaying && !IdleService.systemInhibited && !StateService.isLoading
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) IdleService.lock()
    }

    IdleMonitor {
        timeout: IdleService.dpmsTimeout
        enabled: !IdleService.caffeineEnabled && !IdleService.mediaPlaying && !IdleService.systemInhibited && IdleService.dpmsEnabled && !StateService.isLoading
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle) IdleService.dpmsOff()
            else IdleService.dpmsOn()
        }
    }

    // ── Bar ────────────────────────────────────────────────────────────────
    Bar {}

    // ── Notifications ──────────────────────────────────────────────────────
    Loader {
        active: NotificationService.activePopupCount > 0 || NotificationService.popups.length > 0
        source: "./modules/notifications/NotificationOverlay.qml"
    }

    // ── Lock Screen ────────────────────────────────────────────────────────
    Loader {
        active: LockService.locked
        source: "./modules/lock/LockScreen.qml"
    }

    // ── Power Overlay ──────────────────────────────────────────────────────
    Loader {
        active: PowerService.overlayVisible
        source: "./modules/power/PowerOverlay.qml"
    }

    // ── Screenshot Manager ─────────────────────────────────────────────────
    Loader {
        id: screenshotLoader
        active: root.screenshotActive
        source: "./modules/screenshot/ScreenshotManager.qml"

        onStatusChanged: if (status === Loader.Ready) screenshotLoader.item.startCapture()

        Connections {
            target: screenshotLoader.item
            enabled: screenshotLoader.status === Loader.Ready
            function onActiveChanged() {
                if (screenshotLoader.item && !screenshotLoader.item.active)
                    root.screenshotActive = false
            }
        }
    }

    // ── Launcher ───────────────────────────────────────────────────────────
    Loader {
        id: launcherLoader
        property bool _shown: LauncherService.visible
        property bool _keepAlive: false
        active: _shown || _keepAlive
        source: "./modules/launcher/Launcher.qml"

        on_ShownChanged: {
            if (!_shown) {
                _keepAlive = true
                launcherExitTimer.restart()
            }
        }

        Timer {
            id: launcherExitTimer
            interval: Config.animDurationLong
            onTriggered: launcherLoader._keepAlive = false
        }
    }

    // ── OSD ────────────────────────────────────────────────────────────────
    Loader {
        active: OsdService.visible
        source: "./modules/osd/OsdOverlay.qml"
    }

    // ── Wallpaper Picker ───────────────────────────────────────────────────
    Loader {
        id: wallpaperLoader
        property bool _shown: WallpaperService.pickerVisible
        property bool _keepAlive: false
        active: _shown || _keepAlive
        source: "./modules/wallpaper/WallpaperPicker.qml"

        on_ShownChanged: {
            if (!_shown) {
                _keepAlive = true
                wallpaperExitTimer.restart()
            }
        }

        Timer {
            id: wallpaperExitTimer
            interval: Config.animDurationLong
            onTriggered: wallpaperLoader._keepAlive = false
        }
    }

    // ── Clipboard History ──────────────────────────────────────────────────
    Loader {
        id: clipboardLoader
        property bool _shown: ClipboardService.visible
        property bool _keepAlive: false
        active: _shown || _keepAlive
        source: "./modules/clipboard/ClipboardHistory.qml"

        on_ShownChanged: {
            if (!_shown) {
                _keepAlive = true
                clipboardExitTimer.restart()
            }
        }

        Timer {
            id: clipboardExitTimer
            interval: Config.animDurationLong
            onTriggered: clipboardLoader._keepAlive = false
        }
    }

    // ── Keybinds Overlay ───────────────────────────────────────────────────
    Loader {
        id: keybindsLoader
        active: false
        source: "./modules/keybinds/KeybindsOverlay.qml"

        function toggle() {
            if (active && item) {
                item.hide()
                active = false
            } else {
                active = true
            }
        }

        Connections {
            target: keybindsLoader.item
            enabled: keybindsLoader.status === Loader.Ready
            function onShowingChanged() {
                if (keybindsLoader.item && !keybindsLoader.item.showing)
                    keybindsLoader.active = false
            }
        }

        onStatusChanged: if (status === Loader.Ready && item) item.showing = true
    }

    // ── Preset Control Panel ───────────────────────────────────────────────
    Loader {
        id: controlPanelLoader
        active: false
        source: "./widgets/PresetControlPanel.qml"

        function toggle() {
            if (active && item) {
                item.hide()
                active = false
            } else {
                active = true
            }
        }

        Connections {
            target: controlPanelLoader.item
            enabled: controlPanelLoader.status === Loader.Ready
            function onShownChanged() {
                if (controlPanelLoader.item && !controlPanelLoader.item.shown)
                    controlPanelLoader.active = false
            }
        }

        onStatusChanged: if (status === Loader.Ready && item) item.show()
    }

    // ── Global Shortcuts ───────────────────────────────────────────────────
    GlobalShortcut {
        name: "take_screenshot"
        description: "Screenshot capture"
        onPressed: root.screenshotActive = true
    }

    GlobalShortcut {
        name: "power_menu"
        description: "Power menu"
        onPressed: PowerService.showOverlay()
    }

    GlobalShortcut {
        name: "app_launcher"
        description: "App Launcher"
        onPressed: LauncherService.show()
    }

    GlobalShortcut {
        name: "volume_up"
        description: "Increase volume"
        onPressed: {
            AudioService.increaseVolume()
            OsdService.showVolume(AudioService.volume, AudioService.muted)
        }
    }

    GlobalShortcut {
        name: "volume_down"
        description: "Decrease volume"
        onPressed: {
            AudioService.decreaseVolume()
            OsdService.showVolume(AudioService.volume, AudioService.muted)
        }
    }

    GlobalShortcut {
        name: "volume_mute"
        description: "Mute volume"
        onPressed: {
            AudioService.toggleMute()
            OsdService.showVolume(AudioService.volume, AudioService.muted)
        }
    }

    GlobalShortcut {
        name: "brightness_up"
        description: "Increase brightness"
        onPressed: {
            BrightnessService.increaseBrightness()
            OsdService.showBrightness(BrightnessService.brightness)
        }
    }

    GlobalShortcut {
        name: "brightness_down"
        description: "Decrease brightness"
        onPressed: {
            BrightnessService.decreaseBrightness()
            OsdService.showBrightness(BrightnessService.brightness)
        }
    }

    GlobalShortcut {
        name: "wallpaper_picker"
        description: "Wallpaper picker"
        onPressed: WallpaperService.toggle()
    }

    GlobalShortcut {
        name: "clipboard_history"
        description: "Clipboard history"
        onPressed: ClipboardService.toggle()
    }

    GlobalShortcut {
        name: "lock_screen"
        description: "Lock screen"
        onPressed: IdleService.lock()
    }

    GlobalShortcut {
        name: "keybinds_help"
        description: "Keybinds help"
        onPressed: keybindsLoader.toggle()
    }

    GlobalShortcut {
        name: "control_panel"
        description: "Preset control panel"
        onPressed: controlPanelLoader.toggle()
    }
}
