pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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

        Text {
            text: readout.label
            font.family: Config.font
            font.pixelSize: 9
            font.letterSpacing: 1.2
            font.capitalization: Font.AllUppercase
            color: Config.mutedColor
        }

        Text {
            text: readout.value
            font.family: Config.font
            font.pixelSize: Config.fontSizeSmall
            color: readout.hot ? Config.warningColor : Config.subtextColor

            Behavior on color {
                ColorAnimation {
                    duration: Config.animDurationShort
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
        label: "net"
        value: SystemMonitorService.networkDown
        threshold: 0.82
    }
}
