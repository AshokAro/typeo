//
//  SpriteShaders.swift
//  Typeo
//
//  v2's Metal shaders ported to SpriteKit. SKShader uses a GLSL ES subset, not Metal,
//  so these are rewrites rather than the same files reused. They run on an SKEffectNode
//  wrapping the glyph nodes, so the effect covers the TEXT BLOCK and not the background.
//
//  u_texel is 1/textureSize, supplied per frame because the block's rasterised size
//  changes with the text.
//

import SpriteKit
import simd

enum SpriteShaders {

    static func shader(for effect: ShaderEffect) -> SKShader? {
        guard effect.kind != .none else { return nil }

        let source: String = switch effect.kind {
        case .none:   ""
        case .bloom:  bloom
        case .heat:   heat
        case .noise:  noise
        case .glitch: glitch
        case .chrome: chrome
        case .glass: glass
        case .matrix: matrix
        case .liquify: liquify
        case .halftone: halftone
        case .motionBlur: motionBlur
        case .thermal: thermal
        case .neon: neon
        case .gemSmoke: gemSmoke
        case .meshGradient: meshGradient
        case .grainGradient: grainGradient
        case .dithering: dithering
        }

        let shader = SKShader(source: source)
        shader.uniforms = [
            SKUniform(name: "u_amount", float: Float(effect.intensity)),
            SKUniform(name: "u_time_offset", float: 0),
            SKUniform(name: "u_secondary", float: Float(effect.resolvedSecondary)),
            SKUniform(name: "u_texel", vectorFloat2: vector_float2(0.001, 0.001)),
        ]
        return shader
    }

    /// Fills whatever the inner effect node rasterised with a linear gradient,
    /// keeping the original alpha. Runs on a SEPARATE, inner SKEffectNode: one node
    /// cannot stack two shaders, so fill is inner and FX is outer.
    static func gradientFillShader(_ gradient: GradientPaint) -> SKShader {
        let shader = SKShader(source: gradientFill)
        let start = gradient.start
        let end = gradient.end
        let radians = Float(gradient.angleDegrees * .pi / 180)
        shader.uniforms = [
            SKUniform(name: "u_from", vectorFloat4: vector_float4(
                Float(start.red), Float(start.green), Float(start.blue), Float(start.opacity))),
            SKUniform(name: "u_to", vectorFloat4: vector_float4(
                Float(end.red), Float(end.green), Float(end.blue), Float(end.opacity))),
            SKUniform(name: "u_dir", vectorFloat2: vector_float2(cos(radians), sin(radians))),
        ]
        return shader
    }

    static let gradientFill = """
    void main() {
        vec4 source = texture2D(u_texture, v_tex_coord);
        vec2 centred = v_tex_coord - vec2(0.5);
        float t = clamp(dot(centred, u_dir) + 0.5, 0.0, 1.0);
        vec4 tint = mix(u_from, u_to, t);
        // Premultiplied: keep the glyph's alpha, replace the colour.
        gl_FragColor = vec4(tint.rgb * source.a * tint.a, source.a * tint.a);
    }
    """

    /// Shared noise helpers, prepended to every shader.
    static let helpers = """
    float hash21(vec2 p) {
        p = fract(p * vec2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }
    vec3 hueRotate(vec3 colour, float angle) {
        vec3 k = vec3(0.57735, 0.57735, 0.57735);
        float c = cos(angle);
        float s = sin(angle);
        return colour * c + cross(k, colour) * s + k * dot(k, colour) * (1.0 - c);
    }
    float valueNoise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        float a = hash21(i);
        float b = hash21(i + vec2(1.0, 0.0));
        float c = hash21(i + vec2(0.0, 1.0));
        float d = hash21(i + vec2(1.0, 1.0));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }
    """

    static let bloom = helpers + """
    void main() {
        vec2 uv = v_tex_coord;
        vec4 base = texture2D(u_texture, uv);
        float radius = 6.0 + u_amount * 52.0;

        vec4 accumulated = vec4(0.0);
        float weightSum = 0.0;
        for (int i = 0; i < 24; i++) {
            float t = (float(i) + 0.5) / 24.0;
            float r = radius * sqrt(t);
            float angle = float(i) * 2.39996323;
            float w = exp(-2.2 * t);
            accumulated += texture2D(u_texture, uv + vec2(cos(angle), sin(angle)) * r * u_texel) * w;
            weightSum += w;
        }
        accumulated /= weightSum;
        gl_FragColor = clamp(base + accumulated * u_amount * 2.6, 0.0, 1.0);
    }
    """

    static let heat = helpers + """
    void main() {
        vec2 uv = v_tex_coord;
        float t = u_time + u_time_offset;
        float wobble = sin(uv.y * 34.0 + t * 2.1) * cos(uv.x * 21.0 - t * 1.4);
        float drift = valueNoise(vec2(uv.x * 9.0, uv.y * 9.0 - t * 0.6)) - 0.5;
        vec2 offset = vec2(wobble * 18.0 + drift * 26.0, drift * 10.0) * u_amount * u_texel;
        gl_FragColor = texture2D(u_texture, uv + offset);
    }
    """

    static let noise = helpers + """
    void main() {
        vec2 uv = v_tex_coord;
        float t = u_time + u_time_offset;
        vec4 color = texture2D(u_texture, uv);
        vec2 p = uv / u_texel;
        float g = valueNoise(p * 1.7 + vec2(t * 37.0, t * 61.0));
        float speckle = step(0.965 - u_amount * 0.09, hash21(p + t * 13.0));
        float shift = (g - 0.5) * 0.85 * u_amount;
        color.rgb = clamp(color.rgb + shift * color.a, 0.0, color.a);
        color.rgb = clamp(color.rgb + speckle * u_amount * 0.6 * color.a, 0.0, color.a);
        gl_FragColor = color;
    }
    """

    static let glitch = helpers + """
    void main() {
        vec2 uv = v_tex_coord;
        float t = u_time + u_time_offset;
        float band = floor(uv.y / (26.0 * u_texel.y));
        float jump = hash21(vec2(band, floor(t * 12.0)));
        float tear = (jump - 0.5) * 90.0 * u_amount * step(0.72, jump);
        vec2 shifted = uv + vec2(tear * u_texel.x, 0.0);

        float split = 14.0 * u_amount * u_texel.x;
        vec4 r = texture2D(u_texture, shifted + vec2(split, 0.0));
        vec4 g = texture2D(u_texture, shifted);
        vec4 b = texture2D(u_texture, shifted - vec2(split, 0.0));
        gl_FragColor = vec4(r.r, g.g, b.b, max(max(r.a, g.a), b.a));
    }
    """
}


// MARK: - v6 shader library
//
// Written defensively for SKShader's GLSL ES subset: no early `return` inside main,
// no extra helper functions beyond the shared noise ones, and no if/else-if chains.
// A shader that fails to compile is NOT reported — SpriteKit silently renders the
// node unshaded — so these constraints are cheaper than debugging a silent no-op.
//
// Colour is premultiplied: divide by alpha to read true RGB, multiply back on output,
// and never modify alpha or the glyph edges fringe.

extension SpriteShaders {

    /// Liquid metal: a flowing domain-warped field, not the old static banding, which
    /// read as stripes rather than moving mercury.
    static let chrome = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        float a = max(src.a, 0.001);
        vec2 uv = v_tex_coord;
        float t = u_time * 0.22;

        vec2 q = vec2(valueNoise(uv * 3.0 + t), valueNoise(uv * 3.0 + 5.2 - t));
        vec2 r = vec2(valueNoise(uv * 3.0 + 4.0 * q + t * 0.7),
                      valueNoise(uv * 3.0 + 4.0 * q + 9.2 - t * 0.6));
        float flow = valueNoise(uv * 4.0 + 4.0 * r);

        float band = fract(flow * 3.0 + u_secondary * 2.0);
        float sheen = smoothstep(0.40, 0.50, band) * smoothstep(0.60, 0.50, band);

        vec3 metal = mix(vec3(0.14, 0.16, 0.21), vec3(0.88, 0.92, 1.0), flow);
        metal = clamp(metal + sheen * 0.95, 0.0, 1.0);

        vec3 outc = mix(src.rgb / a, metal, u_amount);
        gl_FragColor = vec4(outc * src.a, src.a);
    }
    """

    static let glass = helpers + """
    void main() {
        vec2 uv = v_tex_coord;
        vec2 e = u_texel * 3.0;
        float ax = texture2D(u_texture, uv + vec2(e.x, 0.0)).a
                 - texture2D(u_texture, uv - vec2(e.x, 0.0)).a;
        float ay = texture2D(u_texture, uv + vec2(0.0, e.y)).a
                 - texture2D(u_texture, uv - vec2(0.0, e.y)).a;

        vec2 bend = vec2(ax, ay) * u_amount * u_texel * 2600.0;
        vec4 src = texture2D(u_texture, uv - bend);
        float a = max(src.a, 0.001);
        vec3 rgb = src.rgb / a;

        float spec = pow(max(0.0, -(ax * 0.6 + ay * 0.8)), 1.5) * u_amount * 2.4;
        vec3 outc = clamp(rgb * (0.82 + 0.18 * u_amount) + spec, 0.0, 1.0);
        gl_FragColor = vec4(outc * src.a, src.a);
    }
    """

    static let matrix = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        float a = max(src.a, 0.001);
        vec3 rgb = src.rgb / a;

        vec2 p = v_tex_coord / u_texel;
        float cell = 24.0;
        float column = floor(p.x / cell);
        float speed = (140.0 + hash21(vec2(column, 3.7)) * 320.0) * (0.35 + u_secondary * 1.3);
        float row = floor((p.y + u_time * speed) / cell);
        float lit = step(0.42, hash21(vec2(column, row)));
        float trail = fract((p.y + u_time * speed) / cell);

        vec3 rain = vec3(0.10, 1.0, 0.32) * lit * (0.35 + 0.65 * trail);
        vec3 outc = mix(rgb, rain, u_amount);
        gl_FragColor = vec4(outc * src.a, src.a);
    }
    """

    static let liquify = helpers + """
    void main() {
        vec2 uv = v_tex_coord;
        float n1 = valueNoise(uv * 4.0 + vec2(u_time * 0.28, 0.0));
        float n2 = valueNoise(uv * 6.0 - vec2(0.0, u_time * 0.21));
        vec2 warp = vec2(n1 - 0.5, n2 - 0.5) * u_amount * 0.14;
        gl_FragColor = texture2D(u_texture, uv + warp);
    }
    """

    static let halftone = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        float a = max(src.a, 0.001);
        vec3 rgb = src.rgb / a;

        vec2 p = v_tex_coord / u_texel;
        float scale = mix(16.0, 4.0, u_amount);
        vec2 grid = mod(p, scale) - scale * 0.5;
        float lum = clamp(dot(rgb, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
        float radius = scale * 0.52 * sqrt(lum);
        float ink = step(length(grid), radius);

        vec3 outc = mix(rgb, rgb * ink, u_amount);
        gl_FragColor = vec4(outc * src.a, src.a);
    }
    """

    static let motionBlur = helpers + """
    void main() {
        float angle = u_secondary * 3.14159265;
        vec2 dir = vec2(cos(angle), sin(angle)) * u_texel * u_amount * 110.0;
        vec4 accumulated = vec4(0.0);
        for (int i = 0; i < 13; i++) {
            float t = float(i) / 12.0 - 0.5;
            accumulated += texture2D(u_texture, v_tex_coord + dir * t);
        }
        gl_FragColor = accumulated / 13.0;
    }
    """

    /// Heatmap. The heat field is a BLURRED ALPHA, not luminance: uniformly white
    /// text has no luminance gradient to map, which is why the old version appeared to
    /// do nothing at all.
    static let thermal = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);

        float heat = 0.0;
        float radius = 12.0 + u_amount * 52.0;
        for (int i = 0; i < 20; i++) {
            float t = (float(i) + 0.5) / 20.0;
            float rr = radius * sqrt(t);
            float ang = float(i) * 2.39996323;
            heat += texture2D(u_texture, v_tex_coord + vec2(cos(ang), sin(ang)) * rr * u_texel).a;
        }
        heat = clamp((heat / 20.0) * 1.45, 0.0, 1.0);

        vec3 c0 = vec3(0.00, 0.00, 0.16);
        vec3 c1 = vec3(0.26, 0.00, 0.66);
        vec3 c2 = vec3(0.95, 0.14, 0.08);
        vec3 c3 = vec3(1.00, 0.76, 0.05);
        vec3 c4 = vec3(1.00, 1.00, 0.93);

        vec3 ramp = mix(c0, c1, smoothstep(0.00, 0.25, heat));
        ramp = mix(ramp, c2, smoothstep(0.25, 0.50, heat));
        ramp = mix(ramp, c3, smoothstep(0.50, 0.75, heat));
        ramp = mix(ramp, c4, smoothstep(0.75, 1.00, heat));

        float alpha = clamp(max(src.a, heat * 0.92), 0.0, 1.0);
        vec3 plain = src.rgb;
        gl_FragColor = vec4(mix(plain, ramp * alpha, u_amount), alpha);
    }
    """

    /// A real neon glow: a coloured falloff built from the alpha field plus the
    /// original core kept bright on top. The old preset used bloom, whose spiral taps
    /// read as pinpoints rather than a continuous halo.
    static let neon = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);

        float glow = 0.0;
        float weight = 0.0;
        float radius = 10.0 + u_amount * 70.0;
        for (int i = 0; i < 44; i++) {
            float t = (float(i) + 0.5) / 44.0;
            float rr = radius * sqrt(t);
            // Golden angle plus a per-tap jitter: with a plain spiral the taps line up
            // into visible rings and the halo reads as pinpoints.
            float ang = float(i) * 2.39996323 + hash21(vec2(float(i), 0.7)) * 1.4;
            float falloff = 1.0 - t * 0.85;
            glow += texture2D(u_texture, v_tex_coord + vec2(cos(ang), sin(ang)) * rr * u_texel).a * falloff;
            weight += falloff;
        }
        glow = clamp(glow / max(weight, 0.001) * 2.4, 0.0, 1.0);

        vec3 cool = vec3(0.25, 0.95, 1.00);
        vec3 warm = vec3(1.00, 0.25, 0.75);
        vec3 tint = mix(cool, warm, u_secondary);

        vec3 halo = tint * glow * u_amount * 1.5;
        vec3 core = src.rgb + vec3(1.0) * src.a * 0.35 * u_amount;
        float alpha = clamp(max(src.a, glow * u_amount), 0.0, 1.0);
        gl_FragColor = vec4(clamp(core + halo, 0.0, 1.0), alpha);
    }
    """

    /// Gem smoke: crystalline facets from a cell grid, with vapour drifting through.
    static let gemSmoke = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        float a = max(src.a, 0.001);
        vec2 uv = v_tex_coord;
        float t = u_time * 0.18;

        float cells = mix(4.0, 16.0, u_secondary);
        vec2 grid = uv * cells;
        vec2 cell = floor(grid);
        vec2 frac = fract(grid);

        // Nearest-point cell structure gives flat facets with hard edges.
        float best = 8.0;
        float bestId = 0.0;
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec2 neighbour = vec2(float(x), float(y));
                vec2 point = neighbour + vec2(
                    hash21(cell + neighbour),
                    hash21(cell + neighbour + 19.7)
                );
                float d = length(point - frac);
                if (d < best) { best = d; bestId = hash21(cell + neighbour + 3.3); }
            }
        }

        float facet = 0.35 + 0.65 * bestId;
        float edge = smoothstep(0.0, 0.14, best);

        float smoke = valueNoise(uv * 3.0 + vec2(t, -t * 0.7));
        smoke = smoothstep(0.35, 0.85, smoke);

        vec3 gem = mix(vec3(0.18, 0.05, 0.42), vec3(0.55, 0.85, 1.0), facet);
        gem = mix(gem, vec3(0.95, 0.85, 1.0), smoke * 0.55);
        gem *= 0.55 + 0.45 * edge;

        vec3 outc = mix(src.rgb / a, clamp(gem, 0.0, 1.0), u_amount);
        gl_FragColor = vec4(outc * src.a, src.a);
    }
    """

    /// Mesh gradient: drifting colour centres blended by inverse distance. Works as a
    /// background fill and as a tint on the text, because it respects source alpha.
    static let meshGradient = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        vec2 uv = v_tex_coord;
        float t = u_time * 0.16;

        vec2 p1 = vec2(0.28 + 0.20 * sin(t * 1.10), 0.30 + 0.18 * cos(t * 0.90));
        vec2 p2 = vec2(0.74 + 0.18 * cos(t * 0.80), 0.34 + 0.20 * sin(t * 1.30));
        vec2 p3 = vec2(0.48 + 0.24 * sin(t * 0.70), 0.76 + 0.16 * cos(t * 1.10));
        vec2 p4 = vec2(0.20 + 0.16 * cos(t * 1.40), 0.78 + 0.14 * sin(t * 0.60));

        // Rotate the palette's HUE rather than cross-fading between two palettes.
        // Blending opposite hues 50/50 lands on grey, which is why the field washed out
        // in the middle of the slider.
        float shift = u_secondary * 6.2831853;
        vec3 c1 = hueRotate(vec3(1.00, 0.22, 0.38), shift);
        vec3 c2 = hueRotate(vec3(0.36, 0.24, 1.00), shift);
        vec3 c3 = hueRotate(vec3(0.10, 0.88, 0.66), shift);
        vec3 c4 = hueRotate(vec3(1.00, 0.74, 0.18), shift);

        // Fourth-power falloff. Inverse-SQUARE weighting averages all four colours
        // toward grey across the middle of the canvas; this keeps the zones distinct.
        float d1 = distance(uv, p1); float d2 = distance(uv, p2);
        float d3 = distance(uv, p3); float d4 = distance(uv, p4);
        float w1 = 1.0 / (0.0008 + d1 * d1 * d1 * d1);
        float w2 = 1.0 / (0.0008 + d2 * d2 * d2 * d2);
        float w3 = 1.0 / (0.0008 + d3 * d3 * d3 * d3);
        float w4 = 1.0 / (0.0008 + d4 * d4 * d4 * d4);

        vec3 mesh = (c1 * w1 + c2 * w2 + c3 * w3 + c4 * w4) / (w1 + w2 + w3 + w4);
        vec3 outc = mix(src.rgb / max(src.a, 0.001), mesh, u_amount);
        gl_FragColor = vec4(outc * src.a, src.a);
    }
    """

    /// Grain gradient: a soft colour sweep with animated film grain over it.
    static let grainGradient = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        vec2 uv = v_tex_coord;
        float t = u_time * 0.5;

        float sweep = clamp(uv.y * 0.7 + uv.x * 0.3, 0.0, 1.0);
        vec3 top = vec3(0.98, 0.45, 0.22);
        vec3 bottom = vec3(0.20, 0.15, 0.48);
        vec3 base = mix(top, bottom, smoothstep(0.0, 1.0, sweep));

        vec2 p = uv / u_texel;
        float grain = hash21(p * 0.9 + vec2(t * 31.0, t * 17.0)) - 0.5;
        base = clamp(base + grain * u_secondary * 0.55, 0.0, 1.0);

        vec3 outc = mix(src.rgb / max(src.a, 0.001), base, u_amount);
        gl_FragColor = vec4(outc * src.a, src.a);
    }
    """

    /// Ordered Bayer dithering. Quantises to a few levels per channel and offsets the
    /// threshold by a 4x4 matrix, which is what gives the retro banded look.
    static let dithering = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        float a = max(src.a, 0.001);
        vec3 rgb = src.rgb / a;

        vec2 p = floor(mod(v_tex_coord / u_texel, 4.0));
        float index = p.x + p.y * 4.0;

        // 4x4 Bayer matrix, unrolled: no array indexing in this GLSL subset.
        float m = 0.0;
        m += step(index, 0.5)  * 0.0625;  m += step(abs(index -  1.0), 0.4) * 0.5625;
        m += step(abs(index -  2.0), 0.4) * 0.1875;  m += step(abs(index -  3.0), 0.4) * 0.6875;
        m += step(abs(index -  4.0), 0.4) * 0.8125;  m += step(abs(index -  5.0), 0.4) * 0.3125;
        m += step(abs(index -  6.0), 0.4) * 0.9375;  m += step(abs(index -  7.0), 0.4) * 0.4375;
        m += step(abs(index -  8.0), 0.4) * 0.2500;  m += step(abs(index -  9.0), 0.4) * 0.7500;
        m += step(abs(index - 10.0), 0.4) * 0.1250;  m += step(abs(index - 11.0), 0.4) * 0.6250;
        m += step(abs(index - 12.0), 0.4) * 1.0000;  m += step(abs(index - 13.0), 0.4) * 0.5000;
        m += step(abs(index - 14.0), 0.4) * 0.8750;  m += step(abs(index - 15.0), 0.4) * 0.3750;

        float levels = mix(2.0, 6.0, u_secondary);
        vec3 dithered = floor(rgb * levels + (m - 0.5)) / (levels - 1.0);
        dithered = clamp(dithered, 0.0, 1.0);

        vec3 outc = mix(rgb, dithered, u_amount);
        gl_FragColor = vec4(outc * src.a, src.a);
    }
    """
}
