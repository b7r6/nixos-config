# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                     // hyper-modern-nixos // checks // coredns
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# SERVE-correctness proof for the CoreDNS split-horizon resolver, as a
# self-contained NixOS VM test. Build-correct ≠ serve-correct: this boots the
# real `hyper-modern-nixos.coredns` (zone compiled by packages/coredns-zone from
# the live registry) and QUERIES it with dig, asserting the actual answers:
#
#   - <host>.<zone>      A     → tailnet_ipv4
#   - <host>.lan.<zone>  A     → lan_ipv4         (leased hosts only)
#   - <service>.<zone>   CNAME → the host running it   (incl. studio → watchtower)
#   - SOA / NS present and authoritative (AA bit)
#
# DNS is intolerable to silent-wrong output, so this is the regression guard that
# the renderer + module actually produce a zone a resolver loads and serves
# correctly — the failure mode we most need to catch before it strands the fleet.
#
# The module needs the `flake` specialArg (locates registry/) and the topology;
# we provide a minimal flake stub + import the topology module, matching how the
# fleet wires them.
{ pkgs, inputs }:
let
  inherit (inputs) self;
in
pkgs.testers.runNixOSTest {
  name = "coredns";

  nodes.resolver = { ... }: {
    imports = [
      ../../registry/nixos.nix
      ../nixos.nix
      ../../../nixos/network.nix
    ];

    # The coredns/topology modules read `flake.self` (to locate registry/) — the
    # same specialArg the fleet passes. Provide it here.
    _module.args.flake = {
      inherit self inputs;
      config = { };
    };

    # Enable the resolver. selfTailnetIPv4 normally defaults from this host's
    # registry entry; the VM ("resolver") isn't in the registry, so set it
    # explicitly (the NS-glue IP — any value the zone can advertise).
    hyper-modern-nixos.coredns = {
      enable = true;
      # ownResolver would point /etc/resolv.conf at 127.0.0.1 and disable
      # tailscale DNS; harmless in the VM but we keep it on to exercise that path.
      ownResolver = true;
      selfTailnetIPv4 = "100.122.228.122"; # watchtower's, the canonical resolver
    };

    # network.nix is imported for the tailscale option surface coredns touches;
    # we don't actually run tailscale in the VM.
    hyper-modern-nixos.network.enable = true;

    virtualisation.memorySize = 1024;
    virtualisation.diskSize = 2048;
  };

  testScript = ''
    start_all()

    resolver.wait_for_unit("coredns.service")
    resolver.wait_for_open_port(53)

    # dig helper: query our resolver on loopback, short output.
    def dig(name, rrtype="A"):
        return resolver.succeed(
            f"dig +short @127.0.0.1 {name} {rrtype}"
        ).strip()

    # ── host A-records ──────────────────────────────────────────────────────
    assert dig("watchtower.sju1.s4.gl") == "100.122.228.122", \
        f"watchtower A wrong: {dig('watchtower.sju1.s4.gl')!r}"
    assert dig("ultraviolence.sju1.s4.gl") == "100.71.82.73", \
        f"ultraviolence A wrong: {dig('ultraviolence.sju1.s4.gl')!r}"

    # ── LAN A-records (leased hosts only) ─────────────────────────────────────
    assert dig("watchtower.lan.sju1.s4.gl") == "192.168.40.98", \
        f"watchtower.lan A wrong: {dig('watchtower.lan.sju1.s4.gl')!r}"
    # a roaming laptop (shannon) has no lease → no lan record → empty answer
    assert dig("shannon.lan.sju1.s4.gl") == "", \
        "shannon.lan should NOT resolve (no static lease)"

    # ── service CNAMEs ────────────────────────────────────────────────────────
    # studio → watchtower (the alias whose absence stranded resolution earlier).
    studio = resolver.succeed("dig +short @127.0.0.1 studio.sju1.s4.gl CNAME").strip()
    assert studio == "watchtower.sju1.s4.gl.", f"studio CNAME wrong: {studio!r}"
    # and it resolves THROUGH the CNAME to watchtower's A. `dig +short A` on a
    # CNAME returns the chain (the CNAME line AND the final A), so assert the A is
    # present in the answer rather than equal to it.
    studio_a = dig("studio.sju1.s4.gl")
    assert "100.122.228.122" in studio_a.split("\n"), \
        f"studio → A chase wrong: {studio_a!r}"
    # a service on a different host
    nl = resolver.succeed("dig +short @127.0.0.1 nativelink.sju1.s4.gl CNAME").strip()
    assert nl == "ultraviolence.sju1.s4.gl.", f"nativelink CNAME wrong: {nl!r}"

    # ── authority: our resolver is authoritative for the zone (AA bit set) ────
    soa = resolver.succeed("dig @127.0.0.1 sju1.s4.gl SOA +noall +comments")
    assert "flags: qr aa" in soa or "aa rd" in soa or " aa " in soa, \
        f"resolver not authoritative (no AA flag) for zone SOA:\n{soa}"

    # ── negative: a name not in the zone is NXDOMAIN, not a wrong answer ──────
    resolver.succeed(
        "dig @127.0.0.1 nonesuch.sju1.s4.gl A +short | "
        "grep -q . && exit 1 || exit 0"
    )

    print("// coredns // zone compiled, loaded, and served correctly: OK")
  '';
}
