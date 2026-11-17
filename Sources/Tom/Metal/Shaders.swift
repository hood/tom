// Compiled at runtime with MTLDevice.makeLibrary(source:), so no Metal toolchain is needed to build.
enum ShaderSource {
    static let code = #"""
#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------- shared

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float hash11(float x) { return fract(sin(x * 127.1 + 311.7) * 43758.5453); }

static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash21(i), b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * vnoise(p);
        p = p * 2.03 + float2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

// cyan -> violet -> magenta -> red, must match Palette.swift
static float3 palette(float f) {
    float3 c0 = float3(0.20, 0.85, 1.00);
    float3 c1 = float3(0.55, 0.40, 1.00);
    float3 c2 = float3(1.00, 0.30, 0.60);
    float3 c3 = float3(1.00, 0.10, 0.08);
    if (f < 0.33) return mix(c0, c1, f / 0.33);
    if (f < 0.66) return mix(c1, c2, (f - 0.33) / 0.33);
    return mix(c2, c3, (f - 0.66) / 0.34);
}

// ---------------------------------------------------------------- plasma orb / aurora

struct PlasmaUniforms {
    float time; float fullness; float hover; float morph;
    float sizeX; float sizeY; float radiusMin; float radiusMax;
    float glow; float intensity; float pad; float pulse;
};

struct VOut { float4 pos [[position]]; float2 uv; };

vertex VOut plasma_vertex(uint vid [[vertex_id]]) {
    float2 p = float2(vid == 1 ? 3.0 : -1.0, vid == 2 ? 3.0 : -1.0);
    VOut o;
    o.pos = float4(p, 0.0, 1.0);
    o.uv = p;
    return o;
}

fragment float4 plasma_fragment(VOut in [[stage_in]], constant PlasmaUniforms& u [[buffer(0)]]) {
    float2 sz = float2(u.sizeX, u.sizeY);
    float m = min(sz.x, sz.y);
    float2 p = in.uv * sz / m;
    float t = u.time;
    float f = clamp(u.fullness, 0.0, 1.0);
    float3 core = palette(f);
    float speed = 0.45 + 1.6 * f;

    // ---- orb: a glass sphere filling up with boiling plasma
    float R = mix(u.radiusMin, u.radiusMax, f) * (1.0 + 0.1 * u.hover + 0.08 * u.pulse);
    float2 q = p / R;
    float r = length(q);
    float level = mix(-1.08, 0.94, f);
    float wave = (0.07 * sin(q.x * 5.0 + t * 2.3 * speed) + 0.04 * sin(q.x * 11.0 - t * 3.4 * speed)
                  + 0.025 * sin(q.x * 19.0 + t * 5.0)) * (0.55 + f);
    float surface = level + wave;
    float edgeW = max(fwidth(q.y), 0.02);
    float liquid = smoothstep(surface + edgeW * 1.5, surface - edgeW * 1.5, q.y);

    float2 w = q * 1.4;
    float2 warp = float2(fbm(w + float2(0.0, t * 0.35 * speed)), fbm(w + float2(5.2, -t * 0.3 * speed)));
    float n = fbm(w * 1.3 + warp * 2.2 + float2(t * 0.15, -t * 0.45 * speed));
    float fil = pow(1.0 - abs(n * 2.0 - 1.0), 7.0);
    float3 hotc = mix(core, float3(1.0, 0.96, 0.92), 0.5);
    float3 deep = core * 0.16 + float3(0.02, 0.0, 0.04);
    float3 liq = mix(deep, core, smoothstep(0.2, 0.85, n)) + hotc * fil * (0.7 + 0.9 * f);
    liq += hotc * exp(-abs(q.y - surface) * 22.0) * (0.35 + 0.6 * f);
    float3 gas = core * (0.07 + 0.1 * n);
    float3 inside = mix(gas, liq, liquid) * (0.9 + 0.45 * u.hover + 0.7 * u.pulse);

    float rim = smoothstep(0.62, 1.0, r);
    inside += core * rim * 0.5 + float3(pow(rim, 8.0) * 0.3);
    inside += float3(exp(-length(q - float2(-0.36, 0.42)) * 6.5) * 0.6);

    float aa = max(fwidth(r), 0.001);
    float sphere = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
    float breathe = 0.82 + 0.18 * sin(t * (1.2 + 2.6 * f));
    float glowA = u.glow * exp(-max(r - 1.0, 0.0) * 3.0) * (0.22 + 0.6 * f + 0.35 * u.hover) * breathe * (1.0 - sphere);
    float3 orbRGB = inside * sphere + core * glowA;
    float orbA = sphere + glowA * 0.5;

    // ---- aurora: what the orb dissolves into behind the panel
    float2 ap = in.uv * sz / 240.0;
    float n1 = fbm(ap * 1.1 + float2(t * 0.05, t * 0.035));
    float n2 = fbm(ap * 1.9 + float2(-t * 0.04, t * 0.06) + n1 * 1.5);
    float band = smoothstep(0.32, 0.85, n2);
    float3 acol = mix(core, float3(0.35, 0.45, 1.0), smoothstep(0.3, 0.7, n1));
    float topFade = 0.35 + 0.65 * (in.uv.y * 0.5 + 0.5);
    float3 aur = acol * band * u.intensity * topFade * 1.6;

    float mp = smoothstep(0.0, 0.75, u.morph);
    return float4(mix(orbRGB, aur, mp), mix(orbA, 0.0, mp));
}

// ---------------------------------------------------------------- disintegration particles

struct ParticleUniforms {
    float originX; float originY; float rowW; float rowH;
    float viewW; float viewH; float texW; float texH;
    float time; float seed; float pointScale; float texScale;
};

struct POut {
    float4 pos [[position]];
    float size [[point_size]];
    float4 color;
    float shape;
};

vertex POut particle_vertex(uint vid [[vertex_id]],
                            constant ParticleUniforms& u [[buffer(0)]],
                            texture2d<float> tex [[texture(0)]]) {
    POut o;
    uint gw = uint(u.texW);
    float2 cell = float2(float(vid % gw), float(vid / gw));
    float2 uv = (cell + 0.5) / float2(u.texW, u.texH);
    constexpr sampler s(coord::normalized, filter::nearest, address::clamp_to_edge);
    float4 c = tex.sample(s, uv, level(0.0));
    if (c.a < 0.02) {
        o.pos = float4(4.0, 4.0, 0.0, 1.0); o.size = 0.0; o.color = float4(0.0); o.shape = 0.0;
        return o;
    }
    float fid = float(vid);
    float h1 = hash11(fid + u.seed);
    float h2 = hash11(fid * 1.37 + u.seed * 3.1);
    float h3 = hash11(fid * 2.11 + u.seed * 7.7);
    float2 origin = float2(u.originX, u.originY) + uv * float2(u.rowW, u.rowH);

    // ragged burn front sweeping left -> right
    float ragged = vnoise(origin * 0.07 + u.seed) * 0.26 + h1 * 0.05;
    float delay = uv.x * 0.62 + ragged;
    float lt = u.time - delay;
    float active = step(0.0, lt);
    lt = max(lt, 0.0);
    float life = 0.75 + h2 * 0.75;
    float p = clamp(lt / life, 0.0, 1.0);

    // ash drifting up and right with turbulence
    float2 dir = normalize(float2(0.35 + h3 * 1.1, -0.9 - h1 * 0.9));
    float speed = 25.0 + h2 * 115.0;
    float2 pos = origin + dir * speed * lt + float2(22.0, -85.0) * lt * lt;
    pos.x += sin(origin.y * 0.2 + lt * 6.0 + h3 * 6.283) * 11.0 * p;
    pos.y += cos(origin.x * 0.07 + lt * 4.5 + h1 * 6.283) * 7.0 * p;

    float heat = active * smoothstep(0.0, 0.05, p) * (1.0 - smoothstep(0.05, 0.6, p));
    float pre = (1.0 - active) * smoothstep(-0.14, 0.0, u.time - delay);
    float3 ember = mix(float3(1.0, 0.30, 0.62), float3(1.0, 0.74, 0.30), h3);
    float3 base = c.rgb / max(c.a, 0.001);
    float glowAmt = clamp(max(heat, pre * 0.75), 0.0, 1.0);
    float3 col = mix(base, ember * 1.9, glowAmt);
    float alpha = c.a * (1.0 - smoothstep(0.25, 1.0, p));
    // emissive pixels carry less alpha so they add light
    o.color = float4(col * alpha, alpha * (1.0 - 0.8 * glowAmt));

    float texel = u.pointScale / u.texScale;
    float big = step(0.985, h1) * 2.5;
    o.size = texel * (1.08 + active * (1.0 + h2 * 2.2 + big) * (1.0 - p * 0.5));
    o.pos = float4(pos.x / u.viewW * 2.0 - 1.0, 1.0 - pos.y / u.viewH * 2.0, 0.0, 1.0);
    o.shape = active;
    return o;
}

fragment float4 particle_fragment(POut in [[stage_in]], float2 pc [[point_coord]]) {
    float d = length(pc - 0.5) * 2.0;
    float soft = 1.0 - smoothstep(0.25, 1.0, d);
    return in.color * mix(1.0, soft, in.shape);
}
"""#
}
