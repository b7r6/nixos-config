# DGX Spark (GB10) CPU clock capped at ~1.37 GHz — root cause & fix

**TL;DR.** On a non-NVIDIA (mainline) kernel, the DGX Spark / GB10 Grace-Blackwell
big cores (Cortex-X925) are stuck at **~1.37 GHz** (≈36% of the rated 3.9 GHz)
and the little cores (A725) at ~1.0 GHz, *no matter what governor you set*.

The cause is a **one-line gap in mainline Linux**: `drivers/cpufreq/cppc_cpufreq.c`
never calls `cppc_set_enable()`. GB10 exposes a **CPPC master Enable register**;
until the OS sets it, the platform (SCP firmware) ignores every OS performance
request (desired/min/max/EPP) and free-runs the cores at CPPC `lowest_perf`.

The fix is to call `cppc_set_enable(cpu, true)` in `cppc_cpufreq_cpu_init()`.
See `patches/cppc-0001-enable-cppc-on-init.patch` (applied to the standard modern
kernel via `cppcDvfsPatches` in `default.nix`). Proven live: **1.37 → 3.9 GHz.**

This affects **any** distro running a mainline kernel on GB10 (NixOS, Arch,
Fedora, …). NVIDIA's own DGX-OS / `linux-nvidia` kernel already carries the
equivalent, which is why the problem is invisible on stock DGX OS.

---

## How to recognize it

- `cat /sys/devices/system/cpu/cpu5/cpufreq/scaling_cur_freq` claims 3.9 GHz but
  the machine is clearly slow; builds/inference run ~2.8× slower than expected.
- Under sustained 100% load, a big core measures **~1.37 GHz**, never boosting,
  regardless of `performance` governor / `scaling_setspeed`.
- CPPC says `highest_perf == nominal_perf == guaranteed_perf` (full), but the
  **delivered** perf sits at `lowest_perf`.

> ⚠️ **Do not trust `cpuinfo_cur_freq` on Grace** — it's unreliable. Use
> `cpuinfo_avg_freq` under an affinitized load, or PMU cycle counts, or the CPPC
> `feedback_ctrs`. All three agree; `cpuinfo_cur_freq` does not.

### Reliable measurement

```bash
# delivered clock of one big core (cpu7) under real load:
taskset -c 7 sh -c 'while :; do :; done' & P=$!; sleep 1.5
cat /sys/devices/system/cpu/cpu7/cpufreq/cpuinfo_avg_freq   # kHz; ~1374902 = capped
kill $P

# ground-truth via PMU (perf must match the kernel; note the heterogeneous PMU):
#   armv8_pmuv3_0 = A725 (cpu 0-4,10-14),  armv8_pmuv3_1 = X925 (cpu 5-9,15-19)
perf stat -C 7 -e cpu-cycles -- sleep 2   # cycles/2s ~ GHz

# CPPC delivered perf (ratio × reference_perf; 53≈lowest, 150≈full on GB10):
cat /sys/devices/system/cpu/cpu7/acpi_cppc/feedback_ctrs   # read twice under load
```

Common trap: a **transient** background CPU hog started inside a script/subshell
often gets reaped before you measure — use a sustained `setsid timeout N …` hog
and confirm the core is actually at 100% before reading the frequency. ("No core
looks busy" under a capped clock is also just the low power draw — a core doing
100% work at 1.37 GHz barely gets warm.)

---

## The diagnosis (why it's the kernel, not hardware)

1. **Both units identical.** Two independent Sparks showed the *exact* same
   1374902 kHz floor. Two coincident hardware defects is not a thing — a shared
   floor means a shared *software* cause.
2. **The cap is real, not a reporting artifact.** PMU cycles, `cpuinfo_avg_freq`
   (NVIDIA's own recommended Grace metric), and CPPC `feedback_ctrs` all agree at
   ~1.37 GHz under verified 100% load. SHA-256 hardware throughput (~760 MB/s at
   ~1.9 cycles/byte) corroborates ~1.4 GHz.
3. **The block is below the cpufreq layer.** With autonomous selection forced
   *off* and `desired_perf` driven to max via the userspace governor, delivered
   perf still didn't move. So it isn't the governor or the auto-select toggle
   logic — the OS's writes weren't reaching/affecting the platform.
4. **The registers are writable MMIO.** Decompiling the DSDT `_CPC`: all control
   registers (Desired +0x18, Min +0x80, Max +0x00, AutoSel +0x50, EPP +0x58, and
   a master **Enable +0x4C**) are `SystemMemory` (not PCC mailbox, not FFixedHW).
   Counters are FFixedHW (AMU). So the OS *can* write them.
5. **Mainline never sets the master Enable.** `grep cppc_set_enable
   drivers/cpufreq/cppc_cpufreq.c` → nothing. NVIDIA's kernel calls
   `cppc_set_enable(cpu, true)`. GB10 requires it; without it the SCP ignores the
   perf registers entirely.

### Proof (no kernel rebuild needed to validate)

`cppc_set_enable` is `EXPORT_SYMBOL_GPL`, so a 15-line out-of-tree module proves
it instantly:

```c
#include <linux/module.h>
#include <linux/cpu.h>
#include <acpi/cppc_acpi.h>
static int __init m_init(void) {
    int cpu;
    for_each_online_cpu(cpu) cppc_set_enable(cpu, true);
    return 0;
}
static void __exit m_exit(void) {}
module_init(m_init); module_exit(m_exit);
MODULE_LICENSE("GPL");
```

`insmod` it, set `performance` governor → cores jump to 3896 MHz (X925) /
2805 MHz (A725), delivered_perf 53 → 152. That's the whole fix; the kernel patch
just moves that call into `cppc_cpufreq_cpu_init()`.

---

## Red herrings — do NOT chase these

Hours were lost here so you don't have to:

- **Firmware.** Flashing the USB-C PD controller (`0x516`), the Embedded
  Controller (`0x03000508`), and the SoC firmware (`0x02009b0b`) via `fwupd`
  changed **nothing**. It's not a firmware-update bug.
- **Power delivery / RMA.** A widely-cited blog frames a persistent ~1.5 GHz cap
  as a "30 W safe mode" hardware defect requiring RMA. It is *not* that here —
  proven by the kernel fix. Direct-to-wall vs UPS, power-brick resets: no effect.
- **`mlx5_core: Detected insufficient power on the PCIe slot (27W)`** in dmesg is
  a **benign ConnectX-7 firmware artifact** — it appears on healthy, full-clock
  units too, only affects NIC throughput on old NIC firmware, and is fixed by the
  mlx driver update. Nothing to do with the CPU clock.
- **`cpuinfo_cur_freq`** reading low: unreliable on Grace by design (see above).

---

## Applying / upstreaming

- **This repo (NixOS):** already wired — `cppcDvfsPatches` in `default.nix` adds
  the patch to `pkgs.linux_latest`; both Sparks use it (they set
  `useNvidiaKernel = false`). Just `nixos-rebuild boot` + reboot.
- **Other distros:** apply `patches/cppc-0001-enable-cppc-on-init.patch` to your
  kernel's `drivers/cpufreq/cppc_cpufreq.c`, or run the module above at boot.
- **Upstream:** this is a real mainline gap and belongs on `linux-pm` (Cc the CPPC
  maintainers). It's adjacent to Sumit Gupta's (NVIDIA) in-review CPPC
  autonomous-selection series (lore 20251105113844.4086250-1-sumitg@nvidia.com,
  Launchpad bug 2131705) but is a distinct, simpler fix: "set the CPPC Enable
  register on init." `-EOPNOTSUPP` (platforms without an Enable register) is
  ignored, so it's a safe no-op everywhere else.

## Verify after reboot

```bash
# fresh kernel, no test module:
for c in 5 7 9 15 17 19; do
  taskset -c $c sh -c 'while :; do :; done' & done; sleep 2
for c in 5 7 9 15 17 19; do
  printf 'cpu%s %s MHz\n' "$c" "$(( $(cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_avg_freq)/1000 ))"
done; pkill -f 'while :'
# want ~3896 MHz on every X925 core.
```
