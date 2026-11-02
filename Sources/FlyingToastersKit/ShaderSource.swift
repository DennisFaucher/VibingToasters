// MARK: - Metal Shader Source
//
// Wire format contract (see AGENTS.md). Every instance is 4 x float4 = 64 bytes.
//   color    : rgb tint, a = alpha multiplier
//   geometry : x, y (NDC pivot position), rotation (radians), size (NDC height units)
//   shape    : half-extent x, half-extent y, pivot x, pivot y (pivot in local -1...1 units)
//   params   : kind, spare, sprite frame index (toaster only), spare
//
// Quad corners come from [[vertex_id]], instances from [[instance_id]], so there is
// no vertex buffer and no vertex descriptor to misconfigure.

let metalShaderSource = """
#include <metal_stdlib>
using namespace metal;

constant float2 kCorners[4] = {
    float2(-1.0, -1.0),
    float2( 1.0, -1.0),
    float2(-1.0,  1.0),
    float2( 1.0,  1.0)
};

struct FrameUniforms {
    float2 viewportSize;
    float2 padding;
};

struct Instance {
    float4 color;
    float4 geometry;
    float4 shape;
    float4 params;
};

struct VertexOut {
    float4 position [[position]];
    float2 local;      // -1...1 across the quad
    float4 color;
    float4 params;
};

vertex VertexOut vertex_main(uint vid [[vertex_id]],
                             uint iid [[instance_id]],
                             constant Instance *instances [[buffer(0)]],
                             constant FrameUniforms &frame [[buffer(1)]])
{
    Instance inst = instances[iid];
    float2 corner = kCorners[vid];

    float aspect = max(frame.viewportSize.x, 1.0) / max(frame.viewportSize.y, 1.0);
    float size = inst.geometry.w;

    float2 extent = corner * inst.shape.xy * size;
    float2 pivot  = inst.shape.zw * inst.shape.xy * size;
    float2 rel    = extent - pivot;

    float c = cos(inst.geometry.z);
    float s = sin(inst.geometry.z);
    float2 spun = float2(rel.x * c - rel.y * s, rel.x * s + rel.y * c);

    // NDC is square; squash x so shapes keep their proportions in pixels.
    spun.x /= aspect;

    VertexOut out;
    out.position = float4(inst.geometry.xy + spun, 0.0, 1.0);
    out.local = corner;
    out.color = inst.color;
    out.params = inst.params;
    return out;
}

static float sdRoundBox(float2 p, float2 halfSize, float r)
{
    float2 q = abs(p) - (halfSize - r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// ---------------------------------------------------------------- toast slice
//
// A slice seen slightly from above: pale wheat top face, toasted centre, and a
// thick orange crust along the lower edge.

static float4 shade_toast(VertexOut in)
{
    float2 p = in.local;

    // Silhouette of the slab.
    float outer = sdRoundBox(p - float2(0.0, 0.08), float2(1.00, 0.92), 0.20);
    float aa = max(fwidth(outer), 1e-4) * 1.2;
    float cov = 1.0 - smoothstep(-aa, aa, outer);
    if (cov < 0.002) {
        discard_fragment();
    }

    // Top face, lifted and inset so a band of crust shows along the lower edge.
    float topD = sdRoundBox(p - float2(0.0, 0.20), float2(0.93, 0.80), 0.18);
    float onTop = 1.0 - smoothstep(-0.010, 0.010, topD);

    // Crust: dark at the very bottom, bright where it meets the top face.
    float3 crust = mix(float3(0.55, 0.24, 0.02), float3(0.92, 0.55, 0.12),
                       smoothstep(-0.72, -0.30, p.y));

    // Toasted surface: pale wheat with only a gentle darker centre.
    float r = length(p * float2(1.0, 1.15));
    float3 bread = mix(float3(0.80, 0.60, 0.28), float3(0.96, 0.85, 0.60),
                       smoothstep(0.05, 0.75, r));

    float3 color = mix(crust, bread, onTop);

    // Thin bright lip along the top face edge.
    float lip = smoothstep(0.04, -0.01, topD) * (1.0 - smoothstep(-0.01, -0.06, topD));
    color += float3(0.16, 0.10, 0.02) * lip;

    // Coarse toasted grain.
    float2 cell = floor(p * 12.0);
    float grain = fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
    color *= 0.96 + 0.07 * grain;

    // Dark outline, like the sprite art.
    color *= mix(1.0, 0.60, smoothstep(-0.040, 0.0, outer));

    // Premultiplied, matching the pipeline's blend state.
    return float4(color * cov, cov);
}

// ------------------------------------------------------------------- toaster
//
// The classic 64x64 sprite, six frames of wing flap, sampled from a texture
// array. The artwork is baked on the CPU (see ToasterFrames.swift) because the
// toaster has to read as a solid object in three-quarter view, and that is a
// drawing problem rather than a distance-field problem.

static float4 shade_toaster(VertexOut in, texture2d_array<float> frames)
{
    constexpr sampler plain(filter::linear, mip_filter::linear, address::clamp_to_edge);

    // local (-1...1) maps straight onto the sprite, with y flipped.
    float2 uv = float2(0.5) + float2(0.5) * float2(in.local.x, -in.local.y);
    uint slice = uint(round(in.params.z));

    // Already premultiplied and already alpha-antialiased by the sampler.
    return frames.sample(plain, uv, slice) * in.color;
}

static float4 shade_star(VertexOut in)
{
    float2 p = in.local;
    float r = length(p);

    float core = 1.0 - smoothstep(0.12, 0.55, r);
    float halo = pow(max(0.0, 1.0 - r), 3.0) * 0.5;

    float spikeH = (1.0 - smoothstep(0.0, 0.13, abs(p.y)))
                 * (1.0 - smoothstep(0.0, 1.0, abs(p.x))) * 0.75;
    float spikeV = (1.0 - smoothstep(0.0, 0.13, abs(p.x)))
                 * (1.0 - smoothstep(0.0, 1.0, abs(p.y))) * 0.75;

    float a = max(max(core, halo), max(spikeH, spikeV)) * in.color.a;
    if (a < 0.004) {
        discard_fragment();
    }
    // Premultiplied, matching the pipeline's blend state.
    return float4(in.color.rgb * a, a);
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d_array<float> toasterFrames [[texture(0)]])
{
    int kind = int(round(in.params.x));
    if (kind == 0) { return shade_toast(in); }
    if (kind == 1) { return shade_toaster(in, toasterFrames); }
    return shade_star(in);
}
"""
