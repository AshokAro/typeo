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
            SKUniform(name: "u_tertiary", float: Float(effect.resolvedTertiary)),
            SKUniform(name: "u_variant", float: Float(effect.resolvedVariant)),
            SKUniform(name: "u_texel", vectorFloat2: vector_float2(0.001, 0.001)),
        ]
        // The rain needs real characters, and a fragment shader cannot draw type.
        if effect.kind == .matrix {
            shader.addUniform(SKUniform(name: "u_glyphs", texture: MatrixGlyphAtlas.texture))
        }
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

    // MARK: - Blurred field layer
    //
    // Some effects need a soft field AROUND the letters — a neon halo, a heat bloom.
    // A single-pass SKShader cannot blur: sampling a ring of taps reproduces the glyph
    // at every tap, which is exactly what "pinpoints of light" and "the text repeated
    // a bunch of times" were. Instead a second layer holds copies of the glyphs, runs
    // a real CIGaussianBlur (verified to work under SKRenderer, and to scale with the
    // scene rather than the raster, so an export matches the screen), and this shader
    // colours the result. SKEffectNode applies `filter` BEFORE `shader`, so the shader
    // is handed the already-blurred alpha.

    struct Field {
        var shader: SKShader
        var blurRadius: Double
        /// Glow adds to what is behind it; a heat field paints over it.
        var additive: Bool
    }

    static func field(for effect: ShaderEffect) -> Field? {
        switch effect.kind {
        case .neon:
            return Field(
                shader: fieldShader(neonField, effect),
                // Spread is its own control: glow strength and glow SIZE are different
                // decisions.
                blurRadius: 6 + effect.resolvedTertiary * 78,
                additive: true
            )
        case .thermal:
            return Field(
                shader: fieldShader(heatField, effect),
                blurRadius: 8 + effect.resolvedSecondary * 76,
                additive: false
            )
        default:
            return nil
        }
    }

    private static func fieldShader(_ source: String, _ effect: ShaderEffect) -> SKShader {
        let shader = SKShader(source: helpers + source)
        shader.uniforms = [
            SKUniform(name: "u_amount", float: Float(effect.intensity)),
            SKUniform(name: "u_secondary", float: Float(effect.resolvedSecondary)),
            SKUniform(name: "u_tertiary", float: Float(effect.resolvedTertiary)),
        ]
        return shader
    }

    static let neonField = """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        float glow = clamp(src.a * (1.6 + u_amount * 2.4), 0.0, 1.0);
        glow = pow(glow, 0.8);
        vec3 tint = hueRotate(vec3(0.15, 0.90, 1.00), u_secondary * 6.2831);
        gl_FragColor = vec4(clamp(tint, 0.0, 1.0) * glow * u_amount, glow * u_amount);
    }
    """

    static let heatField = """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        float heat = clamp(src.a * (1.2 + u_amount * 2.2), 0.0, 1.0);

        vec3 c0 = vec3(0.02, 0.00, 0.18);
        vec3 c1 = vec3(0.26, 0.00, 0.66);
        vec3 c2 = vec3(0.95, 0.14, 0.08);
        vec3 c3 = vec3(1.00, 0.76, 0.05);
        vec3 c4 = vec3(1.00, 1.00, 0.93);

        vec3 ramp = mix(c0, c1, smoothstep(0.00, 0.25, heat));
        ramp = mix(ramp, c2, smoothstep(0.25, 0.50, heat));
        ramp = mix(ramp, c3, smoothstep(0.50, 0.75, heat));
        ramp = mix(ramp, c4, smoothstep(0.75, 1.00, heat));

        float alpha = smoothstep(0.015, 0.22, heat) * u_amount;
        gl_FragColor = vec4(ramp * alpha, alpha);
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
        float radius = (6.0 + u_amount * 52.0) * (0.35 + u_secondary * 1.65);

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
        float t = (u_time + u_time_offset) * (0.3 + u_tertiary * 2.0);
        float wobble = sin(uv.y * 34.0 + t * 2.1) * cos(uv.x * 21.0 - t * 1.4);
        float drift = valueNoise(vec2(uv.x * 9.0, uv.y * 9.0 - t * 0.6)) - 0.5;
        vec2 offset = vec2(wobble * 18.0 + drift * 26.0, drift * 10.0) * u_amount * u_texel;

        vec4 warped = texture2D(u_texture, uv + offset);
        float a = max(warped.a, 0.001);
        vec3 rgb = warped.rgb / a;

        // Temperature: cold air at one end, a hot flame at the other.
        vec3 cool = vec3(0.52, 0.74, 1.00);
        vec3 hot = vec3(1.00, 0.58, 0.24);
        vec3 tint = mix(cool, hot, u_secondary);
        vec3 outc = mix(rgb, clamp(rgb * tint * 1.25, 0.0, 1.0), u_amount);
        gl_FragColor = vec4(outc * warped.a, warped.a);
    }
    """

    /// Four kinds of noise, selected by `u_variant`. Blended by weights rather than
    /// branched: an if/else chain is one of the things that silently stops an SKShader
    /// compiling.
    static let noise = helpers + """
    void main() {
        vec2 uv = v_tex_coord;
        float t = u_time + u_time_offset;
        vec4 color = texture2D(u_texture, uv);
        float a = max(color.a, 0.001);
        vec3 rgb = color.rgb / a;

        // Size: coarse grain at one end, fine at the other.
        float grain = mix(6.0, 0.5, u_secondary);
        vec2 p = (uv / u_texel) / max(grain, 0.05);

        float w0 = step(abs(u_variant - 0.0), 0.4);
        float w1 = step(abs(u_variant - 1.0), 0.4);
        float w2 = step(abs(u_variant - 2.0), 0.4);
        float w3 = step(abs(u_variant - 3.0), 0.4);

        // Grain: soft film noise.
        vec3 film = vec3((valueNoise(p * 1.7 + vec2(t * 37.0, t * 61.0)) - 0.5) * 0.9);

        // Speckle: sparse hot pixels.
        float dots = step(0.978 - u_amount * 0.06, hash21(p + t * 13.0));
        vec3 speckle = vec3(dots) * 0.9;

        // Static: television scan lines, jumping every frame.
        float lineNoise = hash21(vec2(floor(p.y * 0.5), floor(t * 24.0)));
        vec3 stat = vec3((lineNoise - 0.5) * 1.4);

        // Colour: the channels disagree.
        vec3 chroma = vec3(
            hash21(p + vec2(t * 11.0, 0.0)),
            hash21(p + vec2(0.0, t * 17.0)),
            hash21(p + vec2(t * 7.0, t * 5.0))
        ) - 0.5;

        vec3 shift = film * w0 + speckle * w1 + stat * w2 + chroma * w3;
        vec3 outc = clamp(rgb + shift * u_amount, 0.0, 1.0);
        gl_FragColor = vec4(outc * color.a, color.a);
    }
    """

    static let glitch = helpers + """
    void main() {
        vec2 uv = v_tex_coord;
        float t = u_time + u_time_offset;
        float band = floor(uv.y / (mix(70.0, 8.0, u_secondary) * u_texel.y));
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
        // Flow drives the clock rather than offsetting a band: at 0 the metal is a
        // still image instead of a slow crawl.
        float t = (u_time + u_time_offset) * 0.22 * u_secondary;

        vec2 q = vec2(valueNoise(uv * 3.0 + t), valueNoise(uv * 3.0 + 5.2 - t));
        vec2 r = vec2(valueNoise(uv * 3.0 + 4.0 * q + t * 0.7),
                      valueNoise(uv * 3.0 + 4.0 * q + 9.2 - t * 0.6));
        float flow = valueNoise(uv * 4.0 + 4.0 * r);

        float band = fract(flow * 3.0);
        float sheen = smoothstep(0.40, 0.50, band) * smoothstep(0.60, 0.50, band);

        vec3 metal = mix(vec3(0.14, 0.16, 0.21), vec3(0.88, 0.92, 1.0), flow);
        metal = clamp(metal + sheen * 0.95, 0.0, 1.0);
        metal = clamp((metal - 0.5) * (0.55 + u_tertiary * 1.9) + 0.5, 0.0, 1.0);

        vec3 outc = mix(src.rgb / a, metal, u_amount);
        gl_FragColor = vec4(outc * src.a, src.a);
    }
    """

    /// Liquid glass. The letters are not tinted — the BACKGROUND is sampled through
    /// them, bent by the glyph's own edge normal, with a lit bevel on top.
    ///
    /// `.glassEffect` cannot do this: it is a SwiftUI modifier, it cannot attach to a
    /// SpriteKit node, and SKRenderer would not capture it on export. This is the
    /// recipe underneath that look — lens, frost, rim light, contact shadow — written
    /// where the canvas can actually run it.
    static let glass = helpers + """
    void main() {
        vec2 uv = v_tex_coord;
        vec4 src = texture2D(u_texture, uv);
        float a = max(src.a, 0.001);

        // Gradient of the alpha field: zero in the flat middle of a stroke, strong at
        // the contour, which is where real glass bends and catches light.
        vec2 e = u_texel * 2.0;
        float ax = texture2D(u_texture, uv + vec2(e.x, 0.0)).a
                 - texture2D(u_texture, uv - vec2(e.x, 0.0)).a;
        float ay = texture2D(u_texture, uv + vec2(0.0, e.y)).a
                 - texture2D(u_texture, uv - vec2(0.0, e.y)).a;
        vec2 gradient = vec2(ax, ay);
        float slope = length(gradient);
        float edge = clamp(slope * 3.0, 0.0, 1.0);
        // Outward-facing normal of the bevel. Alpha falls off outwards, so the
        // outward direction is the NEGATIVE gradient.
        vec2 normal = -gradient / max(slope, 0.0001);

        // How deep inside a stroke this pixel is. Without it the interior sampled the
        // background straight through and the letters all but disappeared.
        float wide = texture2D(u_texture, uv + vec2(9.0, 0.0) * u_texel).a
                   + texture2D(u_texture, uv - vec2(9.0, 0.0) * u_texel).a
                   + texture2D(u_texture, uv + vec2(0.0, 9.0) * u_texel).a
                   + texture2D(u_texture, uv - vec2(0.0, 9.0) * u_texel).a;
        float interior = smoothstep(1.6, 3.9, wide);

        vec2 bend = gradient * (120.0 + 420.0 * u_amount) * u_texel;
        vec2 lens = clamp(uv - bend, 0.0, 1.0);

        // Frost: a few taps of the background, which is what gives glass its milkiness
        // instead of a plain see-through hole.
        vec3 frost = texture2D(u_background, lens).rgb
                   + texture2D(u_background, clamp(lens + vec2(14.0, 0.0) * u_texel, 0.0, 1.0)).rgb
                   + texture2D(u_background, clamp(lens - vec2(14.0, 0.0) * u_texel, 0.0, 1.0)).rgb
                   + texture2D(u_background, clamp(lens + vec2(0.0, 14.0) * u_texel, 0.0, 1.0)).rgb
                   + texture2D(u_background, clamp(lens - vec2(0.0, 14.0) * u_texel, 0.0, 1.0)).rgb;
        frost *= 0.2;

        // A touch of chromatic separation, strongest where the lens bends hardest.
        float red = texture2D(u_background, clamp(uv - bend * 1.22, 0.0, 1.0)).r;
        vec3 behind = texture2D(u_background, lens).rgb;
        vec3 refracted = mix(vec3(red, behind.g, behind.b), frost, u_secondary);

        // Body: brighter and slightly whitened where the glass is thick.
        vec3 body = mix(refracted, vec3(1.0), 0.12 * u_amount + 0.14 * interior * u_amount);
        body *= 1.0 + 0.22 * interior * u_amount;

        // Bevel lighting from the top left, with a contact shadow opposite it. This is
        // what makes the shape read as a solid object rather than a tinted hole.
        vec2 key = vec2(-0.55, 0.835);
        float lit = max(0.0, dot(normal, key));
        float shade = max(0.0, dot(normal, -key));
        body += vec3(1.0) * pow(lit, 2.0) * edge * (0.45 + 0.75 * u_amount);
        body -= vec3(0.30, 0.30, 0.34) * pow(shade, 2.0) * edge * u_amount;

        vec3 own = src.rgb / a;
        vec3 outc = mix(own, clamp(body, 0.0, 1.0), u_amount);
        gl_FragColor = vec4(outc * src.a, src.a);
    }
    """

    /// Matrix rain, with actual characters from `MatrixGlyphAtlas`. Cells are FIXED to
    /// the canvas and the brightness falls down them — scrolling a texture instead makes
    /// the glyphs slide, which the film never does.
    static let matrix = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        float a = max(src.a, 0.001);
        vec3 rgb = src.rgb / a;

        vec2 p = v_tex_coord / u_texel;
        float cell = mix(52.0, 17.0, u_tertiary);
        float col = floor(p.x / cell);
        float row = floor(p.y / cell);
        float rows = (1.0 / u_texel.y) / cell;

        float t = u_time + u_time_offset;
        float speed = (1.5 + hash21(vec2(col, 3.7)) * 5.5) * (0.25 + u_secondary * 2.4);
        // No gap in the cycle: the rain is only visible INSIDE the letters, so a column
        // whose head is off-screen leaves a hole in the word.
        float span = rows;
        float head = mod(t * speed + hash21(vec2(col, 9.1)) * span, span);

        // Rain falls down the screen; SpriteKit's y grows up.
        float depth = mod(head - (rows - row) + span, span);
        // A long decaying tail over a dim ambient floor, so every cell still reads as
        // a character rather than going black.
        float tail = max(exp(-depth * 0.16), 0.30);
        float leading = smoothstep(1.4, 0.0, depth);

        // Each cell swaps character every so often, on its own offset.
        float flick = floor(t * 5.0 + hash21(vec2(col, row)) * 22.0);
        float index = floor(hash21(vec2(col * 7.13 + flick, row * 3.31)) * 64.0);
        vec2 cellUV = vec2(fract(p.x / cell), fract(p.y / cell));
        vec2 atlasUV = (vec2(mod(index, 8.0), floor(index / 8.0)) + cellUV) * 0.125;
        float glyph = texture2D(u_glyphs, atlasUV).a;

        // Brightness, not just on/off: the leading character is near-white and the
        // trail decays through green.
        vec3 green = vec3(0.16, 1.00, 0.36);
        vec3 rain = mix(green * tail * 1.35, vec3(0.88, 1.00, 0.92), leading * 0.9) * glyph;

        vec3 outc = mix(rgb, rain, u_amount);
        gl_FragColor = vec4(clamp(outc, 0.0, 1.0) * src.a, src.a);
    }
    """

    static let liquify = helpers + """
    void main() {
        vec2 uv = v_tex_coord;
        float scale = mix(1.6, 9.0, u_secondary);
        float t = (u_time + u_time_offset) * (0.25 + u_tertiary * 2.2);
        float n1 = valueNoise(uv * scale + vec2(t * 0.28, 0.0));
        float n2 = valueNoise(uv * scale * 1.5 - vec2(0.0, t * 0.21));
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
        float scale = mix(26.0, 4.0, u_secondary);
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

    /// Heatmap, TEXT layer. The heat FIELD is a real Gaussian blur on its own node
    /// below this one — see `field(for:)`. Sampling a ring of taps here is what made
    /// the old version look like the word printed twenty times.
    static let thermal = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        float a = max(src.a, 0.001);
        vec3 rgb = src.rgb / a;
        // The letters ARE the hot core, so they stay crisp and near-white on top of
        // the field rather than being blurred into it.
        vec3 hot = vec3(1.0, 0.97, 0.86);
        vec3 outc = mix(rgb, hot, u_amount);
        gl_FragColor = vec4(clamp(outc, 0.0, 1.0) * src.a, src.a);
    }
    """

    /// Neon, TEXT layer: the lit tube itself. The halo is a blurred copy underneath
    /// (see `field(for:)`) — building it from taps here is what read as pinpoints.
    static let neon = helpers + """
    void main() {
        vec4 src = texture2D(u_texture, v_tex_coord);
        float a = max(src.a, 0.001);
        vec3 rgb = src.rgb / a;
        vec3 tint = hueRotate(vec3(0.15, 0.90, 1.00), u_secondary * 6.2831);
        vec3 core = mix(rgb, vec3(1.0), 0.7 * u_amount) + clamp(tint, 0.0, 1.0) * 0.3 * u_amount;
        gl_FragColor = vec4(clamp(core, 0.0, 1.0) * src.a, src.a);
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
        float t = (u_time + u_time_offset) * (0.05 + u_tertiary * 0.34);

        // The SHAPE was the one fixed thing about this mesh: the same four centres on
        // the same four paths, with only the palette changing. The variant seeds where
        // they sit and how they travel, so the dice gives a genuinely different field.
        float seed = u_variant * 1.6180339;
        vec2 h1 = vec2(hash21(vec2(seed, 1.0)), hash21(vec2(seed, 2.0)));
        vec2 h2 = vec2(hash21(vec2(seed, 3.0)), hash21(vec2(seed, 4.0)));
        vec2 h3 = vec2(hash21(vec2(seed, 5.0)), hash21(vec2(seed, 6.0)));
        vec2 h4 = vec2(hash21(vec2(seed, 7.0)), hash21(vec2(seed, 8.0)));
        float r1 = 0.6 + hash21(vec2(seed, 9.0)) * 1.4;
        float r2 = 0.6 + hash21(vec2(seed, 10.0)) * 1.4;
        float r3 = 0.6 + hash21(vec2(seed, 11.0)) * 1.4;
        float r4 = 0.6 + hash21(vec2(seed, 12.0)) * 1.4;

        vec2 p1 = vec2(0.16 + 0.68 * h1.x + 0.16 * sin(t * r1), 0.16 + 0.68 * h1.y + 0.15 * cos(t * r2));
        vec2 p2 = vec2(0.16 + 0.68 * h2.x + 0.15 * cos(t * r2), 0.16 + 0.68 * h2.y + 0.16 * sin(t * r3));
        vec2 p3 = vec2(0.16 + 0.68 * h3.x + 0.17 * sin(t * r3), 0.16 + 0.68 * h3.y + 0.14 * cos(t * r4));
        vec2 p4 = vec2(0.16 + 0.68 * h4.x + 0.14 * cos(t * r4), 0.16 + 0.68 * h4.y + 0.17 * sin(t * r1));

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
        float grain = hash21(p * mix(2.4, 0.18, u_tertiary) + vec2(t * 31.0, t * 17.0)) - 0.5;
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

        float cellScale = mix(1.0, 5.0, u_tertiary);
        vec2 p = floor(mod(floor(v_tex_coord / u_texel / cellScale), 4.0));
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

        // Shade the ink before quantising. Flat white is a fixed point of any
        // quantiser — the old version ran correctly and changed nothing at all.
        float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
        float ramp = mix(1.0, 0.10 + 0.90 * v_tex_coord.y, u_amount);
        float shade = clamp(lum * ramp, 0.0, 1.0);

        float levels = mix(2.0, 6.0, u_secondary);
        float quantised = clamp(floor(shade * levels + (m - 0.5)) / max(1.0, levels - 1.0), 0.0, 1.0);

        gl_FragColor = vec4(rgb * quantised * src.a, src.a);
    }
    """
}
