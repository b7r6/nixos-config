pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.config
import qs.services

// Telemetry — the instrument cluster. On a DGX Spark this is the point:
// telemetryDensity fades the MACHINE into the bar. Each readout has a
// register threshold; sliding toward the facility pole reveals them in
// order — cpu, mem, gpu, thermals, network — until the bar reads like a
// console. At the affluent pole the cluster vanishes entirely.
//
// Data comes from SystemMonitorService's existing pollers (including
// nvidia-smi on the GB10) — no new processes.
RowLayout {
    id: root

    spacing: 12
    visible: Config.telemetryDensity > 0.08

    // Fabric link speed (the Mellanox flex): fastest carrier-up interface,
    // /sys/class/net/*/speed. 200000 → "200G" on a ConnectX. Polled slowly —
    // link speed is not weather.
    property string linkSpeed: ""

    Process {
        id: linkProc
        command: ["bash", "-c",
            "for d in /sys/class/net/*/; do n=$(basename \"$d\"); [ \"$n\" = lo ] && continue; s=$(cat \"$d/speed\" 2>/dev/null); case $s in ''|*[!0-9]*) ;; *) echo \"$s\";; esac; done | sort -rn | head -1"]
        stdout: SplitParser {
            onRead: data => {
                const mb = parseInt(data.trim());
                if (!isNaN(mb) && mb > 0)
                    root.linkSpeed = mb >= 1000 ? (mb / 1000) + "G" : mb + "M";
            }
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: linkProc.running = true
    }

    // Running containers (the NGC angle: the shell knows its workloads).
    // Absent/permission-denied docker degrades to 0 → readout hidden.
    property int containerCount: 0

    Process {
        id: ngcProc
        command: ["bash", "-c", "docker ps -q 2>/dev/null | wc -l"]
        stdout: SplitParser {
            onRead: data => {
                const n = parseInt(data.trim());
                root.containerCount = isNaN(n) ? 0 : n;
            }
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: ngcProc.running = true
    }

    component Readout: RowLayout {
        id: readout

        property string label
        property string value
        property real threshold: 0.12
        property bool hot: false

        readonly property real reveal: Math.max(0, Math.min(1, (Config.telemetryDensity - threshold) / 0.12))

        visible: reveal > 0.01
        opacity: reveal
        spacing: 4

        // Facility-mode section flicker: crossing the hot threshold blips
        // the value — the razorgirl glitch, earned by an actual event.
        onHotChanged: {
            if (Config.facility)
                hotFlick.restart();
        }

        Text {
            text: readout.label
            font.family: Config.font
            font.pixelSize: 9
            font.letterSpacing: 1.2
            font.capitalization: Font.AllUppercase
            color: Config.mutedColor
        }

        Text {
            id: readoutValue

            text: readout.value
            font.family: Config.font
            font.pixelSize: Config.fontSizeSmall
            color: readout.hot ? Config.warningColor : Config.subtextColor

            Behavior on color {
                ColorAnimation {
                    duration: Config.animDurationShort
                }
            }

            SequentialAnimation {
                id: hotFlick

                NumberAnimation {
                    target: readoutValue
                    property: "opacity"
                    to: 0.3
                    duration: 45
                }
                NumberAnimation {
                    target: readoutValue
                    property: "opacity"
                    to: 1.0
                    duration: 45
                }
                NumberAnimation {
                    target: readoutValue
                    property: "opacity"
                    to: 0.55
                    duration: 40
                }
                NumberAnimation {
                    target: readoutValue
                    property: "opacity"
                    to: 1.0
                    duration: 110
                }
            }
        }
    }

    Readout {
        label: "cpu"
        value: SystemMonitorService.cpuUsage + "%"
        threshold: 0.10
        hot: SystemMonitorService.cpuUsage > 85
    }

    Readout {
        label: "mem"
        value: SystemMonitorService.ramUsage + "%"
        threshold: 0.28
        hot: SystemMonitorService.ramUsage > 90
    }

    Readout {
        label: "gpu"
        value: SystemMonitorService.gpuUsage + "%"
        threshold: 0.46
        hot: SystemMonitorService.gpuUsage > 92
    }

    Readout {
        label: "tmp"
        value: Math.max(SystemMonitorService.cpuTemp, SystemMonitorService.gpuTemp) + "°"
        threshold: 0.64
        hot: Math.max(SystemMonitorService.cpuTemp, SystemMonitorService.gpuTemp) > 80
    }

    Readout {
        label: "ngc"
        value: root.containerCount
        threshold: 0.73
        visible: reveal > 0.01 && root.containerCount > 0
    }

    Readout {
        label: "net"
        value: SystemMonitorService.networkDown
        threshold: 0.82
    }

    Readout {
        label: "link"
        value: root.linkSpeed
        threshold: 0.92
        visible: reveal > 0.01 && root.linkSpeed !== ""
    }
}
