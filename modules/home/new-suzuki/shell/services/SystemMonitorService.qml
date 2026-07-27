pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ========================================================================
    // CPU PROPERTIES
    // ========================================================================

    readonly property int cpuUsage: internal.cpuUsage
    readonly property int cpuTemp: internal.cpuTemp
    readonly property string cpuIcon: "󰻠"

    // ========================================================================
    // GPU PROPERTIES
    // ========================================================================

    readonly property int gpuUsage: internal.gpuUsage
    readonly property int gpuTemp: internal.gpuTemp
    readonly property string gpuIcon: "󰢮"
    readonly property string gpuType: internal.gpuType // "nvidia", "amd", "intel", "unknown"

    // Deeper NVIDIA instruments (the DGX Spark console). power.draw + clocks.sm
    // are live on GB10; memory is unified (nvidia-smi reports N/A) so it stays 0
    // and its readout hides — the `mem` readout already covers unified RAM.
    readonly property int gpuPower: internal.gpuPower   // watts, rounded
    readonly property int gpuClock: internal.gpuClock   // SM clock, MHz
    readonly property string gpuName: internal.gpuName  // e.g. "GB10"
    readonly property int gpuMemUsage: internal.gpuMemUsage // % (discrete GPUs)

    // ========================================================================
    // RAM PROPERTIES
    // ========================================================================

    readonly property int ramUsage: internal.ramUsage
    readonly property string ramUsed: internal.ramUsed   // GiB, e.g. "5.2"
    readonly property string ramTotal: internal.ramTotal  // GiB, e.g. "15.8"

    // ========================================================================
    // DISK PROPERTIES
    // ========================================================================

    readonly property int diskUsage: internal.diskUsage
    readonly property string diskUsed: internal.diskUsed   // GiB
    readonly property string diskTotal: internal.diskTotal  // GiB

    // ========================================================================
    // NETWORK PROPERTIES
    // ========================================================================

    readonly property string networkDown: internal.networkDown // e.g. "1.2 MB/s"
    readonly property string networkUp: internal.networkUp     // e.g. "340 KB/s"

    // ========================================================================
    // UPTIME
    // ========================================================================

    readonly property string uptime: internal.uptime // e.g. "2d 5h" or "3h 12m"

    // ========================================================================
    // INTERNAL STATE
    // ========================================================================

    QtObject {
        id: internal

        // CPU
        property int cpuUsage: 0
        property int cpuTemp: 0

        // GPU
        property int gpuUsage: 0
        property int gpuTemp: 0
        property string gpuType: "unknown"
        property int gpuPower: 0
        property int gpuClock: 0
        property string gpuName: ""
        property int gpuMemUsage: 0

        // CPU calculation state
        property real prevTotal: 0
        property real prevIdle: 0

        // RAM
        property int ramUsage: 0
        property string ramUsed: "0"
        property string ramTotal: "0"

        // Disk
        property int diskUsage: 0
        property string diskUsed: "0"
        property string diskTotal: "0"

        // Network
        property string networkDown: "0 B/s"
        property string networkUp: "0 B/s"
        property real prevRx: 0
        property real prevTx: 0

        // Uptime
        property string uptime: "0m"
    }

    // ========================================================================
    // INITIALIZATION
    // ========================================================================

    Component.onCompleted: {
        detectGpu.running = true;
        updateCpuUsage.running = true;
        updateCpuTemp.running = true;
        updateRam.running = true;
        updateDisk.running = true;
        updateNetwork.running = true;
        updateUptime.running = true;
    }

    // ========================================================================
    // UPDATE TIMER
    // ========================================================================

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            updateCpuUsage.running = true;
            updateCpuTemp.running = true;
            updateRam.running = true;
            updateNetwork.running = true;
            updateUptime.running = true;

            if (internal.gpuType === "nvidia") {
                updateNvidiaGpu.running = true;
            } else if (internal.gpuType === "amd") {
                updateAmdGpuUsage.running = true;
                updateAmdGpuTemp.running = true;
            } else if (internal.gpuType === "intel") {
                updateIntelGpuTemp.running = true;
            }
        }
    }

    // Disk updates less frequently (every 30s)
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: updateDisk.running = true
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    function _formatBytes(bytes) {
        if (bytes >= 1073741824) {
            return (bytes / 1073741824).toFixed(1) + " GB/s";
        } else if (bytes >= 1048576) {
            return (bytes / 1048576).toFixed(1) + " MB/s";
        } else if (bytes >= 1024) {
            return (bytes / 1024).toFixed(0) + " KB/s";
        }
        return bytes.toFixed(0) + " B/s";
    }

    function _formatGiB(bytes) {
        return (bytes / 1073741824).toFixed(1);
    }

    // ========================================================================
    // GPU DETECTION
    // ========================================================================

    Process {
        id: detectGpu
        command: ["bash", "-c", `
            if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
                echo "nvidia"
            elif [ -f /sys/class/drm/card0/device/gpu_busy_percent ] || [ -f /sys/class/drm/card1/device/gpu_busy_percent ]; then
                echo "amd"
            elif [ -d /sys/class/drm/card0/gt ] || ls /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -1; then
                echo "intel"
            else
                echo "unknown"
            fi
        `]
        stdout: SplitParser {
            onRead: data => {
                const type = data.trim();
                internal.gpuType = type;
                console.log("[SystemMonitor] Detected GPU type:", type);

                if (type === "nvidia") {
                    updateNvidiaGpu.running = true;
                } else if (type === "amd") {
                    updateAmdGpuUsage.running = true;
                    updateAmdGpuTemp.running = true;
                } else if (type === "intel") {
                    updateIntelGpuTemp.running = true;
                }
            }
        }
    }

    // ========================================================================
    // CPU MONITORING
    // ========================================================================

    Process {
        id: updateCpuUsage
        command: ["bash", "-c", "head -1 /proc/stat"]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(/\s+/);
                if (parts.length >= 5) {
                    const user = parseFloat(parts[1]) || 0;
                    const nice = parseFloat(parts[2]) || 0;
                    const system = parseFloat(parts[3]) || 0;
                    const idle = parseFloat(parts[4]) || 0;
                    const iowait = parseFloat(parts[5]) || 0;
                    const irq = parseFloat(parts[6]) || 0;
                    const softirq = parseFloat(parts[7]) || 0;
                    const steal = parseFloat(parts[8]) || 0;

                    const total = user + nice + system + idle + iowait + irq + softirq + steal;
                    const idleTime = idle + iowait;

                    if (internal.prevTotal > 0) {
                        const totalDiff = total - internal.prevTotal;
                        const idleDiff = idleTime - internal.prevIdle;

                        if (totalDiff > 0) {
                            const usage = Math.round(((totalDiff - idleDiff) / totalDiff) * 100);
                            internal.cpuUsage = Math.max(0, Math.min(100, usage));
                        }
                    }

                    internal.prevTotal = total;
                    internal.prevIdle = idleTime;
                }
            }
        }
    }

    Process {
        id: updateCpuTemp
        command: ["bash", "-c", `
            for zone in /sys/class/thermal/thermal_zone*/temp; do
                type_file="\${zone%/temp}/type"
                if [ -f "$type_file" ]; then
                    type=$(cat "$type_file" 2>/dev/null)
                    if [[ "$type" == *"cpu"* ]] || [[ "$type" == *"x86_pkg"* ]] || [[ "$type" == *"coretemp"* ]]; then
                        cat "$zone" 2>/dev/null
                        exit 0
                    fi
                fi
            done
            cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0"
        `]
        stdout: SplitParser {
            onRead: data => {
                const temp = parseInt(data.trim());
                if (!isNaN(temp)) {
                    internal.cpuTemp = Math.round(temp / 1000);
                }
            }
        }
    }

    // ========================================================================
    // RAM MONITORING
    // ========================================================================

    Process {
        id: updateRam
        command: ["bash", "-c", "free -b | awk '/Mem:/{print $2,$3}'"]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(/\s+/);
                if (parts.length >= 2) {
                    const total = parseFloat(parts[0]);
                    const used = parseFloat(parts[1]);
                    if (total > 0) {
                        internal.ramUsage = Math.round((used / total) * 100);
                        internal.ramUsed = root._formatGiB(used);
                        internal.ramTotal = root._formatGiB(total);
                    }
                }
            }
        }
    }

    // ========================================================================
    // DISK MONITORING
    // ========================================================================

    Process {
        id: updateDisk
        command: ["bash", "-c", "df -B1 / | awk 'NR==2{print $2,$3}'"]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(/\s+/);
                if (parts.length >= 2) {
                    const total = parseFloat(parts[0]);
                    const used = parseFloat(parts[1]);
                    if (total > 0) {
                        internal.diskUsage = Math.round((used / total) * 100);
                        internal.diskUsed = root._formatGiB(used);
                        internal.diskTotal = root._formatGiB(total);
                    }
                }
            }
        }
    }

    // ========================================================================
    // NETWORK MONITORING
    // ========================================================================

    Process {
        id: updateNetwork
        command: ["bash", "-c", `
            rx=0; tx=0
            for iface in /sys/class/net/*/; do
                name=$(basename "$iface")
                [ "$name" = "lo" ] && continue
                [ -f "$iface/statistics/rx_bytes" ] || continue
                rx=$((rx + $(cat "$iface/statistics/rx_bytes")))
                tx=$((tx + $(cat "$iface/statistics/tx_bytes")))
            done
            echo "$rx $tx"
        `]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(/\s+/);
                if (parts.length >= 2) {
                    const rx = parseFloat(parts[0]);
                    const tx = parseFloat(parts[1]);

                    if (internal.prevRx > 0) {
                        const rxDelta = (rx - internal.prevRx) / 2; // per second (2s interval)
                        const txDelta = (tx - internal.prevTx) / 2;
                        internal.networkDown = root._formatBytes(Math.max(0, rxDelta));
                        internal.networkUp = root._formatBytes(Math.max(0, txDelta));
                    }

                    internal.prevRx = rx;
                    internal.prevTx = tx;
                }
            }
        }
    }

    // ========================================================================
    // UPTIME
    // ========================================================================

    Process {
        id: updateUptime
        command: ["bash", "-c", "awk '{print int($1)}' /proc/uptime"]
        stdout: SplitParser {
            onRead: data => {
                const totalSeconds = parseInt(data.trim());
                if (isNaN(totalSeconds)) return;

                const days = Math.floor(totalSeconds / 86400);
                const hours = Math.floor((totalSeconds % 86400) / 3600);
                const minutes = Math.floor((totalSeconds % 3600) / 60);

                if (days > 0) {
                    internal.uptime = days + "d " + hours + "h";
                } else if (hours > 0) {
                    internal.uptime = hours + "h " + minutes + "m";
                } else {
                    internal.uptime = minutes + "m";
                }
            }
        }
    }

    // ========================================================================
    // NVIDIA GPU MONITORING
    // ========================================================================

    Process {
        id: updateNvidiaGpu
        // One query, the full instrument row. Fields that read "[N/A]" (unified
        // memory on GB10, power/clock on some parts) parse to NaN and are left
        // at their prior value — the dependent readout hides itself.
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu,power.draw,clocks.sm,memory.used,memory.total,name", "--format=csv,noheader,nounits"]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(",").map(s => s.trim());
                if (parts.length >= 2) {
                    const usage = parseInt(parts[0]);
                    const temp = parseInt(parts[1]);
                    if (!isNaN(usage)) internal.gpuUsage = usage;
                    if (!isNaN(temp)) internal.gpuTemp = temp;
                }
                if (parts.length >= 7) {
                    const power = parseFloat(parts[2]);
                    const clock = parseInt(parts[3]);
                    const memUsed = parseFloat(parts[4]);
                    const memTotal = parseFloat(parts[5]);
                    if (!isNaN(power)) internal.gpuPower = Math.round(power);
                    if (!isNaN(clock)) internal.gpuClock = clock;
                    if (!isNaN(memUsed) && !isNaN(memTotal) && memTotal > 0)
                        internal.gpuMemUsage = Math.round((memUsed / memTotal) * 100);
                    // name is the trailing field(s); GB10 has no comma so parts[6]
                    if (parts[6]) internal.gpuName = parts[6].replace(/^NVIDIA\s+/, "");
                }
            }
        }
    }

    // ========================================================================
    // AMD GPU MONITORING
    // ========================================================================

    Process {
        id: updateAmdGpuUsage
        command: ["bash", "-c", `
            for card in /sys/class/drm/card*/device/gpu_busy_percent; do
                if [ -f "$card" ]; then
                    cat "$card" 2>/dev/null
                    exit 0
                fi
            done
            echo "0"
        `]
        stdout: SplitParser {
            onRead: data => {
                const usage = parseInt(data.trim());
                if (!isNaN(usage)) {
                    internal.gpuUsage = usage;
                }
            }
        }
    }

    Process {
        id: updateAmdGpuTemp
        command: ["bash", "-c", `
            for hwmon in /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input; do
                if [ -f "$hwmon" ]; then
                    cat "$hwmon" 2>/dev/null
                    exit 0
                fi
            done
            cat /sys/class/drm/card0/device/hwmon/hwmon*/temp1_input 2>/dev/null || echo "0"
        `]
        stdout: SplitParser {
            onRead: data => {
                const temp = parseInt(data.trim());
                if (!isNaN(temp)) {
                    internal.gpuTemp = Math.round(temp / 1000);
                }
            }
        }
    }

    // ========================================================================
    // INTEL GPU MONITORING
    // ========================================================================

    Process {
        id: updateIntelGpuTemp
        command: ["bash", "-c", `
            for zone in /sys/class/thermal/thermal_zone*/temp; do
                type_file="\${zone%/temp}/type"
                if [ -f "$type_file" ]; then
                    type=$(cat "$type_file" 2>/dev/null)
                    if [[ "$type" == *"gpu"* ]] || [[ "$type" == *"pch"* ]]; then
                        cat "$zone" 2>/dev/null
                        exit 0
                    fi
                fi
            done
            cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0"
        `]
        stdout: SplitParser {
            onRead: data => {
                const temp = parseInt(data.trim());
                if (!isNaN(temp)) {
                    internal.gpuTemp = Math.round(temp / 1000);
                }
            }
        }
    }

}
