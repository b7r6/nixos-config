pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// ============================================================================
// ThemeService — the wintermute consumer.
//
// The theme is a 4-vector (heroHue × axisHue × luminance × register) owned by
// the wintermute reconciler (continuity: src/apps/wintermute). Its durable
// output is $XDG_STATE_HOME/wintermute/theme.json — generation-stamped base16
// palette + register-axis effect tokens, atomically replaced. Nix seeds the
// same file at activation; a running daemon overwrites it live. This service
// derives the shell's semantic palette + aesthetic profile from that ONE
// contract, so every component (via Config.qml) restyles on file change.
//
// Writes go the other way: applyTheme/commitPad spawn `wintermute preset|set`,
// which bumps the generation fence in theme.state; the daemon broadcasts and
// rewrites theme.json; the FileView round-trip settles our properties.
// ============================================================================

Singleton {
    id: root

    // ── The wintermute vector (read-side mirror) ────────────────────────────
    property int generation: 0
    property real register: 1.0        // 0 affluent … 1 facility
    property bool facility: true
    property var base16: ({})
    property var tokens: ({
        "scanline": 1.0,
        "bracketSize": 1.0,
        "telemetryDensity": 1.0,
        "glassBlur": 0.0,
        "bloom": 0.0,
        "grainOpacity": 0.0
    })

    // ── Semantic palette (derived; razorgirl-carbon defaults pre-load) ──────
    property var palette: ({
        "ink": "#c1cedc",
        "ink-muted": "#6c7a89",
        "ink-faint": "#3d4752",
        "ink-ghost": "#283039",
        "surface": "#191c1f",
        "paper": "#1e2329",
        "border": "#283039",
        "accent": "#54aeff",
        "accent-d": "#80d2ff",
        "glass-edge": "#2154aeff",
        "glass-fill": "#801e2329",
        "glass-fill-hover": "#99283039",
        "shadow": "#14191c1f",
        "success": "#2496ff",
        "warn": "#54aeff",
        "error": "#f85149",
        "font-name": "Berkeley Mono",
        "label": "razorgirl"
    })

    // ── Aesthetic profile (derived from the register axis) ──────────────────
    property var aesthetic: ({
        "textCase": "uppercase",
        "gaps-inner": 6,
        "gaps-outer": 12,
        "kerning": "tight",
        "anim-duration": 300,
        "anim-easing": "expo_out",
        "entrance-direction": "fade-up",
        "entrance-offset": 8,
        "scanlines": true,
        "scanline-idle": 1.0,
        "opacity": 0.9,
        "border-weight": 1,
        "border-alpha": 0.18,
        "shadow-enabled": false,
        "shadow-alpha": 0.04,
        "grain": 0.0,
        "grain-warm": false,
        "label-prefix": ""
    })

    // ── Legacy surface consumed by widgets ──────────────────────────────────
    // The preset pad's axes: polarity = the REGISTER axis (x), luminance =
    // the day↔night axis (y, 0 = day … 1 = night).
    property real polarity: 1.0
    property real luminance: 1.0
    property string currentThemeName: "razorgirl"
    property string colorScheme: "dark"
    readonly property bool isDarkMode: colorScheme === "dark"
    property var availableThemes: ["villa-straylight", "razorgirl", "tessier", "bioptic"]
    property var displayThemes: availableThemes
    property var themePreviews: ({})
    property string themeMode: "preset"
    readonly property bool isAutoMode: false

    readonly property string stateHome: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg && xdg.length > 0) ? xdg : Quickshell.env("HOME") + "/.local/state";
    }

    // The ONE theme selector is the orbital pad (PresetControlPanel);
    // every entry point (bar switcher, quickSettings tile, keybind) opens
    // it through this signal — shell.qml owns the loader.
    signal togglePanel

    function color(key, fallback) {
        return palette[key] ?? fallback;
    }

    function aestheticProp(key, fallback) {
        return aesthetic[key] ?? fallback;
    }

    // ── Write side: everything goes through the wintermute CLI ──────────────

    function applyTheme(themeName) {
        wintermuteProc.command = ["wintermute", "preset", themeName];
        wintermuteProc.running = true;
    }

    function setPresetMode(themeName) {
        themeMode = "preset";
        applyTheme(themeName);
    }

    // The orbital pad commit: x = register, y = luminance ladder. y sweeps
    // the full black/white level range — day levels above the fold, night
    // levels below, matching the two-axis model.
    function commitPad(x, y) {
        const reg = Math.round(Math.max(0, Math.min(1, x)) * 1000);
        let pol, level;
        if (y < 0.5) {
            pol = "light";
            level = y < 0.17 ? "tessier" : (y < 0.33 ? "neoform" : "ghost");
        } else {
            pol = "dark";
            level = y < 0.63 ? "github" : (y < 0.78 ? "carbon" : (y < 0.9 ? "night" : "deep"));
        }
        wintermuteProc.command = ["wintermute", "set",
            "register", String(reg), "polarity", pol, "level", level];
        wintermuteProc.running = true;
    }

    function setAutoMode() {}
    function setColorScheme(scheme) { colorScheme = scheme; }
    function listThemes() {}
    function loadPreviews() {}

    // ── Derivation ──────────────────────────────────────────────────────────

    function _alpha(hex, aa) {
        // #rrggbb → #aarrggbb (Qt alpha-first)
        return "#" + aa + hex.substring(1);
    }

    function _load(text) {
        try {
            const d = JSON.parse(text);
            const p = d.palette;
            if (!p || !p.base00)
                throw new Error("no palette in theme.json");

            const light = d.polarity === "light";
            const reg = d.register ?? 1.0;
            const fac = d.facility ?? (reg >= 0.5);
            const t = d.tokens ?? root.tokens;

            root.base16 = p;
            root.generation = d.generation ?? 0;
            root.register = reg;
            root.facility = fac;
            root.tokens = t;

            root.palette = {
                "ink": p.base05,
                "ink-muted": p.base04,
                "ink-faint": p.base03,
                "ink-ghost": p.base02,
                "surface": p.base00,
                "paper": p.base01,
                "border": p.base02,
                "accent": p.base0A,
                "accent-d": p.base09,
                "glass-edge": _alpha(p.base0A, "21"),
                "glass-fill": _alpha(p.base01, "80"),
                "glass-fill-hover": _alpha(p.base02, "99"),
                "shadow": _alpha(p.base00, "14"),
                "success": p.base0B,
                "warn": p.base0A,
                "error": light ? "#c0392b" : "#f85149",
                "font-name": d.fontName ?? "Berkeley Mono",
                "label": d.slug ?? "wintermute"
            };

            // Register axis → effects + typography. Continuous scalars ride
            // the tokens; the discrete case/kerning switch flips with
            // `facility` at the midpoint.
            root.aesthetic = {
                "textCase": fac ? "uppercase" : "lowercase",
                "gaps-inner": fac ? 6 : 8,
                "gaps-outer": fac ? 12 : 16,
                "kerning": fac ? "tight" : "relaxed",
                "anim-duration": Math.round(500 - 200 * reg),
                "anim-easing": "expo_out",
                "entrance-direction": "fade-up",
                "entrance-offset": fac ? 8 : 14,
                // scanline-idle is SECONDS until the drift starts: aggressive
                // at full facility (5s), a whisper mid-register (30s), never
                // at the affluent pole (0 = disabled).
                "scanlines": t.scanline > 0.05,
                "scanline-idle": t.scanline > 0.05 ? Math.round(5 + 25 * (1 - t.scanline)) : 0,
                "opacity": 0.90 + 0.04 * t.glassBlur,
                "border-weight": 1,
                "border-alpha": 0.10 + 0.08 * reg,
                "shadow-enabled": t.bloom > 0.05,
                "shadow-alpha": 0.04 + 0.08 * t.bloom,
                "grain": 0.05 * t.grainOpacity,
                "grain-warm": light,
                "label-prefix": ""
            };

            root.currentThemeName = d.slug ?? "wintermute";

            // Accountability: acknowledge the applied generation into the
            // ack ledger `wintermute status` and the audit tick read.
            Quickshell.execDetached(["sh", "-c",
                "mkdir -p '" + root.stateHome + "/wintermute/ack' && " +
                "printf '%s\n' " + String(root.generation) + " > '" +
                root.stateHome + "/wintermute/ack/quickshell'"]);
            root.colorScheme = light ? "light" : "dark";
            root.polarity = reg;
            root.luminance = light ? 0.25 : 0.78;

            console.log("[Theme] wintermute gen", root.generation, ":",
                        root.currentThemeName, "register", reg);
        } catch (e) {
            console.error("[Theme] failed to parse wintermute theme.json:", e);
        }
    }

    function _loadPresets(text) {
        try {
            const d = JSON.parse(text);
            root.availableThemes = Object.keys(d);
            root.themePreviews = d;
        } catch (e) {
            console.error("[Theme] failed to parse presets.json:", e);
        }
    }

    // ── Watchers ────────────────────────────────────────────────────────────

    // The live contract: wintermute's durable output (or the Nix seed).
    //
    // THE TRAP (root cause of "spotty theme switching", found live at
    // gen 33-vs-40): onFileChanged fires on every atomic replace, but
    // text() returns the CACHED buffer — re-parsing the same stale JSON
    // forever while the daemon-direct channels moved on. onFileChanged
    // must call reload(); fresh content then arrives via onLoaded.
    FileView {
        path: root.stateHome + "/wintermute/theme.json"
        watchChanges: true
        preload: true
        onLoaded: root._load(text())
        onFileChanged: reload()
    }

    // Build-time corner previews, computed by the same palette math in Nix.
    FileView {
        path: Quickshell.shellDir + "/presets.json"
        preload: true
        onLoaded: root._loadPresets(text())
    }

    Process {
        id: wintermuteProc
        stderr: SplitParser {
            onRead: data => console.error("[Theme] wintermute: " + data)
        }
    }
}
