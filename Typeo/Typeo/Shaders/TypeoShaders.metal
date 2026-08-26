//
//  TypeoShaders.metal
//  Typeo
//
//  v2 shader set. Applied to the TEXT BLOCK, not the whole canvas, and not to chrome.
//  All are [[stitchable]] so SwiftUI can bind them via ShaderLibrary.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// Cheap hash-based value noise — no texture lookups.
static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// MARK: - Bloom  (.layerEffect — glow sampled from the layer itself)

[[ stitchable ]] half4 bloom(float2 position, SwiftUI::Layer layer, float amount) {
    half4 base = layer.sample(position);
    float radius = 6.0 + amount * 52.0;

    // Golden-angle spiral over the disc: sqrt(t) spreads taps by equal AREA rather
    // than along one ring, which is what removes the ghosting a single ring gives.
    const int taps = 48;
    const float goldenAngle = 2.39996323;

    half4 accumulated = half4(0.0h);
    float weightSum = 0.0;

    for (int i = 0; i < taps; ++i) {
        float t = (float(i) + 0.5) / float(taps);
        float r = radius * sqrt(t);
        float angle = float(i) * goldenAngle;
        float weight = exp(-2.2 * t);

        accumulated += layer.sample(position + float2(cos(angle), sin(angle)) * r) * half(weight);
        weightSum += weight;
    }
    accumulated /= half(weightSum);

    half4 glow = accumulated * half(amount * 2.6);
    return clamp(base + glow, half4(0.0h), half4(1.0h));
}

// MARK: - Heat  (.distortionEffect — remaps sampling position)

[[ stitchable ]] float2 heat(float2 position, float time, float amount) {
    float wobble = sin(position.y * 0.035 + time * 2.1) * cos(position.x * 0.021 - time * 1.4);
    float drift = valueNoise(float2(position.x * 0.01, position.y * 0.01 - time * 0.6)) - 0.5;
    float2 offset = float2(wobble * 18.0 + drift * 26.0, drift * 10.0);
    return position + offset * amount;
}

// MARK: - Noise  (.colorEffect — per-pixel colour only)

[[ stitchable ]] half4 grain(float2 position, half4 color, float time, float amount) {
    float g = valueNoise(position * 1.7 + float2(time * 37.0, time * 61.0));
    float speckle = step(0.965 - amount * 0.09, hash21(position + time * 13.0));
    half shift = half((g - 0.5) * 0.85 * amount);
    half4 out = color;
    out.rgb = clamp(out.rgb + shift * color.a, half(0.0), color.a);
    out.rgb = clamp(out.rgb + half(speckle * amount * 0.6) * color.a, half(0.0), color.a);
    return out;
}

// MARK: - Glitch  (.layerEffect — samples neighbouring pixels)

[[ stitchable ]] half4 glitch(float2 position, SwiftUI::Layer layer, float time, float amount) {
    // Horizontal slices torn sideways.
    float band = floor(position.y / 26.0);
    float jump = hash21(float2(band, floor(time * 12.0)));
    float tear = (jump - 0.5) * 90.0 * amount * step(0.72, jump);

    float2 shifted = position + float2(tear, 0.0);

    // Chromatic split widens with intensity.
    float split = 14.0 * amount;
    half4 r = layer.sample(shifted + float2(split, 0.0));
    half4 g = layer.sample(shifted);
    half4 b = layer.sample(shifted - float2(split, 0.0));

    return half4(r.r, g.g, b.b, max(max(r.a, g.a), b.a));
}
