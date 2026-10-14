# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hypermodern // nix // sites
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The soak sites' hosts, generated from ONE source of truth: hypermodern-
# nativelink's `examples/sites.dhall`, rendered to JSON at eval time (IFD, the
# same way modules/flake/registry renders the fleet registry) and turned into
# one `hosts` entry per node, rig and builder of every site, each on the
# generic wrapper configurations/nixos/nl-site/ parameterized by site + role.
#
#   nl-az2-a / -b / -c   node    scheduler/CAS/worker per the Dhall fleet
#   nl-az2-rig           rig     the soak driver + the site's observability sink
#   nl-az2-builder       builder a transient remote builder / deploy host
#
# Per site, the wrapper gets: the tailnet suffix and tags, the scheduler's
# name (the rig's target), the CAS env secret, and the NativeLink package from
# the flake input `nativelinkRev.input` names — asserted to be locked at the
# rev the site says it soaks, so a drifted lock refuses to evaluate rather
# than quietly soaking something else.
#
# The az site stays hand-written (configurations/nixos/nl-az/) until it is
# folded onto nl-site (docs/azure-soak-fleet.md, "Sites": the fold-in must
# prove byte-identical toplevel drvPaths first); `handWritten` keeps the
# generator from producing a second definition of those hosts meanwhile.
#
{ inputs, lib }:
let
  hn = inputs.hypermodern-nativelink;
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

  # import-from-derivation, on purpose: the typed sites are the program and
  # the host list is its output. A small, local, network-free dhall-to-json.
  sites = hn.lib.renderSites {
    inherit pkgs;
    sites = hn + "/examples/sites.dhall";
  };

  handWritten = [ "az" ];

  generated = lib.filterAttrs (name: site: site.enabled && !(lib.elem name handWritten)) sites;

  # The site's NativeLink package: null (the fork module's default, i.e. the
  # `nativelink-nix` input) when the site soaks that, else the named input's.
  packageFor =
    site:
    let
      rev = site.nativelinkRev;
      input =
        inputs.${rev.input}
          or (throw "site ${site.name}: nativelinkRev.input '${rev.input}' is not a flake input (add it to flake.nix)");
    in
    assert lib.assertMsg (input.rev == rev.rev)
      "site ${site.name}: input ${rev.input} is locked at ${input.rev}, sites.dhall says ${rev.rev}";
    if rev.input == "nativelink-nix" then null else input.packages.x86_64-linux.nativelink;

  mkSiteHost = site: host: role: {
    bootstrap = false;
    module = import ./nixos/nl-site {
      inherit site host role;
      package = packageFor site;
    };
  };

  siteHosts =
    site:
    lib.listToAttrs (
      map (n: lib.nameValuePair n.name (mkSiteHost site n.name "node")) site.nodes
      ++ [
        (lib.nameValuePair site.rig.name (mkSiteHost site site.rig.name "rig"))
        (lib.nameValuePair site.builder.name (mkSiteHost site site.builder.name "builder"))
      ]
    );
in
lib.foldl' (acc: site: acc // siteHosts site) { } (lib.attrValues generated)
