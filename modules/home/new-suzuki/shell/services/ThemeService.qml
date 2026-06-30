pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    // ========================================================================
    // PALETTE + AESTHETIC — loaded from palette.json via FileView
    // ========================================================================

    property var palette: ({
        "ink": "#d8e0e7",
        "ink-muted": "#6b7689",
        "ink-faint": "#3a424f",
        "ink-ghost": "#2a3039",
        "surface": "#191c20",
        "paper": "#1f232a",
        "border": "#2a3039",
        "accent": "#54aeff",
        "accent-d": "#80ccff",
        "glass-edge": "#2154aeff",
        "glass-fill": "#801f232a",
        "glass-fill-hover": "#992a3039",
        "shadow": "#14191c20",
        "success": "#218bff",
        "warn": "#54aeff",
        "error": "#f85149",
        "font-name": "Berkeley Mono",
        "label": "razorgirl"
    })

    // Aesthetic profile — non-color properties from the preset
    property var aesthetic: ({
        "textCase": "lowercase",
        "gaps-inner": 6,
        "gaps-outer": 12,
        "kerning": "relaxed",
        "anim-duration": 400,
        "anim-easing": "expo_out",
        "entrance-direction": "fade-up",
        "entrance-offset": 10,
        "scanlines": false,
        "scanline-idle": 0,
        "opacity": 0.9,
        "border-weight": 1,
        "border-alpha": 0.13,
        "shadow-enabled": true,
        "shadow-alpha": 0.08,
        "grain": 0.05,
        "grain-warm": false,
        "label-prefix": ""
    })

    property real polarity: 0.0
    property real luminance: 1.0
    property string currentThemeName: "razorgirl"
    property string colorScheme: "dark"
    readonly property bool isDarkMode: colorScheme === "dark"
    property var availableThemes: []
    property var displayThemes: availableThemes
    property var themePreviews: ({})
    property string themeMode: "preset"
    readonly property bool isAutoMode: false

    function color(key, fallback) {
        return palette[key] ?? fallback;
    }

    function aestheticProp(key, fallback) {
        return aesthetic[key] ?? fallback;
    }

    function applyTheme(themeName) {
        applyThemeProc.command = ["theme-switch", themeName];
        applyThemeProc.running = true;
    }

    function setPresetMode(themeName) {
        themeMode = "preset";
        applyTheme(themeName);
    }

    function setAutoMode() {}

    function setColorScheme(scheme) {
        colorScheme = scheme;
    }

    function listThemes() {
        listThemesProc._collected = [];
        listThemesProc.running = true;
    }

    function loadPreviews() {}

    Component.onCompleted: {
        listThemes();
    }

    // ========================================================================
    // FileView — watches palette.json for live theme switching
    // ========================================================================

    FileView {
        id: paletteWatcher
        path: Quickshell.shellDir + "/palette.json"
        watchChanges: true
        preload: true

        onLoaded: root._loadPalette(text())
        onFileChanged: root._loadPalette(text())
    }

    function _loadPalette(text) {
        try {
            var data = JSON.parse(text);
            root.palette = data;
            root.currentThemeName = data.label || "default";
            root.polarity = data.polarity ?? 0.0;
            root.luminance = data.luminance ?? 1.0;

            // Load aesthetic profile if present
            if (data.aesthetic) {
                root.aesthetic = data.aesthetic;
            }

            // Detect light/dark from surface luminance
            var surface = data.surface || "#191c20";
            var r = parseInt(surface.substr(1, 2), 16);
            var g = parseInt(surface.substr(3, 2), 16);
            var b = parseInt(surface.substr(5, 2), 16);
            var lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
            root.colorScheme = lum > 0.5 ? "light" : "dark";

            console.log("[Theme] Preset loaded:", root.currentThemeName,
                        "polarity:", root.polarity,
                        "luminance:", root.luminance);
        } catch (e) {
            console.error("[Theme] Failed to parse palette.json:", e);
        }
    }

    // ========================================================================
    // Processes
    // ========================================================================

    Process {
        id: applyThemeProc
        stderr: SplitParser {
            onRead: data => console.error("[Theme] " + data)
        }
    }

    Process {
        id: listThemesProc
        command: ["bash", "-c", "ls -1 " + Quickshell.shellDir + "/themes/*.json 2>/dev/null | sed 's|.*/||;s|\\.json$||' | sort"]
        property var _collected: []

        stdout: SplitParser {
            onRead: data => {
                var name = data.trim();
                if (name)
                    listThemesProc._collected.push(name);
            }
        }

        onExited: {
            root.availableThemes = listThemesProc._collected;
            console.log("[Theme] Available presets:", root.availableThemes.join(", "));
        }
    }
}
