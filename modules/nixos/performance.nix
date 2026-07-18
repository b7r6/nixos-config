# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                           // hypermodern // nix // performance
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# We do performance here. This module makes the whole fleet a first-class
# profiling target by default, no per-host ceremony:
#
#   - CPUs run the `performance` governor (max sustained clock, not schedutil's
#     latency-vs-power tradeoff). Fleet-wide mkDefault, so a battery host can
#     still override. NB: on GB10/DGX-Spark the delivered clock is gated by the
#     USB-C PD controller firmware, NOT this governor — keep that firmware
#     current (fwupd) or the cores park at lowest_perf regardless.
#
#   - The perf/ptrace paranoia knobs are OPEN: perf_event_paranoid = -1 (full
#     PMU + kernel + tracepoint access for unprivileged users), kptr_restrict = 0
#     (symbol resolution in stacks), yama.ptrace_scope = 0 (attach/strace any of
#     your own processes). These are the settings that turn "Operation not
#     permitted" into a usable `perf stat` / `strace -p` / `bpftrace`. This is a
#     deliberate trade: these are trusted, tailnet-only boxes — we optimize for
#     the engineer at the keyboard, not for a hostile-multi-tenant threat model.
#
#   - The profiling toolchain ships by default: perf (matched to the running
#     kernel), cpupower, the BPF stack (bpftrace/bcc), the tracers
#     (strace/ltrace), the memory profilers (valgrind/heaptrack), FlameGraph,
#     the sampling GUI (hotspot), and the system-stat/NUMA/topology tools.
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.hyper-modern-nixos.performance;
in
{
  options.hyper-modern-nixos.performance = {
    enable = (lib.mkEnableOption "hyper-modern-nixos.performance") // {
      default = true;
    };

    governor = lib.mkOption {
      type = lib.types.str;
      default = "performance";
      description = "cpufreq governor applied fleet-wide (mkDefault).";
    };

    openParanoia = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the perf/ptrace paranoia knobs (perf_event_paranoid = -1,
        kptr_restrict = 0, yama.ptrace_scope = 0) for unprivileged profiling.
        These are trusted tailnet-only boxes; set false to restore the hardened
        defaults on a host that needs them.
      '';
    };

    tools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the profiling toolchain into environment.systemPackages.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Max sustained clock, not schedutil's ramp. mkDefault: a host (or the
    # existing per-host `powerManagement.cpuFreqGovernor` assignments) can win.
    powerManagement.cpuFreqGovernor = lib.mkDefault cfg.governor;

    # No paranoia — full unprivileged access to the PMU, kernel symbols, and
    # ptrace. Plain values (priority 100) so they win over NixOS's own mkDefault
    # hardening (e.g. kptr_restrict = 1); the override path is this module's
    # `openParanoia = false` / `enable = false`, not per-key priority juggling.
    boot.kernel.sysctl = lib.mkIf cfg.openParanoia {
      "kernel.perf_event_paranoid" = -1;
      "kernel.kptr_restrict" = 0;
      "kernel.yama.ptrace_scope" = 0;
    };

    # The whole profiling stack, on every box. `perf` and `cpupower` are pulled
    # from the running kernel's package set so they always match the ABI.
    environment.systemPackages = lib.mkIf cfg.tools (
      [
        # cpupower is kernel-version-matched; perf is now the top-level `pkgs.perf`
        # (which tracks the configured kernel — resolves to perf-linux-<ver>).
        config.boot.kernelPackages.cpupower
      ]
      ++ (with pkgs; [
        perf

        # BPF-based tracing/observability
        bpftrace
        bcc

        # syscall / library-call tracers
        strace
        ltrace

        # sampling + memory profilers
        valgrind
        heaptrack
        flamegraph
        hotspot

        # kernel function tracing
        trace-cmd

        # system stats, NUMA + topology (Grace is NUMA — hwloc/numactl matter)
        sysstat
        numactl
        hwloc
        iotop
      ])
    );
  };
}
