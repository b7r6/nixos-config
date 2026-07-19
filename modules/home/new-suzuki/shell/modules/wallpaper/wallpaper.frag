#version 440

// ============================================================================
// wallpaper.frag — the animated background field.
//
// One shader, morphing along the register axis (uniform `reg`):
//
//   affluent (reg → 0)   paired ambient blooms on ~40s/50s orbits — the
//                        "Swiss orbital bank" glow — plus fine grain
//   facility (reg → 1)   telemetry constellation (sparse pulsing points on a
//                        jittered grid) + fine scanlines + one slow drifting
//                        bright line (~8s period)
//
// Palette arrives as uniforms from ThemeService (wintermute theme.json), so
// day/night and hero-hue changes morph the field live — QML Behaviors ease
// reg and the colors, the shader just renders the current mix.
//
// Compiled to wallpaper.frag.qsb by qsb (qt6.qtshadertools) in the Nix build.
// ============================================================================

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float reg;
    float grain;
    float aspect;
    vec4 surface;
    vec4 paper;
    vec4 accent;
    vec4 accentD;
};

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);

    // Base field: slow-breathing gradient between paper and surface, gentle
    // vignette pulling the corners down.
    float grad = smoothstep(-0.9, 0.9, p.y + 0.15 * sin(time * 0.03));
    vec3 col = mix(paper.rgb, surface.rgb, grad);
    col *= 1.0 - 0.35 * dot(p, p);

    // ── Affluent pole: paired ambient blooms (~40s / ~50s orbits) ──────────
    float aff = 1.0 - reg;
    if (aff > 0.001) {
        vec2 b1 = 0.42 * vec2(sin(time * 0.157), sin(time * 0.111));
        vec2 b2 = 0.38 * vec2(sin(time * 0.126 + 2.1), sin(time * 0.089 + 1.3));
        float g1 = exp(-9.0 * dot(p - b1, p - b1));
        float g2 = exp(-7.0 * dot(p - b2, p - b2));
        col += aff * (0.10 * g1 * accent.rgb + 0.07 * g2 * accentD.rgb);
    }

    // ── Facility pole: constellation + scanline drift ──────────────────────
    if (reg > 0.001) {
        // Sparse pulsing points on a jittered grid.
        vec2 gp = p * 14.0;
        vec2 cell = floor(gp);
        vec2 cuv = fract(gp) - 0.5;
        float h = hash(cell);
        vec2 jitter = vec2(hash(cell + 1.7), hash(cell + 3.1)) - 0.5;
        float d = length(cuv - 0.7 * jitter);
        float pulse = 0.5 + 0.5 * sin(time * (0.5 + h) + h * 6.2832);
        float star = step(0.982, h) * smoothstep(0.06, 0.0, d) * pulse;
        col += reg * 0.35 * star * accent.rgb;

        // Fine static lines + one slow bright line drifting down (~8s).
        float lines = 0.5 + 0.5 * sin(uv.y * 1200.0);
        col -= reg * 0.020 * lines;
        float drift = fract(uv.y - time * 0.125);
        col += reg * 0.030 * smoothstep(0.012, 0.0, min(drift, 1.0 - drift)) * accent.rgb;
    }

    // Grain rides the affluent token (ThemeService scales it).
    col += (hash(uv * vec2(1920.0, 1080.0) + fract(time)) - 0.5) * grain;

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
