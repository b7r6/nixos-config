# ono-sendai-blue - black level variations
# range from pure black to github's default
# stepwise calculated for perceptual uniformity in HSL space
{

  #
  # base16Scheme = ono-sendai-void;    # L=0%  - true black
  # base16Scheme = ono-sendai-deep;    # L=4%  - hand-tuned default
  # base16Scheme = ono-sendai-night;   # L=8%  - oled threshold
  # base16Scheme = ono-sendai-carbon;  # L=11% - good default
  # base16Scheme = ono-sendai-github;  # L=16% - highly robust
  #

  # n.b. this was eyeballed on low resolution LCDs, very flawed
  # in the execution but something about it works...
  untuned = {
    slug = "ono-sendai-blue-untuned";
    name = "Ono-Sendai Hyper Modern Blue";
    author = "b7r6";
    variant = "dark";

    palette = {
      base00 = "#090b0e";
      base01 = "#13161a";
      base02 = "#1a1f24";
      base03 = "#23292f";
      base04 = "#23292f";
      base05 = "#d8e0e7";
      base06 = "#596775";
      base07 = "#ddf4ff";
      base08 = "#b6e3ff";
      base09 = "#80ccff";
      base0A = "#54aeff";
      base0B = "#218bff";
      base0C = "#0969da";
      base0D = "#54aeff";
      base0E = "#80ccff";
      base0F = "#218bff";
    };
  };

  memphis = {
    slug = "ono-sendai-memphis";
    name = "Ono-Sendai Memphis";
    author = "opus-4";
    variant = "dark";
    palette = {
      base00 = "#000000"; # L=0% - kills berkeley mono and other foundry fonts
      base01 = "#0a0d10"; # L=5% -
      base02 = "#13161a"; # original base01
      base03 = "#1a1f24"; # original base02
      base04 = "#596775";
      base05 = "#d8e0e7";
      base06 = "#ddf4ff";
      base07 = "#e6f7ff";
      base08 = "#b6e3ff";
      base09 = "#80ccff";
      base0A = "#54aeff";
      base0B = "#218bff";
      base0C = "#0969da";
      base0D = "#4d9fff";
      base0E = "#6cb6ff";
      base0F = "#1f6feb";
    };
  };

  chiba = {
    slug = "ono-sendai-chiba";
    name = "Ono-Sendai-chiba";
    author = "opus-4";
    variant = "dark";
    palette = {
      base00 = "#090b0e"; # L=4% - problematic on the samsung panels
      base01 = "#13161a"; # L=8%
      base02 = "#1a1f24"; # L=12%
      base03 = "#23292f"; # L=16%
      base04 = "#596775";
      base05 = "#d8e0e7";
      base06 = "#ddf4ff";
      base07 = "#e6f7ff";
      base08 = "#b6e3ff";
      base09 = "#80ccff";
      base0A = "#54aeff";
      base0B = "#218bff";
      base0C = "#0969da";
      base0D = "#4d9fff";
      base0E = "#6cb6ff";
      base0F = "#1f6feb";
    };
  };

  razorgirl = {
    slug = "ono-sendai-razorgirl";
    name = "Ono-Sendai Razorgirl";
    author = "b7r6/opus-4";
    variant = "dark";
    palette = {
      base00 = "#111417"; # L=8% - attempt to preserve strokes
      base01 = "#181c21"; # L=11%
      base02 = "#21262d"; # L=15%
      base03 = "#2b323a"; # L=19%
      base04 = "#596775";
      base05 = "#d8e0e7";
      base06 = "#ddf4ff";
      base07 = "#e6f7ff";
      base08 = "#b6e3ff"; # HSL(201° 100% 86%) - shifted cool, high luminance
      base09 = "#80ccff"; # HSL(201° 100% 75%) - same hue, darker
      base0A = "#54aeff"; # HSL(211° 100% 66%) - hero
      base0B = "#218bff"; # HSL(211° 100% 57%) - same hue, darker
      base0C = "#0969da"; # HSL(211° 94% 45%)  - desaturated
      base0D = "#4d9fff"; # HSL(211° 100% 65%) - tiny luminance shift
      base0E = "#6cb6ff"; # HSL(211° 100% 71%) - lighter variant
      base0F = "#1f6feb"; # HSL(211° 86% 53%)  - desaturated dark
    };
  };

  sprawl = {
    slug = "ono-sendai-sprawl";
    name = "Ono-Sendai Carbon Sprawl";
    author = "b7r6";
    variant = "dark";
    palette = {
      base00 = "#191c20"; # L=11% - Best compromise
      base01 = "#1f232a"; # L=14%
      base02 = "#2a3039"; # L=19%
      base03 = "#3a424f"; # L=28%
      base04 = "#596775";
      base05 = "#d8e0e7";
      base06 = "#ddf4ff";
      base07 = "#e6f7ff";
      base08 = "#b6e3ff";
      base09 = "#80ccff";
      base0A = "#54aeff";
      base0B = "#218bff";
      base0C = "#0969da";
      base0D = "#4d9fff";
      base0E = "#6cb6ff";
      base0F = "#1f6feb";
    };
  };

  github = {
    slug = "ono-sendai-github";
    name = "Ono-Sendai GitHub";
    author = "b7r6";
    variant = "dark";
    palette = {
      base00 = "#22272e"; # L=16% - github's de-facto default dark mode
      base01 = "#2d333b"; # L=20%
      base02 = "#444c56"; # L=31%
      base03 = "#545d68"; # L=38%
      base04 = "#596775";
      base05 = "#d8e0e7";
      base06 = "#ddf4ff";
      base07 = "#e6f7ff";
      base08 = "#b6e3ff";
      base09 = "#80ccff";
      base0A = "#54aeff";
      base0B = "#218bff";
      base0C = "#0969da";
      base0D = "#4d9fff";
      base0E = "#6cb6ff";
      base0F = "#1f6feb";
    };
  };

  tuned = {
    slug = "ono-sendai-blue-tuned";
    name = "Ono-Sendai Hyper Modern Blue (HSL Tuned)";
    author = "opus-4";
    variant = "dark";
    palette = {
      # grayscale ramp - perceptually uniform with blue tint (211° hue)
      # OLED-safe: starts at L=11% instead of pure black
      base00 = "#191c20"; # HSL(211° 12% 11%) - OLED-safe background
      base01 = "#1f232a"; # HSL(211° 16% 14%) - raised surfaces
      base02 = "#2a3039"; # HSL(211° 17% 19%) - selections
      base03 = "#3a424f"; # HSL(211° 15% 28%) - comments
      base04 = "#6b7689"; # HSL(211° 12% 48%) - dark foreground
      base05 = "#c5d0dd"; # HSL(211° 28% 81%) - default foreground
      base06 = "#dce3ec"; # HSL(211° 32% 89%) - light foreground
      base07 = "#f0f4f8"; # HSL(211° 36% 95%) - light background

      # Accent colors - systematic relationships to hero blue
      # Hero: #54aeff at 211° (your rule-breaker)
      base08 = "#b6e3ff"; # HSL(201° 100% 86%) - Ice blue (shifted cool, high luminance)
      base09 = "#80ccff"; # HSL(201° 100% 75%) - Sky blue (same hue, darker)
      base0A = "#54aeff"; # HSL(211° 100% 66%) - HERO: Electric blue (the heresy)
      base0B = "#218bff"; # HSL(211° 100% 57%) - Deep blue (same hue, darker)
      base0C = "#0969da"; # HSL(211° 94% 45%) - Matrix blue (desaturated)
      base0D = "#4d9fff"; # HSL(211° 100% 65%) - Link blue (tiny luminance shift)
      base0E = "#6cb6ff"; # HSL(211° 100% 71%) - Soft electric (lighter variant)
      base0F = "#1f6feb"; # HSL(211° 86% 53%) - Corp blue (desaturated dark)
    };
  };

  # for comparison: version with more hue variance while maintaining discipline
  spectrum = {
    slug = "ono-sendai-blue-spectrum";
    name = "Ono-Sendai Blue Spectrum (HSL Tuned)";
    author = "opus-4";
    variant = "dark";
    palette = {
      # grayscale ramp
      base00 = "#191c20"; # HSL(211° 12% 11%)
      base01 = "#1f232a"; # HSL(211° 16% 14%)
      base02 = "#2a3039"; # HSL(211° 17% 19%)
      base03 = "#3a424f"; # HSL(211° 15% 28%)
      base04 = "#6b7689"; # HSL(211° 12% 48%)
      base05 = "#c5d0dd"; # HSL(211° 28% 81%)
      base06 = "#dce3ec"; # HSL(211° 32% 89%)
      base07 = "#f0f4f8"; # HSL(211° 36% 95%)

      # controlled hue shifts (±30° max from hero)
      base08 = "#b6e3ff"; # HSL(201° 100% 86%) - Variables (cool shift)
      base09 = "#7dd3ff"; # HSL(201° 100% 74%) - Integers
      base0A = "#54aeff"; # HSL(211° 100% 66%) - Classes (HERO)
      base0B = "#4eb8ff"; # HSL(201° 100% 65%) - Strings (cool shift)
      base0C = "#47c0ff"; # HSL(201° 100% 64%) - Support
      base0D = "#5ba3ff"; # HSL(221° 100% 68%) - Functions (warm shift)
      base0E = "#6c95ff"; # HSL(231° 100% 71%) - Keywords (warmer)
      base0F = "#1f6feb"; # HSL(211° 86% 53%) - Deprecated
    };
  };
}
