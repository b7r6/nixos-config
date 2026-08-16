pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    // ========================================================================
    // PROPERTIES
    // ========================================================================

    property bool visible: false
    property string query: ""
    property int selectedIndex: 0

    // Incremented on each open to force re-evaluation of the app list
    property int _refreshToken: 0

    // Frecency: launch counts persisted through StateService; most-launched
    // apps float to the top of the unfiltered list and break ties in search.
    property var _counts: ({})

    // ── Calculator mode: "=<expr>" evaluates via qalc (libqalculate) ────────
    readonly property bool calcMode: query.startsWith("=")
    property string calcResult: ""

    Process {
        id: calcProc
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line !== "")
                    root.calcResult = line;
            }
        }
    }

    Timer {
        id: calcDebounce
        interval: 120
        onTriggered: {
            calcProc.command = ["qalc", "-t", root.query.slice(1)];
            calcProc.running = true;
        }
    }

    // Filtered app list
    readonly property var filteredApps: {
        void root._refreshToken;

        // Calculator mode short-circuits the app list: one synthetic entry
        // carrying the result (enter copies it).
        if (calcMode) {
            if (calcResult === "" || query.length < 2)
                return [];
            return [{
                name: calcResult,
                comment: "⏎ copy to clipboard",
                icon: "accessories-calculator",
                isCalc: true
            }];
        }

        let apps = DesktopEntries.applications.values;

        const seen = new Set();
        apps = apps.filter(app => {
            const key = app.id || app.execString || app.name;
            if (seen.has(key))
                return false;
            seen.add(key);
            return true;
        });

        const countOf = app => root._counts[app.id || app.name] ?? 0;

        // Frecency first, then alphabetical.
        apps = apps.slice().sort((a, b) => {
            const ca = countOf(a);
            const cb = countOf(b);
            if (ca !== cb)
                return cb - ca;
            const nameA = (a.name || "").toLowerCase();
            const nameB = (b.name || "").toLowerCase();
            return nameA.localeCompare(nameB);
        });

        if (query === "") {
            return apps.slice(0, apps.length);
        }

        const q = query.toLowerCase();

        // Separate into two groups: name match vs description match
        let nameMatches = [];
        let descMatches = [];

        for (const app of apps) {
            const name = (app.name || "").toLowerCase();
            const comment = (app.comment || "").toLowerCase();
            const genericName = (app.genericName || "").toLowerCase();

            if (name.includes(q)) {
                nameMatches.push(app);
            } else if (comment.includes(q) || genericName.includes(q)) {
                descMatches.push(app);
            }
        }

        // Name first, then description
        return [...nameMatches, ...descMatches].slice(0, apps.length);
    }

    // ========================================================================
    // PUBLIC FUNCTIONS
    // ========================================================================

    function show() {
        _refreshToken++;
        _counts = StateService.get("launcher.counts", {});
        query = "";
        selectedIndex = 0;
        visible = true;
    }

    function hide() {
        visible = false;
        query = "";
        calcResult = "";
        selectedIndex = 0;
    }

    function toggle() {
        if (visible)
            hide();
        else
            show();
    }

    function launch(entry) {
        if (!entry)
            return;

        if (entry.isCalc) {
            Quickshell.execDetached(["wl-copy", root.calcResult]);
            hide();
            return;
        }

        console.log("[Launcher] Launching:", entry.name);

        // Frecency bump, persisted.
        const key = entry.id || entry.name;
        const counts = Object.assign({}, root._counts);
        counts[key] = (counts[key] ?? 0) + 1;
        root._counts = counts;
        StateService.set("launcher.counts", counts);

        // Remove field codes from .desktop (%u, %U, %f, %F, %i, %c, %k, etc)
        let cmd = entry.execString;
        cmd = cmd.replace(/%[uUfFdDnNickvm]/g, "").trim();
        cmd = cmd.replace(/\s+/g, " "); // Remove extra spaces

        Quickshell.execDetached(["sh", "-c", cmd]);
        hide();
    }

    function launchSelected() {
        if (filteredApps.length > 0 && selectedIndex >= 0 && selectedIndex < filteredApps.length) {
            launch(filteredApps[selectedIndex]);
        }
    }

    // ========================================================================
    // NAVIGATION
    // ========================================================================

    function navigateUp() {
        if (selectedIndex > 0) {
            selectedIndex--;
        }
    }

    function navigateDown() {
        if (selectedIndex < filteredApps.length - 1) {
            selectedIndex++;
        }
    }

    // Reset selectedIndex when query changes; calc mode debounces into qalc.
    onQueryChanged: {
        selectedIndex = 0;
        if (calcMode && query.length > 1)
            calcDebounce.restart();
        else
            calcResult = "";
    }
}
