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

    static let chrome = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        float a = max(src.a, 0.001);
        vec3 rgb = src.rgb / a;

        float y = v_tex_coord.y;
        float bands = sin((y * 16.0 + u_time * 0.5) * 3.14159) * 0.5 + 0.5;
        float metal = mix(0.22, 1.0, pow(bands, 1.7));
        vec3 tint = mix(vec3(0.30, 0.33, 0.40), vec3(1.0, 0.99, 0.95), metal);

        float sweepPos = fract(y * 0.9 - u_time * 0.12);
        float sweep = smoothstep(0.34, 0.0, abs(sweepPos - 0.5)) * u_secondary;
        tint = clamp(tint + sweep * 0.45, 0.0, 1.0);

        vec3 outc = mix(rgb, tint, u_amount);
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

    static let thermal = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        float a = max(src.a, 0.001);
        vec3 rgb = src.rgb / a;

        float lum = clamp(dot(rgb, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);

        // Four-stop thermal ramp built with mix/step so there is no if/else chain.
        vec3 c0 = vec3(0.02, 0.00, 0.15);
        vec3 c1 = vec3(0.55, 0.00, 0.55);
        vec3 c2 = vec3(1.00, 0.15, 0.05);
        vec3 c3 = vec3(1.00, 0.78, 0.05);
        vec3 c4 = vec3(1.00, 1.00, 0.95);

        vec3 ramp = mix(c0, c1, smoothstep(0.00, 0.25, lum));
        ramp = mix(ramp, c2, smoothstep(0.25, 0.50, lum));
        ramp = mix(ramp, c3, smoothstep(0.50, 0.75, lum));
        ramp = mix(ramp, c4, smoothstep(0.75, 1.00, lum));

        vec3 outc = mix(rgb, ramp, u_amount);
        gl_FragColor = vec4(outc * src.a, src.a);
    }
    """
}
