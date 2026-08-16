#version 440

// ============================================================================
// wallpaper.frag — the animated background field, v2.
//
// One shader, three consumers (desktop layer, lock screen, greeter), morphing
// along the register axis (uniform `reg`):
//
//   affluent (reg → 0)   two-octave nebula depth + paired bloom orbits
//                        (~40s/50s) + the orbital horizon: a planet limb low
//                        in the frame with terminator lights and atmosphere
//                        thinning upward
//   facility (reg → 1)   telemetry constellation (glinting stars + a faint
//                        mesh linking neighbors) + fine scanlines + an ~8s
//                        drifting bright line + character-cell data columns
//                        with glyph churn + the SM-OCCUPANCY BEAM CURTAINS
//
// LIVE MACHINE: `load` (GPU utilization 0..1) and `power` (draw, normalized)
// come from SystemMonitorService — the wallpaper is a readout of the box.
// Idle is calm; under inference the curtains rise, the rain turns torrential,
// the field warms. On a DGX Spark the background IS the workload.
//
// Day (maas) reads the same phenomena as PRINT: ink lines and darkening on
// paper instead of additive glow. Polarity is inferred from surface luma —
// no extra uniforms.
//
// Always-on ordered dither (±0.6/255) kills 8-bit banding on OLED darks —
// the slow near-black gradients are unwatchable without it.
//
// The reconcile sweep: QML animates `sweep` -0.15 → 1.15 on wintermute
// generation bumps; parked outside [0,1] it costs nothing.
//
// Compiled to wallpaper.frag.qsb by qsb (qt6.qtshadertools) at build time.
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
    float sweep;
    float load;
    float power;
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

// Smooth value noise + two octaves — the nebula base.
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm2(vec2 p) {
    return 0.65 * vnoise(p) + 0.35 * vnoise(p * 2.13 + 17.7);
}

// Star position for a constellation cell (jittered), or w < gate for none.
vec3 starIn(vec2 cell, float gate) {
    float h = hash(cell);
    vec2 jitter = (vec2(hash(cell + 1.7), hash(cell + 3.1)) - 0.5) * 0.7;
    return vec3(jitter, step(gate, h));
}

float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
    return length(p - a - ab * t);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);

    float lum = dot(surface.rgb, vec3(0.299, 0.587, 0.114));
    float night = 1.0 - step(0.5, lum);
    float aff = 1.0 - reg;

    // ── Base field ─────────────────────────────────────────────────────────
    // Breathing gradient; nebula depth grows toward the affluent pole and
    // fades toward the flat console of the facility. Day gets a soft paper
    // sheen instead of a hard vignette.
    float grad = smoothstep(-0.9, 0.9, p.y + 0.15 * sin(time * 0.03));
    vec3 col = mix(paper.rgb, surface.rgb, grad);

    float neb = fbm2(p * 1.6 + vec2(time * 0.008, -time * 0.005));
    neb = neb * neb;
    col += night * aff * 0.045 * neb * mix(accent.rgb, accentD.rgb, 0.5);

    // Day wash: much livelier than night's — visible ink clouds drifting,
    // an accent-tinted counter-current underneath.
    float dayNeb = fbm2(p * 1.3 + vec2(time * 0.020, -time * 0.012));
    dayNeb = dayNeb * dayNeb;
    float dayNeb2 = fbm2(p * 2.4 - vec2(time * 0.014, time * 0.009) + 31.7);
    col -= (1.0 - night) * (0.050 * dayNeb + 0.022 * dayNeb2 * dayNeb2);
    col = mix(col, col * mix(vec3(1.0), accent.rgb * 1.35, 0.10),
              (1.0 - night) * dayNeb);

    float vig = dot(p, p);
    col *= 1.0 - mix(0.20, 0.35, night) * vig;

    // Live warm-up: a working GPU lifts the whole field a touch (additive at
    // night, a faint ink cool by day) — present at BOTH poles so even the calm
    // affluent desktop shows the machine breathing.
    col += night * load * 0.022 * mix(accent.rgb, accentD.rgb, 0.5);
    col -= (1.0 - night) * load * 0.012;

    // ── Affluent: bloom orbits + the orbital horizon ───────────────────────
    if (aff > 0.001) {
        vec2 b1 = 0.42 * vec2(sin(time * 0.157), sin(time * 0.111));
        vec2 b2 = 0.38 * vec2(sin(time * 0.126 + 2.1), sin(time * 0.089 + 1.3));
        float g1 = exp(-9.0 * dot(p - b1, p - b1));
        float g2 = exp(-7.0 * dot(p - b2, p - b2));
        col += night * aff * (0.10 * g1 * accent.rgb + 0.07 * g2 * accentD.rgb);
        col -= (1.0 - night) * aff * (0.030 * g1 + 0.020 * g2);

        // The limb. Night: glow + atmosphere + terminator lights drifting
        // slowly along it. Day: a printed ink line with a whisper of wash.
        vec2 hc = vec2(0.0, 1.9);
        float dHor = length(p - hc) - 1.62;
        float limb = exp(-55.0 * abs(dHor));
        float atmo = exp(-6.0 * max(0.0, dHor));
        vec3 horizonTint = mix(accent.rgb, accentD.rgb, 0.35);
        col += night * aff * (0.09 * limb + 0.025 * atmo) * horizonTint;
        col -= (1.0 - night) * aff * (0.10 * limb + 0.008 * atmo);

        float lightCell = floor((p.x + time * 0.004) * 70.0);
        float lh = hash(vec2(lightCell, 7.7));
        float lights = smoothstep(0.010, 0.0, abs(dHor))
                     * step(0.90, lh)
                     * (0.6 + 0.4 * sin(time * (0.8 + lh) + lh * 6.2832));
        col += night * aff * 0.16 * lights * accentD.rgb;
    }

    // ── Facility: constellation mesh + scanlines + data columns ────────────
    if (reg > 0.001) {
        // SM-occupancy beam curtains: columns rising from the floor, one per
        // notional SM, heights driven by live GPU load. At idle a low
        // flickering baseline; under work they climb and the tips go
        // incandescent with power draw. The reference-reel signature, wired to
        // the actual chip. Night = additive accent glow; day = ink histogram.
        float NCOL = 54.0;
        float ci = floor(uv.x * NCOL);
        float cf = fract(uv.x * NCOL);
        float ch2 = hash(vec2(ci, 23.1));
        float wob = 0.5 + 0.5 * sin(time * (0.7 + 1.8 * ch2) + ch2 * 6.2832);
        float colH = (0.015 + 0.05 * ch2) + load * (0.40 + 0.48 * ch2) * (0.6 + 0.4 * wob);
        float yUp = 1.0 - uv.y;
        float cwidth = smoothstep(0.5, 0.17, abs(cf - 0.5));
        float body = cwidth * (1.0 - smoothstep(colH - 0.02, colH, yUp))
                   * (0.35 + 0.65 * clamp(yUp / max(colH, 1e-3), 0.0, 1.0));
        float tip = cwidth * smoothstep(0.022, 0.0, abs(yUp - colH));
        // tips heat toward white as the chip pulls power
        vec3 tipCol = mix(accentD.rgb, vec3(1.0), 0.35 * power);
        float surge = 0.10 + 0.90 * load;   // idle nearly bare, inference ablaze
        col += night * reg * surge * (0.055 * body * accent.rgb + 0.26 * tip * tipCol);
        col -= (1.0 - night) * reg * (0.045 * body + 0.10 * tip);

        // Constellation: glinting stars on a jittered grid, faint mesh
        // linking horizontally/vertically adjacent stars — the telemetry net.
        float GATE = 0.978;
        vec2 gp = p * 14.0;
        vec2 cell = floor(gp);
        vec2 cuv = fract(gp) - 0.5;

        vec3 s0 = starIn(cell, GATE);
        float h0 = hash(cell);
        float pulse = 0.5 + 0.5 * sin(time * (0.5 + h0) + h0 * 6.2832);
        float d = length(cuv - s0.xy);
        float core = smoothstep(0.055, 0.0, d);
        float glintX = smoothstep(0.16, 0.0, abs(cuv.x - s0.x)) * smoothstep(0.012, 0.0, abs(cuv.y - s0.y));
        float glintY = smoothstep(0.16, 0.0, abs(cuv.y - s0.y)) * smoothstep(0.012, 0.0, abs(cuv.x - s0.x));
        float star = s0.z * (core + 0.55 * (glintX + glintY)) * pulse;
        col += night * reg * 0.33 * star * accent.rgb;
        col -= (1.0 - night) * reg * 0.22 * star;

        // Mesh: this cell's star to its right/down neighbors' stars.
        float mesh = 0.0;
        vec3 sr = starIn(cell + vec2(1, 0), GATE);
        vec3 sd = starIn(cell + vec2(0, 1), GATE);
        if (s0.z > 0.5 && sr.z > 0.5)
            mesh += smoothstep(0.020, 0.0, segDist(cuv, s0.xy, sr.xy + vec2(1, 0)));
        if (s0.z > 0.5 && sd.z > 0.5)
            mesh += smoothstep(0.020, 0.0, segDist(cuv, s0.xy, sd.xy + vec2(0, 1)));
        float meshGate = smoothstep(0.6, 1.0, reg);   // links only near the pole
        col += night * meshGate * 0.05 * mesh * accent.rgb;
        col -= (1.0 - night) * meshGate * 0.04 * mesh;

        // Fine static lines + one slow bright line drifting down (~8s).
        float lines = 0.5 + 0.5 * sin(uv.y * 1200.0);
        col -= reg * 0.020 * lines;
        float drift = fract(uv.y - time * 0.125);
        float driftLine = smoothstep(0.012, 0.0, min(drift, 1.0 - drift));
        col += night * reg * 0.030 * driftLine * accent.rgb;
        col -= (1.0 - night) * reg * 0.020 * driftLine;

        // Data columns, character-cell quantized with glyph churn: trails
        // read as cells shimmering, not smooth streaks.
        float colId = floor(p.x * 26.0);
        float ch = hash(vec2(colId, 3.7));
        float head = fract(time * (0.04 + 0.11 * ch) * (1.0 + 2.2 * load) + ch * 7.31);
        float dCol = head - uv.y;
        float trail = smoothstep(0.35, 0.0, abs(dCol)) * step(0.0, dCol);
        float core2 = smoothstep(0.45, 0.10, abs(fract(p.x * 26.0) - 0.5));
        float cellY = floor(uv.y * 90.0);
        float glyph = 0.30 + 0.70 * hash(vec2(colId * 3.1, cellY + floor(time * (6.0 + 18.0 * load)) * 0.13));
        float rain = trail * core2 * glyph * step(0.72 - 0.30 * load, ch);
        col += night * reg * 0.050 * rain * accent.rgb;
        col -= (1.0 - night) * reg * 0.032 * rain;
    }

    // ── Day signature: the MAAS BIOCHIP ────────────────────────────────────
    // Maas Biolabs makes biochips. The paper carries a living circuit:
    // sparse horizontal traces printed in ink, accent-colored signal pulses
    // running the lanes (per-lane speed and direction), via dots at the
    // junction grid. Present at BOTH registers — brand identity, not
    // register effect — but trace density leans facility.
    if (night < 0.5) {
        float laneRow = floor(uv.y * 30.0);
        float lh = hash(vec2(laneRow, 11.3));
        float laneGate = step(0.60 - 0.15 * reg, lh);
        float lineD = abs(fract(uv.y * 30.0) - 0.5);
        float trace = smoothstep(0.10, 0.03, lineD) * laneGate;

        // printed trace
        col -= 0.030 * trace;

        // the signal: an accent pulse with an ink trail
        float dir = lh > 0.80 ? 1.0 : -1.0;
        float speed = (0.06 + 0.18 * hash(vec2(laneRow, 5.1))) * (1.0 + 1.6 * load);
        float along = fract(p.x * 0.5 / aspect + 0.5 - dir * time * speed + lh * 9.0);
        float pulse = smoothstep(0.020, 0.004, along);
        float tail = smoothstep(0.16, 0.0, along) * 0.30;
        col = mix(col, accent.rgb, trace * pulse * 0.85);
        col = mix(col, accent.rgb, trace * tail * 0.30);

        // vias where lanes meet the column grid
        float colX = floor(p.x * 22.0);
        float vh = hash(vec2(colX, laneRow));
        vec2 cellUV = vec2(fract(p.x * 22.0) - 0.5, fract(uv.y * 30.0) - 0.5);
        float via = step(0.88, vh) * laneGate * smoothstep(0.14, 0.06, length(cellUV));
        col -= 0.045 * via;
    }

    // ── The reconcile sweep ────────────────────────────────────────────────
    if (sweep > -0.5) {
        float ds = uv.y - sweep;
        float line = smoothstep(0.005, 0.0, abs(ds));
        float trailS = smoothstep(0.15, 0.0, -ds) * step(ds, 0.0);
        col += night * (0.22 * line + 0.05 * trailS) * accent.rgb;
        col -= (1.0 - night) * (0.12 * line + 0.03 * trailS);
    }

    // ── Grain (affluent token) + ALWAYS-ON dither ──────────────────────────
    col += (hash(uv * vec2(1920.0, 1080.0) + fract(time)) - 0.5) * grain;
    col += (hash(uv * vec2(3840.0, 2160.0) + fract(time * 0.37)) - 0.5) * (1.2 / 255.0);

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
