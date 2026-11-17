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

static float fbmN(float2 p, int octaves) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < octaves; i++) {
        v += a * vnoise(p);
        p = p * 2.03 + float2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

static float fbm(float2 p) { return fbmN(p, 5); }

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
    float glow; float intensity; float wash; float pulse;
    float centerX; float centerY; float orbPts; float quality;
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
    float2 pts = float2((in.uv.x * 0.5 + 0.5) * sz.x, (0.5 - in.uv.y * 0.5) * sz.y);
    float2 c = u.centerX >= 0.0 ? float2(u.centerX, u.centerY) : sz * 0.5;
    float2 p = (pts - c) * float2(1.0, -1.0) / (0.5 * m);
    float t = u.time;
    float bloom = clamp(u.morph, 0.0, 1.0);
    // candy: 5-octave fbm + domain warp. perf: 2 octaves + a cheap sine warp.
    bool hq = u.quality > 0.5;
    int oct = hq ? 5 : 2;
    float f = clamp(u.fullness, 0.0, 1.0);
    float3 core = palette(f);
    float speed = 0.45 + 1.6 * f;

    // ---- orb: a glass sphere filling up with boiling plasma
    float R = mix(u.radiusMin, u.radiusMax, f) * (1.0 + 0.1 * u.hover + 0.08 * u.pulse);
    if (u.wash > 0.5) R = u.orbPts / (0.5 * m) * (1.0 + 0.9 * smoothstep(0.0, 0.3, bloom));
    float2 q = p / R;
    float r = length(q);
    float level = mix(-1.08, 0.94, f);
    float wave = (0.07 * sin(q.x * 5.0 + t * 2.3 * speed) + 0.04 * sin(q.x * 11.0 - t * 3.4 * speed)
                  + 0.025 * sin(q.x * 19.0 + t * 5.0)) * (0.55 + f);
    float surface = level + wave;
    float edgeW = max(fwidth(q.y), 0.02);
    float liquid = smoothstep(surface + edgeW * 1.5, surface - edgeW * 1.5, q.y);

    float2 w = q * 1.4;
    float2 warp = hq
        ? float2(fbm(w + float2(0.0, t * 0.35 * speed)), fbm(w + float2(5.2, -t * 0.3 * speed)))
        : float2(sin(w.y * 2.1 + t * speed), cos(w.x * 1.7 - t * speed)) * 0.3 + 0.5;
    float n = fbmN(w * 1.3 + warp * 2.2 + float2(t * 0.15, -t * 0.45 * speed), oct);
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

    // ---- energy wash: the orb bursts into the panel as a wavefront and dies out
    if (u.wash > 0.5) {
        float2 rel = pts - c;
        float len = length(rel);
        float2 dirv = rel / max(len, 0.001);
        // organic, liquid edge instead of a perfect circle (direction-based noise: no seam)
        float d = len + (fbmN(dirv * 2.4 + float2(t * 0.9, -t * 0.7), oct) - 0.5) * 34.0 * smoothstep(0.0, 0.2, bloom);
        float maxD = length(max(c, sz - c));
        float e = 1.0 - pow(1.0 - bloom, 3.0);
        float front = mix(u.orbPts, maxD * 1.08, e);
        float behind = 1.0 - smoothstep(front - 2.0, front + 2.0, d);
        float wn = fbmN(pts / 60.0 + float2(t * 0.5, -t * 0.7) + (pts - c) / max(front, 1.0) * 1.8, oct);
        float ring = exp(-abs(d - front) / 7.0) * (0.6 + 0.6 * wn);
        float energy = pow(1.0 - bloom, 1.6);
        float3 wcol = (core * (behind * (0.12 + 0.6 * wn) + ring * 1.0) + float3(ring * 0.25)) * energy;
        float wa = (behind * 0.1 + ring * 0.3) * energy;
        float orbFade = 1.0 - smoothstep(0.0, 0.35, bloom);
        float oa = orbA * orbFade;
        return float4(orbRGB * orbFade + wcol * (1.0 - oa), oa + wa * (1.0 - oa));
    }

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
    float stride; float pad0; float pad1; float pad2;
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
    // stride 2 = one particle per 2x2 texel block (perf mode)
    uint gw = uint(ceil(u.texW / u.stride));
    float2 cell = float2(float(vid % gw), float(vid / gw)) * u.stride;
    float2 uv = (cell + 0.5 * u.stride) / float2(u.texW, u.texH);
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

    // ripple outward from the checkbox you clicked
    float2 center = float2(u.originX + 16.0, u.originY + u.rowH * 0.5);
    float2 fromC = origin - center;
    float dist = length(fromC);
    float delay = dist / max(u.rowW, 1.0) * 0.3 + h1 * 0.04;
    float lt = u.time - delay;
    float active = step(0.0, lt);
    lt = max(lt, 0.0);
    float life = 0.32 + h2 * 0.26;
    float p = clamp(lt / life, 0.0, 1.0);

    // pop: random direction biased away from the click, hard drag so it settles instead of drifting
    float ang = h3 * 6.2831853;
    float2 rnd = float2(cos(ang), sin(ang));
    float2 radial = dist > 0.5 ? fromC / dist : rnd;
    float2 dir = normalize(mix(rnd, radial, 0.2));
    float speed = 50.0 + h2 * 130.0;
    float drag = 7.0;
    float2 pos = origin + dir * speed * (1.0 - exp(-lt * drag)) / drag;

    float heat = active * (1.0 - smoothstep(0.0, 0.35, p));
    float3 ember = mix(float3(1.0, 0.45, 0.7), float3(1.0, 0.8, 0.45), h3);
    float3 base = c.rgb / max(c.a, 0.001);
    float glowAmt = clamp(heat * 0.6, 0.0, 1.0);
    float3 col = mix(base, ember * 1.5, glowAmt);
    float alpha = c.a * (1.0 - smoothstep(0.2, 1.0, p));
    o.color = float4(col * alpha, alpha * (1.0 - 0.7 * glowAmt));

    float texel = u.pointScale / u.texScale * u.stride;
    o.size = texel * (1.08 + active * (0.6 + h2 * 1.6) * (1.0 - p));
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
