# ono-sendai-tactical.nix - Military tactical variants
# Chiba and Razorgirl black balances with MIL-STD, Friendly, and Bandit palettes
{
  # Chiba black balance (L=4-16%) with MIL-STD green
  milstd-chiba = {
    slug = "ono-sendai-milstd-chiba";
    name = "Ono-Sendai MIL-STD Chiba";
    author = "opus-4/b7r6";
    variant = "dark";
    palette = {
      base00 = "#090b0e"; # L=4%
      base01 = "#13161a"; # L=8%
      base02 = "#1a1f24"; # L=12%
      base03 = "#23292f"; # L=16%
      base04 = "#596775";
      base05 = "#d8e0e7";
      base06 = "#ddf4ff";
      base07 = "#e6f7ff";
      base08 = "#a8d5a8"; # HSL(120° 35% 74%) - Sage green
      base09 = "#8bc48b"; # HSL(120° 35% 65%) - Field green
      base0A = "#4B7C4B"; # HSL(120° 25% 39%) - MIL-STD green
      base0B = "#5a9c5a"; # HSL(120° 28% 48%) - Forest green
      base0C = "#6b8e6b"; # HSL(120° 14% 48%) - Olive drab
      base0D = "#4d8b6a"; # HSL(150° 28% 42%) - Tactical teal
      base0E = "#7a9c8c"; # HSL(150° 12% 54%) - Desert sage
      base0F = "#3d6b3d"; # HSL(120° 28% 32%) - Deep tactical
    };
  };

  # Razorgirl black balance (L=8-19%) with MIL-STD green
  milstd-razorgirl = {
    slug = "ono-sendai-milstd-razorgirl";
    name = "Ono-Sendai MIL-STD Razorgirl";
    author = "opus-4/b7r6";
    variant = "dark";
    palette = {
      base00 = "#111417"; # L=8%
      base01 = "#181c21"; # L=11%
      base02 = "#21262d"; # L=15%
      base03 = "#2b323a"; # L=19%
      base04 = "#596775";
      base05 = "#d8e0e7";
      base06 = "#ddf4ff";
      base07 = "#e6f7ff";
      base08 = "#a8d5a8";
      base09 = "#8bc48b";
      base0A = "#4B7C4B";
      base0B = "#5a9c5a";
      base0C = "#6b8e6b";
      base0D = "#4d8b6a";
      base0E = "#7a9c8c";
      base0F = "#3d6b3d";
    };
  };

  # Chiba black balance with Friendly blue
  friendly-chiba = {
    slug = "ono-sendai-friendly-chiba";
    name = "Ono-Sendai Friendly Chiba";
    author = "opus-4/b7r6";
    variant = "dark";
    palette = {
      base00 = "#090b0e";
      base01 = "#13161a";
      base02 = "#1a1f24";
      base03 = "#23292f";
      base04 = "#596775";
      base05 = "#d8e0e7";
      base06 = "#ddf4ff";
      base07 = "#e6f7ff";
      base08 = "#87ceeb"; # HSL(197° 71% 72%) - Sky blue
      base09 = "#5f9fd8"; # HSL(210° 58% 60%) - NATO blue
      base0A = "#0066CC"; # HSL(210° 100% 40%) - Friendly Force blue
      base0B = "#4682b4"; # HSL(207° 44% 49%) - Steel blue
      base0C = "#1e90ff"; # HSL(210° 100% 56%) - Dodger blue
      base0D = "#0080ff"; # HSL(210° 100% 50%) - Bright friendly
      base0E = "#6495ed"; # HSL(219° 79% 66%) - Cornflower
      base0F = "#003f7f"; # HSL(210° 100% 25%) - Deep blue
    };
  };

  # Razorgirl black balance with Friendly blue
  friendly-razorgirl = {
    slug = "ono-sendai-friendly-razorgirl";
    name = "Ono-Sendai Friendly Razorgirl";
    author = "opus-4/b7r6";
    variant = "dark";
    palette = {
      base00 = "#111417";
      base01 = "#181c21";
      base02 = "#21262d";
      base03 = "#2b323a";
      base04 = "#596775";
      base05 = "#d8e0e7";
      base06 = "#ddf4ff";
      base07 = "#e6f7ff";
      base08 = "#87ceeb";
      base09 = "#5f9fd8";
      base0A = "#0066CC";
      base0B = "#4682b4";
      base0C = "#1e90ff";
      base0D = "#0080ff";
      base0E = "#6495ed";
      base0F = "#003f7f";
    };
  };

  # Chiba black balance with Bandit red
  bandit-chiba = {
    slug = "ono-sendai-bandit-chiba";
    name = "Ono-Sendai Bandit Chiba";
    author = "opus-4/b7r6";
    variant = "dark";
    palette = {
      base00 = "#090b0e";
      base01 = "#13161a";
      base02 = "#1a1f24";
      base03 = "#23292f";
      base04 = "#596775";
      base05 = "#d8e0e7";
      base06 = "#ddf4ff";
      base07 = "#e6f7ff";
      base08 = "#ff9999"; # HSL(0° 100% 80%) - Light hostile
      base09 = "#ff6b6b"; # HSL(0° 100% 71%) - Warning red
      base0A = "#CC0000"; # HSL(0° 100% 40%) - Hostile Force red
      base0B = "#dc143c"; # HSL(348° 83% 47%) - Crimson
      base0C = "#b22222"; # HSL(0° 68% 42%) - Firebrick
      base0D = "#ff0040"; # HSL(345° 100% 50%) - Threat red
      base0E = "#ff4444"; # HSL(0° 100% 63%) - Alert red
      base0F = "#8b0000"; # HSL(0° 100% 27%) - Dark red
    };
  };

  # Razorgirl black balance with Bandit red
  bandit-razorgirl = {
    slug = "ono-sendai-bandit-razorgirl";
    name = "Ono-Sendai Bandit Razorgirl";
    author = "opus-4/b7r6";
    variant = "dark";
    palette = {
      base00 = "#111417";
      base01 = "#181c21";
      base02 = "#21262d";
      base03 = "#2b323a";
      base04 = "#596775";
      base05 = "#d8e0e7";
      base06 = "#ddf4ff";
      base07 = "#e6f7ff";
      base08 = "#ff9999";
      base09 = "#ff6b6b";
      base0A = "#CC0000";
      base0B = "#dc143c";
      base0C = "#b22222";
      base0D = "#ff0040";
      base0E = "#ff4444";
      base0F = "#8b0000";
    };
  };
}
