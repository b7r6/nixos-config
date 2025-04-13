{ ... }:
{
  nix = {
    buildMachines = [
      {

        hostName = "beratna";
        system = "x86_64-linux"; # or whatever architecture
        maxJobs = 8;

        speedFactor = 2;

        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];

        mandatoryFeatures = [ ];
      }
    ];

    distributedBuilds = true;

    extraOptions = ''
      builders-use-substitutes = true
    '';
  };
}
